# VPS control plane

This repository is the control plane for one VPS with multiple self-hosted services.

It owns:

- shared `nginx` ingress
- centralized TLS with Certbot
- the `registry/services/*.env` service registry
- the external Docker network `edge`
- WireGuard bootstrap and reset scripts

It does not own application lifecycle. Application stacks should be managed by
Dockge and attached to `edge` with stable aliases that match the registry.

## Quick start

1. Clone the repo to `/opt/infra-vps`.
2. Run `sudo bash scripts/setup-server.sh` on a fresh node.
3. Run `sudo SERVER_PUBLIC_IP=<server-ip> bash scripts/setup-wireguard.sh`.
4. Restore the existing registry master key or create a new one.
5. Run `sudo bash scripts/install-scheduled-tasks.sh`.
6. Run `sudo bash scripts/setup-node-layout.sh`.
7. Start the infra stack with `./scripts/deploy-infra.sh`.

From there:

- Dockge manages compose stacks.
- `registry/services/*.env` defines domains, upstream aliases, TLS, and optional
  secret static paths.
- `./scripts/apply-services.sh` renders and applies ingress state from the
  registry.

See [docs/overview.md](/workspaces/infra-vps/docs/overview.md) for the target
layout and operating model.
For the exact rebuild sequence on a new server, use
[docs/canonical-node-bootstrap.md](/workspaces/infra-vps/docs/canonical-node-bootstrap.md).
