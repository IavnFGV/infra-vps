# GitOps Services

This infrastructure uses a GitOps approach for managing services. All service configurations are stored in Git as environment files, with secrets encrypted using a master key.

## Workflow

1. **Service Deployment on VPS**: Services are deployed separately in `/opt/services/<service-name>/docker-compose.yml`. Each service must connect to the `edge` Docker network with a unique alias (e.g., `hello-test-app`).

2. **Local Registration**: Use `python3 scripts/service-wizard.py` to create a service registry file locally.

3. **Commit and Push**: Add the registry file to Git, commit, and push to `main`.

4. **Automatic Deployment**: GitHub Actions deploys to the VPS, running `apply-services.sh` to generate nginx configs, issue certificates, and reload nginx.

## Master Key Management

- **Server Location**: `/opt/infra-secrets/master.key`
- **Local Copy**: `~/.infra-vps-master.key` (for encryption)
- **Generation**: Run `./scripts/create-master-key.sh` on the server.
- **Copy to Local**: `scp deploy@178.104.218.159:/opt/infra-secrets/master.key ~/.infra-vps-master.key && chmod 600 ~/.infra-vps-master.key`
- **Warning**: If the master key is lost, encrypted values cannot be decrypted.

## Encrypting Values

To encrypt a plaintext value locally:

```bash
./scripts/encrypt-value.sh "my-secret-value"
```

This outputs `enc:<ciphertext>` which can be used in service env files.

## Service Registry Format

Services are defined in `registry/services/<service-name>.env`:

```
SERVICE_NAME=hello-test
DOMAIN=hello-test-178-104-218-159.nip.io
UPSTREAM_HOST=hello-test-app
UPSTREAM_PORT=80

ENABLE_HTTPS=true
LETSENCRYPT_EMAIL=enc:ENCRYPTED_EMAIL_HERE

STATIC_ENABLED=false
STATIC_PUBLIC_PREFIX=/static
STATIC_SECRET=enc:ENCRYPTED_SECRET_HERE
STATIC_DIR=/srv/service-static/hello-test
```

- `LETSENCRYPT_EMAIL` and `STATIC_SECRET` must be encrypted if present.
- `STATIC_SECRET` is required if `STATIC_ENABLED=true`.
- `STATIC_DIR` is not a secret.

## Example Service docker-compose.yml

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

## Important Notes

- Nginx configs in `nginx/sites/*.conf` are generated automatically. Do not edit them manually.
- Do not run service wizards on the server for GitOps flow.
- Do not store plaintext secrets in Git.
- Services must be running and connected to the `edge` network before registration.