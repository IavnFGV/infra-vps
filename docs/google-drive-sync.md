# Google Drive sync

This repo supports a simple push-only sync from the VPS to Google Drive.

The goal is convenience and repeatability:

- one local folder on the server
- one `rclone` remote
- one scheduled push to Google Drive
- no live mount
- no automatic restore from Google Drive yet

## Scope

Current scope:

- local folder on the VPS is the source of truth
- files are pushed from the node to Google Drive
- restore to a new node is not part of the initial setup

Out of scope for now:

- bidirectional sync
- pull sync from Google Drive
- using Google Drive as live application storage

## Recommended layout

Local layout on the VPS:

```text
/srv/drive-sync
/srv/drive-sync/infra-vps
/srv/drive-sync/infra-vps/keys
/srv/drive-sync/infra-vps/wireguard
/srv/drive-sync/infra-vps/exports
/srv/drive-sync/infra-vps/notes
/srv/drive-sync/services
```

Suggested remote layout on Google Drive:

```text
Server Files/
└── infra-vps/
    ├── infra-vps/
    └── services/
```

Example service layout:

```text
/srv/drive-sync/services/english-bot
/srv/drive-sync/services/english-bot/inbox
/srv/drive-sync/services/english-bot/exports
/srv/drive-sync/services/english-bot/backups
/srv/drive-sync/services/english-bot/files
```

## Rules

- Keep live databases on local disk only.
- Do not mount Google Drive into Docker as a production data disk.
- Let services write exports, archives, and backup files into
  `/srv/drive-sync/services/<service>/...`.
- Put infra files you want to keep in Google Drive under
  `/srv/drive-sync/infra-vps/...`.
- Local files are the source of truth. If a file is deleted locally, it will be
  deleted on Google Drive on the next sync.

## Bootstrap

Run the setup script on a node where server setup, Docker, and WireGuard are
already finished:

```bash
sudo DRIVE_REMOTE=gdrive \
  DRIVE_PATH='Server Files/infra-vps' \
  bash /opt/infra-vps/scripts/setup-drive-sync.sh
```

What the script does:

- installs `rclone` if needed
- creates `/srv/drive-sync`
- installs the sync helper at `/usr/local/bin/drive-sync-push`
- writes `/etc/drive-sync.env`
- installs `systemd` service and timer units
- enables the timer only if the `rclone` remote already exists

## rclone remote

The setup script expects an existing `rclone` remote name such as `gdrive`.

If the remote is not configured yet:

```bash
sudo rclone config
```

Create a Google Drive remote with the same name passed in `DRIVE_REMOTE`, then
run the setup script again or enable the timer manually:

```bash
sudo systemctl enable --now drive-sync-push.timer
```

Use `sudo` here because the timer and helper run as `root`, so they read the
root `rclone` config.

## Operations

Run a sync immediately:

```bash
sudo /usr/local/bin/drive-sync-push
```

Check timer state:

```bash
systemctl status drive-sync-push.timer
```

Check the latest sync logs:

```bash
journalctl -u drive-sync-push.service -n 100 --no-pager
```

Edit the sync settings:

```bash
sudoedit /etc/drive-sync.env
sudo systemctl daemon-reload
```

## Docker example

Example bind mount for a service that writes export files:

```yaml
services:
  english-bot:
    image: your-image
    volumes:
      - /srv/drive-sync/services/english-bot/files:/app/files
      - /srv/drive-sync/services/english-bot/backups:/app/backups
```

The container writes to local disk. `rclone` pushes those files to Google Drive
later.

## Infra examples

Example files you may choose to keep in Google Drive for convenience:

```bash
cp /opt/infra-secrets/master.key /srv/drive-sync/infra-vps/keys/master.key
cp /etc/wireguard/clients/alice.conf /srv/drive-sync/infra-vps/wireguard/alice.conf
```

For this repo's intended simple workflow, those files are treated as deliberate
convenience copies.
