#!/usr/bin/env bash
# Hook gate for lowly-writing-framework on Claude Code, Copilot CLI, and Codex CLI (bash twin of gate.ps1).
#
# PreCompact:  clears the session markers so the next write is denied again and the skill reloads.
# PostToolUse: records that the skill loaded, via the Skill tool or a read of its SKILL.md.
# PreToolUse:  on GitHub write tools and `gh` write commands, denies up to twice per compaction cycle if the skill hasn't loaded:
#
#              first a soft deny (exit 0 plus decision JSON, so every harness shows the reason), then a hard deny (exit 2) if the model retries without loading it.
#
# Fails open: anything unparseable exits 0. Keep the matching logic in step with gate.ps1.
# Parses the JSON payload with sed/grep so it needs no jq.

WRITE_TOOLS='create_pull_request|update_pull_request|add_pr_review_comment|edit_pr_review_comment|reply_to_comment|reply_and_resolve_review_thread|issue_write|add_issue_comment|pull_request_review_write|add_comment_to_pending_review'
GH_FLAGS='([[:space:]]+-[^[:space:]]+([[:space:]]+[^-[:space:]][^[:space:]]*)?)*'
GH_WRITE_CMD="\\bgh$GH_FLAGS[[:space:]]+(pr|issue|discussion)[[:space:]]+(create|edit|comment|review)\\b"
GH_API_CMD="\\bgh$GH_FLAGS[[:space:]]+api\\b"
GH_API_WRITE='mutation|(-X|--method)[[:space:]=]*(POST|PATCH|PUT|DELETE)|[[:space:]](-f|-F|--field|--raw-field|--input)([[:space:]=]|$)'
SKILL='lowly-writing-framework'

input=$(cat)

# Reads a top-level string field from the JSON payload.
field() { printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n1; }

payload_matches() { printf '%s' "$input" | grep -Eq "$1"; }

# A load is a Skill tool call naming the skill, or (Codex has no skill tool) a shell read of its SKILL.md.
record_load() {
  case "$tool" in
    Skill|skill) payload_matches "\"skill\"[[:space:]]*:[[:space:]]*\"([^\"]*:)?$SKILL\"" && : >"$loaded" ;;
    Bash)        payload_matches "(^|[^A-Za-z0-9_.-])$SKILL[/\\\\]+SKILL\\.md" && : >"$loaded" ;;
  esac
}

# A `gh api` call writes when it names a mutating method or a GraphQL mutation, or sends fields (which makes it a POST) to a REST endpoint.
is_gh_api_write() {
  payload_matches "$GH_API_CMD" || return 1
  payload_matches 'graphql' && { payload_matches 'mutation'; return; }
  payload_matches '(-X|--method)[[:space:]=]*GET' && return 1
  payload_matches "$GH_API_WRITE"
}

# True for a GitHub write tool, with or without an MCP prefix (`mcp__server__` on Claude Code, `server-` on Copilot), or a `gh` write command in Bash.
is_write() {
  local name=${tool##*__}; name=${name##*-}
  case "$name" in
    Bash) payload_matches "$GH_WRITE_CMD" || is_gh_api_write ;;
    *)    [[ "$name" =~ ^($WRITE_TOOLS)$ ]] ;;
  esac
}

# Prints the deny decision. Copilot reads the top-level fields from stdout, Codex and Claude Code the hookSpecificOutput form.
# Exit 0 carries the reason on every harness; Copilot ignores stdout on a non-zero exit, so the hard deny only adds the exit 2 backstop.
deny() {
  local msg="Load the $SKILL skill before writing this artifact, then retry. This reminder fires twice, and again after each context compaction."
  printf '{"permissionDecision":"deny","permissionDecisionReason":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg" "$msg"
  echo "$msg" >&2
}

event=$(field hook_event_name)
tool=$(field tool_name)
session=$(field session_id | tr -c 'A-Za-z0-9_-' '_')
[ -n "$session" ] || exit 0

state_dir="${TMPDIR:-/tmp}/$SKILL"
mkdir -p "$state_dir" 2>/dev/null || exit 0
loaded="$state_dir/$session.loaded"
soft="$state_dir/$session.soft"
nudged="$state_dir/$session.nudged"

case "$event" in
  PreCompact)  rm -f "$loaded" "$soft" "$nudged"; exit 0 ;;
  PostToolUse) record_load; exit 0 ;;
esac

is_write || exit 0
[ -e "$loaded" ] || [ -e "$nudged" ] && exit 0

if [ -e "$soft" ]; then
  : >"$nudged"
  deny
  exit 2
fi
: >"$soft"
deny
exit 0