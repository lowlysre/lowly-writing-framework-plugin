#!/usr/bin/env bash
# Hook gate for lowly-writing-framework on Claude Code, Copilot CLI, and Codex CLI (bash twin of gate.ps1).
# PostToolUse: records that the skill loaded this session, via the Skill tool or a read of its SKILL.md.
# PreToolUse on GitHub write tools and `gh` write commands: denies once if the skill hasn't loaded.
# Fails open: anything unparseable exits 0. Keep the matching logic in step with gate.ps1.
# Parses the JSON payload with sed/grep so it needs no jq.

input=$(cat)
field() { printf '%s' "$input" | sed -nE 's/.*"'"$1"'"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' | head -n1; }

event=$(field hook_event_name)
tool=$(field tool_name)
session=$(field session_id | tr -c 'A-Za-z0-9_-' '_')
[ -n "$session" ] || exit 0

state_dir="${TMPDIR:-/tmp}/lowly-writing-framework"
mkdir -p "$state_dir" 2>/dev/null || exit 0
loaded="$state_dir/$session.loaded"
nudged="$state_dir/$session.nudged"

if [ "$event" = "PostToolUse" ]; then
  case "$tool" in
    Skill|skill)
      printf '%s' "$input" | grep -Eq '"skill"[[:space:]]*:[[:space:]]*"[^"]*lowly-writing-framework' && : >"$loaded"
      ;;
    Bash)
      printf '%s' "$input" | grep -Eq 'lowly-writing-framework[/\\]+SKILL\.md' && : >"$loaded"
      ;;
  esac
  exit 0
fi

tool=${tool##*__}; tool=${tool##*-}
case "$tool" in
  create_pull_request|update_pull_request|add_pr_review_comment|edit_pr_review_comment|reply_to_comment|reply_and_resolve_review_thread) ;;
  Bash) printf '%s' "$input" | grep -Eq '\bgh[[:space:]]+(pr|issue|discussion)[[:space:]]+(create|edit|comment|review)\b' || exit 0 ;;
  *) exit 0 ;;
esac

if [ ! -e "$loaded" ] && [ ! -e "$nudged" ]; then
  : >"$nudged"
  msg='Load the lowly-writing-framework skill before writing this artifact, then retry. This reminder fires once per session.'
  # Copilot reads the top-level fields from stdout, Codex and Claude Code the hookSpecificOutput form; Claude Code and Codex also read stderr on exit 2.
  printf '{"permissionDecision":"deny","permissionDecisionReason":"%s","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"%s"}}\n' "$msg" "$msg"
  echo "$msg" >&2
  exit 2
fi
exit 0