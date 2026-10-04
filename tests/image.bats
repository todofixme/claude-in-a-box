#!/usr/bin/env bats
#
# Tests the built Image itself. These need Docker and an Image on the Host:
#
#   scripts/build-image.sh
#   bats tests/image.bats
#
# Set CLAUDE_BOX_TEST_IMAGE to test a different Image reference.

load helper

setup_file() {
  require_test_image
  # The pinned versions, read from the one place that pins each.
  PINNED_CLAUDE_VERSION="$(
    sed -n 's/^ARG CLAUDE_CODE_VERSION=\(.*\)$/\1/p' "$BATS_TEST_DIRNAME/../Dockerfile"
  )"
  export PINNED_CLAUDE_VERSION
  PINNED_PLAYWRIGHT_CLI_VERSION="$(
    sed -n 's/^ARG PLAYWRIGHT_CLI_VERSION=\(.*\)$/\1/p' "$BATS_TEST_DIRNAME/../Dockerfile"
  )"
  export PINNED_PLAYWRIGHT_CLI_VERSION
}

# Runs a command in a throwaway Box, as the Image's default user.
in_box() {
  docker run --rm --pull never "$IMAGE" "$@"
}

@test "the Image is built for linux/arm64" {
  run docker image inspect --format '{{.Os}}/{{.Architecture}}' "$IMAGE"
  [ "$status" -eq 0 ]
  [ "$output" = "linux/arm64" ]
}

@test "Claude runs as non-root user claude with UID 1000" {
  run in_box id -un
  [ "$status" -eq 0 ]
  [ "$output" = "claude" ]

  run in_box id -u
  [ "$status" -eq 0 ]
  [ "$output" = "1000" ]
}

@test "claude has passwordless sudo" {
  run in_box sudo -n id -u
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "Claude Code is installed at the version the Image pins" {
  [ -n "$PINNED_CLAUDE_VERSION" ]
  run in_box claude --version
  [ "$status" -eq 0 ]
  [[ "$output" == "$PINNED_CLAUDE_VERSION"* ]]
}

@test "the auto-updater is disabled by managed settings" {
  run in_box cat /etc/claude-code/managed-settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"DISABLE_AUTOUPDATER": "1"'* ]]

  # Proves Claude actually reads the managed settings file: the reason names
  # one of the env keys it sets.
  run in_box claude doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Auto-updates: disabled (set by env: DISABLE_"* ]]
}

@test "managed settings leave YOLO mode available" {
  run in_box grep -c disableBypassPermissionsMode /etc/claude-code/managed-settings.json
  [ "$status" -ne 0 ]
}

@test "the Box's home directory belongs to claude, so the claude-home volume is seeded correctly" {
  run in_box stat -c '%U:%G' /home/claude
  [ "$status" -eq 0 ]
  [ "$output" = "claude:claude" ]
}

@test "the Image carries a JDK 21, so a backend Workspace can build with its wrapper" {
  run in_box java -version
  [ "$status" -eq 0 ]
  [[ "$output" == *'version "21'* ]]

  run in_box javac -version
  [ "$status" -eq 0 ]
  [[ "$output" == *" 21"* ]]
}

@test "the Image brings no Gradle or Maven: a Workspace brings its own wrapper" {
  run in_box bash -c 'command -v gradle maven mvn'
  [ "$status" -ne 0 ]
}

@test "the Image carries Docker Engine with the Compose plugin" {
  run in_box bash -c 'command -v dockerd'
  [ "$status" -eq 0 ]

  run in_box docker --version
  [ "$status" -eq 0 ]

  run in_box docker compose version
  [ "$status" -eq 0 ]
}

@test "claude is in the docker group, so it can reach the Box's dockerd" {
  run in_box id -nG
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker"* ]]
}

@test "the Image carries git, gh, glab, jq, yq, ripgrep, httpie and curl" {
  run in_box bash -c 'command -v git gh glab jq yq rg http curl'
  [ "$status" -eq 0 ]
}

@test "the Image sets no Maven or Gradle environment: a Box Cache on each directory is all it takes" {
  run in_box env
  [ "$status" -eq 0 ]
  [[ "$output" != *"MAVEN_"* ]]
  [[ "$output" != *"GRADLE_"* ]]
}

@test "~/.m2 and ~/.gradle belong to claude, so the Box Caches seed correctly" {
  run in_box stat -c '%U:%G' /home/claude/.m2 /home/claude/.gradle
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'claude:claude')" -eq 2 ]
}

@test "corepack is enabled, so pnpm and yarn shims are on the PATH" {
  run in_box bash -c 'command -v corepack && command -v pnpm && command -v yarn'
  [ "$status" -eq 0 ]
}

@test "Playwright CLI is installed at the version the Image pins" {
  [ -n "$PINNED_PLAYWRIGHT_CLI_VERSION" ]
  run in_box playwright-cli --version
  [ "$status" -eq 0 ]
  [[ "$output" == "$PINNED_PLAYWRIGHT_CLI_VERSION"* ]]
}

@test "the Image carries the system libraries headless Chromium needs" {
  run in_box bash -c 'dpkg -s libnss3 libatk-bridge2.0-0t64 libgbm1 >/dev/null && echo OK'
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK"* ]]
}

@test "the Image sets no npm, pnpm or Playwright environment: each Box Cache sits where the tool already looks" {
  run in_box env
  [ "$status" -eq 0 ]
  [[ "$output" != *"NPM_CONFIG_CACHE"* ]]
  [[ "$output" != *"PNPM_HOME"* ]]
  [[ "$output" != *"PLAYWRIGHT_BROWSERS_PATH"* ]]
}

@test "~/.npm, ~/.local/share/pnpm and ~/.cache/ms-playwright belong to claude, so the Box Caches seed correctly" {
  run in_box stat -c '%U:%G' /home/claude/.npm /home/claude/.local/share/pnpm /home/claude/.cache/ms-playwright
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'claude:claude')" -eq 3 ]
}

@test "pnpm is pointed at the Box Cache store-dir, since its own default ignores \$HOME" {
  run in_box pnpm store path
  [ "$status" -eq 0 ]
  [[ "$output" == *"/home/claude/.local/share/pnpm/"* ]]
}

@test "~/.cache and ~/.local/share belong to claude too, so a tool can create a sibling directory there" {
  # corepack's own cache lands at ~/.cache/node, next to ~/.cache/ms-playwright
  # above: a parent `install -d` left root-owned would block that with EACCES.
  run in_box stat -c '%U:%G' /home/claude/.cache /home/claude/.local /home/claude/.local/share
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'claude:claude')" -eq 3 ]
}
