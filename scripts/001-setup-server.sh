#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "[1/9] Removing conflicting Docker packages..."
for pkg in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
  apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done

echo "[2/9] Installing prerequisites..."
apt-get update
apt-get install -y ca-certificates curl git openssl sudo openssh-server

echo "[3/9] Adding Docker official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "[4/9] Adding Docker apt repository..."
. /etc/os-release

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "[5/9] Installing Docker Engine and Compose plugin..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[6/9] Enabling Docker service..."
systemctl enable docker
systemctl start docker

echo "[7/9] Ensuring deploy user exists..."
if id -u deploy >/dev/null 2>&1; then
  echo "User 'deploy' already exists."
else
  adduser --disabled-password --gecos "" deploy
  echo "User 'deploy' created."
fi

usermod -aG sudo deploy
usermod -aG docker deploy

if [[ -f /root/.ssh/authorized_keys ]]; then
  install -d -m 0700 -o deploy -g deploy /home/deploy/.ssh
  install -m 0600 -o deploy -g deploy /root/.ssh/authorized_keys /home/deploy/.ssh/authorized_keys
  echo "Copied root authorized_keys to deploy user."
fi

echo "[8/9] Configuring deploy sudo and SSH hardening..."
install -d -m 0750 /etc/sudoers.d
cat > /etc/sudoers.d/90-deploy <<'EOF'
deploy ALL=(ALL) NOPASSWD:ALL
EOF
chmod 0440 /etc/sudoers.d/90-deploy
visudo -cf /etc/sudoers.d/90-deploy >/dev/null

install -d -m 0755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/90-deploy-hardening.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
PermitEmptyPasswords no
X11Forwarding no
EOF

sshd -t
systemctl restart ssh || systemctl restart sshd
echo "Deploy sudo configured and SSH hardened for key-only access."

echo "[9/9] Verifying installation..."
docker --version
docker compose version

echo
echo "Docker installed successfully."
echo "Use: docker compose up -d"
echo
echo "User 'deploy' is ready with sudo and docker access."
echo "SSH password login is disabled."
echo "SSH root login is disabled."
echo "You can log in as: deploy"
