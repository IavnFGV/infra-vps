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

fix_webroot_permissions() {
  mkdir -p "${WEBROOT_DIR}/.well-known/acme-challenge"

  if [[ ! -w "${WEBROOT_DIR}" ]]; then
    echo "Fixing certbot webroot owner: ${WEBROOT_DIR}"
    sudo chown -R "$(id -u):$(id -g)" "${WEBROOT_DIR}"
  fi

  chmod -R u+rwX,go+rX "${WEBROOT_DIR}"
}

fix_cert_permissions() {
  if [[ -d "${ROOT_DIR}/certbot/conf/live/${DOMAIN}" ]]; then
    chmod -R u+rwX,g+rX,o-rwx "${ROOT_DIR}/certbot/conf/live/${DOMAIN}" || true
  fi
}

fix_webroot_permissions

docker compose run --rm --entrypoint certbot certbot certonly \
  --webroot \
  --webroot-path /var/www/certbot \
  --email "${EMAIL}" \
  --agree-tos \
  --no-eff-email \
  -d "${DOMAIN}"

fix_cert_permissions

echo "Certificate issued for ${DOMAIN}."