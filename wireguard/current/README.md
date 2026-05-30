# Current WireGuard state

This directory is intentionally kept free of secrets.

Do not store these items in the repo:

- server private keys
- client private keys
- `wg0.conf` with real peers
- exported client `.conf` files

The safe, reproducible flow now is:

1. Run `scripts/setup-wireguard.sh` on a fresh server.
2. It generates a new server keypair and a fresh `wg0.conf`.
3. Add clients one by one with `/usr/local/bin/wg-add-client`.

Safe templates live in `wireguard/templates/`.
