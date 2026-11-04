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
