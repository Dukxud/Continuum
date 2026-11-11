# Shared-session client commands. All operations validate the saved job before
# contacting its owner; this adapter never creates a replacement App Server.
function Get-FlutterSharedJobPath {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$AppDirectory
    )
    if($name -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}$'){throw 'Invalid shared-session name.'}
    $job=Join-Path $AppDirectory ($name+'.json')
    if(-not (Test-Path -LiteralPath $job -PathType Leaf)){throw 'Shared job not found.'}
    $saved=Get-Content -LiteralPath $job -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if([string]$saved.executionMode -cne 'shared'){throw 'Job does not use shared execution.'}
    return $job
}

function Get-FlutterSharedStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Request,
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    $job=Get-FlutterSharedJobPath -Name ([string]$Request.name) -AppDirectory $AppDirectory
    $script=Join-Path $SourceDirectory 'components/SharedCodexSession/main.mjs'
    $online=$false
    try {
        $lines=@(& node.exe $script status $job 2>$null)
        if($LASTEXITCODE -eq 0 -and $lines.Count -gt 0){
            $snapshot=($lines | Select-Object -Last 1) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $online=$true
        }
    }catch { $online=$false }
    if(-not $online){
        # Completed jobs lose their transient pipe/descriptor; the
        # persisted result is authoritative. Never leave a stale
        # 'running' snapshot onscreen after a successful exit.
        $resultPath=[IO.Path]::ChangeExtension($job,'.result.json')
        $outcome=Read-JobOutcome -Path $resultPath
        if(-not $outcome){throw 'Shared session unavailable; no recorded outcome yet.'}
        $snapshot=@{
            action='snapshot'; status=[string]$outcome.status; offline=$true
            pending=@(); events=@(); message=[string]$outcome.message
            finishedAt=[string]$outcome.at; nativeViewers=0
        }
    }
    return $snapshot
}

function Open-FlutterSharedTerminal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Request,
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    $job=Get-FlutterSharedJobPath -Name ([string]$Request.name) -AppDirectory $AppDirectory
    $script=Join-Path $SourceDirectory 'components/SharedCodexSession/main.mjs'
    $node=(Get-Command node.exe -ErrorAction Stop).Source
    # The terminal is a client of the authenticated running owner.
    # This action never starts an App Server or creates a fork.
    $lines=@(& $node $script status $job)
    if($LASTEXITCODE -ne 0 -or $lines.Count -eq 0){throw 'Shared session owner is not reachable.'}
    $program=Join-Path $env:ProgramFiles 'PowerShell\7\pwsh.exe'
    if(-not (Test-Path -LiteralPath $program -PathType Leaf)){throw 'PowerShell 7 is missing.'}
    $cli=Get-CodexCliJs
    $cmd="& '$($node.Replace("'","''"))' '$($script.Replace("'","''"))' native '$($job.Replace("'","''"))' '$($cli.Replace("'","''"))'"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))
    $wt=Get-Command wt.exe -ErrorAction SilentlyContinue
    if($wt){
        $terminalArguments='-w new new-tab --title "Continuum viewer" "'+$program+'" -NoLogo -NoExit -EncodedCommand '+$encoded
        [void](Start-Process -FilePath $wt.Source -ArgumentList $terminalArguments -PassThru -ErrorAction Stop)
    }else{
        [void](Start-Process -FilePath $program -ArgumentList @('-NoLogo','-NoExit','-EncodedCommand',$encoded) -PassThru -ErrorAction Stop)
    }
    return @{opened=$true;nativeTui=$true}
}

function Send-FlutterSharedAnswer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Request,
        [Parameter(Mandatory)][string]$SourceDirectory,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    $job=Get-FlutterSharedJobPath -Name ([string]$Request.name) -AppDirectory $AppDirectory
    $body=[pscustomobject]@{action='answer';id=[string]$Request.requestId;result=$Request.result}
    $script=Join-Path $SourceDirectory 'components/SharedCodexSession/main.mjs'
    $wire=$body | ConvertTo-Json -Depth 16 -Compress
    $lines=@($wire | node.exe $script answer $job)
    if($LASTEXITCODE -ne 0 -or $lines.Count -eq 0){throw 'Shared request refused or expired.'}
    $reply=($lines | Select-Object -Last 1) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if($reply.action -ne 'ack'){throw 'Shared request was not acknowledged.'}
    return $reply
}
