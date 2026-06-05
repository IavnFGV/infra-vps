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
REGISTER_SERVICE_SCRIPT_SOURCE="${REPO_ROOT}/scripts/register-service.sh"
REGISTER_SERVICE_SCRIPT_TARGET="${REGISTER_SERVICE_SCRIPT_TARGET:-/usr/local/bin/infra-vps-register-service}"
REGISTER_SERVICE_ALIAS_TARGET="${REGISTER_SERVICE_ALIAS_TARGET:-/usr/local/bin/infra-vps-register}"
CONFIG_FILE="${CONFIG_FILE:-/etc/default/infra-vps-scheduled-tasks}"
SERVICE_CONFIG_FILE="${SERVICE_CONFIG_FILE:-/etc/default/infra-vps-service-registration}"
NODE_CONFIG_FILE="${NODE_CONFIG_FILE:-/etc/default/infra-vps-node}"
SYNC_CRON_FILE="${SYNC_CRON_FILE:-/etc/cron.d/infra-vps-scheduled-tasks-sync}"
TASKS_DIR="${TASKS_DIR:-${REPO_ROOT}/scheduled-tasks}"
SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT:-/srv/scheduled-tasks.d}"
HOST_SERVICE_REGISTRY_DIR="${HOST_SERVICE_REGISTRY_DIR:-/srv/service-registry.d}"
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

detect_server_public_ip() {
  local detected_ip=""

  detected_ip="$(curl -4 -fsSL ifconfig.me 2>/dev/null || true)"
  if [[ -n "${detected_ip}" ]]; then
    printf "%s" "${detected_ip}"
    return 0
  fi

  detected_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == "src") {print $(i+1); exit}}' || true)"
  printf "%s" "${detected_ip}"
}

if [[ ! -f "${SYNC_SCRIPT_SOURCE}" ]]; then
  fail "Missing sync script source file: ${SYNC_SCRIPT_SOURCE}"
fi

if [[ ! -f "${REGISTER_SCRIPT_SOURCE}" ]]; then
  fail "Missing register script source file: ${REGISTER_SCRIPT_SOURCE}"
fi

if [[ ! -f "${REGISTER_SERVICE_SCRIPT_SOURCE}" ]]; then
  fail "Missing register service source file: ${REGISTER_SERVICE_SCRIPT_SOURCE}"
fi

if [[ ! -d "${TASKS_DIR}" ]]; then
  fail "Missing tasks directory: ${TASKS_DIR}"
fi

log "Installing scheduled task sync script"
run install -m 0755 "${SYNC_SCRIPT_SOURCE}" "${SYNC_SCRIPT_TARGET}"

log "Installing service scheduled task register script"
run install -m 0755 "${REGISTER_SCRIPT_SOURCE}" "${REGISTER_SCRIPT_TARGET}"

log "Installing service register script"
run install -m 0755 "${REGISTER_SERVICE_SCRIPT_SOURCE}" "${REGISTER_SERVICE_SCRIPT_TARGET}"
run ln -sfn "${REGISTER_SERVICE_SCRIPT_TARGET}" "${REGISTER_SERVICE_ALIAS_TARGET}"

log "Writing scheduled task config"
cat > "${CONFIG_FILE}" <<EOF
TASKS_DIR=${TASKS_DIR}
SERVICE_TASKS_ROOT=${SERVICE_TASKS_ROOT}
EOF
run chmod 0644 "${CONFIG_FILE}"

log "Writing service registration config"
cat > "${SERVICE_CONFIG_FILE}" <<EOF
HOST_SERVICE_REGISTRY_DIR=${HOST_SERVICE_REGISTRY_DIR}
REGISTER_TASKS_COMMAND=${REGISTER_SCRIPT_TARGET}
APPLY_SERVICES_SCRIPT=${REPO_ROOT}/scripts/apply-services.sh
DECRYPT_SCRIPT=${REPO_ROOT}/scripts/decrypt-value.sh
NODE_OWNER=deploy
EOF
run chmod 0644 "${SERVICE_CONFIG_FILE}"

SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-$(detect_server_public_ip)}"
SERVER_PUBLIC_IP_DASHED="${SERVER_PUBLIC_IP//./-}"
log "Writing node config"
cat > "${NODE_CONFIG_FILE}" <<EOF
SERVER_PUBLIC_IP=${SERVER_PUBLIC_IP}
SERVER_PUBLIC_IP_DASHED=${SERVER_PUBLIC_IP_DASHED}
EOF
run chmod 0644 "${NODE_CONFIG_FILE}"

log "Installing cron sync entry"
cat > "${SYNC_CRON_FILE}" <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

* * * * * root ${SYNC_SCRIPT_TARGET} >> ${SYNC_LOG_FILE} 2>&1
EOF

run chmod 0644 "${SYNC_CRON_FILE}"

log "Running initial cron sync"
run "${SYNC_SCRIPT_TARGET}"

log "Scheduled task install complete"
cat <<EOF

Installed:
  ${SYNC_SCRIPT_TARGET}
  ${REGISTER_SCRIPT_TARGET}
  ${REGISTER_SERVICE_SCRIPT_TARGET}
  ${REGISTER_SERVICE_ALIAS_TARGET}
  ${CONFIG_FILE}
  ${SERVICE_CONFIG_FILE}
  ${NODE_CONFIG_FILE}
  ${SYNC_CRON_FILE}

Useful commands:
  cat /etc/cron.d/infra-vps-scheduled-tasks
  cat ${SYNC_CRON_FILE}
  cat ${CONFIG_FILE}
  tail -n 100 ${SYNC_LOG_FILE}
  ${SYNC_SCRIPT_TARGET}
EOF
