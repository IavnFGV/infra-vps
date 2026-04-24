#!/usr/bin/env bash
set -euo pipefail

# Script to apply services from registry/services/*.env
# Generates nginx configs, issues certificates, and reloads nginx.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

LOG_FILE="${ROOT_DIR}/logs/apply-services.log"
NGINX_SITES_DIR="${ROOT_DIR}/nginx/sites"
SERVICES_DIR="${ROOT_DIR}/registry/services"
DEFAULT_KEY_FILE="/opt/infra-secrets/master.key"
KEY_FILE="${INFRA_MASTER_KEY_FILE:-${DEFAULT_KEY_FILE}}"

# Ensure log directory exists
mkdir -p "$(dirname "${LOG_FILE}")"

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

# Decrypt function (no logging to avoid stdout pollution)
decrypt_value() {
    local encrypted="$1"

    if [[ -z "${encrypted}" ]]; then
        echo ""
        return
    fi

    if [[ "${encrypted}" == enc:* ]]; then
        ./scripts/decrypt-value.sh "${encrypted}"
    else
        echo "${encrypted}"
    fi
}

# Validate required variables
validate_service() {
    local service_name="$1"
    if [[ -z "${SERVICE_NAME:-}" ]]; then
        log "Error: SERVICE_NAME is required for ${service_name}"
        exit 1
    fi
    if [[ -z "${DOMAIN:-}" ]]; then
        log "Error: DOMAIN is required for ${service_name}"
        exit 1
    fi
    if [[ -z "${UPSTREAM_HOST:-}" ]]; then
        log "Error: UPSTREAM_HOST is required for ${service_name}"
        exit 1
    fi
    if [[ -z "${UPSTREAM_PORT:-}" ]]; then
        log "Error: UPSTREAM_PORT is required for ${service_name}"
        exit 1
    fi
    if [[ "${ENABLE_HTTPS:-false}" == "true" && -z "${LETSENCRYPT_EMAIL:-}" ]]; then
        log "Error: LETSENCRYPT_EMAIL is required when ENABLE_HTTPS=true for ${service_name}"
        exit 1
    fi
    if [[ "${STATIC_ENABLED:-false}" == "true" && -z "${STATIC_SECRET:-}" ]]; then
        log "Error: STATIC_SECRET is required when STATIC_ENABLED=true for ${service_name}"
        exit 1
    fi
}

# Generate nginx config for HTTP
generate_http_config() {
    local service_name="$1"
    local domain="$2"
    local upstream_host="$3"
    local upstream_port="$4"
    local static_enabled="$5"
    local static_public_prefix="$6"
    local static_secret="$7"
    local static_dir="$8"

    cat <<EOF
server {
    listen 80;
    server_name ${domain};

    location / {
        proxy_pass http://${upstream_host}:${upstream_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
EOF

    if [[ "${static_enabled}" == "true" ]]; then
        cat <<EOF

    location ${static_public_prefix}/${static_secret}/ {
        alias ${static_dir}/;
        autoindex off;
        try_files \$uri \$uri/ =404;
    }
EOF
    fi

    cat <<EOF
}
EOF
}

# Generate nginx config for HTTPS
generate_https_config() {
    local service_name="$1"
    local domain="$2"
    local upstream_host="$3"
    local upstream_port="$4"
    local static_enabled="$5"
    local static_public_prefix="$6"
    local static_secret="$7"
    local static_dir="$8"

    cat <<EOF
server {
    listen 80;
    server_name ${domain};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    include /etc/nginx/snippets/ssl.conf;

    location / {
        proxy_pass http://${upstream_host}:${upstream_port};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
EOF

    if [[ "${static_enabled}" == "true" ]]; then
        cat <<EOF

    location ${static_public_prefix}/${static_secret}/ {
        alias ${static_dir}/;
        autoindex off;
        try_files \$uri \$uri/ =404;
    }
EOF
    fi

    cat <<EOF
}
EOF
}

# Issue certificate if not exists
issue_certificate() {
    local domain="$1"
    local email="$2"

    local cert_path="${ROOT_DIR}/certbot/conf/live/${domain}/fullchain.pem"
    if [[ -f "${cert_path}" ]]; then
        log "Certificate already exists for ${domain} at ${cert_path}"
        return
    fi

    log "Issuing certificate for ${domain}"
    docker compose run --rm --entrypoint certbot certbot certonly \
        --webroot \
        --webroot-path /var/www/certbot \
        --email "${email}" \
        --agree-tos \
        --no-eff-email \
        -d "${domain}"

    if [[ $? -eq 0 ]]; then
        log "Certificate successfully issued for ${domain}, saved to ${cert_path}"
    else
        log "Certificate issuance failed for ${domain}"
        exit 1
    fi
}

log "Starting apply-services.sh"

# Ensure nginx sites directory exists
mkdir -p "${NGINX_SITES_DIR}"

# Process each service
for service_file in "${SERVICES_DIR}"/*.env; do
    if [[ ! -f "${service_file}" ]]; then
        continue
    fi

    service_name=$(basename "${service_file}" .env)
    log "Processing service: ${service_name}"

    # Source the env file
    # shellcheck disable=SC1090
    source "${service_file}"

    # Decrypt values with logging
    log "Decrypting LETSENCRYPT_EMAIL"
    LETSENCRYPT_EMAIL=$(decrypt_value "${LETSENCRYPT_EMAIL:-}")
    if [[ -n "${LETSENCRYPT_EMAIL}" ]]; then
        log "LETSENCRYPT_EMAIL: decrypted successfully"
    fi

    log "Decrypting STATIC_SECRET"
    STATIC_SECRET=$(decrypt_value "${STATIC_SECRET:-}")
    if [[ -n "${STATIC_SECRET}" ]]; then
        log "STATIC_SECRET: decrypted successfully"
    fi

    # Validate
    validate_service "${service_name}"

    # Generate config file path
    config_file="${NGINX_SITES_DIR}/${SERVICE_NAME}.conf"

    if [[ "${ENABLE_HTTPS:-false}" == "true" ]]; then
        # First, generate HTTP config
        log "Generating HTTP config for ${SERVICE_NAME}"
        generate_http_config "${SERVICE_NAME}" "${DOMAIN}" "${UPSTREAM_HOST}" "${UPSTREAM_PORT}" "${STATIC_ENABLED:-false}" "${STATIC_PUBLIC_PREFIX:-/static}" "${STATIC_SECRET}" "${STATIC_DIR}" > "${config_file}"

        # Test and reload
        log "Testing nginx config"
        docker compose exec nginx nginx -t
        log "Reloading nginx"
        docker compose exec nginx nginx -s reload

        # Issue certificate
        issue_certificate "${DOMAIN}" "${LETSENCRYPT_EMAIL}"

        # Now generate HTTPS config
        log "Generating HTTPS config for ${SERVICE_NAME}"
        generate_https_config "${SERVICE_NAME}" "${DOMAIN}" "${UPSTREAM_HOST}" "${UPSTREAM_PORT}" "${STATIC_ENABLED:-false}" "${STATIC_PUBLIC_PREFIX:-/static}" "${STATIC_SECRET}" "${STATIC_DIR}" > "${config_file}"
    else
        # Generate HTTP only config
        log "Generating HTTP config for ${SERVICE_NAME}"
        generate_http_config "${SERVICE_NAME}" "${DOMAIN}" "${UPSTREAM_HOST}" "${UPSTREAM_PORT}" "${STATIC_ENABLED:-false}" "${STATIC_PUBLIC_PREFIX:-/static}" "${STATIC_SECRET}" "${STATIC_DIR}" > "${config_file}"
    fi

    log "Config generated for ${SERVICE_NAME}"
done

# Final test and reload
log "Final nginx config test"
docker compose exec nginx nginx -t
log "Final nginx reload"
docker compose exec nginx nginx -s reload

log "apply-services.sh completed successfully"