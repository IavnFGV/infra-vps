#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

./scripts/init-edge-network.sh "${EDGE_NETWORK:-edge}"
docker compose up -d
./scripts/check-nginx.sh

echo "Infra stack is up."
