#!/usr/bin/env bash
# Hook gate for lowly-writing-framework on Claude Code, Copilot CLI, and Codex CLI (bash twin of gate.ps1).
#
# PreCompact:  clears the session markers so the next write is denied again and the skill reloads.
# PostToolUse: records that the skill loaded, via the Skill tool or a read of its SKILL.md.
# PreToolUse:  on GitHub write tools and `gh` write commands, denies once per compaction cycle if the skill hasn't loaded.
#
# Fails open: anything unparseable exits 0. Keep the matching logic in step with gate.ps1.
# Parses the JSON payload with sed/grep so it needs no jq.

WRITE_TOOLS='create_pull_request|update_pull_request|add_pr_review_comment|edit_pr_review_comment|reply_to_comment|reply_and_resolve_review_thread'
GH_WRITE_CMD='\bgh[[:space:]]+(pr|issue|discussion)[[:space:]]+(create|edit|comment|review)\b'
SKILL='lowly-writing-framework'

input=$(cat)

# Reads a top-level string field from the JSON payload.
field() { printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n1; }

payload_matches() { printf '%s' "$input" | grep -Eq "$1"; }

# A load is a Skill tool call naming the skill, or (Codex has no skill tool) a shell read of its SKILL.md.
record_load() {
  case "$tool" in
    Skill|skill) payload_matches "\"skill\"[[:space:]]*:[[:space:]]*\"[^\"]*$SKILL" && : >"$loaded" ;;
    Bash)        payload_matches "$SKILL[/\\\\]+SKILL\\.md" && : >"$loaded" ;;
  esac
}

# True for a GitHub write tool, with or without an MCP prefix (`mcp__server__` on Claude Code, `server-` on Copilot), or a `gh` write command in Bash.
is_write() {
  local name=${tool##*__}; name=${name##*-}
  case "$name" in
    Bash) payload_matches "$GH_WRITE_CMD" ;;
    *)    [[ "$name" =~ ^($WRITE_TOOLS)$ ]] ;;
  esac
}

deny() {
  local msg="Load the $SKILL skill before writing this artifact, then retry. This reminder fires once, and again after each context compaction."
  : >"$nudged"
  # Copilot reads the top-level fields from stdout, Codex and Claude Code the hookSpecificOutput form; Claude Code and Codex also read stderr on exit 2.
  printf '{"permissionDecision":"deny","permissionDecisionReason":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg" "$msg"
  echo "$msg" >&2
  exit 2
}

event=$(field hook_event_name)
tool=$(field tool_name)
session=$(field session_id | tr -c 'A-Za-z0-9_-' '_')
[ -n "$session" ] || exit 0

state_dir="${TMPDIR:-/tmp}/$SKILL"
mkdir -p "$state_dir" 2>/dev/null || exit 0
loaded="$state_dir/$session.loaded"
nudged="$state_dir/$session.nudged"

case "$event" in
  PreCompact)  rm -f "$loaded" "$nudged"; exit 0 ;;
  PostToolUse) record_load; exit 0 ;;
esac

is_write || exit 0
[ -e "$loaded" ] || [ -e "$nudged" ] || deny
exit 0