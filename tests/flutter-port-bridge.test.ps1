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
$future=(Get-Date).AddDays(2).Date.AddHours(13).ToString(
    'yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)
Assert-ScheduleRejected -RunAt $future -Expected 'Selected CLI session not verified.'
Assert-ScheduleRejected -RunAt ($future+'Z') -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt ($future+'-06:00') -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt '2026-11-04 10:13:00' -Expected 'Invalid local run time.'
Assert-ScheduleRejected -RunAt ((Get-Date).AddMinutes(-3).ToString('yyyy-MM-ddTHH:mm:ss',[Globalization.CultureInfo]::InvariantCulture)) -Expected 'Choose a time at least 30 seconds ahead.'
Write-Host 'Flutter strict local-time JSON schedule preflight PASS (no task mutation).' -ForegroundColor Green
