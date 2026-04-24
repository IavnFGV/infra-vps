#!/usr/bin/env bash
set -euo pipefail

# Script to decrypt an encrypted value using the master key.
# Usage: ./scripts/decrypt-value.sh <encrypted-value>
# Example: ./scripts/decrypt-value.sh "enc:U2FsdGVkX1+..."

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <encrypted-value>" >&2
    exit 1
fi

ENCRYPTED="$1"

# Default key file location
DEFAULT_KEY_FILE="${HOME}/.infra-vps-master.key"
KEY_FILE="${INFRA_MASTER_KEY_FILE:-${DEFAULT_KEY_FILE}}"

if [[ ! -f "${KEY_FILE}" ]]; then
    echo "Error: Master key file not found at ${KEY_FILE}" >&2
    echo "Please ensure the master key exists or set INFRA_MASTER_KEY_FILE." >&2
    exit 1
fi

if [[ "${ENCRYPTED}" == enc:* ]]; then
    CIPHERTEXT="${ENCRYPTED#enc:}"
    echo "${CIPHERTEXT}" | openssl enc -d -aes-256-cbc -pbkdf2 -salt -base64 -A -pass "file:${KEY_FILE}"
else
    echo "${ENCRYPTED}"
fi