# GitOps Services

This repo keeps the published service registry in Git. Runtime compose stacks
live outside this repo and are expected to be managed by Dockge.

## Workflow

1. Create or update a stack in Dockge.
2. Ensure the stack joins the external `edge` network.
3. Ensure the published container has a stable alias, for example
   `hello-test-app`.
4. Add or update `registry/services/<service>.env` in this repo.
5. Commit and push.
6. Run `./scripts/apply-services.sh` on the server, or let CI do it.

`apply-services.sh` owns ingress only:

- generate `nginx/sites/<service>.conf`
- issue certificates when `ENABLE_HTTPS=true`
- reload `nginx`
- remove ingress config for registry entries that were deleted

It does not start, stop, or mutate application stacks.

## Service removal

To unpublish a service:

1. Remove `registry/services/<service>.env`.
2. Commit and push.
3. Run `./scripts/apply-services.sh`.
4. Remove or archive the stack separately in Dockge.

## Master key management

- Server location: `/opt/infra-secrets/master.key`
- Local copy: `~/.infra-vps-master.key`
- Generation on server: `./scripts/003-create-master-key.sh`
- Warning: if the key is lost, `enc:` values cannot be decrypted

To copy the current key locally:

```bash
scp deploy@YOUR_SERVER_IP:/opt/infra-secrets/master.key ~/.infra-vps-master.key
chmod 600 ~/.infra-vps-master.key
```

## Encrypting values

```bash
./scripts/encrypt-value.sh "my-secret-value"
```

This prints `enc:<ciphertext>` for use in registry files.

## Registry format

Use [templates/service.env.example](/workspaces/infra-vps/templates/service.env.example)
as the base template.

Required fields:

- `SERVICE_NAME`
- `DOMAIN`
- `UPSTREAM_HOST`
- `UPSTREAM_PORT`

Optional TLS fields:

- `ENABLE_HTTPS=true|false`
- `LETSENCRYPT_EMAIL=enc:...` when HTTPS is enabled

Optional secret static path fields:

- `STATIC_ENABLED=true|false`
- `PROXY_MODE=files|proxy|both`
- `STATIC_PUBLIC_PREFIX=/static`
- `STATIC_SECRET=enc:...`
- `STATIC_DIR=/srv/service-static/<service>` for `files` and `both`

Behavior:

- `files`: serve files from `STATIC_DIR`
- `proxy`: forward the secret path to the upstream app
- `both`: serve files first, then fall back to the app

## Example stack contract

```yaml
services:
  app:
    image: nginx:1.27-alpine
    restart: unless-stopped
    expose:
      - "80"
    networks:
      edge:
        aliases:
          - hello-test-app

networks:
  edge:
    external: true
    name: edge
```

## Rules

- Do not edit `nginx/sites/*.conf` manually.
- Do not store plaintext secrets in Git.
- Do not register a service before its stack is already reachable on `edge`.
