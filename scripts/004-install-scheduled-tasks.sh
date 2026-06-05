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
  ${SYNC_CRON_FILE}

Useful commands:
  cat /etc/cron.d/infra-vps-scheduled-tasks
  cat ${SYNC_CRON_FILE}
  cat ${CONFIG_FILE}
  tail -n 100 ${SYNC_LOG_FILE}
  ${SYNC_SCRIPT_TARGET}
EOF
