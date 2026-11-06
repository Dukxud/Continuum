# Windows-native, read-only live Codex event monitor regression tests.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexRunActivity.ps1')
function Assert-Activity([bool]$Condition,[string]$Message){
    if(-not $Condition){throw $Message}
}
$dir=Join-Path ([IO.Path]::GetTempPath()) ('codex-monitor-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $dir -Force)
try {
    $name='CodexResume-20261105-2145-0123abcd'
    $file=Join-Path $dir ($name+'.jsonl')
    $missing=Get-CodexRunActivity -Directory $dir -Name $name
    Assert-Activity (-not $missing.Available -and $missing.Summary -eq 'Waiting for Codex events') 'Missing event stream was presented as live progress.'
    $invalid=Get-CodexRunActivity -Directory $dir -Name '..\secrets'
    Assert-Activity (-not $invalid.Available) 'Untrusted task name crossed read-only path boundary.'
    $events=@(
        '{"type":"thread.started","timestamp":"2026-11-05T12:30:00Z","thread_id":"example"}',
        '{"type":"turn.started"}',
        '{"type":"item.started","item":{"type":"command_execution","command":"pwsh -c echo private-token"}}',
        '{"type":"item.completed","item":{"type":"command_execution","exit_code":0,"aggregated_output":"private-token"}}',
        '{"type":"item.completed","item":{"type":"file_change","changes":[{"path":"private.txt","kind":"update"}]}}',
        '{"type":"item.completed","item":{"type":"agent_message","text":"Reviewed repository state and completed the source audit."}}'
    )
    # The stream may be concurrently open, and its final line may be incomplete.
    $events + @('{"type":"item.completed","item":') |
        Set-Content -LiteralPath $file -Encoding utf8
    $open=[IO.FileStream]::new($file,[IO.FileMode]::Open,
        [IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
        $result=Get-CodexRunActivity -Directory $dir -Name $name
        Assert-Activity ($result.Available -and $result.Summary -eq 'Codex response updated') 'Live JSONL events were not parsed.'
        Assert-Activity ($result.CompletedCommands -eq 1 -and $result.FileChanges -eq 1) 'Recent execution counts are inaccurate.'
        Assert-Activity ($result.LatestResponse -eq 'Reviewed repository state and completed the source audit.') 'Agent update is unavailable.'
        Assert-Activity (@($result.Recent).Count -le 3 -and $null -ne $result.UpdatedAt) 'Activity snapshot is unbounded or undated.'
        Assert-Activity (-not ((@($result.Recent) -join ' ') -match 'private-token')) 'Raw commands or output leaked to dashboard.'
        $milestones=@($result.Timeline)
        Assert-Activity ($milestones.Count -eq 5) 'Milestone timeline includes noisy started-item events or lost completions.'
        Assert-Activity ($milestones[0].At -eq 1793881800) 'Source event timestamp was not preserved.'
        Assert-Activity ($null -ne $result.StartedAt -and $result.StartedAt -gt 0) 'Stream start time is unavailable.'
        Assert-Activity (-not ((@($milestones | ConvertTo-Json -Depth 8) -join ' ') -match 'private-token|private.txt')) 'Timeline revealed command, output or file paths.'
    }finally{$open.Dispose()}
    # Tail bounds must prevent an ancient event from being counted as current.
    $padding='{"type":"item.updated","item":{"type":"reasoning","text":"' + ('x' * 30000) + '"}}'
    1..12 | ForEach-Object { Add-Content -LiteralPath $file -Value $padding -Encoding utf8 }
    Add-Content -LiteralPath $file -Value '{"type":"turn.completed"}' -Encoding utf8
    $bounded=Get-CodexRunActivity -Directory $dir -Name $name
    Assert-Activity ($bounded.Available -and $bounded.Summary -eq 'Codex turn completed') 'Bounded tail did not preserve latest activity.'
    Assert-Activity ($bounded.CompletedCommands -eq 0 -and $bounded.FileChanges -eq 0) 'Ancient event counts were misrepresented as recent.'
    # The worker can finish without a final agent response; never infer one.
    Assert-Activity ([string]::IsNullOrEmpty($bounded.LatestResponse)) 'An earlier response was incorrectly reported as live.'
    Assert-Activity (@($bounded.Timeline).Count -eq 1 -and $bounded.Timeline[0].Label -eq 'Codex turn completed') 'Milestones incorrectly crossed the 256 KiB tail boundary.'
    1..50 | ForEach-Object {
        Add-Content -LiteralPath $file -Value '{"type":"turn.completed"}' -Encoding utf8
    }
    $capped=Get-CodexRunActivity -Directory $dir -Name $name
    Assert-Activity (@($capped.Timeline).Count -eq 32) 'Live activity timeline was not capped at 32 milestones.'
    Write-Host 'Codex activity live JSONL read, bounded milestones, privacy and malformed-tail PASS.' -ForegroundColor Green
}finally{
    Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
}
