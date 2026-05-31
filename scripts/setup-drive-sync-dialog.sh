#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTRAP_SCRIPT="${SCRIPT_DIR}/setup-drive-sync.sh"

if [[ ! -f "${BOOTSTRAP_SCRIPT}" ]]; then
  echo "Missing bootstrap script: ${BOOTSTRAP_SCRIPT}"
  exit 1
fi

timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
  printf '%s [setup-drive-sync-dialog] %s\n' "$(timestamp)" "$*"
}

ask_with_default() {
  local prompt="$1"
  local default_value="$2"
  local answer

  read -r -p "${prompt} [${default_value}]: " answer
  if [[ -z "${answer}" ]]; then
    answer="${default_value}"
  fi
  printf '%s' "${answer}"
}

ask_yes_no() {
  local prompt="$1"
  local default_value="$2"
  local answer

  while true; do
    read -r -p "${prompt} [${default_value}]: " answer
    if [[ -z "${answer}" ]]; then
      answer="${default_value}"
    fi

    case "${answer}" in
      y|Y|yes|YES)
        return 0
        ;;
      n|N|no|NO)
        return 1
        ;;
      *)
        echo "Please answer y or n."
        ;;
    esac
  done
}

log "Starting interactive Google Drive sync setup"
echo
echo "This wizard sets up push-only sync from the server to Google Drive."
echo "It does not restore files from Google Drive back to the server."
echo

DRIVE_REMOTE="$(ask_with_default "rclone remote name" "gdrive")"
echo
DRIVE_PATH="$(ask_with_default "Google Drive path" "server-files")"
echo
LOCAL_SYNC_ROOT="$(ask_with_default "Local sync root" "/srv/drive-sync")"
echo
SYNC_INTERVAL="$(ask_with_default "Sync interval for systemd timer" "5min")"
echo

if ask_yes_no "Open 'sudo rclone config' after bootstrap if the remote is missing?" "y"; then
  RUN_RCLONE_CONFIG_IF_MISSING=1
else
  RUN_RCLONE_CONFIG_IF_MISSING=0
fi

echo
echo "Summary:"
echo "  Remote: ${DRIVE_REMOTE}"
echo "  Google Drive path: ${DRIVE_PATH}"
echo "  Local sync root: ${LOCAL_SYNC_ROOT}"
echo "  Sync interval: ${SYNC_INTERVAL}"
echo

if ! ask_yes_no "Continue with bootstrap?" "y"; then
  echo "Cancelled."
  exit 0
fi

echo
log "Running bootstrap script"
DRIVE_REMOTE="${DRIVE_REMOTE}" \
DRIVE_PATH="${DRIVE_PATH}" \
LOCAL_SYNC_ROOT="${LOCAL_SYNC_ROOT}" \
SYNC_INTERVAL="${SYNC_INTERVAL}" \
bash "${BOOTSTRAP_SCRIPT}"

if rclone listremotes | grep -Fxq "${DRIVE_REMOTE}:"; then
  log "Remote '${DRIVE_REMOTE}' is already configured."
else
  log "Remote '${DRIVE_REMOTE}' is not configured yet."
  if [[ "${RUN_RCLONE_CONFIG_IF_MISSING}" == "1" ]]; then
    echo
    echo "Next step: 'sudo rclone config'"
    echo "Create a Google Drive remote named '${DRIVE_REMOTE}'."
    echo
    if ask_yes_no "Open rclone config now?" "y"; then
      sudo rclone config
      echo
      log "Re-running bootstrap after rclone config"
      DRIVE_REMOTE="${DRIVE_REMOTE}" \
      DRIVE_PATH="${DRIVE_PATH}" \
      LOCAL_SYNC_ROOT="${LOCAL_SYNC_ROOT}" \
      SYNC_INTERVAL="${SYNC_INTERVAL}" \
      bash "${BOOTSTRAP_SCRIPT}"
    fi
  fi
fi

echo
log "Wizard complete"
echo "Useful commands:"
echo "  sudo /usr/local/bin/drive-sync-push"
echo "  systemctl status drive-sync-push.timer"
echo "  journalctl -u drive-sync-push.service -n 100 --no-pager"
