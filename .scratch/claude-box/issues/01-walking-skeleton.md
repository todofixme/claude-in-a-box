# 01: Walking skeleton: a Box running Claude in YOLO mode

**What to build:** A developer runs `claude-box` in any project directory on the Host and lands in Claude Code running with `--dangerously-skip-permissions` inside a Box. The Image is built locally from `node:24-trixie` with Claude Code installed from npm at a pinned version, a non-root user `claude` (UID 1000, passwordless sudo), and Claude managed settings that disable the auto-updater. The Workspace is mounted at the same absolute path as on the Host so each project keeps its own session history and memory. Claude's login and state survive restarts via a shared `claude-home` volume. The start command passes extra arguments to Claude, offers `--shell` for a bash session instead, uses `--pull always` by default with `--no-pull` as escape hatch, and lets the Image reference be overridden so locally built Images can be tested before GHCR exists. Start the README (English) describing install and usage.

**Blocked by:** None (can start immediately)

**Model:** opus

**Status:** ready-for-agent

- [ ] Image builds locally for linux/arm64 from `node:24-trixie`
- [ ] Claude Code version is pinned in one place in the Image definition and the auto-updater is disabled via managed settings
- [ ] Claude runs as non-root user `claude` with passwordless sudo
- [ ] `claude-box` started in a project directory opens Claude in YOLO mode with the Workspace as working directory at its Host path
- [ ] After logging in once, stopping and restarting the Box keeps the login; `claude-box --resume` finds the project's previous session
- [ ] Two different Workspaces have separate session histories
- [ ] `claude-box --shell` opens bash; `--no-pull` skips pulling; Image reference is overridable
- [ ] README explains prerequisites, putting `claude-box` on the PATH, and the flags
