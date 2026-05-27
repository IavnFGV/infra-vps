#!/usr/bin/env bash
set -euo pipefail

echo "=== HARDENING START ==="

echo "[1/6] Fixing SSH permissions..."

fix_ssh_perms() {
  local USERNAME=$1
  local HOME_DIR

  HOME_DIR=$(getent passwd "$USERNAME" | cut -d: -f6)

  if [[ -d "$HOME_DIR/.ssh" ]]; then
    chmod 700 "$HOME_DIR/.ssh"
    chmod 600 "$HOME_DIR/.ssh/authorized_keys" 2>/dev/null || true
    chown -R "$USERNAME:$USERNAME" "$HOME_DIR/.ssh"
    echo "  ✔ $USERNAME SSH perms fixed"
  else
    echo "  ⚠ $USERNAME has no .ssh directory"
  fi
}

fix_ssh_perms root
fix_ssh_perms ivan
fix_ssh_perms deploy

echo
echo "[2/6] Locking passwords for ivan and deploy..."

passwd -l ivan || true
passwd -l deploy || true

echo "  ✔ passwords locked"

echo
echo "[3/6] Writing SSH hardening config..."

mkdir -p /etc/ssh/sshd_config.d

cat > /etc/ssh/sshd_config.d/99-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin prohibit-password
PermitEmptyPasswords no
X11Forwarding no
EOF

echo "  ✔ SSH config written"

echo
echo "[4/6] Validating sshd config..."

sshd -t

echo "  ✔ sshd config valid"

echo
echo "[5/6] Restarting SSH..."

systemctl restart ssh

echo "  ✔ SSH restarted"

echo
echo "[6/6] Installing and configuring Fail2Ban..."

apt-get update -y
apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = ssh
backend = systemd
EOF

systemctl enable fail2ban
systemctl restart fail2ban

echo "  ✔ Fail2Ban enabled"

echo
echo "=== DONE ==="
echo
echo "Check status:"
echo "  sshd -T | grep -E 'passwordauthentication|permitrootlogin'"
echo "  fail2ban-client status sshd"
echo "  passwd -S ivan"
echo "  passwd -S deploy"