# Local synthetic rollouts: check resumable session eligibility without contacting Codex.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/backend/CodexData.ps1')
function Require($test,[string]$message){if(-not $test){throw $message}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('codex-resumable-sources-' + [guid]::NewGuid().ToString('N'))
$originalHome=$env:CODEX_HOME
try {
    $folder=Join-Path $temp 'sessions/2026/11/02'
    [void](New-Item -ItemType Directory -Path $folder -Force)
    $env:CODEX_HOME=$temp
    $interactive='00000000-0000-0000-0000-000000000011'
    $noninteractive='00000000-0000-0000-0000-000000000022'
    $other='00000000-0000-0000-0000-000000000033'
    function Add-Rollout([string]$id,[string]$source,[string]$label) {
        $path=Join-Path $folder ("rollout-2026-11-02T13-00-00-$label-$id.jsonl")
        [pscustomobject]@{
            timestamp='2026-11-02T13:00:00Z';type='session_meta'
            payload=[pscustomobject]@{id=$id;source=$source;cwd=$temp}
        } | ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $path -Encoding utf8
    }
    Add-Rollout $interactive 'cli' 'one'
    Add-Rollout $noninteractive 'exec' 'two'
    Add-Rollout $other 'vscode' 'three'
    Add-Rollout $noninteractive 'exec' 'duplicate'
    '{broken' | Set-Content -LiteralPath (Join-Path $folder 'rollout-invalid.jsonl')
    $sessions=@(Get-RecentCliSessions)
    Require ($sessions.Count -eq 2) "Only the two supported resumable sources may be selected; got $($sessions.Count)."
    Require (@($sessions | Where-Object Id -eq $interactive).Count -eq 1) 'Interactive CLI session was excluded.'
    Require (@($sessions | Where-Object Id -eq $noninteractive).Count -eq 1) 'Non-interactive exec session was excluded or duplicated.'
    Require (@($sessions | Where-Object Id -eq $other).Count -eq 0) 'Unapproved session source was included.'
    Require (@($sessions | Where-Object { $_.Cwd -ne $temp }).Count -eq 0) 'Saved workspace was not preserved.'
    Write-Host 'Resumable CLI/exec discovery, unknown-source exclusion, duplicates, corrupt rollout PASS.'
} finally {
    if($null -eq $originalHome){Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue}else{$env:CODEX_HOME=$originalHome}
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}