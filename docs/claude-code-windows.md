# Claude Code on Windows without Git for Windows

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
