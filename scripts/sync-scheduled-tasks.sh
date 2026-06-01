#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_FILE="${CONFIG_FILE:-/etc/default/infra-vps-scheduled-tasks}"
TASKS_DIR="${TASKS_DIR:-${REPO_ROOT}/scheduled-tasks}"
SERVICE_TASKS_ROOT="${SERVICE_TASKS_ROOT:-/srv/scheduled-tasks.d}"
CRON_FILE="${CRON_FILE:-/etc/cron.d/infra-vps-scheduled-tasks}"
LOG_DIR="${LOG_DIR:-/var/log/infra-vps-scheduled-tasks}"

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s [sync-scheduled-tasks] %s\n' "$(timestamp)" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

if [[ ! -d "${TASKS_DIR}" ]]; then
  fail "Tasks directory not found: ${TASKS_DIR}"
fi

install -d -m 0755 "${LOG_DIR}"

tmp_file="$(mktemp)"
trap 'rm -f "${tmp_file}"' EXIT

{
  echo "SHELL=/bin/bash"
  echo "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
  echo
  echo "# Managed by scripts/sync-scheduled-tasks.sh"
  echo "# Infra tasks source directory: ${TASKS_DIR}"
  echo "# Service tasks source directory: ${SERVICE_TASKS_ROOT}"
} > "${tmp_file}"

build_cron_command() {
  local run_as="$1"
  local workdir="$2"
  local task_script="$3"

  if [[ "${run_as}" == "root" ]]; then
    printf 'cd %q && bash %q' "${workdir}" "${task_script}"
    return 0
  fi

  printf 'runuser -u %q -- bash -lc %q' \
    "${run_as}" \
    "cd ${workdir@Q} && bash ${task_script@Q}"
}

process_task_directory() {
  local task_dir="$1"
  local namespace="$2"

  shopt -s nullglob
  local task_envs=("${task_dir}"/*.env)
  shopt -u nullglob

  for env_file in "${task_envs[@]}"; do
    local task_name task_script cron_log cron_command
    task_name="$(basename "${env_file}" .env)"
    task_script="${task_dir}/${task_name}.sh"

    if [[ ! -f "${task_script}" ]]; then
      log "Skipping ${namespace}/${task_name}: missing task script ${task_script}"
      continue
    fi

    unset ENABLED CRON_EXPR RUN_AS WORKDIR
    # shellcheck disable=SC1090
    source "${env_file}"

    if [[ "${ENABLED:-false}" != "true" ]]; then
      log "Skipping ${namespace}/${task_name}: ENABLED is not true"
      continue
    fi

    if [[ -z "${CRON_EXPR:-}" ]]; then
      log "Skipping ${namespace}/${task_name}: CRON_EXPR is empty"
      continue
    fi

    RUN_AS="${RUN_AS:-root}"
    WORKDIR="${WORKDIR:-${task_dir}}"

    if ! id -u "${RUN_AS}" >/dev/null 2>&1; then
      log "Skipping ${namespace}/${task_name}: RUN_AS user not found: ${RUN_AS}"
      continue
    fi

    cron_log="${LOG_DIR}/${namespace}__${task_name}.log"
    cron_command="$(build_cron_command "${RUN_AS}" "${WORKDIR}" "${task_script}")"

    {
      echo
      echo "# ${namespace}/${task_name}"
      printf '%s root %s >> %s 2>&1\n' \
        "${CRON_EXPR}" \
        "${cron_command}" \
        "${cron_log}"
    } >> "${tmp_file}"
  done
}

process_task_directory "${TASKS_DIR}" "infra"

if [[ -d "${SERVICE_TASKS_ROOT}" ]]; then
  while IFS= read -r -d '' service_dir; do
    service_name="$(basename "${service_dir}")"
    process_task_directory "${service_dir}" "${service_name}"
  done < <(find "${SERVICE_TASKS_ROOT}" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

install -m 0644 "${tmp_file}" "${CRON_FILE}"
log "Cron file updated: ${CRON_FILE}"
