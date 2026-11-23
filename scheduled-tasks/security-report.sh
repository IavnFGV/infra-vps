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
HEARTBEAT_WEEKDAY="${HEARTBEAT_WEEKDAY-1}"    # 1 = Monday, empty = never
KEEP_REPORTS_DAYS="${KEEP_REPORTS_DAYS:-60}"
SCAN_HOST="${SCAN_HOST:-true}"
NOTIFY_BIN="${NOTIFY_BIN:-${REPO_ROOT}/scripts/notify-telegram.sh}"
SUMMARIZE="${SUMMARIZE:-${REPO_ROOT}/scripts/security-report-summarize.py}"
UU_LOG="${UU_LOG:-/var/log/unattended-upgrades/unattended-upgrades.log}"
REBOOT_REQUIRED_FILE="${REBOOT_REQUIRED_FILE:-/var/run/reboot-required}"
IGNORE_FILE="${IGNORE_FILE:-${SCRIPT_DIR}/security-report.trivyignore}"

log() {
  printf '%s [security-report] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

install -d -m 0755 "${REPORT_DIR}" "${REPORT_DIR}/scans"
install -d -m 0755 "${TRIVY_CACHE_DIR}"
scan_dir="$(mktemp -d)"
trap 'rm -rf "${scan_dir}"' EXIT

summarize_args=()
trivy_common=(--cache-dir "${TRIVY_CACHE_DIR}" --quiet --scanners vuln
  --ignore-unfixed --severity "${SEVERITY}" --format json)
if [[ -f "${IGNORE_FILE}" ]]; then
  trivy_common+=(--ignorefile "${IGNORE_FILE}")
fi

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

  # One scan per unique image ID actually running (not per tag: a tag may
  # already point to a newer build than the container uses).
  # label = compose project/service of the containers using it.
  declare -A image_labels=() image_refs=()
  # With the containerd image store, a container's .Image is the index digest
  # while the tag resolves per platform to a manifest digest; compare manifests.
  inspect_format='{{.Image}}	{{.Config.Image}}	{{index .Config.Labels "com.docker.compose.project"}}	{{index .Config.Labels "com.docker.compose.service"}}	{{.Name}}	{{with .ImageManifestDescriptor}}{{.Digest}}{{end}}'
  platform="$(docker version --format '{{.Server.Os}}/{{.Server.Arch}}' 2>/dev/null || true)"
  declare -A image_manifests=()
  while IFS=$'\t' read -r image_id ref project service name manifest; do
    [[ -n "${image_id}" ]] || continue
    if [[ -n "${project}" && -n "${service}" ]]; then
      label="${project}/${service}"
    else
      label="${name#/}"
    fi
    if [[ -n "${image_labels[${image_id}]:-}" ]]; then
      image_labels["${image_id}"]+=",${label}"
    else
      image_labels["${image_id}"]="${label}"
      image_refs["${image_id}"]="${ref}"
      image_manifests["${image_id}"]="${manifest}"
    fi
  done < <(docker ps -q | xargs -r docker inspect --format "${inspect_format}" | sort)

  i=0
  for image_id in "${!image_labels[@]}"; do
    i=$((i + 1))
    label="${image_labels[${image_id}]}"
    ref="${image_refs[${image_id}]}"
    out="${scan_dir}/image-${i}.json"
    target=(--skip-db-update --output "${out}")

    manifest="${image_manifests[${image_id}]}"
    tag_id="$(docker image inspect --format '{{.Id}}' "${ref}" 2>/dev/null || true)"
    tag_manifest=""
    if [[ -n "${manifest}" && -n "${platform}" ]]; then
      tag_manifest="$(docker image inspect --platform "${platform}" --format '{{.Id}}' "${ref}" 2>/dev/null || true)"
    fi
    if [[ "${tag_id}" == "${image_id}" || ( -n "${manifest}" && "${tag_manifest}" == "${manifest}" ) ]]; then
      target+=("${ref}")
    else
      summarize_args+=(--scan-error "${label}=container runs an outdated image (${ref} now points to a newer build); recreate the stack")
      tar="${scan_dir}/image-${i}.tar"
      if ! docker save -o "${tar}" "${image_id}" 2>/dev/null; then
        summarize_args+=(--scan-error "${label}=running image ${image_id:7:12} is not in the local store; cannot scan")
        continue
      fi
      target+=(--input "${tar}")
    fi

    # compose labels the images it builds; a pulled image has no such label.
    # (by tag: with the containerd store the running image id may not resolve)
    built_by="$(docker image inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "${ref}" 2>/dev/null \
      || docker image inspect --format '{{index .Config.Labels "com.docker.compose.project"}}' "${image_id}" 2>/dev/null || true)"
    if [[ -n "${built_by}" && "${built_by}" != "<no value>" ]]; then
      summarize_args+=(--built-locally "${label}")
    fi

    log "Scanning ${label} (${ref}, ${image_id:7:12})"
    if trivy image "${trivy_common[@]}" "${target[@]}"; then
      summarize_args+=(--scan "${label}=${out}")
    else
      summarize_args+=(--scan-error "${label}=trivy image failed for ${ref}")
    fi
    rm -f "${scan_dir}/image-${i}.tar"
  done
fi

# Container labels (compose project, working dir, infra-vps.fix*) let the
# summarizer offer a fix for each component; see docs/security-updates.md.
containers_json="${scan_dir}/containers.inspect"
if docker ps -q | xargs -r docker inspect > "${containers_json}" 2>/dev/null; then
  summarize_args+=(--containers "${containers_json}")
fi

# A github-workflow fix needs a token; without it the fix is shown, no button.
for config_file in "${REPO_ROOT}/config/notify.env" /etc/infra-vps/notify.env; do
  if [[ -r "${config_file}" ]] && grep -q '^GITHUB_FIX_TOKEN=.' "${config_file}"; then
    summarize_args+=(--github-fix-ready)
  fi
done
summarize_args+=(--host-fix "${HOST_AUTOFIX:-apt-upgrade}" --fixes "${REPORT_DIR}/fixes.json")

# Old kernels left on disk are not running; don't report them.
summarize_args+=(--running-kernel "$(uname -r)")

if [[ -n "${HEARTBEAT_WEEKDAY}" && "$(date +%u)" == "${HEARTBEAT_WEEKDAY}" ]]; then
  summarize_args+=(--heartbeat)
fi

stamp="$(date +%Y-%m-%d)"
report="${REPORT_DIR}/${stamp}.txt"
message="${scan_dir}/message.txt"
markup="${scan_dir}/reply-markup.txt"

python3 -I "${SUMMARIZE}" "${summarize_args[@]}" \
  --state "${REPORT_DIR}/state.json" \
  --report "${report}" \
  --message "${message}" \
  --reply-markup "${markup}" \
  --uu-log "${UU_LOG}" \
  --reboot-required-file "${REBOOT_REQUIRED_FILE}"

cp "${report}" "${REPORT_DIR}/latest.txt"
cp "${scan_dir}"/*.json "${REPORT_DIR}/scans/" 2>/dev/null || true
find "${REPORT_DIR}" -maxdepth 1 -name '20*.txt' -mtime "+${KEEP_REPORTS_DAYS}" -delete || true

cat "${report}"

if [[ -s "${message}" ]]; then
  log "Sending notification"
  NOTIFY_REPLY_MARKUP_FILE="${markup}" "${NOTIFY_BIN}" < "${message}" || log "WARNING: notification failed"
else
  log "Nothing new; no notification"
fi
