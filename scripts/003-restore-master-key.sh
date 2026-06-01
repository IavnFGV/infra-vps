#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0 <source-master-key-file>"
  exit 1
fi

if [[ $# -ne 1 ]]; then
  echo "Usage: sudo bash $0 <source-master-key-file>"
  exit 1
fi

SOURCE_FILE="$1"
TARGET_DIR="${INFRA_SECRETS_DIR:-/opt/infra-secrets}"
TARGET_FILE="${INFRA_MASTER_KEY_FILE:-${TARGET_DIR}/master.key}"
TARGET_OWNER="${INFRA_SECRETS_OWNER:-deploy:deploy}"

if [[ ! -f "${SOURCE_FILE}" ]]; then
  echo "Source master key file not found: ${SOURCE_FILE}"
  exit 1
fi

mkdir -p "${TARGET_DIR}"
chmod 700 "${TARGET_DIR}"

if [[ "$(realpath "${SOURCE_FILE}")" != "$(realpath -m "${TARGET_FILE}")" ]]; then
  cp "${SOURCE_FILE}" "${TARGET_FILE}"
fi

chown "${TARGET_OWNER}" "${TARGET_FILE}"
chmod 600 "${TARGET_FILE}"

echo "Master key restored to ${TARGET_FILE}"
