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
  # The pinned version, read from the one place that pins it.
  PINNED_CLAUDE_VERSION="$(
    sed -n 's/^ARG CLAUDE_CODE_VERSION=\(.*\)$/\1/p' "$BATS_TEST_DIRNAME/../Dockerfile"
  )"
  export PINNED_CLAUDE_VERSION
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
