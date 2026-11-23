# Dockge + every Debian/Docker fix available at build time.
# Upstream (louislam/dockge) has not released since 2025-03 and its nightly
# reuses a base image from 2026-03, so OS packages, docker CLI and compose
# inside stay old; open upstream issues #999 #1009 #1011 #1015 ask about it.
# Rebuilt on every infra deploy and weekly (.github/workflows/deploy.yml)
# by scripts/007-install-dockge.sh. The image already has Docker's apt repo,
# so `apt-get upgrade` also updates docker-ce-cli and docker-compose-plugin.
# Not fixed here: Dockge's own npm dependencies (needs an upstream release).
FROM louislam/dockge:1

# Marks the image as ours for the security report (fix route rebuild/deps,
# not "upstream"); compose-built images carry com.docker.compose.project.
LABEL infra-vps.local-build="true"

# Changes on every build, so the build cache never hides a fix.
ARG SECURITY_REFRESH=0
RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y --no-install-recommends \
    && rm -rf /var/lib/apt/lists/*
