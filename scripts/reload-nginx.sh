#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload

echo "Nginx configuration is valid and has been reloaded."
