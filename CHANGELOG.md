# Changelog

Newest first. What changed and why; details are in `docs/` and git history.

## 2026-11-23
- Dockge now runs our image `infra-vps-dockge:local` (`dockge/image/Dockerfile`:
  `louislam/dockge:1` + `apt-get upgrade`, which also updates docker CLI and
  compose from Docker's repo), built by `007-install-dockge.sh` on every infra
  deploy. Upstream has not released since 2025-03 and its security issues are
  unanswered. Findings 218 -> 115, CRITICAL 15 -> 6; the rest is Dockge's own
  npm deps (needs upstream). Dockge got the auto-fix label.
  The image has `LABEL infra-vps.local-build="true"` so the report counts it as
  ours (`docker build` images lack compose's project label).
- Telegram auto-fix buttons for the security report: classifier proposals per
  component (`github-workflow`, `compose-rebuild`, `compose-pull`,
  `apt-upgrade`), `scripts/security-fix-bot.py` as a systemd service with
  chat/user check, confirmation, live status (steps, GitHub run link, job
  states), result message, and a rescan that always sends a summary with the
  fixed component first. GitHub token: `GITHUB_FIX_TOKEN` in
  `config/notify.env` (fine-grained PAT, Actions rw on infra-vps, tts-service,
  EnglishBot-with-agents). First live fix: tts-service redeploy, OK.
- Security report: unique CVE and package counts, fix route per finding
  (rebuild / deps / upstream / host), CRITICAL with network-exploitable
  (CVSS AV:N) count, Telegram lists non-critical findings per package.
- nginx and tts-service: per-build `SECURITY_REFRESH` (was ISO week in tts,
  absent in nginx), so a rebuild always applies the latest OS fixes.
- Fixed: `HEARTBEAT_WEEKDAY=""` enabled the Monday heartbeat instead of
  disabling it; `decrypt-value.sh`/`encrypt-value.sh` failed without `HOME`.
- Context: the 2026-11-23 report showed 56 new HIGH in tts-service — Debian
  published krb5 1.21.3-5+deb13u2 after the image was built; closed by a rebuild.

## 2026-11-22
- Automatic security updates: unattended-upgrades + needrestart + nightly
  reboot window on the host (`008-setup-auto-updates.sh`), daily Trivy report
  with Telegram, Dependabot with auto-merge in service repos, weekly rebuilds.
- Telegram notifications configured (encrypted config in `config/notify.env`).
