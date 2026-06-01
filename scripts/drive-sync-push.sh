#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-/etc/drive-sync.env}"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
fi

SYNC_NAME="${SYNC_NAME:-drive-sync-push}"
LOCAL_SYNC_ROOT="${LOCAL_SYNC_ROOT:-/srv/drive-sync}"
DRIVE_REMOTE="${DRIVE_REMOTE:-}"
DRIVE_PATH="${DRIVE_PATH:-}"
RCLONE_BIN="${RCLONE_BIN:-$(command -v rclone || true)}"
RCLONE_FLAGS="${RCLONE_FLAGS:---fast-list --create-empty-src-dirs --transfers 4 --checkers 8}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s [%s] %s\n' "$(timestamp)" "${SYNC_NAME}" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    fail "Missing required setting: ${name}"
  fi
}

require_var "DRIVE_REMOTE"
require_var "DRIVE_PATH"

if [[ -z "${RCLONE_BIN}" ]]; then
  fail "rclone not found in PATH"
fi

if [[ ! -d "${LOCAL_SYNC_ROOT}" ]]; then
  fail "Local sync root does not exist: ${LOCAL_SYNC_ROOT}"
fi

REMOTE_TARGET="${DRIVE_REMOTE}:${DRIVE_PATH}"

log "Starting push sync"
log "Local root: ${LOCAL_SYNC_ROOT}"
log "Remote: ${REMOTE_TARGET}"

if ! "${RCLONE_BIN}" listremotes | grep -Fxq "${DRIVE_REMOTE}:"; then
  fail "Configured remote '${DRIVE_REMOTE}' is not present in rclone config"
fi

log "Checking remote connectivity"
"${RCLONE_BIN}" about "${DRIVE_REMOTE}:" >/dev/null

log "Ensuring remote path exists"
"${RCLONE_BIN}" mkdir "${REMOTE_TARGET}"

log "Running rclone sync"
"${RCLONE_BIN}" sync "${LOCAL_SYNC_ROOT}" "${REMOTE_TARGET}" ${RCLONE_FLAGS} --progress

log "Push sync completed successfully"
