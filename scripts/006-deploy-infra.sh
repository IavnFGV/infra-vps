#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

ENV_FILE="${ROOT_DIR}/.env"

resolve_certbot_runtime_ids() {
  local certbot_user="${CERTBOT_USER:-deploy}"

  if [[ -n "${CERTBOT_UID:-}" && -n "${CERTBOT_GID:-}" ]]; then
    return 0
  fi

  if id -u "${certbot_user}" >/dev/null 2>&1; then
    CERTBOT_UID="${CERTBOT_UID:-$(id -u "${certbot_user}")}"
    CERTBOT_GID="${CERTBOT_GID:-$(id -g "${certbot_user}")}"
    export CERTBOT_UID CERTBOT_GID
    return 0
  fi

  CERTBOT_UID="${CERTBOT_UID:-$(id -u)}"
  CERTBOT_GID="${CERTBOT_GID:-$(id -g)}"
  export CERTBOT_UID CERTBOT_GID
}

ensure_env_file() {
  if [[ -f "${ENV_FILE}" ]]; then
    return 0
  fi

  if [[ -f "${ROOT_DIR}/.env.example" ]]; then
    cp "${ROOT_DIR}/.env.example" "${ENV_FILE}"
    return 0
  fi

  touch "${ENV_FILE}"
}

set_env_value() {
  local key="$1"
  local value="$2"

  if grep -q "^${key}=" "${ENV_FILE}" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${ENV_FILE}"
  else
    printf '%s=%s\n' "${key}" "${value}" >> "${ENV_FILE}"
  fi
}

persist_certbot_runtime_ids() {
  ensure_env_file
  set_env_value "CERTBOT_UID" "${CERTBOT_UID}"
  set_env_value "CERTBOT_GID" "${CERTBOT_GID}"
}

resolve_certbot_runtime_ids
persist_certbot_runtime_ids

echo "Using certbot runtime UID:GID ${CERTBOT_UID}:${CERTBOT_GID}"
./scripts/init-edge-network.sh "${EDGE_NETWORK:-edge}"
docker compose config --quiet
docker compose pull nginx certbot
docker compose run --rm --no-deps nginx nginx -t
docker compose up -d nginx
./scripts/check-nginx.sh

echo "Infra stack is up."
