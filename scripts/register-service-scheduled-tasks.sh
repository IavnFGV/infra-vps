#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SERVICE_NAME="${SERVICE_NAME:-}"
SERVICE_DIR="${SERVICE_DIR:-}"
SERVICE_TASKS_SOURCE_DIR="${SERVICE_TASKS_SOURCE_DIR:-}"
SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT:-/srv/scheduled-tasks.d}"
SYNC_COMMAND="${SYNC_COMMAND:-/usr/local/bin/infra-vps-sync-scheduled-tasks}"
INFRA_TASKS_DIR="${INFRA_TASKS_DIR:-/opt/infra-vps/scheduled-tasks}"
NODE_OWNER="${NODE_OWNER:-deploy}"

if [[ -z "${SERVICE_NAME}" ]]; then
  echo "SERVICE_NAME is required"
  exit 1
fi

if [[ -z "${SERVICE_DIR}" ]]; then
  echo "SERVICE_DIR is required"
  exit 1
fi

if [[ -z "${SERVICE_TASKS_SOURCE_DIR}" ]]; then
  SERVICE_TASKS_SOURCE_DIR="${SERVICE_DIR}/scheduled-tasks"
fi

if ! id -u "${NODE_OWNER}" >/dev/null 2>&1; then
  echo "User not found: ${NODE_OWNER}"
  exit 1
fi

SERVICE_TASKS_LINK_DIR="${SERVICE_TASKS_ROOT}/${SERVICE_NAME}"

mkdir -p "${SERVICE_TASKS_ROOT}"
chown -R "${NODE_OWNER}:${NODE_OWNER}" "${SERVICE_TASKS_ROOT}"

if [[ -d "${SERVICE_TASKS_SOURCE_DIR}" ]]; then
  rm -rf "${SERVICE_TASKS_LINK_DIR}"
  mkdir -p "${SERVICE_TASKS_LINK_DIR}"

  find "${SERVICE_TASKS_SOURCE_DIR}" -maxdepth 1 -type f \( -name '*.env' -o -name '*.sh' \) -print0 | while IFS= read -r -d '' task_file; do
    ln -sfn "${task_file}" "${SERVICE_TASKS_LINK_DIR}/$(basename "${task_file}")"
  done

  chown -R "${NODE_OWNER}:${NODE_OWNER}" "${SERVICE_TASKS_LINK_DIR}"
else
  rm -rf "${SERVICE_TASKS_LINK_DIR}"
fi

if [[ -x "${SYNC_COMMAND}" ]]; then
  env TASKS_DIR="${INFRA_TASKS_DIR}" SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT}" "${SYNC_COMMAND}"
fi

echo "Service scheduled tasks registered for ${SERVICE_NAME}"
