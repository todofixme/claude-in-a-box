#!/usr/bin/env bash
#
# PID 1 of every Box.
#
# Test Containers need a Docker daemon, and the Host's socket is deliberately
# not mounted (ADR-0001), so the Box runs its own dockerd. Only root can start
# it, which is why the Image's user is root and this script is what drops to
# `claude` for the command the Box was actually started with.
#
# A `--code-graph` Box also gets the Code Graph server configured here
# (ADR-0005). Nothing starts the server: it is a stdio MCP server, so Claude
# starts it on the first connection and it shuts down with the last session.

set -euo pipefail

readonly DOCKERD_LOG=/var/log/dockerd.log
readonly DOCKERD_TIMEOUT_SECONDS=30
# Dropping root, in one place: both the command the Box was started for and
# anything this script runs on claude's behalf go through it.
readonly DROP_TO_CLAUDE=(setpriv --reuid claude --regid claude --init-groups)

log() {
  printf 'box: %s\n' "$1" >&2
}

# CAP_SYS_ADMIN is what `docker run --privileged` grants and what dockerd
# needs. A Box without it was started for something other than running tests
# (the test suite does that), so run the command instead of failing on a
# daemon nobody is going to use: `docker` then says what is missing itself.
has_cap_sys_admin() {
  local effective
  effective="$(sed -n 's/^CapEff:[[:space:]]*//p' /proc/self/status)"
  local cap_sys_admin=21
  (((0x$effective >> cap_sys_admin) & 1))
}

# Runs one command as claude. HOME is passed explicitly because this runs
# before the export at the bottom of the script.
as_claude() {
  "${DROP_TO_CLAUDE[@]}" env HOME=/home/claude "$@"
}

# codebase-memory-mcp persists its configuration under CBM_CACHE_DIR, which in
# a `--code-graph` Box is a Box Cache of the Workspace, so a value baked into
# the Image would be hidden by that volume: it has to be set from inside a
# running Box. `config set` is idempotent, so every start just confirms it.
#
# auto_index makes the first MCP connection index the Workspace, which is why
# no developer and no Claude has to remember an indexing step. ui_enabled is
# the graph's HTTP visualisation, on by default and listening in the Box; no
# port is published for it and nothing in a Box would open it, so it is turned
# off rather than left running.
configure_code_graph() {
  local setting
  for setting in auto_index=true ui_enabled=false; do
    if ! as_claude codebase-memory-mcp config set "${setting%%=*}" "${setting#*=}" >/dev/null; then
      # `set -e` would end the Box here either way; this says why it did.
      log "could not set $setting for the Code Graph server"
      return 1
    fi
  done
}

start_dockerd() {
  dockerd >>"$DOCKERD_LOG" 2>&1 &

  local deadline=$((SECONDS + DOCKERD_TIMEOUT_SECONDS))
  until docker system info >/dev/null 2>&1; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      log "dockerd did not come up within ${DOCKERD_TIMEOUT_SECONDS}s, see $DOCKERD_LOG"
      return 1
    fi
    sleep 0.2
  done
}

if [ "$(id -u)" -eq 0 ]; then
  if has_cap_sys_admin; then
    start_dockerd
  fi

  if [ -n "${CLAUDE_BOX_CODE_GRAPH:-}" ]; then
    configure_code_graph
  fi

  # The terminal docker handed us belongs to root, and Claude's TUI reopens it
  # rather than using the inherited descriptors.
  terminal="$(tty 2>/dev/null || true)"
  if [ -c "$terminal" ]; then
    chown claude "$terminal"
  fi

  export HOME=/home/claude
  exec "${DROP_TO_CLAUDE[@]}" "$@"
fi

exec "$@"
