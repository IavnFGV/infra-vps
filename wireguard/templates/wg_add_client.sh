#!/usr/bin/env bash
set -euo pipefail

WG_DIR="${WG_DIR:-/etc/wireguard}"
SERVER_CONF="${SERVER_CONF:-${WG_DIR}/wg0.conf}"
CLIENTS_DIR="${CLIENTS_DIR:-${WG_DIR}/clients}"
META_FILE="${META_FILE:-${WG_DIR}/.server-meta}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root."
  exit 1
fi

if [[ ! -f "${SERVER_CONF}" ]]; then
  echo "WireGuard server config not found: ${SERVER_CONF}"
  exit 1
fi

if [[ ! -f "${META_FILE}" ]]; then
  echo "WireGuard metadata not found: ${META_FILE}"
  exit 1
fi

# shellcheck disable=SC1090
source "${META_FILE}"

WG_IFACE="${WG_IFACE:-wg0}"
VPN_SUBNET="${VPN_SUBNET:-10.0.0.0/24}"
WG_PORT="${WG_PORT:-51820}"
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-}"
CLIENT_DNS="${CLIENT_DNS:-8.8.8.8, 1.1.1.1}"

if [[ -z "${SERVER_PUBLIC_IP}" ]]; then
  echo "SERVER_PUBLIC_IP is empty in ${META_FILE}"
  exit 1
fi

mkdir -p "${CLIENTS_DIR}"

read -r -p "Client name: " CLIENT_NAME
if [[ -z "${CLIENT_NAME}" ]]; then
  echo "Client name is required."
  exit 1
fi

USED_IPS="$(
  grep '^AllowedIPs = ' "${SERVER_CONF}" 2>/dev/null | awk '{print $3}' | cut -d'/' -f1 | sed 's/.*\.//' || true
)"
NEXT_IP=100
while echo "${USED_IPS}" | grep -q "\b${NEXT_IP}\b"; do
  ((NEXT_IP++))
done
CLIENT_IP="10.0.0.${NEXT_IP}"
echo "Assigned IP: ${CLIENT_IP}"

read -r -p "Route all traffic through VPN? (y/N): " ROUTE_ALL

CLIENT_PRIVATE_KEY="$(wg genkey)"
CLIENT_PUBLIC_KEY="$(printf '%s' "${CLIENT_PRIVATE_KEY}" | wg pubkey)"
CLIENT_CONF="${CLIENTS_DIR}/${CLIENT_NAME}.conf"

cat >>"${SERVER_CONF}" <<EOF
[Peer]
# ${CLIENT_NAME}
PublicKey = ${CLIENT_PUBLIC_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF

cat >"${CLIENT_CONF}" <<EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEY}
Address = ${CLIENT_IP}/32
DNS = ${CLIENT_DNS}

[Peer]
PublicKey = $(wg show "${WG_IFACE}" public-key)
Endpoint = ${SERVER_PUBLIC_IP}:${WG_PORT}
EOF

if [[ "${ROUTE_ALL}" =~ ^[Yy]$ ]]; then
  echo "AllowedIPs = 0.0.0.0/0" >>"${CLIENT_CONF}"
else
  echo "AllowedIPs = ${VPN_SUBNET}" >>"${CLIENT_CONF}"
fi
echo "PersistentKeepalive = 25" >>"${CLIENT_CONF}"

chmod 600 "${CLIENT_CONF}"
wg syncconf "${WG_IFACE}" <(wg-quick strip "${WG_IFACE}")

echo
echo "Client added: ${CLIENT_NAME}"
echo "Config file: ${CLIENT_CONF}"
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ansiutf8 < "${CLIENT_CONF}"
fi
