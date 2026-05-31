#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

DOCKGE_STACKS_DIR="${DOCKGE_STACKS_DIR:-/opt/dockge/stacks}"
DOCKGE_DATA_DIR="${DOCKGE_DATA_DIR:-/opt/dockge/data}"
SERVICES_ROOT="${SERVICES_ROOT:-/srv/services}"
STATIC_ROOT="${STATIC_ROOT:-/srv/service-static}"

mkdir -p "${DOCKGE_STACKS_DIR}"
mkdir -p "${DOCKGE_DATA_DIR}"
mkdir -p "${SERVICES_ROOT}"
mkdir -p "${STATIC_ROOT}"

echo "Node layout prepared:"
echo "  ${DOCKGE_STACKS_DIR}"
echo "  ${DOCKGE_DATA_DIR}"
echo "  ${SERVICES_ROOT}"
echo "  ${STATIC_ROOT}"
