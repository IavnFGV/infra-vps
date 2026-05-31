# Server layout

Suggested layout on the VPS:

```text
/opt/infra-vps
/opt/dockge
/opt/dockge/stacks
/srv/services
/srv/service-static
/srv/drive-sync
/opt/infra-secrets
/etc/wireguard
```

## Ownership

- `/opt/infra-vps` - this repo
- `/opt/dockge` - Dockge install and compose file, owned by `deploy`
- `/opt/dockge/data` - Dockge application data, owned by `deploy`
- `/opt/dockge/stacks/<stack>` - compose stacks managed by Dockge, owned by `deploy`
- `/srv/services/<service>` - persistent application data, owned by `deploy`
- `/srv/service-static/<service>` - optional files for `STATIC_DIR`, owned by `deploy`
- `/srv/drive-sync/...` - push-only sync root for Google Drive exports and convenience copies
- `/opt/infra-secrets/master.key` - registry encryption key
- `/etc/wireguard` - host WireGuard state

## Notes

- Keep application data out of the git repo.
- Keep WireGuard state on the host only.
- Keep `edge` as the single shared Docker network for published services.
- Keep Google Drive sync as a local-folder push workflow, not a live mount.
- If a service uses `PROXY_MODE=files` or `PROXY_MODE=both`, point
  `STATIC_DIR` at its directory under `/srv/service-static`.

Example:

```text
/opt/dockge/stacks/hello-test
/srv/services/hello-test
/srv/service-static/hello-test
```
