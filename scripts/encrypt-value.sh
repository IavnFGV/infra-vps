#!/usr/bin/env bash
set -euo pipefail

# Script to encrypt a plaintext value using the master key.
# Usage: ./scripts/encrypt-value.sh "plaintext-value"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <plaintext-value>" >&2
    exit 1
fi

PLAINTEXT="$1"

# Default key file location
DEFAULT_KEY_FILE="${HOME}/.infra-vps-master.key"
KEY_FILE="${INFRA_MASTER_KEY_FILE:-${DEFAULT_KEY_FILE}}"

if [[ ! -f "${KEY_FILE}" ]]; then
    echo "Error: Master key file not found at ${KEY_FILE}" >&2
    echo "Please ensure the master key exists or set INFRA_MASTER_KEY_FILE." >&2
    exit 1
fi

# Encrypt the plaintext and output in enc:<ciphertext> format
CIPHERTEXT=$(echo -n "${PLAINTEXT}" | openssl enc -aes-256-cbc -pbkdf2 -salt -base64 -A -pass "file:${KEY_FILE}")
echo "enc:${CIPHERTEXT}"