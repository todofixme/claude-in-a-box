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
