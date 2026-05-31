#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo DRIVE_REMOTE=<remote> DRIVE_PATH='server-files/infra-vps' bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELPER_SOURCE="${REPO_ROOT}/scripts/drive-sync-push.sh"
DRIVE_SYNC_TASK_ENV_FILE="${REPO_ROOT}/scheduled-tasks/drive-sync-push-to-google.env"

DRIVE_REMOTE="${DRIVE_REMOTE:-}"
DRIVE_PATH="${DRIVE_PATH:-}"
LOCAL_SYNC_ROOT="${LOCAL_SYNC_ROOT:-/srv/drive-sync}"
SYNC_ENV_FILE="${SYNC_ENV_FILE:-/etc/drive-sync.env}"
SYNC_HELPER_PATH="${SYNC_HELPER_PATH:-/usr/local/bin/drive-sync-push}"
SYNC_SERVICE_NAME="${SYNC_SERVICE_NAME:-drive-sync-push.service}"
SYNC_TIMER_NAME="${SYNC_TIMER_NAME:-drive-sync-push.timer}"
SYNC_CRON_EXPR="${SYNC_CRON_EXPR:-*/5 * * * *}"
SYNC_USER="${SYNC_USER:-root}"
RCLONE_PACKAGE="${RCLONE_PACKAGE:-rclone}"

STEP=0
TOTAL_STEPS=9

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s [setup-drive-sync] %s\n' "$(timestamp)" "$*"
}

step() {
  STEP=$((STEP + 1))
  log "[${STEP}/${TOTAL_STEPS}] $*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

trap 'fail "Setup stopped near line ${LINENO}. Check the message above for the last completed step."' ERR

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Missing required setting: ${name}"
  fi
}

run() {
  log "+ $*"
  "$@"
}

require_var "DRIVE_REMOTE"
require_var "DRIVE_PATH"

if [[ ! -f "${HELPER_SOURCE}" ]]; then
  fail "Missing helper source file: ${HELPER_SOURCE}"
fi

step "Installing rclone if needed"
if command -v rclone >/dev/null 2>&1; then
  log "rclone is already installed: $(rclone version | head -n 1)"
else
  run apt-get update
  run apt-get install -y "${RCLONE_PACKAGE}"
fi

step "Creating local sync directory structure"
run install -d -m 0755 "${LOCAL_SYNC_ROOT}"
run install -d -m 0755 "${LOCAL_SYNC_ROOT}/infra-vps"
run install -d -m 0755 "${LOCAL_SYNC_ROOT}/infra-vps/keys"
run install -d -m 0755 "${LOCAL_SYNC_ROOT}/infra-vps/wireguard"
run install -d -m 0755 "${LOCAL_SYNC_ROOT}/infra-vps/exports"
run install -d -m 0755 "${LOCAL_SYNC_ROOT}/infra-vps/notes"
run install -d -m 0755 "${LOCAL_SYNC_ROOT}/services"

step "Installing sync helper"
run install -m 0755 "${HELPER_SOURCE}" "${SYNC_HELPER_PATH}"

step "Writing environment file"
{
  printf 'DRIVE_REMOTE=%q\n' "${DRIVE_REMOTE}"
  printf 'DRIVE_PATH=%q\n' "${DRIVE_PATH}"
  printf 'LOCAL_SYNC_ROOT=%q\n' "${LOCAL_SYNC_ROOT}"
  printf 'SYNC_NAME=%q\n' "drive-sync-push"
  printf 'RCLONE_FLAGS=%q\n' "--fast-list --create-empty-src-dirs --transfers 4 --checkers 8"
} > "${SYNC_ENV_FILE}"
run chmod 0644 "${SYNC_ENV_FILE}"

step "Writing scheduled task metadata"
if [[ ! -d "$(dirname "${DRIVE_SYNC_TASK_ENV_FILE}")" ]]; then
  fail "Missing scheduled-tasks directory near repo root"
fi
{
  printf 'ENABLED=%q\n' "true"
  printf 'CRON_EXPR=%q\n' "${SYNC_CRON_EXPR}"
} > "${DRIVE_SYNC_TASK_ENV_FILE}"
run chmod 0644 "${DRIVE_SYNC_TASK_ENV_FILE}"

step "Checking rclone remote configuration"
REMOTE_READY=0
if rclone listremotes | grep -Fxq "${DRIVE_REMOTE}:"; then
  REMOTE_READY=1
  log "Remote '${DRIVE_REMOTE}' is present in rclone config."
else
  log "Remote '${DRIVE_REMOTE}' is not configured yet."
fi

step "Disabling legacy systemd timer when present"
run systemctl disable --now "${SYNC_TIMER_NAME}" || true

step "Preparing scheduled drive sync when remote is ready"
if [[ "${REMOTE_READY}" == "1" ]]; then
  run rclone mkdir "${DRIVE_REMOTE}:${DRIVE_PATH}"
  if [[ -x "${REPO_ROOT}/scripts/004-install-scheduled-tasks.sh" ]]; then
    run bash "${REPO_ROOT}/scripts/004-install-scheduled-tasks.sh"
  fi
  log "Scheduled cron-based drive sync is ready."
else
  log "Scheduled drive sync left inactive until rclone remote is configured."
fi

step "Printing summary and next steps"
cat <<EOF

Drive sync bootstrap complete.

Local sync root:
  ${LOCAL_SYNC_ROOT}

Google Drive target:
  ${DRIVE_REMOTE}:${DRIVE_PATH}

Environment file:
  ${SYNC_ENV_FILE}

Scheduled task metadata:
  ${DRIVE_SYNC_TASK_ENV_FILE}

Useful commands:
  cat /etc/cron.d/infra-vps-scheduled-tasks
  tail -n 100 /var/log/infra-vps-scheduled-tasks/drive-sync-push-to-google.log
  ${SYNC_HELPER_PATH}
EOF

if [[ "${REMOTE_READY}" != "1" ]]; then
  cat <<EOF

Next step required:
  1. Run: sudo rclone config
  2. Create remote: ${DRIVE_REMOTE}
  3. Re-run this setup script
EOF
fi
