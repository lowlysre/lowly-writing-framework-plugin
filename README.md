# lowly-writing-framework-plugin

A plugin that bundles the [lowly-writing-framework](https://github.com/lowlysre/lowly-writing-framework) skill and gates GitHub writes on it. The gate denies GitHub write tools and `gh` write commands until the skill has loaded in the session.

The gate covers `create_pull_request`, `update_pull_request`, `add_pr_review_comment`, `edit_pr_review_comment`, `reply_to_comment`, and `reply_and_resolve_review_thread`, plus `gh pr|issue|discussion create|edit|comment|review` run through a shell tool. It denies once per session with exit code 2, then allows the retry. An internal failure in the gate exits 0, so a broken gate never blocks work.

> [!IMPORTANT]
> Install the plugin or run `npx skills add lowlysre/lowly-writing-framework`, not both. Both register the skill, and the agent then sees it twice.

## Install

Claude Code and Copilot CLI:

```
/plugin marketplace add lowlysre/lowly-writing-framework-plugin
/plugin install lowly-writing-framework@lowly-writing-framework
```

Codex CLI:

```
codex plugin marketplace add lowlysre/lowly-writing-framework-plugin
```

Codex skips plugin hooks until you review and trust them. Open `/hooks` after install and trust the gate, or Codex loads the skill and enforces nothing.

### Claude Code on Windows without Git for Windows

Claude Code runs hook commands through Git Bash and has no bash fallback without it. Set `shell: powershell` on a user-level hook that runs `gate.ps1` from the installed plugin path, and the gate runs under Windows PowerShell 5.1:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|(.*(__|-))?(create_pull_request|update_pull_request|add_pr_review_comment|edit_pr_review_comment|reply_to_comment|reply_and_resolve_review_thread)",
        "hooks": [
          {
            "type": "command",
            "shell": "powershell",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"<plugin path>\\hooks\\gate.ps1\""
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Skill|skill",
        "hooks": [
          {
            "type": "command",
            "shell": "powershell",
            "command": "powershell -NoProfile -ExecutionPolicy Bypass -File \"<plugin path>\\hooks\\gate.ps1\""
          }
        ]
      }
    ]
  }
}
```

The plugin's own bash hooks fail to start in that setup. Claude Code reports a non-blocking error for them and the user-level hooks do the gating.

## How the gate works

One script pair holds the matching logic: `hooks/gate.sh` for bash and `hooks/gate.ps1` for Windows PowerShell 5.1 and PowerShell 7. Neither needs `jq`. The hook config differs per harness because each harness reads a different format.

| File | Harness | Notes |
| --- | --- | --- |
| `hooks/hooks.json` | Claude Code, Copilot CLI | `bash` and `powershell` keys; the PowerShell command ends in `; exit $LASTEXITCODE` |
| `hooks/codex-hooks.json` | Codex CLI | `command` and `commandWindows`; referenced from `.codex-plugin/plugin.json` |

- The matcher is `Bash|(.*(__|-))?(<tools>)`. MCP tool names arrive prefixed with `__` on Claude Code and `-` on Copilot CLI.
- Copilot CLI's [hooks reference](https://docs.github.com/en/copilot/reference/hooks-reference) accepts PascalCase event names (`PreToolUse`) in the Claude Code shape, with Claude matcher semantics and `snake_case` payload fields. That is why one file serves both. Its native `camelCase` flat format (`version: 1`, `preToolUse`) is not used.
- A deny exits 2, writes the reason to stderr, and prints `permissionDecision` JSON to stdout in both the top-level and `hookSpecificOutput` shapes. Copilot CLI reads stdout, Claude Code and Codex read stderr.
- Copilot CLI runs the `powershell` field through `pwsh -c`, which reports exit code 1 for any failed native command. The trailing `; exit $LASTEXITCODE` restores exit code 2.

### Skill loaded marker

The gate records the load as an empty file, `<temp dir>/lowly-writing-framework/<session_id>.loaded`. All three harnesses send `session_id` in the hook payload, so the file needs no harness state and works the same under bash and PowerShell.

- Claude Code and Copilot CLI load a skill through a `Skill` or `skill` tool call, which a `PostToolUse` hook records.
- Codex has no skill tool. The model reads `SKILL.md` through its shell tool, so on Codex the gate records a `Bash` call that mentions `lowly-writing-framework/SKILL.md`.

## Codex

Codex plugins can carry hooks. The [plugin docs](https://developers.openai.com/plugins/build/plugins#bundled-mcp-servers-and-lifecycle-hooks) say "When your plugin is enabled, the Codex runtime can load lifecycle hooks from your plugin alongside user, project, and managed hooks." The [hooks docs](https://learn.chatgpt.com/docs/hooks) give the `PreToolUse` payload (`session_id`, `tool_name`, `tool_input`, with `tool_input.command` for `Bash`) and the deny signal ("You can also use exit code `2` and write the blocking reason to `stderr`").

The gate is therefore enforced on Codex, subject to the trust review above. The gap is that no live Codex run exists yet, see the coverage table.

## Vendored skill

`skills/lowly-writing-framework/` is a copy of the upstream skill, unmodified, installed with the `skills` CLI from npm:

```
npx skills add lowlysre/lowly-writing-framework#v2.3.0 --skill lowly-writing-framework --agent universal --copy
```

The CLI writes to `.agents/skills/`, so the copy moves to `skills/` afterward. The CLI records the install in `skills-lock.json`, with a `ref` (the tag), a `source`, and a `computedHash` over the skill's contents. The lockfile pins the tag, and `computedHash` changes with any byte of the copy, line endings included. `.gitattributes` marks `skills/**` as `-text` so git keeps the upstream bytes.

CI runs `npx skills experimental_install` against the lockfile in a scratch directory and diffs the result against `skills/`, so a drifted copy fails the build. The `description` in `SKILL.md` is part of that copy, so it stays identical to the pinned release.

To bump the version, run the `npx skills add` command with the new tag in a scratch directory, replace `skills/lowly-writing-framework/` and `skills-lock.json` with the result, and update `version` in both plugin manifests if the bump should ship.

## Testing

`tests/` holds Pester tests. They run the gate, check the hooks configs against the gate, and run the literal command strings from each config the way the harness runs them.

```
Invoke-Pester -Path tests -CI
```

CI runs them on Ubuntu, macOS, and Windows. On Windows the gate runs under Windows PowerShell 5.1.

### Coverage

"CI" means the Pester suite ran the gate and the hooks command strings on that OS. "Live" means a real harness session denied a write, loaded the skill, and passed the retry.

| Harness | Linux | macOS | Windows |
| --- | --- | --- | --- |
| Copilot CLI | CI | CI | CI; live once on 1.0.91 with `gpt-5-mini`, against the earlier gate in lowlysre/lowly-writing-framework#30, not this plugin |
| Claude Code | CI | CI | CI; not live |
| Codex CLI | CI | CI | CI; not live |

- No live run exists for this plugin on any harness, OS, or model.
- The Claude Code `shell: powershell` configuration, the `.claude-plugin/marketplace.json` install path, and Claude's handling of the extra `bash` and `powershell` keys are untested.
- The Codex install through `.claude-plugin/marketplace.json`, its manifest choice between `.codex-plugin/plugin.json` and `.claude-plugin/plugin.json`, the `${PLUGIN_ROOT}` substitution, and how `commandWindows` is launched are untested. CI runs the `commandWindows` string through `cmd /c`.
- `claude plugin validate` passes the manifests and does not validate hooks.
