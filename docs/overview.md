# Overview

## Goal

Keep one VPS setup simple:

- one shared Nginx
- one place for certificates
- independent bot repositories
- host-based routing by subdomain
- no Kubernetes, no Swarm, no Traefik, no Ansible

## Components

- `docker-compose.yml` - infra stack with Nginx and Certbot
- `nginx/sites/` - per-site virtual host configs
- `scripts/` - small shell helpers
- `data/bot-static/` - optional static files exposed through secret URLs
- `examples/` - sample Compose fragments for bot repos

## Contract with bot repositories

A bot repository must:

- avoid `container_name`
- avoid publishing external `ports` for services that go through Nginx
- use `expose`
- join the external Docker network `edge`
- define a stable network alias, for example `bot1-app`
