#!/usr/bin/env bash
#
# Asks the Code Graph of the Workspace the way Claude would, and prints one
# marker line per thing a test wants to know. `box.bats` feeds it to
# `claude-box --shell --code-graph` on stdin, so it runs as claude, in the
# Workspace, in a Box the entrypoint has already configured.
#
# It opens one MCP session over stdio, the way Claude's MCP client does, and
# asks for nothing but answers: the only `index_repository` call in here is the
# one that has to be refused, on a path outside the Workspace. The graph every
# other marker comes from is the one `auto_index` builds on the connection,
# which is asynchronous — hence the wait for the Workspace to show up in
# `list_projects` rather than a single early call.
#
# The test plants a function called `boxTestMarkerFunction` in the Workspace
# before starting the Box, and `ANSWER:` is what the graph says about it.

# No `-e`, unlike the rest of this repo's scripts: a call that times out must
# still leave the markers after it printable, so each one reports what it
# found and a test asserts on that rather than on an exit status.
set -uo pipefail

# How long the graph may take to appear, and how long one call may take to
# answer. Indexing a Workspace of one file is quick; these are only ceilings.
readonly INDEX_SECONDS=180
readonly CALL_SECONDS=60
readonly SYMBOL=boxTestMarkerFunction
# codebase-memory-mcp's graph UI, which no Box starts and no Box publishes.
readonly UI_PORT=9749
readonly GRAPH_DIR="$HOME/.cache/codebase-memory-mcp"

# The server keeps each Workspace's graph as <its name for it>.db, next to its
# own _config.db. So `yes` means this Box found the Workspace's graph where the
# last Box left it, `no` that this is the first Box to ask for one.
a_graph_exists() {
  local db
  for db in "$GRAPH_DIR"/*.db; do
    case "$db" in
      "$GRAPH_DIR/_config.db" | "$GRAPH_DIR/*.db") ;;
      *) return 0 ;;
    esac
  done
  return 1
}

# The session. Its stdin is a fifo held open on a descriptor of this script's
# own, so the server lives until the last question has been asked rather than
# being cut off at the first EOF.
session_open() {
  session_out="$(mktemp)"
  session_fifo="$(mktemp -u)"
  mkfifo "$session_fifo"
  codebase-memory-mcp <"$session_fifo" >"$session_out" 2>/dev/null &
  session_server=$!
  exec 9>"$session_fifo"

  send '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-box-test","version":"1"}}}'
  send '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  await 1 "$CALL_SECONDS"
}

session_close() {
  exec 9>&-
  wait "$session_server" 2>/dev/null
  rm -f "$session_out" "$session_fifo"
}

send() {
  printf '%s\n' "$1" >&9
}

# Waits for the response with that id. A response is only there once its line
# is whole, which is what the closing brace stands for.
await() {
  local deadline=$((SECONDS + $2))
  until response "$1" >/dev/null; do
    [ "$SECONDS" -lt "$deadline" ] || return 1
    sleep 0.5
  done
}

response() {
  grep -m1 -E "\"id\":$1,.*\}$" "$session_out" 2>/dev/null
}

# One tool call, and the text it answered with.
ask() {
  local id="$1" tool="$2" arguments="$3"
  send "$(
    printf '{"jsonrpc":"2.0","id":%s,"method":"tools/call","params":{"name":"%s","arguments":%s}}' \
      "$id" "$tool" "$arguments"
  )"
  await "$id" "$CALL_SECONDS" || true
  response "$id" | jq -r '.result.content[0].text' 2>/dev/null
}

# The name the server gave this Workspace, read back from the graph rather
# than guessed from the path.
project_in() {
  printf '%s\n' "$1" | awk -v root="$PWD" '$2 == root { print $1; exit }'
}

if a_graph_exists; then
  echo "PREEXISTING: yes"
else
  echo "PREEXISTING: no"
fi

echo "ROOT: ${CBM_ALLOWED_ROOT:-unset}"
echo "AUTO_INDEX: $(codebase-memory-mcp config get auto_index 2>&1)"
echo "UI_ENABLED: $(codebase-memory-mcp config get ui_enabled 2>&1)"

session_open

# The connection above is what indexes the Workspace. Asking again until it is
# in the graph is what Claude's own first question would amount to; the ids go
# up because each call needs its own, which is why the two calls after this
# loop start at 900, out of its reach.
id=2
deadline=$((SECONDS + INDEX_SECONDS))
while :; do
  projects="$(ask "$id" list_projects '{}')"
  project="$(project_in "$projects")"
  [ -z "$project" ] || break
  [ "$SECONDS" -lt "$deadline" ] || break
  sleep 2
  id=$((id + 1))
done

echo "PROJECTS: $(printf '%s' "$projects" | tr '\n' ' ')"
echo "PROJECT: ${project:-none}"

# A real query, the kind Claude would ask instead of searching hundreds of
# files with `rg`.
echo "ANSWER: $(
  ask 900 search_graph "$(printf '{"project":"%s","query":"%s"}' "$project" "$SYMBOL")" |
    tr '\n' ' '
)"

# Indexing something outside the Workspace, which the server has to refuse:
# $HOME holds Claude's login and every Box Cache.
echo "OUTSIDE: $(
  ask 901 index_repository "$(printf '{"repo_path":"%s"}' "$HOME")" | tr '\n' ' '
)"

# The graph UI listens on 127.0.0.1:9749 when it is left enabled. /proc/net/tcp
# holds the port in hex and 0A is LISTEN.
if awk 'NR > 1 && $4 == "0A" { print $2 }' /proc/net/tcp /proc/net/tcp6 2>/dev/null |
  grep -q ":$(printf '%04X' "$UI_PORT")\$"; then
  echo "UI_LISTENING: yes"
else
  echo "UI_LISTENING: no"
fi

session_close
