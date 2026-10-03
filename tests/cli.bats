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

@test "mounts the Host's Maven repository and Gradle dependency cache read-only" {
  run env CLAUDE_BOX_HOST_HOME=/Users/dev "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-v /Users/dev/.m2/repository:/host-caches/maven/repository:ro"* ]]
  [[ "$output" == *"-v /Users/dev/.gradle/caches/modules-2:/host-caches/gradle/modules-2:ro"* ]]
}

@test "never mounts the Host's ~/.m2 or ~/.gradle themselves, which hold credentials" {
  run env CLAUDE_BOX_HOST_HOME=/Users/dev "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"-v /Users/dev/.m2:"* ]]
  [[ "$output" != *"-v /Users/dev/.gradle:"* ]]
  [[ "$output" != *"/Users/dev/.gradle/caches:"* ]]
}

@test "reads the Host Caches out of the Host's home directory by default" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-v $HOME/.m2/repository:"* ]]
  [[ "$output" == *"-v $HOME/.gradle/caches/modules-2:"* ]]
}

@test "gives Maven and Gradle Box Caches shared by every Box" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-v claude-maven:/box-caches/maven"* ]]
  [[ "$output" == *"-v claude-gradle:/box-caches/gradle"* ]]
}

@test "CLAUDE_BOX_MAVEN_VOLUME and CLAUDE_BOX_GRADLE_VOLUME override the Box Caches" {
  run env CLAUDE_BOX_MAVEN_VOLUME=other-maven CLAUDE_BOX_GRADLE_VOLUME=other-gradle \
    "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-v other-maven:/box-caches/maven"* ]]
  [[ "$output" == *"-v other-gradle:/box-caches/gradle"* ]]
  [[ "$output" != *"-v claude-maven:"* ]]
  [[ "$output" != *"-v claude-gradle:"* ]]
}

@test "an empty CLAUDE_BOX_HOST_HOME fails instead of sharing the Host's caches" {
  run env CLAUDE_BOX_HOST_HOME= "$CLAUDE_BOX" --dry-run
  [ "$status" -ne 0 ]
  [[ "$output" == *"no Host home directory"* ]]
  [[ "$output" != *"$HOME/.m2/repository"* ]]
}

@test "--dry-run creates nothing in the Host's home directory" {
  host_home="$(make_workspace)"
  run env CLAUDE_BOX_HOST_HOME="$host_home" "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$host_home/.m2" ]
  [ ! -e "$host_home/.gradle" ]
  rm -rf "$host_home"
}
