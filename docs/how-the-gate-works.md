# How the gate works

The gate covers `create_pull_request`, `update_pull_request`, `add_pr_review_comment`, `edit_pr_review_comment`, `reply_to_comment`, and `reply_and_resolve_review_thread`, plus `gh pr|issue|discussion create|edit|comment|review` run through a shell tool. It denies once per session with exit code 2, then allows the retry. An internal failure in the gate exits 0, so a broken gate never blocks work.

One script pair holds the matching logic: `hooks/gate.sh` for bash and `hooks/gate.ps1` for Windows PowerShell 5.1 and PowerShell 7. Neither needs `jq`. One hook config serves all three harnesses.

| Key in `hooks/hooks.json` | Read by |
| --- | --- |
| `command`, `bash` | Claude Code (`command`), Copilot CLI on Linux and macOS (`bash`), Codex on Linux and macOS (`command`) |
| `powershell` | Copilot CLI on Windows; the command ends in `; exit $LASTEXITCODE` |
| `commandWindows` | Codex on Windows |

- The matcher is `Bash|(.*(__|-))?(<tools>)`. MCP tool names arrive prefixed with `__` on Claude Code and `-` on Copilot CLI.
- Copilot CLI's [hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference) accepts PascalCase event names (`PreToolUse`) in the Claude Code shape, with Claude matcher semantics and `snake_case` payload fields. That is why one file serves both. Its native `camelCase` flat format (`version: 1`, `preToolUse`) is not used.
- A deny exits 2, writes the reason to stderr, and prints `permissionDecision` JSON to stdout in both the top-level and `hookSpecificOutput` shapes. Copilot CLI reads stdout, Claude Code and Codex read stderr.
- Copilot CLI runs the `powershell` field through `pwsh -c`, which reports exit code 1 for any failed native command. The trailing `; exit $LASTEXITCODE` restores exit code 2.

## Skill loaded marker

The gate records the load as an empty file, `<temp dir>/lowly-writing-framework/<session_id>.loaded`. All three harnesses send `session_id` in the hook payload, so the file needs no harness state and works the same under bash and PowerShell.

- Claude Code and Copilot CLI load a skill through a `Skill` or `skill` tool call, which a `PostToolUse` hook records.
- Codex has no skill tool. The model reads `SKILL.md` through its shell tool, so on Codex the shared `PostToolUse` matcher also covers `Bash`, and the gate records a call that mentions `lowly-writing-framework/SKILL.md`.
