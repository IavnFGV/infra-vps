# infra-vps repository guidance

## What this is
Infrastructure of one VPS (`ssh vps1`, Ubuntu, Docker with the containerd
image store): shared nginx + certbot, service registry, scheduled tasks,
backups, host security updates, the daily security report with Telegram
auto-fix buttons, and Dockge (stack UI, localhost only).
Applications (EnglishBot-with-agents, tts-service, ...) live in their own
repos and deploy themselves into `/opt/dockge/stacks/<service>` via their
GitHub Actions.

## Read this first
1. `AGENTS.md` (this file)
2. `docs/codex-handoff.md` — scope and constraints (no k8s/Traefik/Ansible...)
3. `docs/server-layout.md` — paths on the server
4. `docs/security-updates.md` — updates, security report, auto-fix buttons
5. `CHANGELOG.md` — what changed and why, newest first

## Server facts that are easy to get wrong
- The repo clone on the server is `/workspaces/infra-vps` (some docs say
  `/opt/infra-vps`). Deploy = push to `main`: `.github/workflows/deploy.yml`
  runs tests, then on the server `006-deploy-infra.sh`, `apply-services.sh`,
  `007-install-dockge.sh` (if Dockge is installed), `009-setup-security-fix-bot.sh`.
- Push over SSH: `git push git@github.com:IavnFGV/infra-vps.git main`.
- Secrets are committed encrypted (`enc:...`, `scripts/encrypt-value.sh`);
  the master key is `/opt/infra-secrets/master.key` on the server only.
  `decrypt-value.sh` needs `INFRA_MASTER_KEY_FILE` (it defaults to `$HOME`).
- containerd image store: a container's `.Image` is the index digest and may
  not resolve with `docker image inspect <id>`; resolve by tag (`.Config.Image`).
- Images we build (nginx, Dockge, services) must pass a per-build
  `SECURITY_REFRESH` build arg before their `apt-get/apk upgrade` layer,
  otherwise the build cache silently keeps old packages.
- The report treats an image as ours when it has the compose project label
  (compose builds) or `infra-vps.local-build` (images built with `docker build`,
  e.g. Dockge). Without either, its findings are routed to "upstream".
- systemd units run without `HOME`; scripts with `set -u` must not expand it bare.
- `pgrep -f <name>` over `ssh` matches the ssh command line itself.

## Security report / auto-fix map
- `scheduled-tasks/security-report.sh` (daily 05:15 UTC): Trivy scans the host
  and every running image, then `scripts/security-report-summarize.py`
  (classifier: fix routes, counts, CRITICAL/network, fix proposals) writes
  `/var/log/infra-vps-security/{latest.txt,state.json,fixes.json}` and sends
  Telegram via `scripts/notify-telegram.sh` (buttons = `reply_markup`).
- `scripts/security-fix-bot.py` (systemd `infra-vps-security-fix-bot`):
  Telegram long polling; button -> confirmation -> executor -> live status ->
  rescan with a summary. Log: `/var/log/infra-vps-security/fixes.log`.
- A component opts in with compose labels `infra-vps.fix=...` (see
  `docs/security-updates.md`). New fix type = executor in `EXECUTORS` +
  rule in `FIX_ACTIONS`/`plan_fixes`.

## Workflow for agents
1. Keep changes small and scripts explicit (bash + stdlib Python).
2. Run tests: `python3 -m unittest discover -s tests` (CI runs the same).
3. After every completed task update `CHANGELOG.md`, and the doc of the area
   you touched; add here any new trap that cost time.
