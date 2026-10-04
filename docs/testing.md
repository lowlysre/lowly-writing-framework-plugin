# Testing

`tests/` holds Pester tests. They run the gate, check the hooks configs against the gate, and run the literal command strings from each config the way the harness runs them.

```
Invoke-Pester -Path tests -CI
```

CI runs them on `ubuntu-slim`, `macos-latest`, and `windows-latest`. On Windows the gate runs under Windows PowerShell 5.1.

Two more CI jobs sit beside the Pester matrix:

- `validate-manifests` runs `claude plugin validate` on `.claude-plugin/marketplace.json` and `.claude-plugin/plugin.json`.
- `vendored-skill` restores the skill from `skills-lock.json` and diffs it against `skills/`.

## What the tests cover

- The soft deny (exit 0 with the deny JSON), the hard deny on a retry (exit 2), and the allow after that.
- An allow once the skill has loaded, with a fresh session id each time so the markers don't leak between tests.
- `PreCompact` deleting the markers so the gate denies again.
- Fail-open behavior: an internal gate failure exits 0.
- The write tool list and matcher in `hooks/hooks.json` matching both gates.

## Known gaps

CI exercises the gate and the hook command strings, not a harness install. These paths are untested:

- The Claude Code `shell: powershell` configuration, the `.claude-plugin/marketplace.json` install path, and Claude's handling of the extra `bash` and `powershell` keys are untested.
- The Codex install through `.claude-plugin/marketplace.json`, its manifest choice, the `CLAUDE_PLUGIN_ROOT` expansion, its handling of the extra `bash` and `powershell` keys, and how `commandWindows` is launched are untested. The docs describe Claude-compatible manifests as accepted without naming `.claude-plugin/plugin.json` explicitly. CI runs the `commandWindows` string through `cmd /c`.
- `claude plugin validate` passes the manifests and does not validate hooks.
- Copilot's reason text was checked live on one install only. In the Copilot desktop app, the exit 0 soft deny showed the reason text, and the exit 2 hard deny showed only `hook exited with code 2`. Claude Code and Codex are expected to honor the exit 0 JSON deny per their docs, but that is untested here.
- A harness that ignores the exit 0 JSON lets the first write through. The exit 2 on the retry is the backstop.
- Whether any harness fires `PreCompact` with `hook_event_name` set to `PreCompact` is untested. Copilot's `preCompact` is notification-only, so it may not finish before the next tool call.
- Skill-load detection on Claude Code and Codex is untested.
