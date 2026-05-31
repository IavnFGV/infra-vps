# Server layout

Suggested layout on the VPS:

```text
/opt/infra-vps
/opt/dockge
/opt/dockge/stacks
/srv/services
/srv/service-static
/opt/infra-secrets
/etc/wireguard
```

## Ownership

- `/opt/infra-vps` - this repo
- `/opt/dockge` - Dockge install
- `/opt/dockge/stacks/<stack>` - compose stacks managed by Dockge
- `/srv/services/<service>` - persistent application data
- `/srv/service-static/<service>` - optional files for `STATIC_DIR`
- `/opt/infra-secrets/master.key` - registry encryption key
- `/etc/wireguard` - host WireGuard state

## Notes

- Keep application data out of the git repo.
- Keep WireGuard state on the host only.
- Keep `edge` as the single shared Docker network for published services.
- If a service uses `PROXY_MODE=files` or `PROXY_MODE=both`, point
  `STATIC_DIR` at its directory under `/srv/service-static`.

Example:

```text
/opt/dockge/stacks/hello-test
/srv/services/hello-test
/srv/service-static/hello-test
```
