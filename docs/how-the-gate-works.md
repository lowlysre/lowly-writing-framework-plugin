# How the gate works

The gate covers `create_pull_request`, `update_pull_request`, `add_pr_review_comment`, `edit_pr_review_comment`, `reply_to_comment`, and `reply_and_resolve_review_thread`, plus `gh pr|issue|discussion create|edit|comment|review` run through a shell tool. It denies once per session with exit code 2, then allows the retry. An internal failure in the gate exits 0, so a broken gate never blocks work.

One script pair holds the matching logic: `hooks/gate.sh` for bash and `hooks/gate.ps1` for Windows PowerShell 5.1 and PowerShell 7. Neither needs `jq`. 

## Compatibility

The plugin targets the Claude Code plugin spec, and the other two harnesses accept that format:

- Copilot CLI's [hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference) accepts PascalCase event names (`PreToolUse`) in the Claude Code shape, with Claude matcher semantics and `snake_case` payload fields. Its native `camelCase` flat format is not used.
- Codex's [plugin docs](https://developers.openai.com/plugins/build/plugins) say OpenAI "also accepts legacy and Claude-compatible manifests" and that Codex discovers `hooks/hooks.json` by default. Codex skips plugin hooks until the user trusts them in `/hooks`.

The only additions to the Claude shape are per-OS command keys, so one `hooks/hooks.json` serves all three:

| Key in `hooks/hooks.json` | Read by |
| --- | --- |
| `command`, `bash` | Claude Code (`command`), Copilot CLI on Linux and macOS (`bash`), Codex on Linux and macOS (`command`) |
| `powershell` | Copilot CLI on Windows; the command ends in `; exit $LASTEXITCODE` |
| `commandWindows` | Codex on Windows |

- The matcher is `Bash|(.*(__|-))?(<tools>)`. MCP tool names arrive prefixed with `__` on Claude Code and `-` on Copilot CLI.
- A deny exits 2, writes the reason to stderr, and prints `permissionDecision` JSON to stdout in both the top-level and `hookSpecificOutput` shapes. Copilot CLI reads stdout, Claude Code and Codex read stderr.
- Copilot CLI runs the `powershell` field through `pwsh -c`, which reports exit code 1 for any failed native command. The trailing `; exit $LASTEXITCODE` restores exit code 2.

## Skill loaded marker

The gate records the load as an empty file, `<temp dir>/lowly-writing-framework/<session_id>.loaded`. All three harnesses send `session_id` in the hook payload, so the file needs no harness state and works the same under bash and PowerShell.

- Claude Code and Copilot CLI load a skill through a `Skill` or `skill` tool call, which a `PostToolUse` hook records.
- Codex has no skill tool. The model reads `SKILL.md` through its shell tool, so on Codex the shared `PostToolUse` matcher also covers `Bash`, and the gate records a call that mentions `lowly-writing-framework/SKILL.md`.

A PreCompact hook deletes the session's markers, including the .nudged file that limits the deny to once per session. Compaction can drop the skill text from the model's context, so the next write is denied again and the agent reloads the skill. If the harness keeps the skill through compaction, the cost is one extra reminder. Claude Code, Copilot CLI, and Codex each document a pre-compaction event.
