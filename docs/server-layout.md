# Server layout

Suggested layout on the VPS:

```text
/opt/infra-vps-minimal
/opt/bots/bot1
/opt/bots/bot2
/opt/bots/tts
```

Example:

- infra repo cloned into `/opt/infra-vps-minimal`
- each bot repo cloned into its own directory under `/opt/bots/`

If a bot needs static files served directly by Nginx in `PROXY_MODE=files`, mount the matching directory from:

```text
/opt/infra-vps-minimal/data/bot-static/<bot-name>
```

into the bot container.
