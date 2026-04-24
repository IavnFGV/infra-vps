# Troubleshooting

## Nginx cannot reach upstream

Symptoms:

- `502 Bad Gateway`
- errors about host not found in upstream

Check:

1. bot container is running
2. bot service is connected to `edge`
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
2. files exist in `data/bot-static/<name>/`
3. `alias` target directory exists
4. file path under the secret prefix is correct

## nip.io note

`nip.io` is convenient for early setup, but for stable production use a real domain later.
This repository structure can be kept the same when you switch.
