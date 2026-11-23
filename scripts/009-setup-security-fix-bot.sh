#!/usr/bin/env bash
set -euo pipefail

# Telegram auto-fix buttons of the security report (scripts/security-fix-bot.py)
# as a systemd service. Idempotent; the infra deploy runs it every time.
#
# The bot is restarted only when its code or unit changed: a fix of infra-vps
# itself runs this deploy, and must not kill the bot that waits for it.
#
# Options (environment):
#   ENABLE_FIX_BOT=true   false = stop and disable the service

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
UNIT_NAME="infra-vps-security-fix-bot.service"
UNIT_FILE="/etc/systemd/system/${UNIT_NAME}"
STAMP_FILE="/var/lib/infra-vps/security-fix-bot.sha256"
ENABLE_FIX_BOT="${ENABLE_FIX_BOT:-true}"

if [[ "${ENABLE_FIX_BOT}" != "true" ]]; then
  systemctl disable --now "${UNIT_NAME}" 2>/dev/null || true
  echo "[fix-bot] disabled"
  exit 0
fi

unit="$(cat <<UNIT
# Managed by infra-vps/scripts/009-setup-security-fix-bot.sh — re-run it instead of editing.
[Unit]
Description=infra-vps security report auto-fix buttons (Telegram)
After=network-online.target docker.service
Wants=network-online.target

[Service]
Environment=INFRA_MASTER_KEY_FILE=/opt/infra-secrets/master.key
ExecStart=/usr/bin/python3 -I ${REPO_ROOT}/scripts/security-fix-bot.py
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
UNIT
)"

install -d -m 0755 "$(dirname "${STAMP_FILE}")"
if [[ "$(cat "${UNIT_FILE}" 2>/dev/null || true)" != "${unit}" ]]; then
  printf '%s\n' "${unit}" > "${UNIT_FILE}"
  systemctl daemon-reload
fi

stamp="$(cat "${UNIT_FILE}" "${REPO_ROOT}/scripts/security-fix-bot.py" | sha256sum | cut -d' ' -f1)"
systemctl enable "${UNIT_NAME}" >/dev/null 2>&1
if [[ "$(cat "${STAMP_FILE}" 2>/dev/null || true)" != "${stamp}" ]] || ! systemctl is-active --quiet "${UNIT_NAME}"; then
  systemctl restart "${UNIT_NAME}"
  printf '%s\n' "${stamp}" > "${STAMP_FILE}"
  echo "[fix-bot] (re)started ${UNIT_NAME}"
else
  echo "[fix-bot] ${UNIT_NAME} is up to date"
fi
