# Evidence reader tests are entirely local and never invoke the Codex CLI.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexJobStore.ps1')
function Require($ok,[string]$why){if(-not $ok){throw $why}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-evidence-' + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp -Force)
try {
    $name='CodexResume-20261102-1501-f0e770de'
    $events=Join-Path $temp ($name+'.jsonl')
    $log=Join-Path $temp ($name+'.log')
    @(
        'bad json'
        '{"type":"error","message":"Temporary network error"}'
        '{"type":"item.completed","item":{"type":"agent_message","text":"SCHEDULER_QA_COMPLETED"}}'
        '{"type":"turn.completed"}'
    ) | Set-Content -LiteralPath $events
    'Codex exit code: 0' | Set-Content -LiteralPath $log
    $evidence=Get-CodexRunEvidence -Directory $temp -Name $name
    Require ($evidence.Response -eq 'SCHEDULER_QA_COMPLETED') 'Completed turn did not override a transient error.'
    Require ($evidence.Transcript -match 'Codex exit code: 0') 'Worker log missing.'
    @(
        '{"type":"item.completed","item":{"type":"agent_message","text":"Partial response"}}'
        '{"type":"turn.failed","error":{"message":"Usage limit reached"}}'
    ) | Set-Content -LiteralPath $events
    $failed=Get-CodexRunEvidence -Directory $temp -Name $name
    Require ($failed.Response -eq 'Usage limit reached') 'Terminal failure must override partial agent output.'
    Remove-Item -LiteralPath $events
    Remove-Item -LiteralPath $log
    $missing=Get-CodexRunEvidence -Directory $temp -Name $name
    Require ($missing.Response -match 'No final Codex response' -and $missing.Transcript -match 'No worker transcript') 'Missing evidence was fabricated.'
    $invalid=Get-CodexRunEvidence -Directory $temp -Name '../secrets'
    Require ($invalid.Response -match 'No final Codex response') 'Unsafe job name was accepted.'
    Write-Host 'Read-only Codex evidence: success, failure, invalid event, missing file, and path guard PASS.'
} finally {
    Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
