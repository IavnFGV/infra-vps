#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <domain> <email>"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

DOMAIN="$1"
EMAIL="$2"
WEBROOT_DIR="${ROOT_DIR}/certbot/www"

mkdir -p \
  "${ROOT_DIR}/certbot/www/.well-known/acme-challenge" \
  "${ROOT_DIR}/certbot/work" \
  "${ROOT_DIR}/certbot/logs" \
  "${ROOT_DIR}/certbot/conf"

chmod -R u+rwX,go+rX "${ROOT_DIR}/certbot/www"
chmod -R u+rwX,go-rwx "${ROOT_DIR}/certbot/work" "${ROOT_DIR}/certbot/logs" "${ROOT_DIR}/certbot/conf"

docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --config-dir /etc/letsencrypt \
  --work-dir /var/www/certbot-work \
  --logs-dir /var/www/certbot-logs \
  --email "${EMAIL}" \
  --agree-tos \
  --no-eff-email \
  --non-interactive \
  --keep-until-expiring \
  -d "${DOMAIN}"

echo "Certificate issued for ${DOMAIN}."