#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

SYNC_SCRIPT_SOURCE="${REPO_ROOT}/scripts/sync-scheduled-tasks.sh"
SYNC_SCRIPT_TARGET="${SYNC_SCRIPT_TARGET:-/usr/local/bin/infra-vps-sync-scheduled-tasks}"
REGISTER_SCRIPT_SOURCE="${REPO_ROOT}/scripts/register-service-scheduled-tasks.sh"
REGISTER_SCRIPT_TARGET="${REGISTER_SCRIPT_TARGET:-/usr/local/bin/infra-vps-register-service-scheduled-tasks}"
SYNC_CRON_FILE="${SYNC_CRON_FILE:-/etc/cron.d/infra-vps-scheduled-tasks-sync}"
TASKS_DIR="${TASKS_DIR:-${REPO_ROOT}/scheduled-tasks}"
SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT:-/srv/scheduled-tasks.d}"
SYNC_LOG_FILE="${SYNC_LOG_FILE:-/var/log/infra-vps-sync-scheduled-tasks.log}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s [install-scheduled-tasks] %s\n' "$(timestamp)" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

run() {
  log "+ $*"
  "$@"
}

if [[ ! -f "${SYNC_SCRIPT_SOURCE}" ]]; then
  fail "Missing sync script source file: ${SYNC_SCRIPT_SOURCE}"
fi

if [[ ! -f "${REGISTER_SCRIPT_SOURCE}" ]]; then
  fail "Missing register script source file: ${REGISTER_SCRIPT_SOURCE}"
fi

if [[ ! -d "${TASKS_DIR}" ]]; then
  fail "Missing tasks directory: ${TASKS_DIR}"
fi

log "Installing scheduled task sync script"
run install -m 0755 "${SYNC_SCRIPT_SOURCE}" "${SYNC_SCRIPT_TARGET}"

log "Installing service scheduled task register script"
run install -m 0755 "${REGISTER_SCRIPT_SOURCE}" "${REGISTER_SCRIPT_TARGET}"

log "Installing cron sync entry"
cat > "${SYNC_CRON_FILE}" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

* * * * * root TASKS_DIR=${TASKS_DIR} SERVICE_TASKS_ROOT=${SERVICE_TASKS_ROOT} ${SYNC_SCRIPT_TARGET} >> ${SYNC_LOG_FILE} 2>&1
EOF

run chmod 0644 "${SYNC_CRON_FILE}"

log "Running initial cron sync"
run env TASKS_DIR="${TASKS_DIR}" SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT}" "${SYNC_SCRIPT_TARGET}"

log "Scheduled task install complete"
cat <<EOF

Installed:
  ${SYNC_SCRIPT_TARGET}
  ${REGISTER_SCRIPT_TARGET}
  ${SYNC_CRON_FILE}

Useful commands:
  cat /etc/cron.d/infra-vps-scheduled-tasks
  cat ${SYNC_CRON_FILE}
  tail -n 100 ${SYNC_LOG_FILE}
  env TASKS_DIR=${TASKS_DIR} SERVICE_TASKS_ROOT=${SERVICE_TASKS_ROOT} ${SYNC_SCRIPT_TARGET}
EOF
