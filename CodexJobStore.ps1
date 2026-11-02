# Codex-specific on-disk task and outcome readers. No GUI or worker globals.
Import-Module (Join-Path $PSScriptRoot 'components/JobOutcomes/JobOutcomes.psm1') -ErrorAction Stop
function Get-CodexJobPayloadFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory)
    if(-not (Test-Path -LiteralPath $Directory -PathType Container)){return}
    # Filter *before* any ordering or selection: .result.json is a result,
    # not a saved task. Never discard valid older jobs due to arbitrary "top 5".
    Get-ChildItem -LiteralPath $Directory -Filter 'CodexResume-*.json' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.result\.json$' } |
        Sort-Object LastWriteTime -Descending
}
function Get-CodexRunHistory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,[ValidateRange(1,1000)][int]$Limit=50)
    if(-not (Test-Path -LiteralPath $Directory -PathType Container)){return}
    $paths=Get-ChildItem -LiteralPath $Directory -Filter 'CodexResume-*.result.json' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First $Limit
    foreach($file in $paths){
        $name=$file.Name.Substring(0,$file.Name.Length - '.result.json'.Length)
        $state=Read-JobOutcome -Path $file.FullName
        if(-not $state){
            [pscustomobject]@{Name=$name;When=$file.LastWriteTime;Status='unreadable';Attempt=$null;ExitCode=$null;Message='Result file invalid or unreadable';NextJob=''}
            continue
        }
        $when=$file.LastWriteTime
        try {$when=[DateTimeOffset]::Parse([string]$state.at).LocalDateTime} catch {}
        [pscustomobject]@{
            Name=$name;When=$when;Status=[string]$state.status;Attempt=[int]$state.attempt
            ExitCode=$state.exitCode;Message=[string]$state.message;NextJob=[string]$state.nextJob
        }
    }
}

# Read only the named Scheduler's own artifacts. Never accept an arbitrary path
# from a Windows task or a row selection as a file to open.
function Get-CodexRunEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,
          [Parameter(Mandatory)][string]$Name)
    $fallback='No final Codex response was recorded for this run.'
    $result=[ordered]@{Response=$fallback;Transcript='No worker transcript available.'}
    if($Name -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}$'){return [pscustomobject]$result}
    if(-not (Test-Path -LiteralPath $Directory -PathType Container)){return [pscustomobject]$result}
    $events=Join-Path $Directory ($Name+'.jsonl')
    if(Test-Path -LiteralPath $events -PathType Leaf){
        $lastReply=$null
        $lastFailure=$null
        try {
            foreach($line in @(Get-Content -LiteralPath $events -Tail 1200 -ErrorAction Stop)){
                try {$entry=$line | ConvertFrom-Json -ErrorAction Stop} catch {continue}
                if($entry.type -eq 'item.completed' -and $entry.item.type -eq 'agent_message' -and $entry.item.text -is [string]){
                    $lastReply=[string]$entry.item.text
                } elseif($entry.type -eq 'turn.failed' -and $entry.error.message){
                    $lastFailure=[string]$entry.error.message
                } elseif($entry.type -eq 'error' -and $entry.message){
                    $lastFailure=[string]$entry.message
                } elseif($entry.type -eq 'turn.completed'){
                    # A successful turn supersedes earlier transient errors.
                    $lastFailure=$null
                }
            }
            if(-not [string]::IsNullOrWhiteSpace($lastFailure)){$result.Response=$lastFailure}
            elseif(-not [string]::IsNullOrWhiteSpace($lastReply)){$result.Response=$lastReply}
        } catch {$result.Response='Codex event log could not be read.'}
    }
    $transcript=Join-Path $Directory ($Name+'.log')
    if(Test-Path -LiteralPath $transcript -PathType Leaf){
        try {$result.Transcript=(Get-Content -LiteralPath $transcript -Tail 350 -ErrorAction Stop | Out-String)}
        catch {$result.Transcript='Worker transcript could not be read.'}
    }
    return [pscustomobject]$result
}
