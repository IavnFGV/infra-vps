#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 4 ]]; then
  echo "Usage: $0 <site_name> <domain> <upstream_host> <upstream_port> [static_secret] [static_dir_name]"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SITE_NAME="$1"
DOMAIN="$2"
UPSTREAM_HOST="$3"
UPSTREAM_PORT="$4"
STATIC_SECRET="${5:-}"
STATIC_DIR_NAME="${6:-${SITE_NAME}}"
SITE_FILE="${ROOT_DIR}/nginx/sites/${SITE_NAME}.conf"

STATIC_BLOCK=""
if [[ -n "${STATIC_SECRET}" ]]; then
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

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

${STATIC_BLOCK}    location / {
        proxy_pass http://${UPSTREAM_HOST}:${UPSTREAM_PORT};
        include /etc/nginx/snippets/proxy.conf;
    }
}
EOF

echo "HTTPS config written to ${SITE_FILE}"
echo "Run: ./scripts/reload-nginx.sh"
