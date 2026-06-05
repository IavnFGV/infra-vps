#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

log() {
  printf '%s [cert-renew] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

log "Starting certificate renewal check"

docker compose run --rm --entrypoint certbot certbot renew \
  --webroot \
  --webroot-path /var/www/certbot \
  --config-dir /etc/letsencrypt \
  --work-dir /var/www/certbot-work \
  --logs-dir /var/www/certbot-logs

log "Renewal check complete; reloading nginx"
docker compose exec -T nginx nginx -t </dev/null
docker compose exec -T nginx nginx -s reload </dev/null
log "Nginx reloaded after renewal check"
