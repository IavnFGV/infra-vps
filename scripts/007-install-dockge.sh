#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

DOCKGE_DIR="${DOCKGE_DIR:-/opt/dockge}"
DOCKGE_STACKS_DIR="${DOCKGE_STACKS_DIR:-/opt/dockge/stacks}"
DOCKGE_DATA_DIR="${DOCKGE_DATA_DIR:-${DOCKGE_DIR}/data}"
DOCKGE_IMAGE="${DOCKGE_IMAGE:-louislam/dockge:1}"
DOCKGE_BIND_ADDRESS="${DOCKGE_BIND_ADDRESS:-127.0.0.1}"
DOCKGE_PORT="${DOCKGE_PORT:-5001}"
DOCKGE_USER="${DOCKGE_USER:-deploy}"
COMPOSE_FILE="${DOCKGE_DIR}/compose.yaml"

if ! id -u "${DOCKGE_USER}" >/dev/null 2>&1; then
  echo "User not found: ${DOCKGE_USER}"
  exit 1
fi

DOCKGE_UID="$(id -u "${DOCKGE_USER}")"
DOCKGE_GID="$(id -g "${DOCKGE_USER}")"

mkdir -p "${DOCKGE_DIR}"
mkdir -p "${DOCKGE_STACKS_DIR}"
mkdir -p "${DOCKGE_DATA_DIR}"

cat > "${COMPOSE_FILE}" <<EOF
services:
  dockge:
    image: ${DOCKGE_IMAGE}
    restart: unless-stopped
    ports:
      - ${DOCKGE_BIND_ADDRESS}:${DOCKGE_PORT}:5001
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${DOCKGE_DATA_DIR}:/app/data
      - ${DOCKGE_STACKS_DIR}:${DOCKGE_STACKS_DIR}
    environment:
      - DOCKGE_STACKS_DIR=${DOCKGE_STACKS_DIR}
      - PUID=${DOCKGE_UID}
      - PGID=${DOCKGE_GID}
EOF

chown -R "${DOCKGE_USER}:${DOCKGE_USER}" "${DOCKGE_DIR}"

(
  cd "${DOCKGE_DIR}"
  docker compose up -d
)

echo "Dockge installed."
echo "Compose file: ${COMPOSE_FILE}"
echo "Stacks dir: ${DOCKGE_STACKS_DIR}"
echo "Data dir: ${DOCKGE_DATA_DIR}"
echo "Listen address: ${DOCKGE_BIND_ADDRESS}:${DOCKGE_PORT}"
if [[ "${DOCKGE_BIND_ADDRESS}" == "127.0.0.1" ]]; then
  echo "Dockge is only reachable from the server itself by default."
fi
