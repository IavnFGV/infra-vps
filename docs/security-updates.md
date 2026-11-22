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
| Python dependencies of a service | Dependabot PR -> tests + `pip-audit` -> auto-merge (patch/minor) -> deploy | security PRs as soon as an advisory is published; routine bumps weekly |
| Base image of a service (`python:3.x-slim`, Debian packages inside) | weekly scheduled run of the service deploy workflow (`docker compose build --pull`) | Monday 02:17 UTC |
| Images pinned in this repo (`nginx`) | Dependabot (`docker-compose` ecosystem) -> auto-merge for patch -> infra deploy | daily check |
| Anything the above missed | `scheduled-tasks/security-report.sh` (Trivy) reports it | daily 05:15 |

Major version bumps are never merged automatically: they stay as open PRs.

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

Telegram gets a message only when there is news; on Mondays it also sends a
heartbeat with totals, so silence on Monday means the task is broken.

Files:

- `/var/log/infra-vps-security/latest.txt` — last full report
- `/var/log/infra-vps-security/YYYY-MM-DD.txt` — history (60 days)
- `/var/log/infra-vps-security/scans/*.json` — raw Trivy output of the last run
- `/var/log/infra-vps-scheduled-tasks/infra__security-report.log` — task output
- `/var/log/unattended-upgrades/unattended-upgrades.log` — apt upgrades

## A vulnerability shows up in the report. What now?

- **host**: usually fixed in `-updates`, not `-security`; it will arrive with
  the security pocket soon, or run `sudo apt upgrade` by hand.
- **a service image**, base OS package: wait for Monday rebuild, or run the
  service's deploy workflow manually (`Actions -> Run workflow`).
- **a service image**, Python package: check for an open Dependabot PR
  (major bumps wait for you), or bump it yourself.
- **nginx / other pinned images**: check for a Dependabot PR in this repo.
- **a stack deployed only through Dockge** (no CI): `docker compose pull && docker compose up -d` in that stack.

## Ignoring a finding

Add the ID with a reason and date to `scheduled-tasks/security-report.trivyignore`.
Use it only for findings that do not apply, never to silence a real fix.

## GitHub repository settings (once per repo)

- Settings -> Code security: enable **Dependabot alerts** and **Dependabot security updates**.
- Scheduled workflows are disabled by GitHub after 60 days without commits;
  auto-merged Dependabot PRs normally keep the repo active.
- Workflow emails on failure are the signal that an auto update broke tests.
