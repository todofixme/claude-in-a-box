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
  PINNED_CCSTATUSLINE_VERSION="$(
    sed -n 's/^ARG CCSTATUSLINE_VERSION=\(.*\)$/\1/p' "$BATS_TEST_DIRNAME/../Dockerfile"
  )"
  export PINNED_CCSTATUSLINE_VERSION
  # The release tag, so without its leading `v` for comparison with what the
  # binary reports.
  PINNED_CODE_GRAPH_VERSION="$(
    sed -n 's/^ARG CODEBASE_MEMORY_MCP_VERSION=v\{0,1\}\(.*\)$/\1/p' "$BATS_TEST_DIRNAME/../Dockerfile"
  )"
  export PINNED_CODE_GRAPH_VERSION
}

# Runs a command in a throwaway Box, as the Image's default user. `-i` keeps
# stdin open so a test can pipe input into it; nothing pipes into the ones
# that don't need to.
in_box() {
  docker run --rm -i --pull never "$IMAGE" "$@"
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

@test "the status line is set by managed settings to run ccstatusline, so it applies regardless of the claude-home volume" {
  run in_box cat /etc/claude-code/managed-settings.json
  [ "$status" -eq 0 ]
  [[ "$output" == *'"statusLine"'* ]]
  [[ "$output" == *'"command": "ccstatusline"'* ]]
}

@test "ccstatusline is installed at the version the Image pins" {
  [ -n "$PINNED_CCSTATUSLINE_VERSION" ]
  run in_box ccstatusline --version
  [ "$status" -eq 0 ]
  [[ "$output" == "$PINNED_CCSTATUSLINE_VERSION"* ]]
}

@test "ccstatusline renders the default layout from Claude's session JSON on stdin" {
  run in_box ccstatusline <<< '{"model":{"display_name":"TestModel"}}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Model:"* ]]
  [[ "$output" == *"TestModel"* ]]
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

@test "codebase-memory-mcp is on the PATH at the version the Image pins" {
  [ -n "$PINNED_CODE_GRAPH_VERSION" ]
  run in_box bash -c 'command -v codebase-memory-mcp'
  [ "$status" -eq 0 ]

  run in_box codebase-memory-mcp --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"$PINNED_CODE_GRAPH_VERSION"* ]]
}

@test "codebase-memory-mcp serves the 17 tools a Code Graph is asked with" {
  # 17 is the number a --code-graph Box adds to Claude's context and the
  # reason the server is a flag rather than something every Box carries, so
  # it is counted rather than taken on trust. `--help` ends with the list.
  run in_box codebase-memory-mcp --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"index_repository"* ]]
  [[ "$output" == *"search_graph"* ]]

  tools="$(
    printf '%s\n' "$output" | sed -n '/^Tools:/,$p' |
      tr ',' '\n' | grep -cE '[a-z_]{4,}'
  )"
  [ "$tools" -eq 17 ]
}

@test "~/.cache/codebase-memory-mcp belongs to claude, so the graph's Box Cache seeds correctly" {
  run in_box stat -c '%U:%G' /home/claude/.cache/codebase-memory-mcp
  [ "$status" -eq 0 ]
  [ "$output" = "claude:claude" ]
}

@test "the Image sets no CBM environment: claude-box sets what a --code-graph Box needs" {
  run in_box env
  [ "$status" -eq 0 ]
  [[ "$output" != *"CBM_"* ]]
  [[ "$output" != *"CLAUDE_BOX_CODE_GRAPH"* ]]
}

@test "the Image registers the Code Graph server nowhere: --mcp-config does that per Box" {
  run in_box cat /etc/claude-code/managed-settings.json
  [ "$status" -eq 0 ]
  [[ "$output" != *"codebase-memory-mcp"* ]]
  [[ "$output" != *"mcpServers"* ]]

  # The managed MCP surface takes MCP over from a Workspace's own .mcp.json in
  # every Box, which is why ADR-0005 does not use it.
  run in_box test -e /etc/claude-code/managed-mcp.json
  [ "$status" -ne 0 ]

  # The tarball's own installer writes client configuration; only the binary
  # is kept.
  run in_box bash -c 'ls /usr/local/bin | grep -c codebase-memory'
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}
