# Overview

## Goal

Keep one VPS setup simple and boring:

- one shared Nginx
- one place for certificates
- one infra repo as source of truth for ingress
- compose stacks managed outside this repo
- host-based routing by subdomain
- no Kubernetes, no Swarm, no Traefik, no Ansible
- one optional push-only Google Drive sync folder for exports and convenience

## Ownership split

`infra-vps` owns:

- `nginx` and Certbot
- `registry/services/*.env`
- generated virtual hosts in `nginx/sites/`
- the shared Docker network `edge`
- host bootstrap and WireGuard scripts

Dockge owns:

- compose stack files
- container lifecycle
- restarts, edits, and stack-level operations

Uptime Kuma owns:

- health checks
- notifications
- dashboards and status pages

## Components

- `docker-compose.yml` - infra stack with `nginx` and `certbot`
- `registry/services/` - desired published services
- `nginx/sites/` - generated service configs plus `_default.conf`
- `scripts/apply-services.sh` - registry to nginx compiler
- `scripts/001-setup-server.sh` - baseline node bootstrap
- `scripts/002-setup-wireguard.sh` - host VPN bootstrap
- `scripts/003-restore-master-key.sh` - restore the registry master key
- `scripts/003-create-master-key.sh` - create a new registry master key
- `scripts/setup-drive-sync.sh` - Google Drive sync bootstrap
- `scripts/drive-sync-push.sh` - push-only `rclone` helper
- `scripts/004-install-scheduled-tasks.sh` - install repo-managed scheduled task sync
- `scripts/005-setup-node-layout.sh` - prepare Dockge and service directories
- `scripts/006-deploy-infra.sh` - start the infra stack and validate `nginx`
- `scripts/sync-scheduled-tasks.sh` - generate cron entries from repo task metadata
- `scheduled-tasks/` - small host backup copy tasks plus per-task cron metadata

## Contract with application stacks

Every published stack must:

- avoid `container_name`
- avoid binding `80` or `443` on the host
- use `expose`
- join the external Docker network `edge`
- define a stable network alias that matches `UPSTREAM_HOST`
- keep persistent data outside the repo, for example under `/srv/services/<name>`

## Operating model

1. A stack is created and started in Dockge.
2. The stack joins `edge` with a stable alias.
3. A matching `registry/services/<service>.env` file is added to this repo.
4. `./scripts/apply-services.sh` generates the `nginx` config, issues a
   certificate if needed, and reloads `nginx`.

This repo is the source of truth for public exposure, not for application
runtime state.

For the exact node rebuild sequence, see
[canonical-node-bootstrap.md](/workspaces/infra-vps/docs/canonical-node-bootstrap.md).

For optional convenience sync to Google Drive, see
[docs/google-drive-sync.md](/workspaces/infra-vps/docs/google-drive-sync.md).
