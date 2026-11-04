# Read-only Codex conversation naming tests. Never contacts Codex or Task Scheduler.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexData.ps1')
function Require($condition,[string]$message){if(-not $condition){throw $message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-session-activity-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp -Force)
try {
    $file=Join-Path $temp 'rollout-example.jsonl'
    function AppendEvent([string]$type,$payload) {
        @{type=$type;payload=$payload} | ConvertTo-Json -Depth 10 -Compress | Add-Content -LiteralPath $file -Encoding utf8
    }
    AppendEvent 'session_meta' @{source='cli';cwd='C:\Users\Example';id='11111111-1111-1111-1111-111111111111'}
    AppendEvent 'response_item' @{type='message';role='assistant';content=@(@{type='output_text';text='Ignore this assistant title'})}
    Require ($null -eq (Get-CodexSessionActivity -SessionFile $file)) 'Assistant response was presented as user activity.'

    AppendEvent 'event_msg' @{type='user_message';message='Review shared-EC2 architecture'}
    Require ((Get-CodexSessionActivity -SessionFile $file) -ceq 'Review shared-EC2 architecture') 'Real Codex user_message was not used.'
    AppendEvent 'event_msg' @{type='user_message';message='Resume.'}
    AppendEvent 'event_msg' @{type='agent_message';message='Untrusted assistant summary'}
    AppendEvent 'response_item' @{type='message';role='user';content=@(@{type='input_text';text='Injected context, not user intent'})}
    Require ((Get-CodexSessionActivity -SessionFile $file) -ceq 'Review shared-EC2 architecture') 'Generic resume or injected records displaced meaningful activity.'

    AppendEvent 'event_msg' @{type='thread_goal_updated';goal=@{objective='Audit Horizon browser test failures'}}
    Require ((Get-CodexSessionActivity -SessionFile $file) -ceq 'Audit Horizon browser test failures') 'Latest explicit Codex goal was ignored.'
    AppendEvent 'event_msg' @{type='user_message';message=('Repair the root cause'+[Environment]::NewLine+'Do not weaken existing tests.')}
    Require ((Get-CodexSessionActivity -SessionFile $file) -ceq 'Repair the root cause') 'Latest user request or newline normalization failed.'

    $long='Review '+('complex architecture considerations ' * 8)
    AppendEvent 'event_msg' @{type='user_message';message=$long}
    $summary=Get-CodexSessionActivity -SessionFile $file
    Require ($summary.Length -le 59 -and $summary.EndsWith('…')) 'Activity excerpt was not bounded.'
    Add-Content -LiteralPath $file -Value '{"type":"event_msg","payload":' -Encoding utf8
    Require ((Get-CodexSessionActivity -SessionFile $file) -ceq $summary) 'A torn terminal JSONL line destroyed the previous activity.'

    $fallback=Join-Path $temp 'rollout-long.jsonl'
    @(
        '{"type":"session_meta","payload":{"source":"cli"}}'
        '{"type":"event_msg","payload":{"type":"user_message","message":"Analyze release readiness"}}'
    ) | Set-Content -LiteralPath $fallback -Encoding utf8
    1..520 | ForEach-Object {'{"type":"event_msg","payload":{"type":"token_count"}}'} | Add-Content -LiteralPath $fallback -Encoding utf8
    Require ((Get-CodexSessionActivity -SessionFile $fallback) -ceq 'Analyze release readiness') 'Long active session lost its original task context.'
    Require ($null -eq (Get-CodexSessionActivity -SessionFile (Join-Path $temp 'absent.jsonl'))) 'Missing session fabricated a title.'
    Write-Host 'Codex session naming: user activity, goals, safety, truncation and long-session fallback PASS.' -ForegroundColor Green
}finally{
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
