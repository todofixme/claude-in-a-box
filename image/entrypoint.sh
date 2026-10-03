#!/usr/bin/env bash
#
# PID 1 of every Box.
#
# Test Containers need a Docker daemon, and the Host's socket is deliberately
# not mounted (ADR-0001), so the Box runs its own dockerd. Only root can start
# it, which is why the Image's user is root and this script is what drops to
# `claude` for the command the Box was actually started with.

set -euo pipefail

readonly DOCKERD_LOG=/var/log/dockerd.log
readonly DOCKERD_TIMEOUT_SECONDS=30

log() {
  printf 'box: %s\n' "$1" >&2
}

# CAP_SYS_ADMIN is what `docker run --privileged` grants and what dockerd
# needs. A Box without it was started for something other than running tests
# (the test suite does that), so run the command instead of failing on a
# daemon nobody is going to use: `docker` then says what is missing itself.
privileged() {
  local effective
  effective="$(sed -n 's/^CapEff:[[:space:]]*//p' /proc/self/status)"
  local cap_sys_admin=21
  (((0x$effective >> cap_sys_admin) & 1))
}

start_dockerd() {
  dockerd >>"$DOCKERD_LOG" 2>&1 &

  local waited=0
  until docker system info >/dev/null 2>&1; do
    if [ "$waited" -ge "$((DOCKERD_TIMEOUT_SECONDS * 5))" ]; then
      log "dockerd did not come up within ${DOCKERD_TIMEOUT_SECONDS}s, see $DOCKERD_LOG"
      return 1
    fi
    sleep 0.2
    waited=$((waited + 1))
  done
}

if [ "$(id -u)" -eq 0 ]; then
  if privileged; then
    start_dockerd || true
  fi

  # The terminal docker handed us belongs to root, and Claude's TUI reopens it
  # rather than using the inherited descriptors.
  terminal="$(tty 2>/dev/null || true)"
  if [ -c "$terminal" ]; then
    chown claude "$terminal"
  fi

  export HOME=/home/claude
  exec setpriv --reuid claude --regid claude --init-groups "$@"
fi

exec "$@"
