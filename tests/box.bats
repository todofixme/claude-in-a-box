#!/usr/bin/env bats
#
# Starts real Boxes through bin/claude-box. These need Docker and an Image on
# the Host:
#
#   scripts/build-image.sh
#   bats tests/box.bats
#
# They use their own home volume, so the developer's Claude login is untouched.

load helper

setup_file() {
  require_test_image
  export CLAUDE_BOX_HOME_VOLUME="claude-box-test-home-$$"
  export CLAUDE_BOX_IMAGE="$IMAGE"
}

teardown_file() {
  docker volume rm -f "$CLAUDE_BOX_HOME_VOLUME" >/dev/null 2>&1 || true
}

setup() {
  enter_workspace
}

teardown() {
  # Every Box leaves its Workspace's Docker data behind on purpose; in the
  # tests that data is throwaway.
  forget_docker_volume
  leave_workspace
}

# Runs one shell script in a Box on the current directory. `bash -l` reads it
# from stdin, which is how a non-interactive Box is driven.
box_shell() {
  printf '%s\n' "$1" | "$CLAUDE_BOX" --no-pull --shell
}

@test "the Box works in the Workspace at its Host path" {
  run box_shell 'pwd'
  [ "$status" -eq 0 ]
  [[ "$output" == *"$WORKSPACE"* ]]
}

@test "Claude can read and write the Workspace" {
  echo "from the Host" > "$WORKSPACE/host.txt"

  run box_shell 'cat host.txt && echo "from the Box" > box.txt'
  [ "$status" -eq 0 ]
  [[ "$output" == *"from the Host"* ]]
  [ "$(cat "$WORKSPACE/box.txt")" = "from the Box" ]
}

@test "stopping and restarting the Box keeps Claude's state" {
  run box_shell 'mkdir -p ~/.claude && echo stored > ~/.claude/marker'
  [ "$status" -eq 0 ]

  # A second Box: the first one is gone (--rm), only the volume remains.
  run box_shell 'cat ~/.claude/marker'
  [ "$status" -eq 0 ]
  [[ "$output" == *"stored"* ]]
}

@test "two Workspaces have separate session histories" {
  # Claude records a session under ~/.claude/projects/<working directory>, so
  # Workspaces mounted at their own Host paths cannot share a history. A
  # prompt is enough to create the directory; it need not get an answer.
  run box_shell 'rm -rf ~/.claude/projects; claude -p hi >/dev/null 2>&1; ls ~/.claude/projects'
  [ "$status" -eq 0 ]
  first="$output"
  [ "$(printf '%s\n' "$first" | wc -l | tr -d ' ')" -eq 1 ]

  enter_other_workspace
  run box_shell 'claude -p hi >/dev/null 2>&1; ls ~/.claude/projects'
  status_other="$status"
  second="$output"
  forget_docker_volume
  leave_other_workspace

  [ "$status_other" -eq 0 ]
  # The second Workspace added its own directory next to the first one's,
  # rather than writing into it.
  [ "$(printf '%s\n' "$second" | wc -l | tr -d ' ')" -eq 2 ]
  [[ "$second" == *"$first"* ]]
  [ "$first" != "$second" ]
}

@test "the Box's home directory is writable by claude" {
  run box_shell 'touch ~/writable && id -un'
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude"* ]]
}

@test "--no-pull fails on the Host when the Image is missing, without reaching a registry" {
  run env CLAUDE_BOX_IMAGE="claude-in-a-box:definitely-not-built" \
    "$CLAUDE_BOX" --no-pull --shell
  [ "$status" -ne 0 ]
}

@test "Claude can use the Box's own Docker, Compose plugin included" {
  run box_shell 'id -un && docker run --rm hello-world && docker compose version'
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"Hello from Docker!"* ]]
  [[ "$output" == *"Docker Compose version"* ]]
}

@test "images pulled in a Box stay in the Workspace's Docker data for the next one" {
  run box_shell 'docker pull hello-world'
  [ "$status" -eq 0 ]

  # A second Box: same Workspace, so the same Docker data volume. A Test
  # Container image is cached the same way, just bigger.
  run box_shell 'docker image inspect hello-world >/dev/null && echo cached'
  [ "$status" -eq 0 ]
  [[ "$output" == *"cached"* ]]
}

@test "only one Box per Workspace, while Boxes on other Workspaces run side by side" {
  name="$(workspace_box_name)"
  printf 'sleep 60\n' | "$CLAUDE_BOX" --no-pull --shell >/dev/null 2>&1 &
  running=$!

  for _ in $(seq 60); do
    box_is_running "$name" && break
    sleep 0.5
  done
  box_is_running "$name"

  run box_shell 'true'
  refused_status="$status"
  refused_output="$output"

  enter_other_workspace
  run box_shell 'echo side by side'
  other_status="$status"
  other_output="$output"
  forget_docker_volume
  leave_other_workspace

  docker rm -f "$name" >/dev/null 2>&1 || true
  wait "$running" 2>/dev/null || true

  [ "$refused_status" -ne 0 ]
  [[ "$refused_output" == *"a Box is already running on $WORKSPACE"* ]]
  [ "$other_status" -eq 0 ]
  [[ "$other_output" == *"side by side"* ]]
}

@test "a Box that did not clean up after itself is reported as that, not as a running one" {
  name="$(workspace_box_name)"
  docker create --name "$name" "$CLAUDE_BOX_IMAGE" true >/dev/null

  run box_shell 'true'
  docker rm -f "$name" >/dev/null

  [ "$status" -ne 0 ]
  [[ "$output" == *"did not clean up after itself"* ]]
  [[ "$output" == *"docker rm $name"* ]]
}
