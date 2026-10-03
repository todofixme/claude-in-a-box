# Shared setup for the claude-box test suite. `load helper` to use it.

# The Image the tests that need one run against.
test_image() {
  echo "${CLAUDE_BOX_TEST_IMAGE:-claude-in-a-box:dev}"
}

# Skips the calling file unless the Image is on the Host. Call from setup_file.
require_test_image() {
  local image
  image="$(test_image)"
  docker image inspect "$image" >/dev/null 2>&1 ||
    skip "Image $image is not on the Host; run scripts/build-image.sh first"
  export IMAGE="$image"
}

# A fresh Workspace, as the physical path the CLI resolves to: on macOS a
# temporary directory sits behind the /var -> /private/var symlink.
make_workspace() {
  (cd "$(mktemp -d)" && pwd -P)
}

# Enters a fresh Workspace and remembers it in $WORKSPACE. Call from setup.
enter_workspace() {
  CLAUDE_BOX="$BATS_TEST_DIRNAME/../bin/claude-box"
  WORKSPACE="$(make_workspace)"
  cd "$WORKSPACE" || return 1
}

# Leaves and removes the Workspace. Call from teardown.
leave_workspace() {
  cd "$BATS_TEST_DIRNAME" || return 1
  rm -rf "$WORKSPACE"
}

# The name claude-box gives the Box on the current Workspace.
workspace_box_name() {
  "$CLAUDE_BOX" --dry-run | sed -n 's/.*--name \([^ ]*\).*/\1/p'
}

# The volume holding the Docker data of this Workspace's Box.
workspace_docker_volume() {
  "$CLAUDE_BOX" --dry-run | sed -n 's|.*-v \([^ ]*\):/var/lib/docker.*|\1|p'
}

# A second Workspace next to the one from setup, to compare against. Leave it
# through leave_other_workspace, which puts us back in $WORKSPACE: a teardown
# running from a removed directory can no longer tell which Box is ours.
enter_other_workspace() {
  OTHER_WORKSPACE="$(make_workspace)"
  cd "$OTHER_WORKSPACE" || return 1
}

leave_other_workspace() {
  cd "$WORKSPACE" || return 1
  rm -rf "$OTHER_WORKSPACE"
}

# Throws away the Docker data a Box left behind for the Workspace we are in.
# Call it from the Workspace, before leaving or removing it.
forget_docker_volume() {
  local volume
  volume="$(workspace_docker_volume)"
  [ -n "$volume" ] || return 0
  docker volume rm -f "$volume" >/dev/null 2>&1 || true
}

# Whether a Box of that name is running.
box_is_running() {
  [ -n "$(docker ps --quiet --filter "name=^$1\$")" ]
}

# A throwaway Host home for the Host Caches, so no test reads or writes the
# developer's own ~/.m2 and ~/.gradle. Remembered in $HOST_HOME. Call from
# setup, and leave_host_home from teardown.
enter_host_home() {
  HOST_HOME="$(make_workspace)"
  export CLAUDE_BOX_HOST_HOME="$HOST_HOME"
}

leave_host_home() {
  unset CLAUDE_BOX_HOST_HOME
  rm -rf "$HOST_HOME"
}
