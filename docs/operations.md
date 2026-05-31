# Operations

## Common commands

Start infra stack:

```bash
docker compose up -d
```

Stop infra stack:

```bash
docker compose down
```

Check `nginx` config:

```bash
./scripts/check-nginx.sh
```

Reload `nginx`:

```bash
./scripts/reload-nginx.sh
```

List generated site configs:

```bash
./scripts/list-sites.sh
```

Apply the service registry:

```bash
./scripts/apply-services.sh
```

## Normal service lifecycle

1. Start or update the stack in Dockge.
2. Ensure the stack joins `edge` and exposes a stable alias.
3. Add or edit `registry/services/<service>.env`.
4. Run `./scripts/apply-services.sh`.

## WireGuard lifecycle

Fresh setup:

```bash
sudo SERVER_PUBLIC_IP=<server-ip> bash scripts/002-setup-wireguard.sh
```

Full rebuild:

```bash
sudo SERVER_PUBLIC_IP=<server-ip> bash scripts/reset-wireguard.sh
```

## Google Drive sync lifecycle

Bootstrap:

```bash
sudo bash scripts/setup-drive-sync-dialog.sh
```

Direct bootstrap:

```bash
sudo DRIVE_REMOTE=gdrive \
  DRIVE_PATH='server-files/infra-vps' \
  bash scripts/setup-drive-sync.sh
```

Run a sync now:

```bash
sudo /usr/local/bin/drive-sync-push
```

Check sync logs:

```bash
tail -n 100 /var/log/infra-vps-scheduled-tasks/drive-sync-push-to-google.log
```

Install repo-managed scheduled tasks:

```bash
sudo bash scripts/004-install-scheduled-tasks.sh
```

Rebuild cron entries from repo tasks:

```bash
sudo env TASKS_DIR=/opt/infra-vps/scheduled-tasks /usr/local/bin/infra-vps-sync-scheduled-tasks
```

Check generated cron entries:

```bash
cat /etc/cron.d/infra-vps-scheduled-tasks
```

Show status for all scheduled tasks:

```bash
sudo bash scripts/show-scheduled-tasks-status.sh
```

Check a task log:

```bash
tail -n 100 /var/log/infra-vps-scheduled-tasks/backup-wireguard-to-drive-sync.log
```
