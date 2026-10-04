# Codex

Codex reads this plugin from the `.claude-plugin/` tree, so there is no separate Codex manifest or hooks file. The [plugin docs](https://developers.openai.com/plugins/build/plugins) say "OpenAI also accepts legacy and Claude-compatible manifests", list `.claude-plugin/marketplace.json` as a legacy-compatible marketplace, and say Codex discovers `hooks/hooks.json` by default when the manifest doesn't define `hooks`. Codex also expands `CLAUDE_PLUGIN_ROOT`, so the Claude Code placeholder works unchanged. The [hooks docs](https://learn.chatgpt.com/docs/hooks) give the `PreToolUse` payload (`session_id`, `tool_name`, `tool_input`, with `tool_input.command` for `Bash`) and the deny signal ("You can also use exit code `2` and write the blocking reason to `stderr`").

The gate is therefore enforced on Codex, subject to the trust review above. No live Codex run exists yet, see the coverage table.
