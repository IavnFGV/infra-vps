#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE_DIR="${TEMPLATE_DIR:-${REPO_ROOT}/wireguard/templates}"
WG_DIR="${WG_DIR:-/etc/wireguard}"
WG_IFACE="${WG_IFACE:-wg0}"
VPN_SUBNET="${VPN_SUBNET:-10.0.0.0/24}"
SERVER_VPN_IP="${SERVER_VPN_IP:-10.0.0.1/24}"
WG_PORT="${WG_PORT:-51820}"
CLIENT_DNS="${CLIENT_DNS:-8.8.8.8, 1.1.1.1}"
SERVER_PUBLIC_IP="${SERVER_PUBLIC_IP:-$(curl -4 -fsSL ifconfig.me 2>/dev/null || true)}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/wireguard-setup}"
UPLINK_IFACE="${UPLINK_IFACE:-$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')}"
FORCE="${FORCE:-0}"

if [[ -z "${UPLINK_IFACE}" ]]; then
  echo "Could not detect uplink interface. Set UPLINK_IFACE explicitly."
  exit 1
fi

if [[ -z "${SERVER_PUBLIC_IP}" ]]; then
  echo "Could not detect public IP. Set SERVER_PUBLIC_IP explicitly."
  exit 1
fi

TIMESTAMP="$(date -u +%Y%m%d-%H%M%S)"
BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
SERVER_CONF="${WG_DIR}/${WG_IFACE}.conf"
SERVER_PRIVATE_KEY_FILE="${WG_DIR}/privatekey"
SERVER_PUBLIC_KEY_FILE="${WG_DIR}/publickey"

echo "[1/8] Installing WireGuard packages..."
apt-get update
apt-get install -y wireguard wireguard-tools iptables qrencode rsync

echo "[2/8] Backing up current WireGuard config..."
mkdir -p "${BACKUP_DIR}" "${WG_DIR}"
if [[ -d "${WG_DIR}" ]]; then
  cp -a "${WG_DIR}" "${BACKUP_DIR}/wireguard.before"
fi

if [[ -f "${SERVER_CONF}" && "${FORCE}" != "1" ]]; then
  echo "WireGuard config already exists: ${SERVER_CONF}"
  echo "Set FORCE=1 if you want to overwrite it."
  exit 1
fi

if [[ "${FORCE}" == "1" ]]; then
  echo "[2a] Resetting existing WireGuard state..."
  systemctl stop "wg-quick@${WG_IFACE}" >/dev/null 2>&1 || true
  rm -rf "${WG_DIR}"
  mkdir -p "${WG_DIR}"
fi

echo "[3/8] Generating fresh WireGuard server keys..."
umask 077
wg genkey | tee "${SERVER_PRIVATE_KEY_FILE}" | wg pubkey > "${SERVER_PUBLIC_KEY_FILE}"
SERVER_PRIVATE_KEY="$(cat "${SERVER_PRIVATE_KEY_FILE}")"

echo "[4/8] Writing ${WG_IFACE}.conf..."
mkdir -p "${WG_DIR}/clients"
cat >"${SERVER_CONF}" <<EOF
[Interface]
Address = ${SERVER_VPN_IP}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ${UPLINK_IFACE} -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ${UPLINK_IFACE} -j MASQUERADE
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
EOF

echo "[5/8] Installing helper scripts and metadata..."
if [[ -f "${TEMPLATE_DIR}/wg_add_client.sh" ]]; then
  install -m 0755 "${TEMPLATE_DIR}/wg_add_client.sh" "${WG_DIR}/wg_add_client.sh"
  install -m 0755 "${TEMPLATE_DIR}/wg_add_client.sh" /usr/local/bin/wg-add-client
fi

{
  printf 'WG_IFACE=%q\n' "${WG_IFACE}"
  printf 'VPN_SUBNET=%q\n' "${VPN_SUBNET}"
  printf 'SERVER_VPN_IP=%q\n' "${SERVER_VPN_IP}"
  printf 'WG_PORT=%q\n' "${WG_PORT}"
  printf 'SERVER_PUBLIC_IP=%q\n' "${SERVER_PUBLIC_IP}"
  printf 'CLIENT_DNS=%q\n' "${CLIENT_DNS}"
} >"${WG_DIR}/.server-meta"

echo "[6/8] Setting permissions and sysctl..."
chmod 700 "${WG_DIR}"
find "${WG_DIR}" -type f \( -name '*privatekey*' -o -name 'privatekey' -o -name '*.key' -o -name '*.conf' -o -name '.server-meta' \) -exec chmod 600 {} +
find "${WG_DIR}" -type f \( -name '*publickey*' -o -name 'publickey' \) -exec chmod 644 {} +
chmod 755 "${WG_DIR}/wg_add_client.sh" 2>/dev/null || true

cat >/etc/sysctl.d/99-wireguard-forward.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

echo "[7/8] Enabling and starting WireGuard..."
systemctl enable "wg-quick@${WG_IFACE}"
if systemctl is-active --quiet "wg-quick@${WG_IFACE}"; then
  systemctl restart "wg-quick@${WG_IFACE}"
else
  systemctl start "wg-quick@${WG_IFACE}"
fi

echo "[8/8] Summary..."
echo "WireGuard backup: ${BACKUP_DIR}"
echo "WireGuard uplink interface: ${UPLINK_IFACE}"
echo "WireGuard public IP: ${SERVER_PUBLIC_IP}"
echo "Client add helper: /usr/local/bin/wg-add-client"

echo
echo "Check:"
echo "  systemctl status wg-quick@${WG_IFACE}"
echo "  wg show"
echo "  ss -lunp | grep 51820"
echo "  iptables -t nat -S"
