# Hetzner node bootstrap with WireGuard

This is the exact order for bringing up a fresh Hetzner Ubuntu node with this
repo and creating a fresh WireGuard server without storing private keys in git.

## 1. Create the server

- Create a new Ubuntu VPS in Hetzner.
- Open inbound `22/tcp`, `80/tcp`, `443/tcp`, `51820/udp`.
- Attach your SSH key during server creation.

## 2. Login and clone the repo

```bash
ssh root@YOUR_HETZNER_IP
apt-get update
apt-get install -y git
git clone <YOUR_REPO_URL> /workspaces/infra-vps
cd /workspaces/infra-vps
```

If the repo is private, use the access method you normally use.

## 3. Run base server setup

```bash
sudo bash /workspaces/infra-vps/scripts/setup-server.sh
```

This installs Docker and Docker Compose, creates `deploy`, copies the current
SSH key from `root` to `deploy`, grants passwordless `sudo`, disables SSH
password login, and disables SSH login for `root`.

## 4. Create a fresh WireGuard server

```bash
sudo SERVER_PUBLIC_IP=YOUR_HETZNER_IP \
  bash /workspaces/infra-vps/scripts/setup-wireguard.sh
```

This will:

- install WireGuard packages
- generate a new server keypair
- create a fresh `/etc/wireguard/wg0.conf`
- auto-detect the default uplink interface
- enable IP forwarding
- enable and start `wg-quick@wg0`
- install `/usr/local/bin/wg-add-client`
- install `qrencode` for client QR output

## 5. Verify WireGuard

```bash
systemctl status wg-quick@wg0
wg show
ss -lunp | grep 51820
iptables -t nat -S
```

Expected result:

- `wg-quick@wg0` is active
- WireGuard listens on UDP `51820`
- NAT rules exist for the detected uplink interface

## 6. Add clients again

Add each client as needed:

```bash
/usr/local/bin/wg-add-client
```

The script creates a client config in `/etc/wireguard/clients/` and prints a QR
code if `qrencode` is installed.

## 7. Start infra stack

```bash
cd /workspaces/infra-vps
./scripts/init-edge-network.sh
docker compose up -d
./scripts/check-nginx.sh
```

## 8. Keep it reproducible

When WireGuard changes later:

- keep `/etc/wireguard` only on the server
- keep the safe templates in git
- add clients again manually on the next server

This avoids committing private keys and personal client configs.
