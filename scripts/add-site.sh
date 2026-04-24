#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<USAGE
Usage:
  $0 <site_name> <domain> <upstream_host> [upstream_port] [static_secret] [static_dir_name]

Examples:
  $0 bot1 bot1-203-0-113-10.nip.io bot1-app 8080
  $0 bot1 bot1-203-0-113-10.nip.io bot1-app 8080 4f9e8c2d7b6a1e0f3c9b8a7d6e5f4a3b bot1
USAGE
}

if [[ $# -lt 3 ]]; then
  usage
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_NAME="$1"
DOMAIN="$2"
UPSTREAM_HOST="$3"
UPSTREAM_PORT="${4:-8080}"
STATIC_SECRET="${5:-}"
STATIC_DIR_NAME="${6:-${SITE_NAME}}"
SITE_FILE="${ROOT_DIR}/nginx/sites/${SITE_NAME}.conf"
STATIC_HOST_DIR="${ROOT_DIR}/data/bot-static/${STATIC_DIR_NAME}"

STATIC_BLOCK=""
if [[ -n "${STATIC_SECRET}" ]]; then
  mkdir -p "${STATIC_HOST_DIR}"
  STATIC_BLOCK=$(cat <<BLOCK
    location /__static_${STATIC_SECRET}__/ {
        alias /srv/bot-static/${STATIC_DIR_NAME}/;
        autoindex off;
        expires 7d;
        add_header Cache-Control "public, max-age=604800";
        try_files \$uri \$uri/ =404;
    }

BLOCK
)
fi

cat > "${SITE_FILE}" <<EOF
server {
    listen 80;
    server_name ${DOMAIN};

    include /etc/nginx/snippets/acme.conf;

${STATIC_BLOCK}    location / {
        proxy_pass http://${UPSTREAM_HOST}:${UPSTREAM_PORT};
        include /etc/nginx/snippets/proxy.conf;
    }
}
EOF

echo "Created ${SITE_FILE}"
if [[ -n "${STATIC_SECRET}" ]]; then
  echo "Static directory created: ${STATIC_HOST_DIR}"
  echo "Secret static prefix: /__static_${STATIC_SECRET}__/"
fi

echo "Next steps:"
echo "  1) ./scripts/reload-nginx.sh"
echo "  2) ./scripts/issue-cert.sh ${DOMAIN} <email>"
echo "  3) ./scripts/enable-https.sh ${SITE_NAME} ${DOMAIN} ${UPSTREAM_HOST} ${UPSTREAM_PORT} ${STATIC_SECRET} ${STATIC_DIR_NAME}"
