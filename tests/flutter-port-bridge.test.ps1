# Read-only integration test of the actual Windows JSON bridge.
# No scheduled task creation, cancellation, or login state changes.
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows required for bridge integration.'}
$project=Join-Path (Split-Path -Parent $PSScriptRoot) 'flutter_port'
$bridge=Join-Path $project 'windows_bridge.ps1'
if(-not (Test-Path -LiteralPath $bridge -PathType Leaf)){throw 'Flutter JSON bridge missing.'}
foreach($action in @('load','pending')){
    $output=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action $action)
    if($LASTEXITCODE -ne 0 -or -not $output){throw "Flutter $action bridge request failed."}
    try{
        $body=($output | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    }catch{
        throw "Flutter $action response did not contain valid JSON."
    }
    if($body.ok -ne $true){throw "Flutter $action bridge rejected request: $($body.error)"}
    if($null -eq $body.result -or $body.result.pending -isnot [array] -or $body.result.history -isnot [array]){
        throw "Flutter $action response is missing scheduler lists."
    }
    if($action -eq 'load' -and $body.result.sessions -isnot [array]){
        throw 'Flutter load response is missing saved conversation list.'
    }
    Write-Host "Flutter Windows $action read-only integration PASS." -ForegroundColor Green
}

# A real Windows bridge integration check: the same CodexData functions used
# by WinForms must resolve the Git root for a selected saved CLI session.
# A disposable CODEX_HOME prevents access to the operator's real conversations.
$originalCodexHome=$env:CODEX_HOME
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('flutter-repository-selection-'+[guid]::NewGuid().ToString('N'))
try {
    $repository=Join-Path $fixture 'qa-repository'
    $sessions=Join-Path $fixture 'codex-home\sessions\2026\11\04'
    [void](New-Item -ItemType Directory -Path $repository,$sessions -Force)
    & git init -b main $repository | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Unable to initialize disposable Git fixture.'}
    $sessionId=[guid]::NewGuid().ToString()
    $metadata=@{type='session_meta';payload=@{
        id=$sessionId;source='exec';cwd=$repository
    }} | ConvertTo-Json -Depth 8 -Compress
    Set-Content -LiteralPath (Join-Path $sessions ('rollout-'+$sessionId+'.jsonl')) -Value $metadata -Encoding utf8
    $env:CODEX_HOME=Join-Path $fixture 'codex-home'
    $payload=@{sessionId=$sessionId} | ConvertTo-Json -Compress
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $output=@(& pwsh -NoLogo -NoProfile -NonInteractive -STA -File $bridge -Action select -Payload $encoded)
    $exitCode=$LASTEXITCODE
    if(-not $output){throw "Bridge select returned no response (exit $exitCode)."}
    $answer=($output | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($exitCode -ne 0 -or $answer.ok -ne $true){
        throw "Bridge select rejected disposable session (exit $exitCode): $($answer.error)"
    }
    if($answer.result.sessionId -cne $sessionId){
        throw "Bridge selected the wrong session (expected $sessionId)."
    }
    $actual=[string]$answer.result.found.Root
    $expected=(& git -C $repository rev-parse --show-toplevel)
    if($LASTEXITCODE -ne 0){throw 'Git root verification failed.'}
    $actual=$actual.Replace('\','/').TrimEnd('/')
    $expected=([string]$expected).Replace('\','/').TrimEnd('/')
    if($actual -ine $expected){
        throw "Flutter bridge must resolve the original CodexData Git root. Expected '$expected', found '$actual'."
    }
    Write-Host 'Flutter real bridge selected disposable Git-backed CLI session PASS.' -ForegroundColor Green

    # The same resolver must *not* borrow that root for a different CLI
    # conversation whose recorded directory is outside any Git checkout.
    $outside=Join-Path $fixture 'outside-git'
    [void](New-Item -ItemType Directory -Path $outside)
    $otherId=[guid]::NewGuid().ToString()
    $otherMeta=@{type='session_meta';payload=@{
        id=$otherId;source='cli';cwd=$outside
    }} | ConvertTo-Json -Depth 8 -Compress
    Set-Content -LiteralPath (Join-Path $sessions ('rollout-'+$otherId+'.jsonl')) -Value $otherMeta -Encoding utf8
    $otherPayload=@{sessionId=$otherId} | ConvertTo-Json -Compress
    $otherEncoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($otherPayload))
    $otherOutput=@(& pwsh -NoLogo -NoProfile -NonInteractive -STA -File $bridge -Action select -Payload $otherEncoded)
    $otherExit=$LASTEXITCODE
    if(-not $otherOutput){throw "Non-repository CLI selection produced no response (exit $otherExit)."}
    $otherAnswer=($otherOutput | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($otherExit -ne 0 -or $otherAnswer.ok -ne $true){
        throw "Non-repository CLI selection failed rather than remaining unresolved: $($otherAnswer.error)"
    }
    if($null -ne $otherAnswer.result.found){
        throw "Unrelated CLI session must not inherit another session's Git repository."
    }
    Write-Host 'Flutter real bridge correctly leaves a non-Git CLI session unresolved PASS.' -ForegroundColor Green
    $listed=@(& pwsh -NoLogo -NoProfile -NonInteractive -STA -File $bridge -Action load)
    $listedExit=$LASTEXITCODE
    if($listedExit -ne 0 -or -not $listed){throw "Could not list disposable sessions (exit $listedExit)."}
    $listedResult=($listed | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($listedResult.ok -ne $true){throw "Cannot list sessions: $($listedResult.error)"}
    $gitSession=@($listedResult.result.sessions | Where-Object Id -eq $sessionId)
    $outsideSession=@($listedResult.result.sessions | Where-Object Id -eq $otherId)
    if($gitSession.Count -ne 1 -or $outsideSession.Count -ne 1){
        throw 'Git-backed and non-Git sessions must both appear in the chooser.'
    }
    if(-not $gitSession[0].Display.StartsWith('Git: qa-repository | ') -or
       -not $gitSession[0].Display.EndsWith($sessionId.Substring(28))){
        throw 'Git-backed session label must show the project, time and short ID.'
    }
    if(-not $outsideSession[0].Display.StartsWith('Outside Git: outside-git | ') -or
       -not $outsideSession[0].Display.EndsWith($otherId.Substring(28))){
        throw 'Non-Git session label must distinguish its starting folder, time and short ID.'
    }
    if($gitSession[0].Display.Contains($sessionId) -or
       $outsideSession[0].Display.Contains($otherId)){
        throw 'Full UUID must not crowd out session identity in the chooser.'
    }
    Write-Host 'Flutter conversation labels clearly distinguish Git-backed and outside-Git sessions PASS.' -ForegroundColor Green

} finally {
    if($null -eq $originalCodexHome){Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue}
    else{$env:CODEX_HOME=$originalCodexHome}
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}

# Exercise Flutter's actual JSON-in/JSON-out scheduling boundary, without
# contacting Codex or registering any task: the all-zero session is unverified
# and the repository path is deliberately empty.
function Assert-ScheduleRejected {
    param([Parameter(Mandatory)][string]$RunAt,[Parameter(Mandatory)][string]$Expected)
    $payload=@{
        sessionId='00000000-0000-0000-0000-000000000000'
        runAt=$RunAt
        repo=''
    } | ConvertTo-Json -Compress
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $output=@(& pwsh -NoProfile -NonInteractive -STA -File $bridge -Action schedule -Payload $encoded)
    $exit=$LASTEXITCODE
    if(-not $output){throw "Schedule preflight returned no response for $RunAt"}
    $answer=($output | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
    if($exit -eq 0 -or $answer.ok -ne $false -or $answer.error -cne $Expected){
        throw "Schedule preflight '$RunAt' expected '$Expected', got '$($answer.error)' (exit $exit)"
    }
}
$future=(Get-Date).AddDays(2).Date.AddHours(13).AddSeconds(37).ToString(
    'yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
Assert-ScheduleRejected -RunAt $future -Expected 'Selected CLI session not verified.'
Assert-ScheduleRejected -RunAt ($future+'Z') -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt ($future+'-06:00') -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt '2026-11-04 10:13:00' -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt ((Get-Date).AddMinutes(-3).ToString('yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)) -Expected 'Choose a time at least 30 seconds ahead.'
Write-Host 'Flutter strict local-time JSON schedule preflight PASS (no task mutation).' -ForegroundColor Green
