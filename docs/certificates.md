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

This repo ships automatic renewal through the scheduled task layer.

Default task files:

- `scheduled-tasks/cert-renew.env`
- `scheduled-tasks/cert-renew.sh`

The task runs daily and uses `certbot renew`, which renews certificates only
when they are close enough to expiry.

Manual run:

```bash
cd /workspaces/infra-vps
bash scheduled-tasks/cert-renew.sh
```
