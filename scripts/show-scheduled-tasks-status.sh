#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_FILE="${CONFIG_FILE:-/etc/default/infra-vps-scheduled-tasks}"
TASKS_DIR="${TASKS_DIR:-${REPO_ROOT}/scheduled-tasks}"
SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT:-/srv/scheduled-tasks.d}"
CRON_FILE="${CRON_FILE:-/etc/cron.d/infra-vps-scheduled-tasks}"
LOG_DIR="${LOG_DIR:-/var/log/infra-vps-scheduled-tasks}"
LOG_LINES="${LOG_LINES:-3}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

print_header() {
  echo "Scheduled tasks status"
  echo "Infra tasks dir:   ${TASKS_DIR}"
  echo "Service tasks dir: ${SERVICE_TASKS_ROOT}"
  echo "Cron file:         ${CRON_FILE}"
  echo "Log dir:           ${LOG_DIR}"
  echo
}

print_task_status() {
  local namespace="$1"
  local task_dir="$2"
  local task_name="$3"
  local task_script="${task_dir}/${task_name}.sh"
  local task_env="${task_dir}/${task_name}.env"
  local enabled="false"
  local cron_expr=""
  local cron_state="missing"
  local log_file="${LOG_DIR}/${namespace}__${task_name}.log"
  local last_log_time="never"

  unset ENABLED CRON_EXPR RUN_AS WORKDIR
  # shellcheck disable=SC1090
  source "${task_env}"

  enabled="${ENABLED:-false}"
  cron_expr="${CRON_EXPR:-}"

  if [[ -f "${CRON_FILE}" ]] && grep -Fq "# ${namespace}/${task_name}" "${CRON_FILE}"; then
    cron_state="installed"
  fi

  if [[ -f "${log_file}" ]]; then
    last_log_time="$(stat -c '%y' "${log_file}" 2>/dev/null || echo "unknown")"
  fi

  echo "Task: ${namespace}/${task_name}"
  echo "  enabled: ${enabled}"
  echo "  cron: ${cron_expr:-<empty>}"
  echo "  installed in cron: ${cron_state}"
  echo "  log file: ${log_file}"
  echo "  last log update: ${last_log_time}"

  if [[ ! -f "${task_script}" ]]; then
    echo "  status: missing script ${task_script}"
    echo
    return 0
  fi

  if [[ -f "${log_file}" ]]; then
    echo "  recent log lines:"
    tail -n "${LOG_LINES}" "${log_file}" | sed 's/^/    /'
  else
    echo "  recent log lines:"
    echo "    <no log file yet>"
  fi

  echo
}

print_task_directory() {
  local namespace="$1"
  local task_dir="$2"

  shopt -s nullglob
  local task_envs=("${task_dir}"/*.env)
  shopt -u nullglob

  if [[ "${#task_envs[@]}" -eq 0 ]]; then
    return 0
  fi

  for env_file in "${task_envs[@]}"; do
    print_task_status "${namespace}" "${task_dir}" "$(basename "${env_file}" .env)"
  done
}

if [[ ! -d "${TASKS_DIR}" ]]; then
  echo "Tasks directory not found: ${TASKS_DIR}"
  exit 1
fi

print_header

found_any=0

shopt -s nullglob
infra_envs=("${TASKS_DIR}"/*.env)
shopt -u nullglob
if [[ "${#infra_envs[@]}" -gt 0 ]]; then
  print_task_directory "infra" "${TASKS_DIR}"
  found_any=1
fi

if [[ -d "${SERVICE_TASKS_ROOT}" ]]; then
  while IFS= read -r -d '' service_dir; do
    shopt -s nullglob
    service_envs=("${service_dir}"/*.env)
    shopt -u nullglob
    if [[ "${#service_envs[@]}" -gt 0 ]]; then
      print_task_directory "$(basename "${service_dir}")" "${service_dir}"
      found_any=1
    fi
  done < <(find "${SERVICE_TASKS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

if [[ "${found_any}" -eq 0 ]]; then
  echo "No task metadata files found."
fi
