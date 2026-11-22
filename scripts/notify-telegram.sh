#!/usr/bin/env bash
set -euo pipefail

# Send a plain-text message to Telegram.
# Usage: notify-telegram.sh "message"   or   echo "message" | notify-telegram.sh
#
# Config file (default /etc/infra-vps/notify.env, chmod 600):
#   TELEGRAM_BOT_TOKEN=123:abc        (plain or enc:... via decrypt-value.sh)
#   TELEGRAM_CHAT_ID=123456789
#
# Missing config is not an error: the message is only printed, so scheduled
# tasks keep working before Telegram is configured.

NOTIFY_CONFIG_FILE="${NOTIFY_CONFIG_FILE:-/etc/infra-vps/notify.env}"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
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

if [[ -r "${NOTIFY_CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${NOTIFY_CONFIG_FILE}"
fi

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
  echo "[notify] Telegram is not configured (${NOTIFY_CONFIG_FILE}); message follows:"
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
