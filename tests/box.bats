#!/usr/bin/env bats
#
# Starts real Boxes through bin/claude-box. These need Docker and an Image on
# the Host:
#
#   scripts/build-image.sh
#   bats tests/box.bats
#
# They use their own home volume, so the developer's Claude login is untouched.
# Box Caches are per Workspace, so a test's Workspace brings its own.

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
  # Every Box leaves its Workspace's Docker data and Box Caches behind on
  # purpose; in the tests they are throwaway.
  forget_workspace_volumes
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

@test "a customised ccstatusline layout survives a Box restart, because it lives in the claude-home volume" {
  run box_shell '
    mkdir -p ~/.config/ccstatusline
    cat > ~/.config/ccstatusline/settings.json <<EOF
{
  "version": 4,
  "lines": [[ { "id": "1", "type": "custom-text", "customText": "MARKER-XYZ" } ]],
  "globalOverrides": {}
}
EOF'
  [ "$status" -eq 0 ]

  # A second Box, same mechanism as the test above.
  run box_shell 'echo "{}" | ccstatusline'
  [ "$status" -eq 0 ]
  [[ "$output" == *"MARKER-XYZ"* ]]
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
  forget_workspace_volumes
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

@test "a commit made by Claude in the Box carries the Host's Git name and email" {
  config="$(mktemp)"
  GIT_CONFIG_GLOBAL="$config" git config --global user.name "Box Test Developer"
  GIT_CONFIG_GLOBAL="$config" git config --global user.email "box-test@example.com"

  # In ~ rather than the mounted Workspace: a Workspace directory owned by the
  # Host's user looks dubious to Git once it runs as claude (UID 1000) inside
  # the Box, which is a Docker-Desktop-on-macOS detail unrelated to this test.
  GIT_CONFIG_GLOBAL="$config" run box_shell '
    mkdir -p ~/work && cd ~/work
    git init -q repo && cd repo
    git commit --allow-empty -q -m "test"
    git log -1 --format="%an <%ae>"'
  rm -f "$config"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Box Test Developer <box-test@example.com>"* ]]
}

@test "git push from the Box fails for lack of credentials" {
  run box_shell '
    mkdir -p ~/work && cd ~/work
    git init -q repo && cd repo
    git commit --allow-empty -q -m "test"
    GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10" \
      git push git@github.com:torvalds/linux.git HEAD:refs/heads/this-will-fail'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Permission denied"* ]]
}

@test "CLAUDE_BOX_GH_TOKEN and CLAUDE_BOX_GITLAB_TOKEN reach the Box as GH_TOKEN and GITLAB_TOKEN" {
  CLAUDE_BOX_GH_TOKEN=a-github-token CLAUDE_BOX_GITLAB_TOKEN=a-gitlab-token \
    run box_shell 'env | grep -E "^(GH_TOKEN|GITLAB_TOKEN)="'
  [ "$status" -eq 0 ]
  [[ "$output" == *"GH_TOKEN=a-github-token"* ]]
  [[ "$output" == *"GITLAB_TOKEN=a-gitlab-token"* ]]
}

@test "no GitHub or GitLab token env var exists in the Box when neither is set on the Host" {
  unset CLAUDE_BOX_GH_TOKEN CLAUDE_BOX_GITLAB_TOKEN
  run box_shell 'env | grep -E "GH_TOKEN|GITLAB_TOKEN" || echo NONE'
  [ "$status" -eq 0 ]
  [[ "$output" == *"NONE"* ]]
  [[ "$output" != *"TOKEN="* ]]
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
  forget_workspace_volumes
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

@test "nothing of the Host's home reaches the Box, caches included" {
  # $HOME is the Host's home as this test's shell sees it; the Box has its own
  # at the same place in its own filesystem, so the Host's path is the honest
  # thing to look for.
  run box_shell '
    for path in '"$HOME"' '"$HOME"'/.m2 '"$HOME"'/.gradle '"$HOME"'/.npm '"$HOME"'/.local/share/pnpm '"$HOME"'/.cache/ms-playwright; do
      test -e "$path" && echo "VISIBLE $path"
    done
    echo DONE'
  [ "$status" -eq 0 ]
  [[ "$output" != *"VISIBLE"* ]]
  [[ "$output" == *"DONE"* ]]
}

@test "what a build downloads lands in the Workspace's Box Caches and the next Box finds it" {
  # Where Maven, Gradle, npm, pnpm and Playwright themselves put what they
  # download, with no setting in the Image pointing any of them anywhere else.
  run box_shell '
    mkdir -p ~/.m2/repository ~/.gradle/wrapper/dists ~/.npm ~/.local/share/pnpm ~/.cache/ms-playwright
    for path in ~/.m2/repository/marker ~/.gradle/wrapper/dists/marker ~/.npm/marker ~/.local/share/pnpm/marker ~/.cache/ms-playwright/marker; do
      echo downloaded > "$path"
    done
    id -un'
  [ "$status" -eq 0 ]
  [[ "$output" == *"claude"* ]]

  # A second Box: the Box Caches are volumes, so they outlive the first one.
  run box_shell 'cat ~/.m2/repository/marker ~/.gradle/wrapper/dists/marker ~/.npm/marker ~/.local/share/pnpm/marker ~/.cache/ms-playwright/marker'
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c downloaded)" -eq 5 ]
}

@test "another Workspace downloads into Box Caches of its own" {
  run box_shell '
    mkdir -p ~/.m2/repository ~/.local/share/pnpm
    echo here > ~/.m2/repository/marker
    echo here > ~/.local/share/pnpm/marker'
  [ "$status" -eq 0 ]

  enter_other_workspace
  run box_shell 'cat ~/.m2/repository/marker ~/.local/share/pnpm/marker 2>&1; ls -A ~/.m2 ~/.local/share/pnpm 2>&1'
  status_other="$status"
  other_output="$output"
  forget_workspace_volumes
  leave_other_workspace

  [ "$status_other" -eq 0 ]
  [[ "$other_output" != *"here"* ]]
}

# Drives tests/code-graph-probe.sh in a --code-graph Box on the current
# directory. The probe asks the Code Graph the way Claude's MCP client does
# and prints one marker line per thing a test reads; see the script.
probe_code_graph() {
  "$CLAUDE_BOX" --no-pull --shell --code-graph < "$BATS_TEST_DIRNAME/code-graph-probe.sh"
}

# The function the probe queries the graph for, in a Workspace file. Nothing
# indexes it: a --code-graph Box does that itself on the first MCP connection.
plant_marker_function() {
  mkdir -p "$WORKSPACE/src"
  cat > "$WORKSPACE/src/marker.js" <<'EOF'
export function boxTestMarkerFunction(name) {
  return `hello ${name}`;
}
EOF
}

# One marker line's value, by name.
marker() {
  local name="$1" probed="$2"
  printf '%s\n' "$probed" | sed -n "s/^$name: //p" | head -1
}

@test "a query in a --code-graph Box is answered from a graph nobody indexed by hand" {
  plant_marker_function

  run probe_code_graph
  [ "$status" -eq 0 ]

  # This Box is the first on the Workspace, so it started without a graph.
  [ "$(marker PREEXISTING "$output")" = "no" ]
  # The entrypoint configured the server, because claude-box said so.
  [[ "$(marker AUTO_INDEX "$output")" == *"true"* ]]
  # The Workspace is in the graph, and the probe never asked for an index.
  [[ "$(marker PROJECTS "$output")" == *"$WORKSPACE"* ]]
  # And the query is answered with the file and line the function is on.
  [[ "$(marker ANSWER "$output")" == *"boxTestMarkerFunction"* ]]
  [[ "$(marker ANSWER "$output")" == *"src/marker.js"* ]]
}

@test "the Code Graph of a Workspace is found again by the next Box on it" {
  plant_marker_function

  run probe_code_graph
  [ "$status" -eq 0 ]
  [ "$(marker PREEXISTING "$output")" = "no" ]
  first_project="$(marker PROJECT "$output")"

  # A second Box: the graph is a Box Cache of the Workspace, so it outlives
  # the first one.
  run probe_code_graph
  [ "$status" -eq 0 ]
  [ "$(marker PREEXISTING "$output")" = "yes" ]
  [ "$(marker PROJECT "$output")" = "$first_project" ]
  [[ "$(marker ANSWER "$output")" == *"boxTestMarkerFunction"* ]]
}

@test "another Workspace has a Code Graph of its own" {
  plant_marker_function

  run probe_code_graph
  [ "$status" -eq 0 ]
  here="$(marker PROJECTS "$output")"

  enter_other_workspace
  run probe_code_graph
  status_other="$status"
  there="$(marker PROJECTS "$output")"
  forget_workspace_volumes
  leave_other_workspace

  [ "$status_other" -eq 0 ]
  # The second Workspace's graph knows only itself: the first Workspace's
  # path is not in it.
  [[ "$there" != *"$WORKSPACE"* ]]
  [[ "$here" != "$there" ]]
}

@test "indexing cannot reach outside the Workspace" {
  plant_marker_function

  run probe_code_graph
  [ "$status" -eq 0 ]
  [ "$(marker ROOT "$output")" = "$WORKSPACE" ]
  # $HOME in the Box holds Claude's login and every Box Cache; the server
  # refuses it rather than indexing it.
  [[ "$(marker OUTSIDE "$output")" == *"outside the allowed root"* ]]
  [[ "$(marker PROJECTS "$output")" != *"/home/claude"* ]]
}

@test "the graph UI never starts, so there is nothing for a published port to reach" {
  plant_marker_function

  run probe_code_graph
  [ "$status" -eq 0 ]
  [[ "$(marker UI_ENABLED "$output")" == *"false"* ]]
  [ "$(marker UI_LISTENING "$output")" = "no" ]
}

@test "Claude in the Box accepts the --mcp-config claude-box registers the server with" {
  # Read from the CLI rather than written out again, so the two cannot drift.
  config="$(
    sed -n 's/^readonly CODE_GRAPH_MCP_CONFIG=.\(.*\).$/\1/p' "$BATS_TEST_DIRNAME/../bin/claude-box"
  )"
  [ -n "$config" ]

  # `claude doctor` validates every --mcp-config value before doing anything,
  # which is as far as a Box with no login can get. --mcp-config takes several
  # values, so `doctor` itself is read as a second one and reported missing:
  # that complaint is expected, and the config claude-box sends must not be
  # named beside it.
  run box_shell "claude --mcp-config '$config' doctor 2>&1 | head -5"
  [ "$status" -eq 0 ]
  [[ "$output" != *"mcpServers"* ]]
  [[ "$output" != *"codebase-memory-mcp"* ]]

  # The same invocation with a config Claude cannot read, to show the check
  # above would have caught one.
  run box_shell "claude --mcp-config '{\"mcpServers\":}' doctor 2>&1 | head -5"
  [ "$status" -eq 0 ]
  [[ "$output" == *"mcpServers"* ]]
}

@test "a Box without --code-graph leaves no Box Cache for a graph on the Host" {
  run box_shell 'test -e ~/.cache/codebase-memory-mcp && ls -A ~/.cache/codebase-memory-mcp; echo DONE'
  [ "$status" -eq 0 ]
  # The directory is in the Image, so it exists; nothing is mounted onto it
  # and nothing wrote to it.
  [[ "$output" == *"DONE"* ]]
  [[ "$output" != *".db"* ]]

  # The one a --code-graph Box would have given this Workspace.
  graph_cache="$(workspace_volumes --code-graph | grep codegraph)"
  [ -n "$graph_cache" ]
  run docker volume ls --format '{{.Name}}'
  [ "$status" -eq 0 ]
  [[ "$output" != *"$graph_cache"* ]]
}

@test "a Box without --code-graph has no CBM environment and no Code Graph configured for it" {
  run box_shell 'env | grep -E "CBM_|CLAUDE_BOX_CODE_GRAPH" || echo NONE'
  [ "$status" -eq 0 ]
  [[ "$output" == *"NONE"* ]]

  # The server is on the PATH either way — it is in the Image — but nothing
  # turned auto_index on for this Box.
  run box_shell 'codebase-memory-mcp config get auto_index'
  [ "$status" -eq 0 ]
  [[ "$output" == *"false"* ]]
}
