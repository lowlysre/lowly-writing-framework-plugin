# Testing

`tests/` holds Pester tests. They run the gate, check the hooks configs against the gate, and run the literal command strings from each config the way the harness runs them.

```
Invoke-Pester -Path tests -CI
```

CI runs them on Ubuntu, macOS, and Windows. On Windows the gate runs under Windows PowerShell 5.1.

## Coverage

"CI" means the Pester suite ran the gate and the hooks command strings on that OS. "Live" means a real harness session denied a write, loaded the skill, and passed the retry.

| Harness | Linux | macOS | Windows |
| --- | --- | --- | --- |
| Copilot CLI | CI | CI | CI; live once on 1.0.91 with `gpt-5-mini`, against the earlier gate in lowlysre/lowly-writing-framework#30, not this plugin |
| Claude Code | CI | CI | CI; not live |
| Codex CLI | CI | CI | CI; not live |

- No live run exists for this plugin on any harness, OS, or model.
- The Claude Code `shell: powershell` configuration, the `.claude-plugin/marketplace.json` install path, and Claude's handling of the extra `bash` and `powershell` keys are untested.
- The Codex install through `.claude-plugin/marketplace.json`, its manifest choice, the `CLAUDE_PLUGIN_ROOT` expansion, its handling of the extra `bash` and `powershell` keys, and how `commandWindows` is launched are untested. The docs describe Claude-compatible manifests as accepted without naming `.claude-plugin/plugin.json` explicitly. CI runs the `commandWindows` string through `cmd /c`.
- `claude plugin validate` passes the manifests and does not validate hooks.
