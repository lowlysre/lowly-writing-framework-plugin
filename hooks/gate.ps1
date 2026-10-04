<#
.SYNOPSIS
Hook gate for lowly-writing-framework on Claude Code, Copilot CLI, and Codex CLI (PowerShell twin of gate.sh).
Runs on Windows PowerShell 5.1 and PowerShell 7.
.DESCRIPTION
PreCompact: clears both markers so the next write is denied again and the skill reloads.
PostToolUse: records that the skill loaded this session, via the Skill tool or a read of its SKILL.md.
PreToolUse on GitHub write tools and `gh` write commands: denies once per compaction cycle if the skill hasn't loaded.
Fails open: any internal error prints a warning to stderr and exits 0.
Keep the matching logic in step with gate.sh.
#>
$ErrorActionPreference = 'Stop'
$stateDir = Join-Path ([IO.Path]::GetTempPath()) 'lowly-writing-framework'

try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $session = $in.session_id -replace '[^\w-]', '_'
    if (-not $session) { exit 0 }
    New-Item -ItemType Directory -Force $stateDir | Out-Null
    $loaded = Join-Path $stateDir "$session.loaded"
    $nudged = Join-Path $stateDir "$session.nudged"

    if ($in.hook_event_name -eq 'PreCompact') {
        Remove-Item $loaded, $nudged -ErrorAction SilentlyContinue
        exit 0
    }

    if ($in.hook_event_name -eq 'PostToolUse') {
        if ($in.tool_name -eq 'Skill' -or $in.tool_name -eq 'skill') {
            if ($in.tool_input.skill -match 'lowly-writing-framework') { New-Item -Force $loaded | Out-Null }
        }
        elseif ($in.tool_name -eq 'Bash') {
            if ([string]$in.tool_input.command -match 'lowly-writing-framework[/\\]+SKILL\.md') { New-Item -Force $loaded | Out-Null }
        }
        exit 0
    }

    $tool = $in.tool_name -replace '^.*(__|-)', ''
    $isWrite = $false
    switch -Regex ($tool) {
        '^(create_pull_request|update_pull_request|add_pr_review_comment|edit_pr_review_comment|reply_to_comment|reply_and_resolve_review_thread)$' { $isWrite = $true }
        '^Bash$' { $isWrite = [string]$in.tool_input.command -match '\bgh\s+(pr|issue|discussion)\s+(create|edit|comment|review)\b' }
    }
    if (-not $isWrite) { exit 0 }

    if (-not (Test-Path $loaded) -and -not (Test-Path $nudged)) {
        New-Item -Force $nudged | Out-Null
        $msg = 'Load the lowly-writing-framework skill before writing this artifact, then retry. This reminder fires once, and again after each context compaction.'
        $decision = [ordered]@{ permissionDecision = 'deny'; permissionDecisionReason = $msg }
        $decision.hookSpecificOutput = [ordered]@{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $msg }
        # Copilot reads the top-level fields from stdout, Codex and Claude Code the hookSpecificOutput form; Claude Code and Codex also read stderr on exit 2.
        [Console]::Out.WriteLine(($decision | ConvertTo-Json -Compress -Depth 3))
        [Console]::Error.WriteLine($msg)
        exit 2
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine("lowly-writing-framework hook error (failing open): $_")
    exit 0
}
