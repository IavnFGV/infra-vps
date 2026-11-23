# Security updates

Goal: fixes for known vulnerabilities reach the server without manual work,
and everything that happened is visible in a log and in Telegram.

Nothing here makes decisions on its own beyond fixed rules: apt security
pockets, Dependabot patch/minor bumps that pass tests, and a weekly rebuild.

## Layers

| What | Who fixes it | When |
|------|--------------|------|
| Host OS packages (kernel, openssl, ssh, ...) | `unattended-upgrades` (security pockets only) | daily 03:30, reboot at 04:30 if required |
| Docker Engine / containerd / compose plugin | `unattended-upgrades` (`download.docker.com`) | same |
| Libraries used by running daemons | `needrestart` restarts the affected services | right after the upgrade |
| Python dependencies of a service | Dependabot PR -> tests + `pip-audit` -> auto-merge -> deploy | security PRs as soon as an advisory is published; routine bumps weekly |
| Base image of a service (`python:3.x-slim`, Debian packages inside) | weekly scheduled run of the service deploy workflow (`docker compose build --pull`) | Monday 02:17 UTC |
| nginx (`nginx/image/Dockerfile`: official image + `apk upgrade`) | rebuilt on every infra deploy and weekly; Dependabot bumps the base tag -> auto-merge -> deploy (`nginx -t` gates the restart) | weekly Monday 02:47 UTC + daily tag check |
| Dockge (`dockge/image/Dockerfile`: `louislam/dockge:1` + `apt-get upgrade`, incl. docker CLI/compose from Docker's repo) | `scripts/007-install-dockge.sh`, run by every infra deploy when `/opt/dockge/compose.yaml` exists | weekly Monday 02:47 UTC |
| Fixes that need a human "go" | Telegram button from the security report (see below) | when you press it |
| Anything the above missed | `scheduled-tasks/security-report.sh` (Trivy) reports it | daily 05:15 |

Every Dependabot PR is merged once tests pass, major versions included.
A PR whose tests fail stays open — that is the only thing to look at by hand.

## Server setup

```bash
sudo bash scripts/008-setup-auto-updates.sh
infra-vps-notify "test"                      # should arrive in Telegram
sudo bash scheduled-tasks/security-report.sh # first scan by hand
```

Telegram config lives in the repo as `config/notify.env` with encrypted
values, so moving to a new server needs nothing beyond the usual bootstrap
(master key restore in step 003 + step 008). Create it once:

```bash
cp config/notify.env.example config/notify.env
./scripts/encrypt-value.sh "<bot token>"   # -> TELEGRAM_BOT_TOKEN=enc:...
./scripts/encrypt-value.sh "<chat id>"     # -> TELEGRAM_CHAT_ID=enc:...
git add config/notify.env && git commit
```

`/etc/infra-vps/notify.env` (optional, chmod 600) overrides it on one server.
Without any Telegram config the report still goes to the log.

## Moving to another server

Everything is in this repo and re-created by `008-setup-auto-updates.sh`
(it is part of the bootstrap sequence). Only these are server-local and are
simply rebuilt: report history in `/var/log/infra-vps-security/` (the first
scan on the new server reports everything as new once) and the Trivy cache.

The `security-report` task is picked up by the existing scheduled task sync
(`scheduled-tasks/security-report.env`), no extra cron setup needed.

Options of `008-setup-auto-updates.sh` (environment variables): `AUTO_REBOOT`,
`REBOOT_TIME`, `APT_UPDATE_TIME`, `APT_UPGRADE_TIME`, `INCLUDE_DOCKER_UPDATES`,
`INSTALL_TRIVY`. Re-run the script to change them.

## What the daily report contains

- OS packages installed by `unattended-upgrades` in the last 24h, errors, pending reboot
- HIGH/CRITICAL vulnerabilities **with a fix available** in host OS packages
  and in every running container image (labelled `compose-project/service`)
- which of those are new since the previous run and which got resolved
- totals: findings, unique CVEs, affected packages (per image too)
- fix route of every finding:
  `♻️ rebuild image` (OS package in an image built from our Dockerfile — the
  `apt-get upgrade` / `apk upgrade` layer fixes it on rebuild),
  `🛠 deps/Dockerfile change` (Python/Node/Go package in our image — needs a
  dependency bump), `📥 new upstream image` (anything in a pulled third-party
  image such as Dockge), `🖥 host unattended-upgrades`.
  "Ours" = the image carries compose's `com.docker.compose.project` label.
- CRITICAL count, with `🌐` on the network-exploitable ones (CVSS v3 `AV:N`);
  in Telegram CRITICAL are listed one per CVE (network first), the rest
  grouped one line per package

Telegram gets a message only when there is news; on Mondays it also sends a
heartbeat with totals, so silence on Monday means the task is broken.

Files:

- `/var/log/infra-vps-security/latest.txt` — last full report
- `/var/log/infra-vps-security/YYYY-MM-DD.txt` — history (60 days)
- `/var/log/infra-vps-security/scans/*.json` — raw Trivy output of the last run
- `/var/log/infra-vps-scheduled-tasks/infra__security-report.log` — task output
- `/var/log/unattended-upgrades/unattended-upgrades.log` — apt upgrades

## Auto-fix buttons in Telegram

When a finding can be fixed without a code change, the message carries a
button `🔧 Fix <component> (N)` and a line saying what will run, how many
findings it closes and which containers restart. Pressing it asks for
confirmation; `✅ Запустить` runs the fix, the bot reports the result
(with the GitHub run link) and rescans, so the next message shows
`✅ Resolved`.

Pieces:

- classifier: `scripts/security-report-summarize.py` (`plan_fixes`) — one
  proposal per component, stored in `/var/log/infra-vps-security/fixes.json`
  (valid 7 days, replaced by the next sent report)
- buttons: `scripts/security-fix-bot.py`, systemd unit
  `infra-vps-security-fix-bot`, installed/updated by
  `scripts/009-setup-security-fix-bot.sh` (run by every infra deploy;
  restarts the bot only when its code changed). Telegram long polling:
  no webhook, no open port. Log: `/var/log/infra-vps-security/fixes.log`
- only presses from `TELEGRAM_CHAT_ID` by a user in `TELEGRAM_ADMIN_IDS`
  (default: the chat id itself = you, in a private chat with the bot) are
  accepted; the button carries only a proposal id, the action comes from
  `fixes.json`

What is offered:

| Fix type | Closes | Declared by |
|---|---|---|
| `github-workflow` | OS packages in an image we build (`♻️ rebuild`) | container labels, see below |
| `compose-rebuild` | same, for a stack without CI | container labels |
| `compose-pull` | anything in a pulled image, if upstream has a newer one | container labels |
| `apt-upgrade` | host packages (`apt-get install --only-upgrade`) | always, `HOST_AUTOFIX=none` in `scheduled-tasks/security-report.env` turns it off |

`🛠 deps/Dockerfile change` findings never get a button: they need a
dependency bump (Dependabot) or a Dockerfile edit.

### Adding a service or component

Scanning needs nothing: every running container is scanned. For a fix
button add labels to the service in its compose file and redeploy it:

```yaml
services:
  app:
    labels:
      infra-vps.fix: github-workflow          # run the repo's deploy workflow
      infra-vps.fix.repo: <owner>/<repo>
      infra-vps.fix.workflow: deploy.yml      # default deploy.yml
      infra-vps.fix.ref: main                 # default main
      # or: infra-vps.fix: compose-rebuild    # build --pull + up -d in the stack dir
      # or: infra-vps.fix: compose-pull       # pull + up -d (third-party image)
```

For `github-workflow` the workflow must have `workflow_dispatch` and must
not be stopped by the build cache: pass a per-build `SECURITY_REFRESH`
build arg before the `apt-get upgrade` layer (see TtsService). The token
must cover the repo.

A new kind of fix = a function in `EXECUTORS` (`security-fix-bot.py`) plus
its rule in `FIX_ACTIONS` / `plan_fixes` (summarizer).

### GitHub token for `github-workflow`

Fine-grained personal access token: repositories `infra-vps`,
`tts-service`, `EnglishBot-with-agents` (and new ones), permission
**Actions: Read and write**, nothing else. Then:

```bash
./scripts/encrypt-value.sh "<token>"   # -> add GITHUB_FIX_TOKEN=enc:... to config/notify.env
```

(or a plain `GITHUB_FIX_TOKEN=...` in `/etc/infra-vps/notify.env`, chmod 600).
Without it those fixes are listed with `[needs GITHUB_FIX_TOKEN]` and no button.

## A vulnerability shows up in the report. What now?

- **host**: usually fixed in `-updates`, not `-security`; it will arrive with
  the security pocket soon, or run `sudo apt upgrade` by hand.
- **a service image**, base OS package: wait for Monday rebuild, or run the
  service's deploy workflow manually (`Actions -> Run workflow`).
- **a service image**, Python package: check for an open Dependabot PR
  (it stays open only if tests failed), or bump it yourself.
- **nginx**: rebuilt with Alpine fixes on every infra deploy and weekly; to force it now run the infra deploy workflow manually.
- **Dockge**: same, via `007-install-dockge.sh`. What stays after a rebuild
  (`🛠 deps`) is Dockge's own npm packages and the Go runtime of build tools
  left in the upstream image (esbuild, healthcheck): only an upstream release
  fixes them. Upstream has not released since 2025-03 (1.5.0); its `:nightly`
  rebuilds only the app layer on a `:base` from 2026-03, and security issues
  (#999, #1009, #1011, #1015) are open without answer. Measured 2026-11-23:
  218 findings / 15 CRITICAL on `louislam/dockge:1` -> 115 / 6 on our build,
  no Debian findings left. Dockge listens on 127.0.0.1 only.
- **Other stacks serving static files**: use `image: infra-vps-nginx:local` with
  `pull_policy: never` (the image exists only in the local Docker store). The infra
  deploy recreates every running stack that uses it, so they get each rebuild too.
- **a stack deployed only through Dockge** (no CI): `docker compose pull && docker compose up -d` in that stack.

## Ignoring a finding

Add the ID with a reason and date to `scheduled-tasks/security-report.trivyignore`.
Use it only for findings that do not apply, never to silence a real fix.

## GitHub repository settings (once per repo)

- Settings -> Code security: enable **Dependabot alerts** and **Dependabot security updates**.
- Scheduled workflows are disabled by GitHub after 60 days without commits;
  auto-merged Dependabot PRs normally keep the repo active.
- Workflow emails on failure are the signal that an auto update broke tests.
