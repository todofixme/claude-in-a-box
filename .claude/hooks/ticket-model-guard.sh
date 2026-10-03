#!/usr/bin/env bash
# Ensures /implement runs a ticket on the model named in its "Model:" line.
#
# SessionStart / PostModelSwitch: remember the session's current model.
# UserPromptSubmit: on "/implement <ticket>", block if the remembered model
# belongs to a different family than the ticket's. If the model is unknown,
# let the prompt through and ask Claude to check its own model instead.
set -euo pipefail

input=$(cat)
event=$(jq -r '.hook_event_name // ""' <<<"$input")
session=$(jq -r '.session_id // "unknown"' <<<"$input")
project="${CLAUDE_PROJECT_DIR:-$(jq -r '.cwd // "."' <<<"$input")}"
state="${TMPDIR:-/tmp}/claude-model-${session}"

case "$event" in
  SessionStart)
    model=$(jq -r '.model // empty' <<<"$input")
    [[ -n "$model" ]] && printf '%s\n' "$model" >"$state"
    exit 0
    ;;
  PostModelSwitch)
    model=$(jq -r '.to_model // empty' <<<"$input")
    [[ -n "$model" ]] && printf '%s\n' "$model" >"$state"
    exit 0
    ;;
  UserPromptSubmit) ;;
  *) exit 0 ;;
esac

prompt=$(jq -r '.prompt // ""' <<<"$input")
[[ "$prompt" =~ ^/implement([[:space:]]|$) ]] || exit 0

# Ticket by path (.scratch/.../NN-slug.md) or by bare number (03).
ticket=$(grep -oE '\.scratch/[^[:space:]]+\.md' <<<"$prompt" | head -1 || true)
if [[ -z "$ticket" ]]; then
  num=$(grep -oE '(^|[[:space:]])[0-9]{1,2}([[:space:]]|$)' <<<"${prompt#/implement}" | head -1 | tr -d '[:space:]' || true)
  if [[ -n "$num" ]]; then
    num=$(printf '%02d' "$((10#$num))")
    shopt -s nullglob
    matches=("$project"/.scratch/*/issues/"$num"-*.md)
    (( ${#matches[@]} == 1 )) && ticket="${matches[0]#"$project"/}"
  fi
fi
[[ -n "$ticket" ]] || exit 0
file="$project/$ticket"
[[ -f "$file" ]] || exit 0

# Accepts "Model: opus" and "**Model:** opus".
wanted=$(grep -m1 -E '^(\*\*)?Model:' "$file" | sed -E 's/^(\*\*)?Model:(\*\*)?[[:space:]]*//; s/[[:space:]]+$//' || true)
[[ -n "$wanted" ]] || exit 0
current=$(cat "$state" 2>/dev/null || true)

family() {
  local m
  m=$(tr '[:upper:]' '[:lower:]' <<<"$1") # macOS ships bash 3.2: no ${1,,}
  for f in fable opus sonnet haiku; do
    [[ "$m" == *"$f"* ]] && { echo "$f"; return; }
  done
  echo "$m"
}

if [[ -z "$current" ]]; then
  jq -n --arg t "$ticket" --arg m "$wanted" '{
    systemMessage: "Ticket \($t) is marked for model \($m); current model unknown.",
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: "Ticket \($t) is marked for model \($m). If your own model differs, ask the user via AskUserQuestion before any other action whether to switch. On yes: stop and point to /model \($m); \"continue\" resumes afterwards. If it matches, do not mention it."
    }
  }'
  exit 0
fi

[[ "$(family "$current")" == "$(family "$wanted")" ]] && exit 0

jq -n --arg t "$ticket" --arg m "$wanted" --arg c "$current" '{
  decision: "block",
  reason: "Ticket \($t) is marked for model \($m), but the current model is \($c). Run /model \($m) and retry."
}'
