<#
.SYNOPSIS
Hook gate for lowly-writing-framework on Claude Code, Copilot CLI, and Codex CLI (PowerShell twin of gate.sh).
Runs on Windows PowerShell 5.1 and PowerShell 7.
.DESCRIPTION
PreCompact:  clears the session markers so the next write is denied again and the skill reloads.
PostToolUse: records that the skill loaded, via the Skill tool or a read of its SKILL.md.
PreToolUse:  on GitHub write tools and `gh` write commands, denies up to twice per compaction cycle if the skill hasn't loaded:
first a soft deny (exit 0 plus decision JSON, so every harness shows the reason), then a hard deny (exit 2) if the model retries without loading it.
Fails open: any internal error prints a warning to stderr and exits 0.
Keep the matching logic in step with gate.sh.
#>
$ErrorActionPreference = 'Stop'

$Skill = 'lowly-writing-framework'
$WriteTools = '^(create_pull_request|update_pull_request|add_pr_review_comment|edit_pr_review_comment|reply_to_comment|reply_and_resolve_review_thread|issue_write|add_issue_comment|pull_request_review_write|add_comment_to_pending_review)$'
$GhFlags = '(\s+-\S+(\s+[^-\s]\S*)?)*'
$GhWriteCmd = "\bgh$GhFlags\s+(pr|issue|discussion)\s+(create|edit|comment|review)\b"
$GhApiCmd = "\bgh$GhFlags\s+api\b"
$GhApiWrite = 'mutation|(-X|--method)[\s=]*(POST|PATCH|PUT|DELETE)|\s(-f|-F|--field|--raw-field|--input)(\s|=|$)'

# A load is a Skill tool call naming the skill, or (Codex has no skill tool) a shell read of its SKILL.md.
function Test-SkillLoad($in) {
    switch ($in.tool_name) {
        { $_ -in 'Skill', 'skill' } { return [string]$in.tool_input.skill -match "^(.*:)?$Skill$" }
        'Bash' { return [string]$in.tool_input.command -match "(^|[^\w.-])$Skill[/\\]+SKILL\.md" }
        default { return $false }
    }
}

# A `gh api` call writes when it names a mutating method or a GraphQL mutation, or sends fields (which makes it a POST) to a REST endpoint.
function Test-GhApiWrite($cmd) {
    if ($cmd -cnotmatch $GhApiCmd) { return $false }
    if ($cmd -match 'graphql') { return $cmd -match 'mutation' }
    if ($cmd -match '(-X|--method)[\s=]*GET') { return $false }
    return $cmd -match $GhApiWrite
}

# True for a GitHub write tool, with or without an MCP prefix (`mcp__server__` on Claude Code, `server-` on Copilot), or a `gh` write command in Bash.
function Test-GitHubWrite($in) {
    $name = $in.tool_name -replace '^.*(__|-)', ''
    if ($name -eq 'Bash') {
        $cmd = [string]$in.tool_input.command
        return ($cmd -match $GhWriteCmd) -or (Test-GhApiWrite $cmd)
    }
    return $name -match $WriteTools
}

function Write-Deny {
    $msg = "Load the $Skill skill before writing this artifact, then retry. This reminder fires twice, and again after each context compaction."
    $decision = [ordered]@{ permissionDecision = 'deny'; permissionDecisionReason = $msg }
    $decision.hookSpecificOutput = [ordered]@{ hookEventName = 'PreToolUse'; permissionDecision = 'deny'; permissionDecisionReason = $msg }
    # Copilot reads the top-level fields from stdout, Codex and Claude Code the hookSpecificOutput form.
    # Copilot ignores stdout on a non-zero exit, so the caller exits 0 first and exits 2 only as the backstop.
    [Console]::Out.WriteLine(($decision | ConvertTo-Json -Compress -Depth 3))
    [Console]::Error.WriteLine($msg)
}

try {
    $in = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $session = $in.session_id -replace '[^\w-]', '_'
    if (-not $session) { exit 0 }

    $stateDir = Join-Path ([IO.Path]::GetTempPath()) $Skill
    New-Item -ItemType Directory -Force $stateDir | Out-Null
    $loaded = Join-Path $stateDir "$session.loaded"
    $soft = Join-Path $stateDir "$session.soft"
    $nudged = Join-Path $stateDir "$session.nudged"

    switch ($in.hook_event_name) {
        'PreCompact' {
            Remove-Item $loaded, $soft, $nudged -ErrorAction SilentlyContinue
            exit 0
        }
        'PostToolUse' {
            if (Test-SkillLoad $in) { New-Item -Force $loaded | Out-Null }
            exit 0
        }
    }

    if (-not (Test-GitHubWrite $in)) { exit 0 }

    if ((Test-Path $loaded) -or (Test-Path $nudged)) { exit 0 }

    Write-Deny
    if (Test-Path $soft) {
        New-Item -Force $nudged | Out-Null
        exit 2
    }
    New-Item -Force $soft | Out-Null
    exit 0
}
catch {
    [Console]::Error.WriteLine("lowly-writing-framework hook error (failing open): $_")
    exit 0
}