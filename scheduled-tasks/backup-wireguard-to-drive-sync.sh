#!/usr/bin/env bash
set -euo pipefail

WG_DIR="${WG_DIR:-/etc/wireguard}"
WG_CLIENTS_DIR="${WG_CLIENTS_DIR:-${WG_DIR}/clients}"
SYNC_ROOT="${SYNC_ROOT:-/srv/drive-sync}"
TARGET_DIR="${TARGET_DIR:-${SYNC_ROOT}/infra-vps/wireguard}"
WG_SERVER_CONFIG_NAME="${WG_SERVER_CONFIG_NAME:-wg0.conf}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s [backup-wireguard-to-drive-sync] %s\n' "$(timestamp)" "$*"
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

if [[ ! -d "${WG_DIR}" ]]; then
  fail "WireGuard directory not found: ${WG_DIR}"
fi

log "Preparing target directory: ${TARGET_DIR}"
install -d -m 0700 "${TARGET_DIR}"

SERVER_CONFIG_PATH="${WG_DIR}/${WG_SERVER_CONFIG_NAME}"
if [[ -f "${SERVER_CONFIG_PATH}" ]]; then
  sync_file_if_changed "${SERVER_CONFIG_PATH}" "${TARGET_DIR}/${WG_SERVER_CONFIG_NAME}"
else
  log "Server config not found, skipping: ${SERVER_CONFIG_PATH}"
fi

if compgen -G "${WG_CLIENTS_DIR}/*.conf" >/dev/null 2>&1; then
  log "Copying client configs from: ${WG_CLIENTS_DIR}"
  find "${WG_CLIENTS_DIR}" -maxdepth 1 -type f -name '*.conf' -print0 | while IFS= read -r -d '' client_conf; do
    sync_file_if_changed "${client_conf}" "${TARGET_DIR}/$(basename "${client_conf}")"
  done
else
  log "No client configs found in: ${WG_CLIENTS_DIR}"
fi

log "WireGuard backup copy completed"
