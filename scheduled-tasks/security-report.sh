#!/usr/bin/env bash
set -euo pipefail

# Daily security report:
#   1. Trivy scan of the host OS packages and of every running container image
#      (only HIGH/CRITICAL with a fix available — things we can actually act on)
#   2. what unattended-upgrades installed in the last 24h, pending reboot
#   3. log to /var/log/infra-vps-security/, Telegram on news (+ weekly heartbeat)
#
# This task only reports. Fixes arrive through:
#   - unattended-upgrades (host OS)
#   - Dependabot + auto-merge + weekly rebuild in each service repo (images)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

REPORT_DIR="${REPORT_DIR:-/var/log/infra-vps-security}"
TRIVY_CACHE_DIR="${TRIVY_CACHE_DIR:-/var/cache/trivy}"
SEVERITY="${SEVERITY:-HIGH,CRITICAL}"
HEARTBEAT_WEEKDAY="${HEARTBEAT_WEEKDAY:-1}"   # 1 = Monday, empty = never
KEEP_REPORTS_DAYS="${KEEP_REPORTS_DAYS:-60}"
SCAN_HOST="${SCAN_HOST:-true}"
NOTIFY_BIN="${NOTIFY_BIN:-${REPO_ROOT}/scripts/notify-telegram.sh}"
SUMMARIZE="${SUMMARIZE:-${REPO_ROOT}/scripts/security-report-summarize.py}"
UU_LOG="${UU_LOG:-/var/log/unattended-upgrades/unattended-upgrades.log}"
REBOOT_REQUIRED_FILE="${REBOOT_REQUIRED_FILE:-/var/run/reboot-required}"

log() {
  printf '%s [security-report] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

install -d -m 0750 "${REPORT_DIR}" "${REPORT_DIR}/scans"
install -d -m 0755 "${TRIVY_CACHE_DIR}"
scan_dir="$(mktemp -d)"
trap 'rm -rf "${scan_dir}"' EXIT

summarize_args=()
trivy_common=(--cache-dir "${TRIVY_CACHE_DIR}" --quiet --scanners vuln
  --ignore-unfixed --severity "${SEVERITY}" --format json)

if ! command -v trivy >/dev/null 2>&1; then
  summarize_args+=(--scan-error "trivy=not installed (run scripts/008-setup-auto-updates.sh)")
else
  log "Updating Trivy vulnerability DB"
  if ! trivy image --cache-dir "${TRIVY_CACHE_DIR}" --quiet --download-db-only; then
    summarize_args+=(--scan-error "trivy-db=failed to download vulnerability DB")
  fi

  if [[ "${SCAN_HOST}" == "true" ]]; then
    log "Scanning host OS packages"
    out="${scan_dir}/host.json"
    if trivy rootfs "${trivy_common[@]}" --pkg-types os \
      --skip-dirs /proc,/sys,/dev,/run,/tmp,/var/lib/docker,/var/lib/containerd,/srv,/opt,/home,/snap \
      --output "${out}" /; then
      summarize_args+=(--scan "host=${out}")
    else
      summarize_args+=(--scan-error "host=trivy rootfs failed")
    fi
  fi

  # One scan per unique image; label = compose project/service of containers using it.
  declare -A image_labels=()
  while IFS=$'\t' read -r image project service name; do
    [[ -n "${image}" ]] || continue
    if [[ -n "${project}" && -n "${service}" ]]; then
      label="${project}/${service}"
    else
      label="${name}"
    fi
    if [[ -n "${image_labels[${image}]:-}" ]]; then
      image_labels["${image}"]+=",${label}"
    else
      image_labels["${image}"]="${label}"
    fi
  done < <(docker ps --format '{{.Image}}	{{.Label "com.docker.compose.project"}}	{{.Label "com.docker.compose.service"}}	{{.Names}}' | sort)

  i=0
  for image in "${!image_labels[@]}"; do
    i=$((i + 1))
    label="${image_labels[${image}]}"
    out="${scan_dir}/image-${i}.json"
    log "Scanning ${label} (${image})"
    if trivy image "${trivy_common[@]}" --skip-db-update --output "${out}" "${image}"; then
      summarize_args+=(--scan "${label}=${out}")
    else
      summarize_args+=(--scan-error "${label}=trivy image failed for ${image}")
    fi
  done
fi

if [[ -n "${HEARTBEAT_WEEKDAY}" && "$(date +%u)" == "${HEARTBEAT_WEEKDAY}" ]]; then
  summarize_args+=(--heartbeat)
fi

stamp="$(date +%Y-%m-%d)"
report="${REPORT_DIR}/${stamp}.txt"
message="${scan_dir}/message.txt"

python3 -I "${SUMMARIZE}" "${summarize_args[@]}" \
  --state "${REPORT_DIR}/state.json" \
  --report "${report}" \
  --message "${message}" \
  --uu-log "${UU_LOG}" \
  --reboot-required-file "${REBOOT_REQUIRED_FILE}"

cp "${report}" "${REPORT_DIR}/latest.txt"
cp "${scan_dir}"/*.json "${REPORT_DIR}/scans/" 2>/dev/null || true
find "${REPORT_DIR}" -maxdepth 1 -name '20*.txt' -mtime "+${KEEP_REPORTS_DAYS}" -delete || true

cat "${report}"

if [[ -s "${message}" ]]; then
  log "Sending notification"
  "${NOTIFY_BIN}" < "${message}" || log "WARNING: notification failed"
else
  log "Nothing new; no notification"
fi
