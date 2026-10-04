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

@test "passes the Host's Git identity to the Box, read from Git config" {
  config="$(mktemp)"
  GIT_CONFIG_GLOBAL="$config" git config --global user.name "TestDeveloper"
  GIT_CONFIG_GLOBAL="$config" git config --global user.email "test@example.com"

  GIT_CONFIG_GLOBAL="$config" run "$CLAUDE_BOX" --dry-run
  rm -f "$config"
  [ "$status" -eq 0 ]
  [[ "$output" == *"-e GIT_AUTHOR_NAME=TestDeveloper"* ]]
  [[ "$output" == *"-e GIT_COMMITTER_NAME=TestDeveloper"* ]]
  [[ "$output" == *"-e GIT_AUTHOR_EMAIL=test@example.com"* ]]
  [[ "$output" == *"-e GIT_COMMITTER_EMAIL=test@example.com"* ]]
}

@test "does not pass a Git identity to the Box when Git has none configured" {
  missing_config="$(mktemp -u)"
  GIT_CONFIG_GLOBAL="$missing_config" GIT_CONFIG_NOSYSTEM=1 run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"GIT_AUTHOR_NAME"* ]]
  [[ "$output" != *"GIT_AUTHOR_EMAIL"* ]]
  [[ "$output" != *"GIT_COMMITTER_NAME"* ]]
  [[ "$output" != *"GIT_COMMITTER_EMAIL"* ]]
}

@test "passes CLAUDE_BOX_GH_TOKEN into the Box as GH_TOKEN, which gh reads directly" {
  CLAUDE_BOX_GH_TOKEN=a-github-token run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-e GH_TOKEN=a-github-token"* ]]
}

@test "passes CLAUDE_BOX_GITLAB_TOKEN into the Box as GITLAB_TOKEN, which glab reads directly" {
  CLAUDE_BOX_GITLAB_TOKEN=a-gitlab-token run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"-e GITLAB_TOKEN=a-gitlab-token"* ]]
}

@test "no GitHub or GitLab token env var exists in the Box when neither is set on the Host" {
  unset CLAUDE_BOX_GH_TOKEN CLAUDE_BOX_GITLAB_TOKEN
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"GH_TOKEN"* ]]
  [[ "$output" != *"GITLAB_TOKEN"* ]]
}

@test "--help documents the GitHub and GitLab token variables" {
  run "$CLAUDE_BOX" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"CLAUDE_BOX_GH_TOKEN"* ]]
  [[ "$output" == *"CLAUDE_BOX_GITLAB_TOKEN"* ]]
}

@test "--code-graph starts Claude with the code-graph MCP server" {
  run "$CLAUDE_BOX" --dry-run --code-graph
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude --dangerously-skip-permissions --mcp-config"* ]]
  [[ "$output" == *'code-graph'* ]]
  [[ "$output" == *'codebase-memory-mcp'* ]]
}

@test "--code-graph puts --mcp-config behind a prompt, which it would otherwise swallow" {
  # Claude's --mcp-config takes several values, so a prompt standing right
  # behind it is read as another config file.
  run "$CLAUDE_BOX" --dry-run --code-graph "find the dead code"
  [ "$status" -eq 0 ]
  [[ "$output" == *"find\ the\ dead\ code --mcp-config"* ]]
  [[ "$output" != *"--mcp-config "*"find\ the\ dead\ code"* ]]
}

@test "CLAUDE_BOX_CODE_GRAPH does what the flag does" {
  # Compared whole rather than feature by feature: the two ways in must give
  # the same Box, not merely both mention the graph.
  with_flag="$("$CLAUDE_BOX" --dry-run --code-graph)"
  with_variable="$(CLAUDE_BOX_CODE_GRAPH=1 "$CLAUDE_BOX" --dry-run)"
  [ "$with_flag" = "$with_variable" ]
  [[ "$with_variable" == *"--mcp-config"* ]]
}

@test "--code-graph gives the Workspace a Box Cache for its graph and confines indexing to it" {
  run "$CLAUDE_BOX" --dry-run --code-graph
  [ "$status" -eq 0 ]
  [[ "$output" =~ -v\ claude-codegraph-[A-Za-z0-9_.-]+:/home/claude/\.cache/codebase-memory-mcp ]]
  [[ "$output" == *"-e CBM_ALLOWED_ROOT=$WORKSPACE"* ]]
  [[ "$output" == *"-e CLAUDE_BOX_CODE_GRAPH=1"* ]]
}

@test "the graph Box Cache is the same on every start in a Workspace, and another Workspace's is not" {
  here="$(workspace_volumes --code-graph)"
  # The six a plain Box gets, plus the graph.
  [ "$(printf '%s\n' "$here" | wc -l | tr -d ' ')" -eq 7 ]
  [ "$here" = "$(workspace_volumes --code-graph)" ]

  enter_other_workspace
  there="$(workspace_volumes --code-graph)"
  leave_other_workspace

  [ "$here" != "$there" ]
}

@test "a Box without --code-graph has no MCP config, no graph mount and nothing of the server" {
  run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"--mcp-config"* ]]
  [[ "$output" != *"codegraph"* ]]
  [[ "$output" != *"codebase-memory-mcp"* ]]
  [[ "$output" != *"CBM_"* ]]
  [[ "$output" != *"CLAUDE_BOX_CODE_GRAPH"* ]]
}

@test "an empty CLAUDE_BOX_CODE_GRAPH leaves the Box without a graph" {
  CLAUDE_BOX_CODE_GRAPH= run "$CLAUDE_BOX" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" != *"--mcp-config"* ]]
  [[ "$output" != *"codegraph"* ]]
}

@test "--code-graph publishes no port, so the graph UI is unreachable even if it ran" {
  run "$CLAUDE_BOX" --dry-run --code-graph
  [ "$status" -eq 0 ]
  [[ "$output" != *" -p "* ]]
  [[ "$output" != *"--publish"* ]]
  [[ "$output" != *"9749"* ]]
}

@test "--shell --code-graph opens a shell in a Box that has the graph but no Claude to register it with" {
  run "$CLAUDE_BOX" --dry-run --shell --code-graph
  [ "$status" -eq 0 ]
  [[ "$output" == *"bash -l"* ]]
  [[ "$output" == *"-e CLAUDE_BOX_CODE_GRAPH=1"* ]]
  [[ "$output" != *"--mcp-config"* ]]
}

@test "--help documents --code-graph, CLAUDE_BOX_CODE_GRAPH and that the graph can lag the working tree" {
  run "$CLAUDE_BOX" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"--code-graph"* ]]
  [[ "$output" == *"CLAUDE_BOX_CODE_GRAPH"* ]]
  [[ "$output" == *"codebase-memory-mcp"* ]]
  [[ "$output" == *"lag the working tree"* ]]
}
