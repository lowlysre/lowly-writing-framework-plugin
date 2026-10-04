# lowly-writing-framework-plugin

<p align="center">
  <img src="skills/lowly-writing-framework/assets/hero-og.png" alt="lowly-writing-framework" width="480">
</p>

Bundles the [lowly-writing-framework](https://github.com/lowlysre/lowly-writing-framework) skill and denies GitHub write tools and `gh` write commands until the skill has loaded in the session. Works on Claude Code, Copilot CLI, and Codex CLI from one `.claude-plugin/` tree: Copilot CLI and Codex both accept the Claude Code plugin and hooks format, so there is a single manifest and hooks config.

| | Skill alone (`npx skills add`) | Plugin (with skill) |
|---|:---:|:---:|
| Writing framework skill | ✅ | ✅ |
| Works on Claude Code, Copilot CLI, Codex CLI | ✅ | ✅ |
| Agent decides whether to load the skill | ✅ | ✅ |
| Blocks GitHub writes until the skill loads | ❌ | ✅ |
| Re-arms the block after context compaction | ❌ | ✅ |

> [!IMPORTANT]
> Install the plugin or run `npx skills add lowlysre/lowly-writing-framework`, not both. Both register the skill, and the agent then sees it twice.

## Install

### Claude Code* / Copilot CLI

```
/plugin marketplace add lowlysre/lowly-writing-framework-plugin
/plugin install lowly-writing-framework@lowly-writing-framework
```

\* Without Git on Windows, Claude Code can't run the bash hooks. Copy [`examples/claude-code-windows-settings.json`](examples/claude-code-windows-settings.json) into your user settings and replace `<plugin path>` with the installed plugin directory.

### Codex CLI

```
codex plugin marketplace add lowlysre/lowly-writing-framework-plugin
```

Codex skips plugin hooks until you trust them in `/hooks`.

## Vendored skill

`skills/` is an unmodified copy of the upstream skill at the tag in `mise.toml`, committed because a plugin installs by cloning this repo. The `skills` CLI records the install in `skills-lock.json` (tag `ref` plus a `computedHash` that changes with any byte, line endings included), and CI diffs `skills/` against a fresh restore from it.

To bump, change `skill_ref` in `mise.toml`, run `mise run vendor`, and bump the plugin `version` if it should ship. `mise run verify` runs the CI check locally.

## Docs

- [How the gate works](docs/how-the-gate-works.md): what it denies, the hook config, why Codex needs no separate config, the skill-loaded marker
- [Testing](docs/testing.md): the Pester suite and known gaps
