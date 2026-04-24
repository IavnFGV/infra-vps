# Operations

## Common commands

Start stack:

```bash
docker compose up -d
```

Stop stack:

```bash
docker compose down
```

Check Nginx config:

```bash
./scripts/check-nginx.sh
```

Reload Nginx:

```bash
./scripts/reload-nginx.sh
```

List configured sites:

```bash
./scripts/list-sites.sh
```

## Add one more bot later

Repeat the same lifecycle:

- prepare bot Compose with alias in `edge`
- add site config
- reload Nginx
- issue cert
- enable HTTPS
