#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TASKS_DIR="${TASKS_DIR:-${REPO_ROOT}/scheduled-tasks}"
CRON_FILE="${CRON_FILE:-/etc/cron.d/infra-vps-scheduled-tasks}"
LOG_DIR="${LOG_DIR:-/var/log/infra-vps-scheduled-tasks}"
LOG_LINES="${LOG_LINES:-3}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

print_header() {
  echo "Scheduled tasks status"
  echo "Tasks dir: ${TASKS_DIR}"
  echo "Cron file: ${CRON_FILE}"
  echo "Log dir:   ${LOG_DIR}"
  echo
}

print_task_status() {
  local task_name="$1"
  local task_script="${TASKS_DIR}/${task_name}.sh"
  local task_env="${TASKS_DIR}/${task_name}.env"
  local enabled="false"
  local cron_expr=""
  local cron_state="missing"
  local log_file="${LOG_DIR}/${task_name}.log"
  local last_log_time="never"

  unset ENABLED CRON_EXPR
  # shellcheck disable=SC1090
  source "${task_env}"

  enabled="${ENABLED:-false}"
  cron_expr="${CRON_EXPR:-}"

  if [[ -f "${CRON_FILE}" ]] && grep -Fq "bash ${task_script}" "${CRON_FILE}"; then
    cron_state="installed"
  fi

  if [[ -f "${log_file}" ]]; then
    last_log_time="$(stat -c '%y' "${log_file}" 2>/dev/null || echo "unknown")"
  fi

  echo "Task: ${task_name}"
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

if [[ ! -d "${TASKS_DIR}" ]]; then
  echo "Tasks directory not found: ${TASKS_DIR}"
  exit 1
fi

print_header

shopt -s nullglob
task_envs=("${TASKS_DIR}"/*.env)
shopt -u nullglob

if [[ "${#task_envs[@]}" -eq 0 ]]; then
  echo "No task metadata files found."
  exit 0
fi

for env_file in "${task_envs[@]}"; do
  print_task_status "$(basename "${env_file}" .env)"
done
