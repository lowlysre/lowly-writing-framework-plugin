BeforeAll {
    $script:root = Split-Path $PSScriptRoot -Parent
    $script:stateDir = Join-Path ([IO.Path]::GetTempPath()) 'lowly-writing-framework'
    $script:psExe = if ($IsWindows -or $PSVersionTable.PSEdition -eq 'Desktop') { 'powershell' } else { 'pwsh' }
    function script:Invoke-Gate($Name, $Event) {
        $json = $Event | ConvertTo-Json -Depth 5 -Compress
        $path = Join-Path $script:root "hooks/$Name"
        $out = if ($Name -like '*.sh') { $json | & bash $path 2>&1 } else { $json | & $script:psExe -NoProfile -File $path 2>&1 }
        [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out -join "`n") }
    }
    function script:Test-Denied($Result) { $Result.Output -match '"permissionDecision":"deny"' }
    function script:New-Event($Name, $Session, $Tool, $ToolInput) {
        @{ hook_event_name = $Name; session_id = $Session; tool_name = $Tool; tool_input = $ToolInput }
    }
}

Describe '<gate>' -ForEach @(@{ gate = 'gate.ps1' }, @{ gate = 'gate.sh' }) {
    BeforeEach { $script:sid = "t-$([guid]::NewGuid())" }
    AfterEach { Remove-Item (Join-Path $script:stateDir "$($script:sid).*") -ErrorAction SilentlyContinue }

    It 'soft-denies a GitHub write tool with exit 0, hard-denies the retry with exit 2, then allows' {
        $e = New-Event PreToolUse $script:sid 'create_pull_request' @{ title = 't' }
        $first = Invoke-Gate $gate $e
        $first.Code | Should -Be 0
        Test-Denied $first | Should -BeTrue
        $first.Output | Should -Match 'Load the lowly-writing-framework skill'
        $second = Invoke-Gate $gate $e
        $second.Code | Should -Be 2
        Test-Denied $second | Should -BeTrue
        $third = Invoke-Gate $gate $e
        $third.Code | Should -Be 0
        Test-Denied $third | Should -BeFalse
    }
    It 'matches MCP-prefixed tool names' {
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'mcp__github__add_pr_review_comment' @{ body = 'x' })) | Should -BeTrue
    }
    It 'matches Copilot-style hyphen-prefixed tool names' {
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'github-mcp-server-reply_to_comment' @{ response = 'x' })) | Should -BeTrue
    }
    It 'emits the deny decision on stdout in both shapes' {
        $out = (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'create_pull_request' @{ title = 't' })).Output
        $out | Should -Match '"permissionDecision":"deny"'
        $out | Should -Match '"hookSpecificOutput":\{"hookEventName":"PreToolUse","permissionDecision":"deny"'
    }
    It 'denies gh write commands through Bash' {
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'Bash' @{ command = 'gh pr create --title t' })) | Should -BeTrue
    }
    It 'ignores unrelated Bash commands and tools' {
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'Bash' @{ command = 'gh pr view 1' })) | Should -BeFalse
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'Edit' @{ file_path = 'a' })) | Should -BeFalse
    }
    It 'allows the first write once the Skill tool has loaded the skill' {
        (Invoke-Gate $gate (New-Event PostToolUse $script:sid 'Skill' @{ skill = 'lowly-writing-framework' })).Code | Should -Be 0
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'create_pull_request' @{ title = 't' })) | Should -BeFalse
    }
    It 'accepts the plugin-namespaced skill name' {
        (Invoke-Gate $gate (New-Event PostToolUse $script:sid 'Skill' @{ skill = 'lowly-writing-framework:lowly-writing-framework' })).Code | Should -Be 0
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'create_pull_request' @{ title = 't' })) | Should -BeFalse
    }
    It 'treats a Codex shell read of SKILL.md as loading the skill' -ForEach @(
        @{ cmd = 'cat /home/u/.codex/plugins/cache/m/lowly-writing-framework/0.1.0/skills/lowly-writing-framework/SKILL.md' }
        @{ cmd = 'Get-Content C:\Users\u\skills\lowly-writing-framework\SKILL.md' }
    ) {
        (Invoke-Gate $gate (New-Event PostToolUse $script:sid 'Bash' @{ command = $cmd })).Code | Should -Be 0
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'Bash' @{ command = 'gh pr create --title t' })) | Should -BeFalse
    }
    It 'does not count a different skill or file as loaded' {
        (Invoke-Gate $gate (New-Event PostToolUse $script:sid 'Skill' @{ skill = 'other' })).Code | Should -Be 0
        (Invoke-Gate $gate (New-Event PostToolUse $script:sid 'Bash' @{ command = 'cat other/SKILL.md' })).Code | Should -Be 0
        Test-Denied (Invoke-Gate $gate (New-Event PreToolUse $script:sid 'create_pull_request' @{ title = 't' })) | Should -BeTrue
    }
    It 'denies again after PreCompact clears the loaded marker' {
        $w = New-Event PreToolUse $script:sid 'create_pull_request' @{ title = 't' }
        (Invoke-Gate $gate (New-Event PostToolUse $script:sid 'Skill' @{ skill = 'lowly-writing-framework' })).Code | Should -Be 0
        Test-Denied (Invoke-Gate $gate $w) | Should -BeFalse
        (Invoke-Gate $gate (New-Event PreCompact $script:sid $null $null)).Code | Should -Be 0
        Test-Denied (Invoke-Gate $gate $w) | Should -BeTrue
    }
    It 'denies again after PreCompact clears the soft and nudged markers' {
        $w = New-Event PreToolUse $script:sid 'create_pull_request' @{ title = 't' }
        (Invoke-Gate $gate $w).Code | Should -Be 0
        (Invoke-Gate $gate $w).Code | Should -Be 2
        Test-Denied (Invoke-Gate $gate $w) | Should -BeFalse
        (Invoke-Gate $gate (New-Event PreCompact $script:sid $null $null)).Code | Should -Be 0
        $again = Invoke-Gate $gate $w
        $again.Code | Should -Be 0
        Test-Denied $again | Should -BeTrue
    }
    It 'fails open on unparseable input' {
        $path = Join-Path $script:root "hooks/$gate"
        $out = if ($gate -like '*.sh') { 'not json' | & bash $path 2>&1 } else { 'not json' | & $script:psExe -NoProfile -File $path 2>&1 }
        $LASTEXITCODE | Should -Be 0
    }
}
