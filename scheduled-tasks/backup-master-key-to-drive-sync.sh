#!/usr/bin/env bash
set -euo pipefail

DEFAULT_KEY_FILE="/opt/infra-secrets/master.key"
KEY_FILE="${INFRA_MASTER_KEY_FILE:-${DEFAULT_KEY_FILE}}"
SYNC_ROOT="${SYNC_ROOT:-/srv/drive-sync}"
TARGET_DIR="${TARGET_DIR:-${SYNC_ROOT}/infra-vps/keys}"
TARGET_FILE="${TARGET_FILE:-${TARGET_DIR}/master.key}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s [backup-master-key-to-drive-sync] %s\n' "$(timestamp)" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

sync_file_if_changed() {
  local source_file="$1"
  local target_file="$2"

  if [[ ! -f "${target_file}" ]]; then
    log "Creating backup copy: ${target_file}"
    install -m 0600 "${source_file}" "${target_file}"
    return 0
  fi

  if cmp -s "${source_file}" "${target_file}"; then
    log "No changes detected: ${target_file}"
    return 0
  fi

  log "Updating changed file: ${target_file}"
  install -m 0600 "${source_file}" "${target_file}"
}

if [[ "${EUID}" -ne 0 ]]; then
  fail "Run as root"
fi

if [[ ! -f "${KEY_FILE}" ]]; then
  fail "Master key file not found: ${KEY_FILE}"
fi

log "Preparing target directory: ${TARGET_DIR}"
install -d -m 0700 "${TARGET_DIR}"
sync_file_if_changed "${KEY_FILE}" "${TARGET_FILE}"
log "Master key backup copy completed"
