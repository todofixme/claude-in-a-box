#!/usr/bin/env bats
#
# Tests for the claude-box CLI at its seam: the docker argv it assembles.
# `--dry-run` prints that argv instead of executing it, so these tests need
# neither Docker nor a built Image.

load helper

setup() {
  enter_workspace
}

teardown() {
  leave_workspace
}

@test "mounts the Workspace into the Box at its Host path and works there" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-v $WORKSPACE:$WORKSPACE"* ]]
  [[ "$output" == *"-w $WORKSPACE"* ]]
}

@test "starts Claude in YOLO mode from the published Image, pulling it first" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--pull always"* ]]
  [[ "$output" == *"ghcr.io/todofixme/claude-in-a-box:latest claude --dangerously-skip-permissions"* ]]
}

@test "keeps Claude's login and state in the shared claude-home volume" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-v claude-home:/home/claude"* ]]
}

@test "passes unrecognised arguments through to Claude" {
  run "$CLAUDE_BOX" --dry-run --resume
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --dangerously-skip-permissions --resume"* ]]
}

@test "passes arguments after -- through to Claude even when they collide with its own flags" {
  run "$CLAUDE_BOX" --dry-run -- --shell --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --dangerously-skip-permissions --shell --dry-run"* ]]
}

@test "--shell opens a bash login shell instead of Claude" {
  run "$CLAUDE_BOX" --dry-run --shell
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude-in-a-box:latest bash -l"* ]]
  [[ "$output" != *"--dangerously-skip-permissions"* ]]
}

@test "--shell rejects Claude arguments rather than silently dropping them" {
  run "$CLAUDE_BOX" --dry-run --shell --resume
  [ "$status" -ne 0 ]
  [[ "$output" == *"--shell takes no Claude arguments"* ]]
}

@test "--no-pull uses the Image already on the Host" {
  run "$CLAUDE_BOX" --dry-run --no-pull
  [ "$status" -eq 0 ]
  [[ "$output" == *"--pull never"* ]]
  [[ "$output" != *"--pull always"* ]]
}

@test "--image starts the Box from a locally built Image" {
  run "$CLAUDE_BOX" --dry-run --no-pull --image claude-in-a-box:dev
  [ "$status" -eq 0 ]
  [[ "$output" == *"--pull never claude-in-a-box:dev claude --dangerously-skip-permissions"* ]]
}

@test "--image= form is accepted too" {
  run "$CLAUDE_BOX" --dry-run --image=claude-in-a-box:dev
  [ "$status" -eq 0 ]
  [[ "$output" == *" claude-in-a-box:dev claude "* ]]
}

@test "--image without a reference fails" {
  run "$CLAUDE_BOX" --dry-run --image
  [ "$status" -ne 0 ]
  [[ "$output" == *"--image needs an Image reference"* ]]
}

@test "CLAUDE_BOX_IMAGE overrides the default Image" {
  CLAUDE_BOX_IMAGE=claude-in-a-box:dev run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *" claude-in-a-box:dev claude "* ]]
}

@test "--image wins over CLAUDE_BOX_IMAGE" {
  CLAUDE_BOX_IMAGE=claude-in-a-box:from-env run "$CLAUDE_BOX" --dry-run --image claude-in-a-box:from-flag
  [ "$status" -eq 0 ]
  [[ "$output" == *" claude-in-a-box:from-flag claude "* ]]
}

@test "a Workspace reached through a symlink is mounted at its physical path" {
  link="$(make_workspace)/link"
  ln -s "$WORKSPACE" "$link"
  cd "$link"
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-v $WORKSPACE:$WORKSPACE"* ]]
  [[ "$output" != *"$link:"* ]]
  rm -rf "$(dirname "$link")"
}

@test "--help documents the flags without starting a Box" {
  run "$CLAUDE_BOX" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--shell"* ]]
  [[ "$output" == *"--no-pull"* ]]
  [[ "$output" == *"--image"* ]]
  [[ "$output" != *"docker run"* ]]
}

@test "asks docker for a terminal only when there is one to forward" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"docker run --rm -i "* ]]
  [[ "$output" != *" -t "* ]]
}

@test "CLAUDE_BOX_HOME_VOLUME overrides the volume holding Claude's state" {
  CLAUDE_BOX_HOME_VOLUME=other-home run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-v other-home:/home/claude"* ]]
  [[ "$output" != *"-v claude-home:"* ]]
}

@test "a trailing -- with nothing after it starts Claude normally" {
  # Guards the `set -u` trap of appending an empty "$@" to the argument array.
  run "$CLAUDE_BOX" --dry-run --
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --dangerously-skip-permissions"* ]]
}

@test "runs the Box privileged, because its own dockerd needs that" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"--privileged"* ]]
}

@test "never mounts the Host's Docker socket into the Box" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"docker.sock"* ]]
}

@test "gives the Workspace its own volume for the Box's Docker data" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ -v\ claude-docker-[A-Za-z0-9_.-]+:/var/lib/docker ]]
}

@test "names the Box after the Workspace" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ --name\ claude-box-[A-Za-z0-9_.-]+ ]]
}

@test "the Box name and Docker data volume are the same on every start in a Workspace" {
  first="$(workspace_box_name):$(workspace_docker_volume)"
  second="$(workspace_box_name):$(workspace_docker_volume)"
  [ "$first" = "$second" ]
}

@test "another Workspace gets another Box name and Docker data volume" {
  here="$(workspace_box_name):$(workspace_docker_volume)"

  enter_other_workspace
  there="$(workspace_box_name):$(workspace_docker_volume)"
  leave_other_workspace

  [ "$here" != "$there" ]
}

@test "gives the Workspace its own Box Caches for Maven and Gradle" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ -v\ claude-maven-[A-Za-z0-9_.-]+:/home/claude/\.m2 ]]
  [[ "$output" =~ -v\ claude-gradle-[A-Za-z0-9_.-]+:/home/claude/\.gradle ]]
}

@test "gives the Workspace its own Box Caches for npm, pnpm and Playwright" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" =~ -v\ claude-npm-[A-Za-z0-9_.-]+:/home/claude/\.npm ]]
  [[ "$output" =~ -v\ claude-pnpm-[A-Za-z0-9_.-]+:/home/claude/\.local/share/pnpm ]]
  [[ "$output" =~ -v\ claude-playwright-[A-Za-z0-9_.-]+:/home/claude/\.cache/ms-playwright ]]
}

@test "mounts nothing of the Host's home, so its frontend and backend caches stay out" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"-v $HOME/.m2"* ]]
  [[ "$output" != *"-v $HOME/.gradle"* ]]
  [[ "$output" != *"-v $HOME/.npm"* ]]
  [[ "$output" != *"-v $HOME/.local/share/pnpm"* ]]
  [[ "$output" != *"-v $HOME/.cache/ms-playwright"* ]]
  [[ "$output" != *":ro"* ]]
}

@test "the Box Caches are the same on every start in a Workspace, and another Workspace's are not" {
  here="$(workspace_volumes)"
  [ "$(printf '%s\n' "$here" | wc -l | tr -d ' ')" -eq 6 ]
  [ "$here" = "$(workspace_volumes)" ]

  enter_other_workspace
  there="$(workspace_volumes)"
  leave_other_workspace

  [ "$here" != "$there" ]
}

@test "--help documents no cache settings, because there are none to make" {
  run "$CLAUDE_BOX" --help
  [ "$status" -eq 0 ]
  [[ "$output" != *"HOST_HOME"* ]]
  [[ "$output" != *"MAVEN"* ]]
  [[ "$output" != *"GRADLE"* ]]
  [[ "$output" != *"NPM"* ]]
  [[ "$output" != *"PNPM"* ]]
  [[ "$output" != *"PLAYWRIGHT"* ]]
}
