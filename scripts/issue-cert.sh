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
  if [[ ! -d "${WEBROOT_DIR}" ]]; then
    mkdir -p "${WEBROOT_DIR}"
  fi

  if [[ ! -w "${WEBROOT_DIR}" ]]; then
    echo "Fixing certbot webroot permissions: ${WEBROOT_DIR}"
    sudo chown -R "$(id -u):$(id -g)" "${WEBROOT_DIR}"
  fi

  mkdir -p "${WEBROOT_DIR}/.well-known/acme-challenge"
  chmod -R u+rwX,go+rX "${WEBROOT_DIR}"
}

fix_cert_permissions() {
  local live_dir="${ROOT_DIR}/certbot/conf/live/${DOMAIN}"

  if [[ -d "${live_dir}" ]]; then
    chmod -R u+rwX,g+rX,o-rwx "${live_dir}" 2>/dev/null || true
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