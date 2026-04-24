# Minimal VPS infra repo for multiple bots

This repository provides a small and explicit infrastructure layer for a single VPS:

- one shared Nginx reverse proxy
- centralized TLS with Certbot
- one external Docker network named `edge`
- several independent bot repositories deployed separately
- optional secret static path for files served by Nginx

## Main idea

Bot repositories do **not** expose ports `80/443` directly.
They only connect their internal web services to the shared Docker network `edge`.
Nginx lives here, in the infra repository, and routes requests by hostname.

## Quick start

1. Copy `.env.example` to `.env` and adjust values if needed.
2. Create shared network:
   `./scripts/init-edge-network.sh`
3. Start infra stack:
   `docker compose up -d`
4. Check Nginx:
   `./scripts/check-nginx.sh`

After that you can add sites for individual bots.

See `docs/` for step-by-step usage.
