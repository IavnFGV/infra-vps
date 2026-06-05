#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

CONFIG_FILE="${CONFIG_FILE:-/etc/default/infra-vps-service-registration}"
NODE_CONFIG_FILE="${NODE_CONFIG_FILE:-/etc/default/infra-vps-node}"
HOST_SERVICE_REGISTRY_DIR="${HOST_SERVICE_REGISTRY_DIR:-/srv/service-registry.d}"
REGISTER_TASKS_COMMAND="${REGISTER_TASKS_COMMAND:-/usr/local/bin/infra-vps-register-service-scheduled-tasks}"
APPLY_SERVICES_SCRIPT="${APPLY_SERVICES_SCRIPT:-}"
DECRYPT_SCRIPT="${DECRYPT_SCRIPT:-}"
INFRA_MASTER_KEY_FILE="${INFRA_MASTER_KEY_FILE:-/opt/infra-secrets/master.key}"
NODE_OWNER="${NODE_OWNER:-deploy}"
SKIP_TASKS=false

if [[ -f "${CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${CONFIG_FILE}"
fi

if [[ -f "${NODE_CONFIG_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${NODE_CONFIG_FILE}"
fi

usage() {
  cat <<EOF
Usage:
  infra-vps-register-service --card /path/to/service.env [--service-dir /path/to/service] [--tasks-dir /path/to/tasks] [--runtime-env /path/to/infra-runtime.env] [--skip-tasks]

Required:
  --card         Path to the service registration card

Optional:
  --service-dir  Service checkout directory on the server
  --tasks-dir    Service scheduled-tasks directory
  --runtime-env  Generated runtime env file for the service
  --skip-tasks   Do not register service-owned scheduled tasks
EOF
}

CARD_PATH=""
SERVICE_DIR=""
TASKS_DIR=""
RUNTIME_ENV_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --card)
      CARD_PATH="${2:-}"
      shift 2
      ;;
    --service-dir)
      SERVICE_DIR="${2:-}"
      shift 2
      ;;
    --tasks-dir)
      TASKS_DIR="${2:-}"
      shift 2
      ;;
    --runtime-env)
      RUNTIME_ENV_FILE="${2:-}"
      shift 2
      ;;
    --skip-tasks)
      SKIP_TASKS=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${CARD_PATH}" ]]; then
  echo "--card is required"
  usage
  exit 1
fi

CARD_PATH="$(realpath "${CARD_PATH}")"
CARD_DIR="$(dirname "${CARD_PATH}")"

if [[ ! -f "${CARD_PATH}" ]]; then
  echo "Service card not found: ${CARD_PATH}"
  exit 1
fi

if [[ -z "${SERVICE_DIR}" ]]; then
  SERVICE_DIR="${CARD_DIR}"
fi

SERVICE_DIR="$(realpath "${SERVICE_DIR}")"

resolve_relative_path() {
  local maybe_relative="$1"
  local base_dir="$2"

  if [[ -z "${maybe_relative}" ]]; then
    printf ""
    return 0
  fi

  if [[ "${maybe_relative}" = /* ]]; then
    printf "%s" "${maybe_relative}"
  else
    printf "%s/%s" "${base_dir}" "${maybe_relative}"
  fi
}

unset SERVICE_NAME DOMAIN UPSTREAM_HOST UPSTREAM_PORT ENABLE_HTTPS LETSENCRYPT_EMAIL STATIC_SECRET
unset SERVICE_TASKS_SOURCE_DIR DOMAIN_TEMPLATE
# shellcheck disable=SC1090
source "${CARD_PATH}"

require_var() {
  local var_name="$1"

  if [[ -z "${!var_name:-}" ]]; then
    echo "${var_name} is required in ${CARD_PATH}"
    exit 1
  fi
}

require_var "SERVICE_NAME"
require_var "UPSTREAM_HOST"
require_var "UPSTREAM_PORT"
require_var "STATIC_SECRET"

detect_server_public_ip() {
  local detected_ip=""

  detected_ip="$(curl -4 -fsSL ifconfig.me 2>/dev/null || true)"
  if [[ -n "${detected_ip}" ]]; then
    printf "%s" "${detected_ip}"
    return 0
  fi

  detected_ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i=1; i<=NF; i++) if ($i == \"src\") {print $(i+1); exit}}' || true)"
  printf "%s" "${detected_ip}"
}

render_domain_template() {
  local template="$1"
  local rendered=""

  rendered="${template//\$\{SERVER_PUBLIC_IP_DASHED\}/${SERVER_PUBLIC_IP_DASHED}}"
  rendered="${rendered//\$\{SERVER_PUBLIC_IP\}/${SERVER_PUBLIC_IP}}"
  printf "%s" "${rendered}"
}

SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-$(detect_server_public_ip)}"
SERVER_PUBLIC_IP_DASHED="${SERVER_PUBLIC_IP_DASHED:-${SERVER_PUBLIC_IP//./-}}"

if [[ -n "${DOMAIN_TEMPLATE:-}" ]]; then
  if [[ -z "${SERVER_PUBLIC_IP}" ]]; then
    echo "Could not determine SERVER_PUBLIC_IP for DOMAIN_TEMPLATE in ${CARD_PATH}"
    exit 1
  fi
  DOMAIN="$(render_domain_template "${DOMAIN_TEMPLATE}")"
fi

require_var "DOMAIN"

ENABLE_HTTPS="${ENABLE_HTTPS:-false}"
SCHEME="http"
if [[ "${ENABLE_HTTPS}" == "true" ]]; then
  require_var "LETSENCRYPT_EMAIL"
  SCHEME="https"
fi

if [[ -z "${TASKS_DIR}" && -n "${SERVICE_TASKS_SOURCE_DIR:-}" ]]; then
  TASKS_DIR="$(resolve_relative_path "${SERVICE_TASKS_SOURCE_DIR}" "${SERVICE_DIR}")"
fi

if [[ -z "${TASKS_DIR}" ]]; then
  TASKS_DIR="${SERVICE_DIR}/scheduled-tasks"
fi

if [[ -z "${RUNTIME_ENV_FILE}" ]]; then
  RUNTIME_ENV_FILE="/srv/services/${SERVICE_NAME}/infra-runtime.env"
fi

if ! id -u "${NODE_OWNER}" >/dev/null 2>&1; then
  echo "User not found: ${NODE_OWNER}"
  exit 1
fi

mkdir -p "${HOST_SERVICE_REGISTRY_DIR}"
install -m 0644 "${CARD_PATH}" "${HOST_SERVICE_REGISTRY_DIR}/${SERVICE_NAME}.env"
chown "${NODE_OWNER}:${NODE_OWNER}" "${HOST_SERVICE_REGISTRY_DIR}/${SERVICE_NAME}.env" || true

if [[ -n "${APPLY_SERVICES_SCRIPT}" ]]; then
  (
    cd "$(dirname "${APPLY_SERVICES_SCRIPT}")/.."
    HOST_SERVICES_DIR="${HOST_SERVICE_REGISTRY_DIR}" bash "${APPLY_SERVICES_SCRIPT}"
  )
fi

decrypted_static_secret="${STATIC_SECRET}"
if [[ "${STATIC_SECRET}" == enc:* ]]; then
  if [[ -z "${DECRYPT_SCRIPT}" ]]; then
    echo "DECRYPT_SCRIPT is not configured"
    exit 1
  fi
  decrypted_static_secret="$(INFRA_MASTER_KEY_FILE="${INFRA_MASTER_KEY_FILE}" "${DECRYPT_SCRIPT}" "${STATIC_SECRET}")"
fi

mkdir -p "$(dirname "${RUNTIME_ENV_FILE}")"
cat > "${RUNTIME_ENV_FILE}" <<EOF
INFRA_SERVICE_NAME=${SERVICE_NAME}
INFRA_DOMAIN=${DOMAIN}
INFRA_PUBLIC_BASE_URL=${SCHEME}://${DOMAIN}
INFRA_STATIC_BASE_URL=${SCHEME}://${DOMAIN}/static/${decrypted_static_secret}
EOF
chmod 0644 "${RUNTIME_ENV_FILE}"
chown "${NODE_OWNER}:${NODE_OWNER}" "${RUNTIME_ENV_FILE}" || true

if [[ "${SKIP_TASKS}" == "false" && -d "${TASKS_DIR}" ]]; then
  if [[ ! -x "${REGISTER_TASKS_COMMAND}" ]]; then
    echo "Register tasks command is missing or not executable: ${REGISTER_TASKS_COMMAND}"
    exit 1
  fi

  SERVICE_NAME="${SERVICE_NAME}" \
    SERVICE_DIR="${SERVICE_DIR}" \
    SERVICE_TASKS_SOURCE_DIR="${TASKS_DIR}" \
    "${REGISTER_TASKS_COMMAND}"
elif [[ "${SKIP_TASKS}" == "false" ]]; then
  echo "No scheduled tasks directory found for ${SERVICE_NAME}: ${TASKS_DIR}"
fi

echo "Service registration updated for ${SERVICE_NAME}"
echo "Host registry: ${HOST_SERVICE_REGISTRY_DIR}/${SERVICE_NAME}.env"
echo "Runtime env: ${RUNTIME_ENV_FILE}"
