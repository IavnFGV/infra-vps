#!/usr/bin/env bash
set -euo pipefail

# Script to create the master key if it doesn't exist.
# Default location: /opt/infra-secrets/master.key

DEFAULT_KEY_FILE="/opt/infra-secrets/master.key"
KEY_FILE="${INFRA_MASTER_KEY_FILE:-${DEFAULT_KEY_FILE}}"

KEY_DIR=$(dirname "${KEY_FILE}")

# Create directory if it doesn't exist
if [[ ! -d "${KEY_DIR}" ]]; then
    mkdir -p "${KEY_DIR}"
    chmod 700 "${KEY_DIR}"
fi

# Create key if it doesn't exist
if [[ -f "${KEY_FILE}" ]]; then
    echo "Master key already exists at ${KEY_FILE}. Not overwriting."
    exit 0
fi

# Generate a random 32-byte base64 key
openssl rand -base64 32 > "${KEY_FILE}"
sudo chown -R deploy:deploy /opt/infra-secrets
sudo chmod 700 /opt/infra-secrets
chmod 600 "${KEY_FILE}"

echo "Master key created at ${KEY_FILE}"
