#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
find "${ROOT_DIR}/nginx/sites" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' | sort
