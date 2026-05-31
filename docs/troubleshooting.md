# Troubleshooting

## Nginx cannot reach upstream

Symptoms:

- `502 Bad Gateway`
- errors about host not found in upstream

Check:

1. the application container is running
2. the service is connected to `edge`
3. alias matches Nginx config exactly
4. internal port is correct

Useful commands:

```bash
docker network inspect edge
docker compose logs -f nginx
```

## Certificate issuance fails

Check:

1. domain points to the VPS IP
2. port 80 is reachable from the internet
3. site HTTP config is already loaded in Nginx
4. ACME location exists in config

## Static files return 404

Check:

1. the secret prefix matches config
2. files exist in the configured `STATIC_DIR`
3. `alias` target directory exists
4. file path under the secret prefix is correct

## Secret proxy path returns 404 or wrong app route

Check:

1. `PROXY_MODE=proxy` or `PROXY_MODE=both` is set for the service
2. the secret prefix matches config
3. the app expects paths after the secret prefix, because Nginx strips that prefix before proxying
4. the upstream container is reachable on `edge`

## Secret path serves old file instead of app

Check:

1. `PROXY_MODE=both` serves static files first and only falls back to the app if no file matches
2. the requested path does not accidentally exist in `STATIC_DIR`

## nip.io note

`nip.io` is convenient for early setup, but for stable production use a real domain later.
This repository structure can be kept the same when you switch.
