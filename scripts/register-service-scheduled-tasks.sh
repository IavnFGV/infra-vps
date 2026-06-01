#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SERVICE_NAME="${SERVICE_NAME:-}"
SERVICE_DIR="${SERVICE_DIR:-}"
SERVICE_TASKS_SOURCE_DIR="${SERVICE_TASKS_SOURCE_DIR:-}"
CONFIG_FILE="${CONFIG_FILE:-/etc/default/infra-vps-scheduled-tasks}"
SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT:-/srv/scheduled-tasks.d}"
SYNC_COMMAND="${SYNC_COMMAND:-/usr/local/bin/infra-vps-sync-scheduled-tasks}"
NODE_OWNER="${NODE_OWNER:-deploy}"

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

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
registered_count=0
script_only_count=0
env_only_count=0
registered_tasks=()
script_only_tasks=()
env_only_tasks=()

mkdir -p "${SERVICE_TASKS_ROOT}"
chown -R "${NODE_OWNER}:${NODE_OWNER}" "${SERVICE_TASKS_ROOT}"

if [[ -d "${SERVICE_TASKS_SOURCE_DIR}" ]]; then
  rm -rf "${SERVICE_TASKS_LINK_DIR}"
  mkdir -p "${SERVICE_TASKS_LINK_DIR}"

  find "${SERVICE_TASKS_SOURCE_DIR}" -maxdepth 1 -type f \( -name '*.env' -o -name '*.sh' \) -print0 | while IFS= read -r -d '' task_file; do
    ln -sfn "${task_file}" "${SERVICE_TASKS_LINK_DIR}/$(basename "${task_file}")"
  done

  chown -R "${NODE_OWNER}:${NODE_OWNER}" "${SERVICE_TASKS_LINK_DIR}"

  shopt -s nullglob
  env_files=("${SERVICE_TASKS_SOURCE_DIR}"/*.env)
  sh_files=("${SERVICE_TASKS_SOURCE_DIR}"/*.sh)
  shopt -u nullglob

  for env_file in "${env_files[@]}"; do
    task_name="$(basename "${env_file}" .env)"
    if [[ -f "${SERVICE_TASKS_SOURCE_DIR}/${task_name}.sh" ]]; then
      ((registered_count+=1))
      registered_tasks+=("${task_name}")
    else
      ((env_only_count+=1))
      env_only_tasks+=("${task_name}")
    fi
  done

  for sh_file in "${sh_files[@]}"; do
    task_name="$(basename "${sh_file}" .sh)"
    if [[ ! -f "${SERVICE_TASKS_SOURCE_DIR}/${task_name}.env" ]]; then
      ((script_only_count+=1))
      script_only_tasks+=("${task_name}")
    fi
  done
else
  rm -rf "${SERVICE_TASKS_LINK_DIR}"
fi

if [[ -x "${SYNC_COMMAND}" ]]; then
  env TASKS_DIR="${TASKS_DIR}" SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT}" "${SYNC_COMMAND}"
fi

if [[ ! -d "${SERVICE_TASKS_SOURCE_DIR}" ]]; then
  echo "No scheduled-tasks directory for ${SERVICE_NAME}; registration cleared"
elif [[ "${registered_count}" -eq 0 ]]; then
  echo "No complete scheduled task definitions found for ${SERVICE_NAME} (need matching .env + .sh files)"
else
  echo "Registered ${registered_count} scheduled task definition(s) for ${SERVICE_NAME}"
  printf 'Registered tasks: %s\n' "$(IFS=', '; echo "${registered_tasks[*]}")"
fi

if [[ "${script_only_count}" -gt 0 ]]; then
  printf 'Missing .env for tasks: %s\n' "$(IFS=', '; echo "${script_only_tasks[*]}")"
fi

if [[ "${env_only_count}" -gt 0 ]]; then
  printf 'Missing .sh for tasks: %s\n' "$(IFS=', '; echo "${env_only_tasks[*]}")"
fi
