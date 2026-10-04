# lowly-writing-framework-plugin

Bundles the [lowly-writing-framework](https://github.com/lowlysre/lowly-writing-framework) skill and denies GitHub write tools and `gh` write commands until the skill has loaded in the session. Works on Claude Code, Copilot CLI, and Codex CLI from one `.claude-plugin/` tree.

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

Codex skips plugin hooks until you trust them in `/hooks`. Claude Code without Git for Windows needs `shell: powershell`, see [Claude Code on Windows](docs/claude-code-windows.md).

## Docs

- [How the gate works](docs/how-the-gate-works.md): what it denies, the hook config, the skill-loaded marker
- [Codex](docs/codex.md): why Codex needs no separate config
- [Vendored skill](docs/vendored-skill.md): how the skill is pinned, verified, and bumped
- [Testing](docs/testing.md): the Pester suite and the OS, harness, and model coverage table

> [!NOTE]
> No live harness run exists for this plugin. CI runs the gate and the literal hook commands on Ubuntu, macOS, and Windows. See [coverage](docs/testing.md#coverage).