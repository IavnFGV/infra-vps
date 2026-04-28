#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

echo "[1/7] Removing conflicting Docker packages..."
for pkg in docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc; do
  apt-get remove -y "$pkg" >/dev/null 2>&1 || true
done

echo "[2/7] Installing prerequisites..."
apt-get update
apt-get install -y ca-certificates curl git openssl

echo "[3/7] Adding Docker official GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "[4/7] Adding Docker apt repository..."
. /etc/os-release

cat > /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

echo "[5/7] Installing Docker Engine and Compose plugin..."
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[6/7] Enabling Docker service..."
systemctl enable docker
systemctl start docker

echo "[7/7] Verifying installation..."
docker --version
docker compose version

echo
echo "Docker installed successfully."
echo "Use: docker compose up -d"
echo
echo "Optional: allow a non-root user to run Docker:"
echo "  usermod -aG docker <username>"
echo "Then log out and log in again."

usermod -aG docker deploy