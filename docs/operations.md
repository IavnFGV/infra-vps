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
sudo SERVER_PUBLIC_IP=<server-ip> bash scripts/setup-wireguard.sh
```

Full rebuild:

```bash
sudo SERVER_PUBLIC_IP=<server-ip> bash scripts/reset-wireguard.sh
```
