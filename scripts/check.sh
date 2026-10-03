#!/usr/bin/env bash
#
# Everything CI and a developer should run before committing: shellcheck over
# the shell sources, then the test suite. The tests that need a built Image
# skip themselves when there is none on the Host.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$repo_root"

echo "==> shellcheck"
shellcheck bin/claude-box scripts/*.sh

echo "==> bats"
bats tests/
