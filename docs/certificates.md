# Certificates

## Ownership

This repo owns certificate issuance and renewal for published services.
Application stacks should not manage their own public certificates on the same
VPS.

## Flow

`./scripts/apply-services.sh` follows the boring sequence:

1. generate the HTTP config
2. reload `nginx`
3. issue the certificate with Certbot webroot
4. rewrite the service config to HTTPS
5. reload `nginx` again

## Manual issue path

```bash
./scripts/issue-cert.sh example-203-0-113-10.nip.io you@example.com
```

## Renew certificates

This repo does not currently ship an automatic renewal timer.
If you want renewal outside deploy runs, use cron or systemd, for example:

```bash
docker compose run --rm certbot renew --webroot --webroot-path /var/www/certbot
./scripts/reload-nginx.sh
```
