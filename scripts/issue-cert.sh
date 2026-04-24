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

docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --email "${EMAIL}" \
  --agree-tos \
  --no-eff-email \
  -d "${DOMAIN}"

# Fix permissions so deploy user can read certificates
if [[ -d "${ROOT_DIR}/certbot/conf/live/${DOMAIN}" ]]; then
    chmod -R u+rw,g+r,o-rwx "${ROOT_DIR}/certbot/conf/live/${DOMAIN}"
fi

echo "Certificate issued for ${DOMAIN}."
