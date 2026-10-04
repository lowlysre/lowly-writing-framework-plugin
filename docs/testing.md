# Testing

`tests/` holds Pester tests. They run the gate, check the hooks configs against the gate, and run the literal command strings from each config the way the harness runs them.

```
Invoke-Pester -Path tests -CI
```

CI runs them on Ubuntu, macOS, and Windows. On Windows the gate runs under Windows PowerShell 5.1.

## Known gaps

CI exercises the gate and the hook command strings, not a harness install. These paths are untested:

- The Claude Code `shell: powershell` configuration, the `.claude-plugin/marketplace.json` install path, and Claude's handling of the extra `bash` and `powershell` keys are untested.
- The Codex install through `.claude-plugin/marketplace.json`, its manifest choice, the `CLAUDE_PLUGIN_ROOT` expansion, its handling of the extra `bash` and `powershell` keys, and how `commandWindows` is launched are untested. The docs describe Claude-compatible manifests as accepted without naming `.claude-plugin/plugin.json` explicitly. CI runs the `commandWindows` string through `cmd /c`.
- `claude plugin validate` passes the manifests and does not validate hooks.
