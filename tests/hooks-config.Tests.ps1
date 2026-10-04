BeforeDiscovery {
    $script:isWin = $IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop'
    $script:hasBash = [bool](Get-Command bash -ErrorAction SilentlyContinue)
}

BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:stateDir = Join-Path ([IO.Path]::GetTempPath()) 'lowly-writing-framework'
    $script:psExe = if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') { 'powershell' } else { 'pwsh' }
    $script:claude = (Get-Content (Join-Path $script:root 'hooks/hooks.json') -Raw | ConvertFrom-Json).hooks
    $script:writeTools = 'create_pull_request', 'update_pull_request', 'add_pr_review_comment', 'edit_pr_review_comment', 'reply_to_comment', 'reply_and_resolve_review_thread'

    # The harness substitutes the plugin root textually before it runs the command string.
    function script:Expand($Command) {
        $Command.Replace('${CLAUDE_PLUGIN_ROOT}', $script:root).Replace('${PLUGIN_ROOT}', $script:root)
    }
    function script:Invoke-Hook($Shell, $Command, $Payload) {
        $json = $Payload | ConvertTo-Json -Depth 5 -Compress
        $text = Expand $Command
        $out = switch ($Shell) {
            'powershell' { $json | & $script:psExe -NoProfile -c $text 2>&1 }
            'cmd' { $json | & cmd /c $text 2>&1 }
            default { $json | & bash -c $text 2>&1 }
        }
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out -join "`n") }
    }
    function script:New-Pre($Session, $Tool, $ToolInput) {
        @{ hook_event_name = 'PreToolUse'; session_id = $Session; tool_name = $Tool; tool_input = $ToolInput }
    }
}

Describe 'plugin packaging' {
    It 'ships a marketplace entry that agrees with the plugin name' {
        $p = Get-Content (Join-Path $script:root '.claude-plugin/plugin.json') -Raw | ConvertFrom-Json
        $m = Get-Content (Join-Path $script:root '.claude-plugin/marketplace.json') -Raw | ConvertFrom-Json
        $m.plugins[0].name | Should -Be $p.name
    }
    It 'vendors the skill with a lockfile entry' {
        Test-Path (Join-Path $script:root 'skills/lowly-writing-framework/SKILL.md') | Should -BeTrue
        $lock = Get-Content (Join-Path $script:root 'skills-lock.json') -Raw | ConvertFrom-Json
        $lock.skills.'lowly-writing-framework'.ref | Should -Match '^v\d+\.\d+\.\d+$'
    }
}

Describe 'hooks configs' {
    It 'declares a command hook for <name> with the gate script' -ForEach @(
        @{ name = 'claude PreToolUse'; entry = { $script:claude.PreToolUse[0] } }
        @{ name = 'claude PostToolUse'; entry = { $script:claude.PostToolUse[0] } }
    ) {
        $e = & $entry
        $e.matcher | Should -Not -BeNullOrEmpty
        $e.hooks[0].type | Should -Be 'command'
        $e.hooks[0].command | Should -Match 'gate\.sh'
    }
    It 'declares a PreCompact hook for the gate script' {
        $script:claude.PreCompact[0].hooks[0].command | Should -Match 'gate\.sh'
    }
    It 'references scripts that exist' {
        foreach ($rel in 'hooks/gate.sh', 'hooks/gate.ps1') {
            Test-Path (Join-Path $script:root $rel) | Should -BeTrue -Because $rel
        }
    }
    It 'uses the plugin root placeholder in every command' {
        $h = $script:claude.PreToolUse[0].hooks[0]
        foreach ($f in 'command', 'bash', 'powershell', 'commandWindows') { $h.$f | Should -Match '\$\{CLAUDE_PLUGIN_ROOT\}' }
    }
    It 'forwards the gate exit code from the powershell command' {
        # Copilot runs this through `pwsh -c`, which reports 1 for any failed native command and would lose exit code 2.
        $script:claude.PreToolUse[0].hooks[0].powershell | Should -Match 'exit \$LASTEXITCODE\s*$'
    }
    It 'marks gate.sh executable in git' -Skip:(-not (Get-Command git -ErrorAction SilentlyContinue)) {
        (git -C $script:root ls-files -s hooks/gate.sh) | Should -Match '^100755'
    }
}

Describe 'matchers' {
    # Copilot anchors a non-literal matcher as ^(?:PATTERN)$ against the tool name.
    It 'PreToolUse matches <tool>' -ForEach @(
        @{ tool = 'Bash' }, @{ tool = 'create_pull_request' }, @{ tool = 'mcp__github__add_pr_review_comment' },
        @{ tool = 'github-mcp-server-reply_to_comment' }, @{ tool = 'reply_and_resolve_review_thread' }
    ) {
        $tool | Should -Match "^(?:$($script:claude.PreToolUse[0].matcher))`$"
    }
    It 'PreToolUse ignores <tool>' -ForEach @(
        @{ tool = 'Edit' }, @{ tool = 'Read' }, @{ tool = 'create_pull_request_extra' }, @{ tool = 'create_issue' }
    ) {
        $tool | Should -Not -Match "^(?:$($script:claude.PreToolUse[0].matcher))`$"
    }
    It 'PostToolUse matches the skill tool and, for Codex, Bash' -ForEach @(@{ tool = 'Skill' }, @{ tool = 'skill' }, @{ tool = 'Bash' }) {
        $tool | Should -Match "^(?:$($script:claude.PostToolUse[0].matcher))`$"
    }
    It 'PostToolUse ignores <tool>' -ForEach @(@{ tool = 'Edit' }, @{ tool = 'Read' }) {
        $tool | Should -Not -Match "^(?:$($script:claude.PostToolUse[0].matcher))`$"
    }
    It 'lists the same write tools as both gates' {
        $inMatcher = ([regex]::Match($script:claude.PreToolUse[0].matcher, '\((create_pull_request[^)]*)\)').Groups[1].Value -split '\|') | Sort-Object
        $inSh = ([regex]::Match((Get-Content (Join-Path $script:root 'hooks/gate.sh') -Raw), 'WRITE_TOOLS=''(create_pull_request[^'']*)''').Groups[1].Value -split '\|') | Sort-Object
        $inPs = ([regex]::Match((Get-Content (Join-Path $script:root 'hooks/gate.ps1') -Raw), '\^\((create_pull_request[^)]*)\)\$').Groups[1].Value -split '\|') | Sort-Object
        $inMatcher | Should -Be ($script:writeTools | Sort-Object)
        $inSh | Should -Be $inMatcher
        $inPs | Should -Be $inMatcher
    }
}

Describe 'hook commands as the harness runs them' {
    BeforeEach { $script:sid = "p-$([guid]::NewGuid())" }
    AfterEach { Remove-Item (Join-Path $script:stateDir "$($script:sid).*") -ErrorAction SilentlyContinue }

    It 'runs the <name> command: deny, then allow after the skill loads' -ForEach @(
        @{ name = 'claude command'; pre = { $script:claude.PreToolUse[0].hooks[0].command }; post = { $script:claude.PostToolUse[0].hooks[0].command }; tool = 'skill'; input = @{ skill = 'lowly-writing-framework' } }
        @{ name = 'claude bash'; pre = { $script:claude.PreToolUse[0].hooks[0].bash }; post = { $script:claude.PostToolUse[0].hooks[0].bash }; tool = 'skill'; input = @{ skill = 'lowly-writing-framework' } }
        @{ name = 'codex file read'; pre = { $script:claude.PreToolUse[0].hooks[0].command }; post = { $script:claude.PostToolUse[0].hooks[0].command }; tool = 'Bash'; input = @{ command = 'cat skills/lowly-writing-framework/SKILL.md' } }
    ) -Skip:(-not $script:hasBash) {
        $cmd = & $pre
        $deny = Invoke-Hook 'bash' $cmd (New-Pre $script:sid 'Bash' @{ command = 'gh pr create --title t' })
        $deny.Code | Should -Be 2
        $deny.Output | Should -Match 'Load the lowly-writing-framework skill'
        $load = @{ hook_event_name = 'PostToolUse'; session_id = $script:sid; tool_name = $tool; tool_input = $input }
        (Invoke-Hook 'bash' (& $post) $load).Code | Should -Be 0
        (Invoke-Hook 'bash' $cmd (New-Pre $script:sid 'Bash' @{ command = 'gh pr create --title t' })).Code | Should -Be 0
    }
    It 'runs the <name> command on Windows and keeps exit code 2' -ForEach @(
        @{ name = 'claude powershell'; shell = 'powershell'; cmd = { $script:claude.PreToolUse[0].hooks[0].powershell } }
        @{ name = 'codex commandWindows'; shell = 'cmd'; cmd = { $script:claude.PreToolUse[0].hooks[0].commandWindows } }
    ) -Skip:(-not $script:isWin) {
        $c = & $cmd
        $deny = Invoke-Hook $shell $c (New-Pre $script:sid 'Bash' @{ command = 'gh pr create --title t' })
        $deny.Code | Should -Be 2
        $deny.Output | Should -Match 'permissionDecision'
        (Invoke-Hook $shell $c (New-Pre $script:sid 'Bash' @{ command = 'gh pr view 1' })).Code | Should -Be 0
    }
}
