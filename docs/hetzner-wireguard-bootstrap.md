# Hetzner node bootstrap with WireGuard

This is the canonical order for bringing up a fresh Hetzner Ubuntu node for
this repo, with WireGuard on the host, Dockge for compose stacks, and this repo
owning ingress and TLS.

## 1. Create the server

- Create a new Ubuntu VPS in Hetzner.
- Open inbound `22/tcp`, `80/tcp`, `443/tcp`, `51820/udp`.
- Attach your SSH key during server creation.

## 2. Login and clone the repo

```bash
ssh root@YOUR_HETZNER_IP
apt-get update
apt-get install -y git
git clone <YOUR_REPO_URL> /opt/infra-vps
cd /opt/infra-vps
```

If the repo is private, use the access method you normally use.

## 3. Run base server setup

```bash
sudo bash /opt/infra-vps/scripts/setup-server.sh
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

If you want to fully rebuild WireGuard from scratch on an already used server:

```bash
sudo SERVER_PUBLIC_IP=YOUR_HETZNER_IP \
  bash /workspaces/infra-vps/scripts/reset-wireguard.sh
```

This stops `wg0`, backs up the current `/etc/wireguard`, removes the old state,
and recreates the server config from zero.

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

## 7. Restore the registry master key

If you already have encrypted values in `registry/services/*.env`, copy the
existing key from the old node before applying services:

```bash
install -d -m 700 /opt/infra-secrets
scp deploy@OLD_SERVER_IP:/opt/infra-secrets/master.key /opt/infra-secrets/master.key
chmod 600 /opt/infra-secrets/master.key
```

If this is a brand new environment with no existing encrypted registry values:

```bash
./scripts/create-master-key.sh
```

## 8. Start infra stack

```bash
cd /opt/infra-vps
./scripts/init-edge-network.sh
docker compose up -d
./scripts/check-nginx.sh
```

## 9. Install Dockge and create stack storage

Create the canonical directories now, even if you install Dockge later:

```bash
mkdir -p /opt/dockge/stacks
mkdir -p /srv/services
mkdir -p /srv/service-static
```

Install Dockge using the method you prefer, but keep its stacks under
`/opt/dockge/stacks`.

## 10. Migrate services safely

Use this order:

1. Bring up WireGuard and verify access.
2. Start the infra stack.
3. Install Dockge.
4. Recreate application stacks in Dockge.
5. Make each published stack join `edge` with the alias referenced by
   `UPSTREAM_HOST`.
6. Only after the stack is reachable, apply the matching
   `registry/services/<service>.env`.
7. Add Uptime Kuma as a Dockge-managed stack after ingress is stable.

This keeps `nginx`, TLS, VPN, and application rollout separated.

## 11. Keep it reproducible

When WireGuard changes later:

- keep `/etc/wireguard` only on the server
- keep the safe templates in git
- add clients again manually on the next server

This avoids committing private keys and personal client configs.
