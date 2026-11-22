#!/usr/bin/env bash
set -euo pipefail

# Automatic security updates for the host OS (Ubuntu):
#   - unattended-upgrades: security pockets (+ Docker CE repo, + Trivy repo)
#   - needrestart: restart services that use updated libraries automatically
#   - automatic reboot in a fixed night window when a kernel/libc update needs it
#   - Trivy: vulnerability scanner used by scheduled-tasks/security-report.sh
#   - infra-vps-notify: Telegram helper used by scheduled tasks
#
# Idempotent: safe to re-run after changing options.
#
# Options (environment):
#   AUTO_REBOOT=true              reboot automatically when required
#   REBOOT_TIME=04:30             server-local time for that reboot
#   APT_UPDATE_TIME=03:00         refresh package lists
#   APT_UPGRADE_TIME=03:30        install security updates
#   INCLUDE_DOCKER_UPDATES=true   also auto-update docker-ce / containerd / compose
#   INSTALL_TRIVY=true

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

AUTO_REBOOT="${AUTO_REBOOT:-true}"
REBOOT_TIME="${REBOOT_TIME:-04:30}"
APT_UPDATE_TIME="${APT_UPDATE_TIME:-03:00}"
APT_UPGRADE_TIME="${APT_UPGRADE_TIME:-03:30}"
INCLUDE_DOCKER_UPDATES="${INCLUDE_DOCKER_UPDATES:-true}"
INSTALL_TRIVY="${INSTALL_TRIVY:-true}"

UU_CONF="/etc/apt/apt.conf.d/52infra-vps-unattended-upgrades"
AUTO_CONF="/etc/apt/apt.conf.d/20auto-upgrades"
NEEDRESTART_CONF="/etc/needrestart/conf.d/50-infra-vps.conf"
NOTIFY_TARGET="/usr/local/bin/infra-vps-notify"
NOTIFY_CONFIG_DIR="/etc/infra-vps"
NOTIFY_CONFIG_FILE="${NOTIFY_CONFIG_DIR}/notify.env"

log() {
  printf '%s [setup-auto-updates] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*"
}

log "[1/7] Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y unattended-upgrades needrestart curl ca-certificates gnupg python3

if [[ "${INSTALL_TRIVY}" == "true" ]]; then
  log "[2/7] Installing Trivy from the official apt repository"
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://aquasecurity.github.io/trivy-repo/deb/public.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/trivy.gpg
  chmod a+r /etc/apt/keyrings/trivy.gpg
  cat > /etc/apt/sources.list.d/trivy.sources <<'EOF'
Types: deb
URIs: https://aquasecurity.github.io/trivy-repo/deb
Suites: generic
Components: main
Signed-By: /etc/apt/keyrings/trivy.gpg
EOF
  apt-get update
  apt-get install -y trivy
else
  log "[2/7] Skipping Trivy (INSTALL_TRIVY=${INSTALL_TRIVY})"
fi

log "[3/7] Writing ${UU_CONF}"
docker_origin_line=""
if [[ "${INCLUDE_DOCKER_UPDATES}" == "true" ]]; then
  # Containers have restart policies, so a dockerd restart is a short blip.
  docker_origin_line='        "site=download.docker.com";'
fi
trivy_origin_line=""
if [[ "${INSTALL_TRIVY}" == "true" ]]; then
  trivy_origin_line='        "site=aquasecurity.github.io";'
fi

cat > "${UU_CONF}" <<EOF
// Managed by infra-vps/scripts/008-setup-auto-updates.sh — re-run it instead of editing.
Unattended-Upgrade::Origins-Pattern {
        "origin=\${distro_id},archive=\${distro_codename}-security,label=\${distro_id}";
        "origin=\${distro_id}ESMApps,archive=\${distro_codename}-apps-security";
        "origin=\${distro_id}ESM,archive=\${distro_codename}-infra-security";
${docker_origin_line}
${trivy_origin_line}
};
Unattended-Upgrade::Automatic-Reboot "${AUTO_REBOOT}";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "${REBOOT_TIME}";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::SyslogEnable "true";
Dpkg::Options {
        "--force-confdef";
        "--force-confold";
};
EOF
chmod 0644 "${UU_CONF}"

cat > "${AUTO_CONF}" <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
chmod 0644 "${AUTO_CONF}"

log "[4/7] Pinning apt timers: lists ${APT_UPDATE_TIME}, upgrade ${APT_UPGRADE_TIME}, reboot ${REBOOT_TIME}"
install -d -m 0755 /etc/systemd/system/apt-daily.timer.d /etc/systemd/system/apt-daily-upgrade.timer.d
cat > /etc/systemd/system/apt-daily.timer.d/infra-vps.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* ${APT_UPDATE_TIME}
RandomizedDelaySec=10m
Persistent=true
EOF
cat > /etc/systemd/system/apt-daily-upgrade.timer.d/infra-vps.conf <<EOF
[Timer]
OnCalendar=
OnCalendar=*-*-* ${APT_UPGRADE_TIME}
RandomizedDelaySec=10m
Persistent=true
EOF
systemctl daemon-reload
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service

log "[5/7] Configuring needrestart to restart affected services automatically"
install -d -m 0755 /etc/needrestart/conf.d
cat > "${NEEDRESTART_CONF}" <<'EOF'
# Managed by infra-vps/scripts/008-setup-auto-updates.sh
# 'a' = restart services that use updated libraries automatically instead of
# only listing them. Containers have restart policies, so even a dockerd
# restart is a short blip.
$nrconf{restart} = 'a';
EOF
chmod 0644 "${NEEDRESTART_CONF}"

log "[6/7] Installing Telegram notify helper"
chmod 0755 "${REPO_ROOT}/scripts/notify-telegram.sh"
ln -sfn "${REPO_ROOT}/scripts/notify-telegram.sh" "${NOTIFY_TARGET}"
install -d -m 0700 "${NOTIFY_CONFIG_DIR}"
if [[ ! -f "${NOTIFY_CONFIG_FILE}" ]]; then
  cat > "${NOTIFY_CONFIG_FILE}" <<'EOF'
# Telegram notifications for infra-vps scheduled tasks.
# Values may be plain or enc:... (see scripts/encrypt-value.sh).
# Get chat id: send a message to the bot, then open
#   https://api.telegram.org/bot<TOKEN>/getUpdates
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
EOF
  log "Created ${NOTIFY_CONFIG_FILE} — fill in the bot token and chat id"
else
  log "Keeping existing ${NOTIFY_CONFIG_FILE}"
fi
chmod 0600 "${NOTIFY_CONFIG_FILE}"

log "[7/7] Dry run of unattended-upgrades"
unattended-upgrade --dry-run -v 2>&1 | grep -E "Allowed origins|Packages that will be upgraded|No packages found" || true

log "Done"
cat <<EOF

Configured:
  ${UU_CONF}
  ${AUTO_CONF}
  ${NEEDRESTART_CONF}
  /etc/systemd/system/apt-daily{,-upgrade}.timer.d/infra-vps.conf
  ${NOTIFY_TARGET} -> ${REPO_ROOT}/scripts/notify-telegram.sh
  ${NOTIFY_CONFIG_FILE}

Next:
  sudo nano ${NOTIFY_CONFIG_FILE}
  infra-vps-notify "test from \$(hostname)"
  sudo bash ${REPO_ROOT}/scheduled-tasks/security-report.sh   # first scan by hand

Useful:
  systemctl list-timers 'apt-daily*'
  tail -n 50 /var/log/unattended-upgrades/unattended-upgrades.log
  cat /var/run/reboot-required.pkgs 2>/dev/null
EOF
