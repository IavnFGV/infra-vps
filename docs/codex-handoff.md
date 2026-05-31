# Codex handoff

This repository is intentionally narrow.
Do not introduce Kubernetes, Traefik, Swarm, Ansible, Terraform, or dynamic
reverse-proxy discovery.

## What this repo is responsible for

- one shared Nginx reverse proxy for a single VPS
- centralized TLS via Certbot webroot flow
- host-based routing by subdomain
- the service registry in `registry/services/*.env`
- one shared external Docker network named `edge`
- optional secret static path for service-owned files

## What Dockge-managed stacks are responsible for

- their own application code
- their own deployment lifecycle
- joining the external Docker network `edge`
- exposing internal HTTP ports only
- setting a stable network alias used by Nginx upstreams

## Important constraints

- no `container_name`
- no app-managed Nginx on `80/443`
- route by hostname, not by path prefix for apps
- keep scripts explicit and readable
- keep file layout easy to understand for humans

## Expected bot Compose pattern

- `expose`, not public `ports`, for web services behind Nginx
- `networks.edge.external: true`
- alias such as `hello-test-app`, `api-app`, or `uptime-kuma-app`

## Secret path model

An unguessable secret path may be used either for direct static file serving or as a hidden proxy entrypoint into an app:

```text
/__static_<secret>/...
```

This is obscurity, not authorization.
Do not present it as real security.
