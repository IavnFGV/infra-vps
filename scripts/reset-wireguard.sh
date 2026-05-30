#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
if [[ -z "${SERVER_PUBLIC_IP}" ]]; then
  SERVER_PUBLIC_IP="$(curl -4 -fsSL ifconfig.me 2>/dev/null || true)"
fi

if [[ -z "${SERVER_PUBLIC_IP}" ]]; then
  echo "Could not detect public IP. Set SERVER_PUBLIC_IP explicitly."
  exit 1
fi

echo "Resetting WireGuard from scratch..."
FORCE=1 SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP}" bash "${SCRIPT_DIR}/setup-wireguard.sh"
