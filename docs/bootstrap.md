# Bootstrap

For the exact rebuild and migration sequence on a new node, use
[canonical-node-bootstrap.md](/workspaces/infra-vps/docs/canonical-node-bootstrap.md).

## Prerequisites on VPS

- Docker Engine
- Docker Compose plugin
- openssl
- ports `80` and `443` reachable from the internet

## Initial setup

```bash
sudo bash scripts/001-setup-server.sh
sudo SERVER_PUBLIC_IP=<server-ip> bash scripts/002-setup-wireguard.sh
sudo bash scripts/004-install-scheduled-tasks.sh
sudo bash scripts/005-setup-node-layout.sh
./scripts/006-deploy-infra.sh
sudo bash scripts/008-setup-auto-updates.sh
sudo bash scripts/009-setup-security-fix-bot.sh
```

## Result

After this step:

- shared Docker network `edge` exists
- Nginx listens on `80` and `443`
- Certbot webroot is mounted
- repo-managed scheduled tasks are installed
- the node is ready for Dockge-managed stacks to join `edge`
