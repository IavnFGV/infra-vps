# Canonical Node Bootstrap

This is the canonical migration and bootstrap path for a fresh server.

Use this when:

- moving to a new VPS
- rebuilding an existing node from scratch
- recreating the infra baseline in the expected repo layout

Assumptions:

- Ubuntu server
- repo cloned to `/opt/infra-vps`
- this repo owns ingress, TLS, service registry, WireGuard helpers, and optional
  Google Drive sync
- Dockge will manage compose stacks after the node baseline is ready

## Canonical command sequence

```bash
ssh root@YOUR_SERVER_IP
apt-get update
apt-get install -y git
git clone <YOUR_REPO_URL> /opt/infra-vps

sudo bash /opt/infra-vps/scripts/001-setup-server.sh

sudo SERVER_PUBLIC_IP=YOUR_SERVER_IP \
  bash /opt/infra-vps/scripts/002-setup-wireguard.sh

scp deploy@OLD_SERVER_IP:/opt/infra-secrets/master.key /tmp/infra-vps-master.key
sudo bash /opt/infra-vps/scripts/003-restore-master-key.sh /tmp/infra-vps-master.key

sudo bash /opt/infra-vps/scripts/004-install-scheduled-tasks.sh
sudo bash /opt/infra-vps/scripts/005-setup-node-layout.sh

cd /opt/infra-vps
./scripts/006-deploy-infra.sh

sudo bash /opt/infra-vps/scripts/007-install-dockge.sh
```

If there is no old environment and no existing encrypted registry values,
replace the master key copy step with:

```bash
sudo bash /opt/infra-vps/scripts/003-create-master-key.sh
```

## What this sequence does

1. Installs Docker and Docker Compose.
2. Creates the `deploy` user and hardens SSH access.
3. Sets up WireGuard on the host.
4. Restores the existing registry decryption key.
5. Installs repo-managed scheduled tasks.
6. Prepares the canonical directories for Dockge and service data.
7. Starts the infra stack and validates `nginx`.
8. Installs Dockge in the canonical host location.

## What comes next

After the canonical bootstrap is done:

1. Recreate application stacks in Dockge under `/opt/dockge/stacks`.
2. Make each published stack join `edge` with the alias used in
   `registry/services/*.env`.
3. Run `./scripts/apply-services.sh` only after the upstream container is
   reachable on `edge`.
4. Add Uptime Kuma after ingress is already stable.

## Optional steps

Set up the optional Google Drive push-only sync layer:

```bash
sudo bash /opt/infra-vps/scripts/setup-drive-sync-dialog.sh
```

See [google-drive-sync.md](/workspaces/infra-vps/docs/google-drive-sync.md).

## Verification checklist

Run these checks after bootstrap:

```bash
docker --version
docker compose version
systemctl status wg-quick@wg0
wg show
docker network inspect edge
docker compose ps
./scripts/check-nginx.sh
```

Expected state:

- Docker is installed and running
- WireGuard is active
- `edge` exists
- `nginx` container is up
- `nginx -t` passes
