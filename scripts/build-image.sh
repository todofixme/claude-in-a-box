#!/usr/bin/env bash
#
# Build the Image locally so it can be tested before it exists in GHCR:
#
#   scripts/build-image.sh
#   claude-box --no-pull --image claude-in-a-box:dev
#
# Pass extra docker build arguments after the script name.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tag="claude-in-a-box:dev"

exec docker build \
  --platform linux/arm64 \
  --tag "$tag" \
  "$@" \
  "$repo_root"
