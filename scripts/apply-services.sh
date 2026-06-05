#!/usr/bin/env bash
set -euo pipefail

# Applies services from registry/services/*.env.
# Generates nginx configs, issues certificates when needed, and reloads nginx.
# Application lifecycle is managed outside this repo, for example by Dockge.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

LOG_FILE="${ROOT_DIR}/logs/apply-services.log"
NGINX_SITES_DIR="${ROOT_DIR}/nginx/sites"
SERVICES_DIR="${ROOT_DIR}/registry/services"
HOST_SERVICES_DIR="${HOST_SERVICES_DIR:-/srv/service-registry.d}"
DEFAULT_KEY_FILE="/opt/infra-secrets/master.key"
KEY_FILE="${INFRA_MASTER_KEY_FILE:-${DEFAULT_KEY_FILE}}"

mkdir -p "$(dirname "${LOG_FILE}")"
mkdir -p "${NGINX_SITES_DIR}"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "${LOG_FILE}"
}

registry_service_files() {
    local dir

    for dir in "${SERVICES_DIR}" "${HOST_SERVICES_DIR}"; do
        [[ -d "${dir}" ]] || continue

        local service_file
        for service_file in "${dir}"/*.env; do
            [[ -f "${service_file}" ]] || continue
            printf '%s\n' "${service_file}"
        done
    done
}

service_exists_in_registry() {
    local service_name="$1"

    [[ -f "${SERVICES_DIR}/${service_name}.env" ]] && return 0
    [[ -f "${HOST_SERVICES_DIR}/${service_name}.env" ]] && return 0
    return 1
}

decrypt_value() {
    local value="$1"

    if [[ -z "${value}" ]]; then
        printf ""
        return 0
    fi

    if [[ "${value}" == enc:* ]]; then
        INFRA_MASTER_KEY_FILE="${KEY_FILE}" ./scripts/decrypt-value.sh "${value}"
    else
        printf "%s" "${value}"
    fi
}

require_var() {
    local var_name="$1"
    local service_name="$2"

    if [[ -z "${!var_name:-}" ]]; then
        log "ERROR: ${var_name} is required for ${service_name}"
        exit 1
    fi
}

normalize_dir_with_trailing_slash() {
    local dir="$1"

    dir="${dir%/}/"

    printf "%s" "${dir}"
}

generate_secret_location() {
    local static_secret="$1"
    local static_dir="$2"

    local secret_location="/static/${static_secret}"

    cat <<EOF

    location = ${secret_location} {
        return 301 ${secret_location}/;
    }

    location ${secret_location}/ {
        alias ${static_dir};
        autoindex off;
        try_files \$uri \$uri/ =404;
    }
EOF
}

generate_http_config() {
    local domain="$1"
    local upstream_host="$2"
    local upstream_port="$3"
    local static_secret="$4"
    local static_dir="$5"

    cat <<EOF
server {
    listen 80;
    server_name ${domain};

    include /etc/nginx/snippets/acme.conf;

    location / {
        proxy_pass http://${upstream_host}:${upstream_port};
        include /etc/nginx/snippets/proxy.conf;
    }
EOF

    if [[ -n "${static_secret}" ]]; then
        generate_secret_location \
            "${static_secret}" \
            "${static_dir}"
    fi

    cat <<EOF
}
EOF
}

generate_https_config() {
    local domain="$1"
    local upstream_host="$2"
    local upstream_port="$3"
    local static_secret="$4"
    local static_dir="$5"

    cat <<EOF
server {
    listen 80;
    server_name ${domain};

    include /etc/nginx/snippets/acme.conf;

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;

    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;

    include /etc/nginx/snippets/ssl.conf;

    location / {
        proxy_pass http://${upstream_host}:${upstream_port};
        include /etc/nginx/snippets/proxy.conf;
    }
EOF

    if [[ -n "${static_secret}" ]]; then
        generate_secret_location \
            "${static_secret}" \
            "${static_dir}"
    fi

    cat <<EOF
}
EOF
}

validate_service() {
    local service_file_name="$1"

    require_var "SERVICE_NAME" "${service_file_name}"
    require_var "DOMAIN" "${SERVICE_NAME}"
    require_var "UPSTREAM_HOST" "${SERVICE_NAME}"
    require_var "UPSTREAM_PORT" "${SERVICE_NAME}"

    if [[ "${ENABLE_HTTPS:-false}" == "true" ]]; then
        require_var "LETSENCRYPT_EMAIL" "${SERVICE_NAME}"
    fi

    require_var "STATIC_SECRET" "${SERVICE_NAME}"
}

issue_certificate_if_needed() {
    local domain="$1"
    local email="$2"
    local cert_path="${ROOT_DIR}/certbot/conf/live/${domain}/fullchain.pem"

    if [[ -f "${cert_path}" ]]; then
        log "Certificate already exists for ${domain}"
        return 0
    fi

    log "Issuing certificate for ${domain}"

    if ! ./scripts/issue-cert.sh "${domain}" "${email}" 2>&1 | tee -a "${LOG_FILE}"; then
        log "ERROR: certificate issuance command failed for ${domain}"
        exit 1
    fi

    if [[ ! -f "${cert_path}" ]]; then
        log "ERROR: certificate file was not created: ${cert_path}"
        exit 1
    fi

    log "Certificate issued for ${domain}"
}

apply_service() {
    local service_file="$1"
    local service_file_name
    service_file_name="$(basename "${service_file}" .env)"

    unset SERVICE_NAME DOMAIN UPSTREAM_HOST UPSTREAM_PORT
    unset ENABLE_HTTPS LETSENCRYPT_EMAIL
    unset STATIC_SECRET STATIC_DIR

    log "Processing service file: ${service_file}"

    # shellcheck disable=SC1090
    source "${service_file}"

    LETSENCRYPT_EMAIL="$(decrypt_value "${LETSENCRYPT_EMAIL:-}")"
    STATIC_SECRET="$(decrypt_value "${STATIC_SECRET:-}")"

    ENABLE_HTTPS="${ENABLE_HTTPS:-false}"
    STATIC_DIR="$(normalize_dir_with_trailing_slash "/srv/service-static/${SERVICE_NAME}")"

    validate_service "${service_file_name}"

    local config_file="${NGINX_SITES_DIR}/${SERVICE_NAME}.conf"

    log "Generating HTTP config for ${SERVICE_NAME}"
    generate_http_config \
        "${DOMAIN}" \
        "${UPSTREAM_HOST}" \
        "${UPSTREAM_PORT}" \
        "${STATIC_SECRET:-}" \
        "${STATIC_DIR}" \
        > "${config_file}"

    if [[ "${ENABLE_HTTPS}" == "true" ]]; then
        log "Testing nginx config before certificate issue"
        docker compose exec nginx nginx -t

        log "Reloading nginx with HTTP config for ACME challenge"
        docker compose exec nginx nginx -s reload

        issue_certificate_if_needed "${DOMAIN}" "${LETSENCRYPT_EMAIL}"

        log "Generating HTTPS config for ${SERVICE_NAME}"
        generate_https_config \
            "${DOMAIN}" \
            "${UPSTREAM_HOST}" \
            "${UPSTREAM_PORT}" \
            "${STATIC_SECRET:-}" \
            "${STATIC_DIR}" \
            > "${config_file}"
    fi

    log "Config generated for ${SERVICE_NAME}: ${config_file}"
}

log "Starting apply-services.sh"

if [[ ! -d "${SERVICES_DIR}" && ! -d "${HOST_SERVICES_DIR}" ]]; then
    log "No services registry directories found: ${SERVICES_DIR} ${HOST_SERVICES_DIR}"
    exit 0
fi

found_services=false

while IFS= read -r service_file; do
    found_services=true
    apply_service "${service_file}"
done < <(registry_service_files)

if [[ "${found_services}" == "false" ]]; then
    log "No service registry files found in ${SERVICES_DIR} or ${HOST_SERVICES_DIR}"
fi

# Remove configs for services no longer in registry.
# This repo owns ingress state only; it does not stop application stacks.
log "Checking for removed services"
for config_file in "${NGINX_SITES_DIR}"/*.conf; do
    if [[ ! -f "${config_file}" ]]; then
        continue
    fi

    config_name=$(basename "${config_file}" .conf)
    
    # Skip default configs
    if [[ "${config_name}" == "_default" ]]; then
        continue
    fi
    
    # Check if service still exists in registry
    if ! service_exists_in_registry "${config_name}"; then
        cert_domain="$(awk '/server_name / {print $2}' "${config_file}" | head -n1 | tr -d ';' || true)"
        log "Removing config for removed service: ${config_name}"
        rm -f "${config_file}"

        # Optionally remove certificate state if it exists.
        # Certificate directories are keyed by domain, not service name, so
        # automatic cleanup is only best-effort based on the generated config.
        cert_dir="${ROOT_DIR}/certbot/conf/live/${cert_domain}"
        if [[ -z "${cert_domain}" ]]; then
            log "Warning: could not determine certificate domain for ${config_name}; skipping certificate cleanup"
            continue
        fi

        if [[ -d "${cert_dir}" ]]; then
            log "Removing certificate for removed service domain: ${cert_domain}"
            rm -rf "${cert_dir}"
        fi
    fi
done

log "Final nginx config test"
docker compose exec nginx nginx -t

log "Final nginx reload"
docker compose exec nginx nginx -s reload

log "apply-services.sh completed successfully"
