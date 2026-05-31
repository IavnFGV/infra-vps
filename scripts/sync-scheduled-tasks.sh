#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TASKS_DIR="${TASKS_DIR:-${REPO_ROOT}/scheduled-tasks}"
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
  echo "# Source directory: ${TASKS_DIR}"
} > "${tmp_file}"

shopt -s nullglob
task_envs=("${TASKS_DIR}"/*.env)
shopt -u nullglob

for env_file in "${task_envs[@]}"; do
  task_name="$(basename "${env_file}" .env)"
  task_script="${TASKS_DIR}/${task_name}.sh"

  if [[ ! -f "${task_script}" ]]; then
    log "Skipping ${task_name}: missing task script ${task_script}"
    continue
  fi

  unset ENABLED CRON_EXPR
  # shellcheck disable=SC1090
  source "${env_file}"

  if [[ "${ENABLED:-false}" != "true" ]]; then
    log "Skipping ${task_name}: ENABLED is not true"
    continue
  fi

  if [[ -z "${CRON_EXPR:-}" ]]; then
    log "Skipping ${task_name}: CRON_EXPR is empty"
    continue
  fi

  cron_log="${LOG_DIR}/${task_name}.log"

  {
    echo
    echo "# ${task_name}"
    printf '%s root cd %s && bash %s >> %s 2>&1\n' \
      "${CRON_EXPR}" \
      "${REPO_ROOT}" \
      "${task_script}" \
      "${cron_log}"
  } >> "${tmp_file}"
done

install -m 0644 "${tmp_file}" "${CRON_FILE}"
log "Cron file updated: ${CRON_FILE}"
