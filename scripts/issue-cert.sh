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

mkdir -p "${WEBROOT_DIR}/.well-known/acme-challenge"
chmod -R u+rwX,go+rX "${WEBROOT_DIR}"

docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --email "${EMAIL}" \
  --agree-tos \
  --no-eff-email \
  --non-interactive \
  --keep-until-expiring \
  -d "${DOMAIN}"

echo "Certificate issued for ${DOMAIN}."