#!/usr/bin/env bash
set -euo pipefail

# Send a plain-text message to Telegram.
# Usage: notify-telegram.sh "message"   or   echo "message" | notify-telegram.sh
#
# Config (later file overrides earlier):
#   1. <repo>/config/notify.env  — committed, values encrypted as enc:...
#      (scripts/encrypt-value.sh), so a new server only needs the master key
#   2. /etc/infra-vps/notify.env — optional server-local override, chmod 600
# Keys:
#   TELEGRAM_BOT_TOKEN=enc:...
#   TELEGRAM_CHAT_ID=enc:...
# NOTIFY_CONFIG_FILE=<path> uses only that file.
#
# Missing config is not an error: the message is only printed, so scheduled
# tasks keep working before Telegram is configured.

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
if [[ -n "${NOTIFY_CONFIG_FILE:-}" ]]; then
  config_files=("${NOTIFY_CONFIG_FILE}")
else
  config_files=("${REPO_ROOT}/config/notify.env" "/etc/infra-vps/notify.env")
fi
DECRYPT_SCRIPT="${DECRYPT_SCRIPT:-${SCRIPT_DIR}/decrypt-value.sh}"
TELEGRAM_API_URL="${TELEGRAM_API_URL:-https://api.telegram.org}"
MAX_LEN=3900

if [[ $# -gt 0 ]]; then
  message="$*"
else
  message="$(cat)"
fi

if [[ -z "${message}" ]]; then
  exit 0
fi

for config_file in "${config_files[@]}"; do
  if [[ -r "${config_file}" ]]; then
    # shellcheck disable=SC1090
    source "${config_file}"
  fi
done

resolve() {
  local value="$1"
  if [[ "${value}" == enc:* ]]; then
    INFRA_MASTER_KEY_FILE="${INFRA_MASTER_KEY_FILE:-/opt/infra-secrets/master.key}" \
      "${DECRYPT_SCRIPT}" "${value}"
  else
    printf '%s' "${value}"
  fi
}

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "[notify] Telegram is not configured (${config_files[*]}); message follows:"
  printf '%s\n' "${message}"
  exit 0
fi

token="$(resolve "${TELEGRAM_BOT_TOKEN}")"
chat_id="$(resolve "${TELEGRAM_CHAT_ID}")"

host="$(hostname -s 2>/dev/null || echo vps)"
message="[${host}] ${message}"
if (( ${#message} > MAX_LEN )); then
  message="${message:0:MAX_LEN}
... (truncated, see log on server)"
fi

# Token goes through a config file for curl, so it never shows up in `ps`.
curl_cfg="$(mktemp)"
trap 'rm -f "${curl_cfg}"' EXIT
chmod 600 "${curl_cfg}"
printf 'url = "%s/bot%s/sendMessage"\n' "${TELEGRAM_API_URL}" "${token}" > "${curl_cfg}"

if ! curl -fsS --max-time 20 --config "${curl_cfg}" \
  --data-urlencode "chat_id=${chat_id}" \
  --data-urlencode "text=${message}" \
  --data-urlencode "disable_web_page_preview=true" \
  -o /dev/null; then
  echo "[notify] WARNING: failed to send Telegram message" >&2
  exit 1
fi
