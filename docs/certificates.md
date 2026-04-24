# Certificates

## HTTP first, HTTPS second

The simplest flow is:

1. create HTTP config
2. reload Nginx
3. issue certificate through webroot
4. switch site to HTTPS config
5. reload Nginx again

This is intentionally boring and explicit.

## Issue certificate

```bash
./scripts/issue-cert.sh example-203-0-113-10.nip.io you@example.com
```

## Renew certificates

This repository does not automate renewal with a daemon.
Use cron or a systemd timer if needed, for example:

```bash
docker compose run --rm certbot renew --webroot --webroot-path /var/www/certbot
./scripts/reload-nginx.sh
```
