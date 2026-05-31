#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

NODE_OWNER="${NODE_OWNER:-deploy}"
DOCKGE_STACKS_DIR="${DOCKGE_STACKS_DIR:-/opt/dockge/stacks}"
DOCKGE_DATA_DIR="${DOCKGE_DATA_DIR:-/opt/dockge/data}"
SERVICES_ROOT="${SERVICES_ROOT:-/srv/services}"
STATIC_ROOT="${STATIC_ROOT:-/srv/service-static}"

if ! id -u "${NODE_OWNER}" >/dev/null 2>&1; then
  echo "User not found: ${NODE_OWNER}"
  exit 1
fi

mkdir -p "${DOCKGE_STACKS_DIR}"
mkdir -p "${DOCKGE_DATA_DIR}"
mkdir -p "${SERVICES_ROOT}"
mkdir -p "${STATIC_ROOT}"

chown -R "${NODE_OWNER}:${NODE_OWNER}" /opt/dockge
chown -R "${NODE_OWNER}:${NODE_OWNER}" "${SERVICES_ROOT}"
chown -R "${NODE_OWNER}:${NODE_OWNER}" "${STATIC_ROOT}"

echo "Node layout prepared:"
echo "  ${DOCKGE_STACKS_DIR}"
echo "  ${DOCKGE_DATA_DIR}"
echo "  ${SERVICES_ROOT}"
echo "  ${STATIC_ROOT}"
echo "Owner: ${NODE_OWNER}:${NODE_OWNER}"
