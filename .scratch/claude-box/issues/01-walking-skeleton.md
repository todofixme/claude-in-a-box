# 01: Walking skeleton: a Box running Claude in YOLO mode

**What to build:** A developer runs `claude-box` in any project directory on the Host and lands in Claude Code running with `--dangerously-skip-permissions` inside a Box. The Image is built locally from `node:24-trixie` with Claude Code installed from npm at a pinned version, a non-root user `claude` (UID 1000, passwordless sudo), and Claude managed settings that disable the auto-updater. The Workspace is mounted at the same absolute path as on the Host so each project keeps its own session history and memory. Claude's login and state survive restarts via a shared `claude-home` volume. The start command passes extra arguments to Claude, offers `--shell` for a bash session instead, uses `--pull always` by default with `--no-pull` as escape hatch, and lets the Image reference be overridden so locally built Images can be tested before GHCR exists. Start the README (English) describing install and usage.

**Blocked by:** None (can start immediately)

**Model:** opus

**Status:** ready-for-human

- [x] Image builds locally for linux/arm64 from `node:24-trixie`
- [x] Claude Code version is pinned in one place in the Image definition and the auto-updater is disabled via managed settings
- [x] Claude runs as non-root user `claude` with passwordless sudo
- [x] `claude-box` started in a project directory opens Claude in YOLO mode with the Workspace as working directory at its Host path
- [ ] After logging in once, stopping and restarting the Box keeps the login; `claude-box --resume` finds the project's previous session
- [x] Two different Workspaces have separate session histories
- [x] `claude-box --shell` opens bash; `--no-pull` skips pulling; Image reference is overridable
- [x] README explains prerequisites, putting `claude-box` on the PATH, and the flags

## Comments

Implemented. `scripts/check.sh` runs shellcheck plus 30 bats tests in three
parts: `tests/cli.bats` (the docker argv, via `--dry-run`), `tests/image.bats`
(the built Image) and `tests/box.bats` (real Boxes).

The one criterion left unticked is the login half of "after logging in once,
stopping and restarting the Box keeps the login". It needs an interactive
browser login, which an agent cannot perform. The mechanism it rests on is
covered: state written under `/home/claude` in one Box is present in the next
(`tests/box.bats`), and that is where Claude keeps its credentials. The
`--resume` half is covered by `tests/box.bats` showing a per-Workspace session
transcript in the volume, plus the argument pass-through test in
`tests/cli.bats`. Please confirm with one manual login.

Two additions beyond the ticket:

- `CLAUDE_BOX_HOME_VOLUME` overrides the home volume name. Needed so
  `tests/box.bats` can start real Boxes without touching the developer's own
  Claude login; also useful for a second, separate login.
- Managed settings set `DISABLE_UPDATES` next to `DISABLE_AUTOUPDATER`.
  `DISABLE_AUTOUPDATER` alone still lets `claude update` run, which would move
  the Box off the version the Image pins.

`-t` is passed to docker only when stdin is a terminal; docker refuses to start
otherwise, which would make `--shell` unusable from a script or a test.

The default Image reference is already `ghcr.io/todofixme/claude-in-a-box:latest`
with `--pull always`, so `claude-box` with no flags will fail until 02 publishes
it. Until then: `scripts/build-image.sh` and
`claude-box --no-pull --image claude-in-a-box:dev`.

### Review

`/code-review` ran both axes against the spec. Findings acted on:

- README used "Mac", "your machine" and "project" where `GLOSSARY.md` requires
  Host and Workspace. The README now introduces Host alongside Box, Image and
  Workspace, and uses the glossary's words throughout.
- README claimed the Box kept Claude from endangering anything else, without
  carrying ADR-0002's accepted risk. It now has a "What a Box does not
  protect" section: no network filter, Workspace contents can leave.
- README stated "only the Workspace is mounted" as an invariant, which
  ADR-0003 will contradict in 04. Rephrased as current state.
- `in_box` meant two incompatible things: argv in `tests/image.bats`, a shell
  script on stdin in `tests/box.bats`. The second is now `box_shell`.
- The Image-skip and Workspace setup were duplicated across test files; they
  live in `tests/helper.bash`.
- `CLAUDE_BOX_DEV_TAG` in `scripts/build-image.sh` had no readers and was not
  asked for. Removed.
- The Dockerfile explained why UID 1000 is reused but not that renaming `node`
  leaves no `node` user or group behind. Noted there now.
- README called `--no-pull` the offline escape hatch without saying it maps to
  `--pull never` and so refuses to pull at all. Said explicitly now.

Findings noted and kept as they are:

- `--dry-run` is public surface that exists for the test suite. It is the seam
  the tests were agreed at, so it stays.
- The `# renovate:` comment on the version pin belongs to 08. One line, no
  behaviour, and it saves 08 having to find the pin.
