# Bootstrap

## Prerequisites on VPS

- Docker Engine
- Docker Compose plugin
- openssl
- ports `80` and `443` reachable from the internet

## Initial setup

```bash
cp .env.example .env
./scripts/init-edge-network.sh
docker compose up -d
./scripts/check-nginx.sh
```

## Result

After this step:

- shared Docker network `edge` exists
- Nginx listens on `80` and `443`
- Certbot webroot is mounted
- you can add sites for bot projects
