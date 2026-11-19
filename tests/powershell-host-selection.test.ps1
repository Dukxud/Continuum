# Saved task actions pin the current verified PowerShell installation instead
# of assuming it also exists under Program Files or searching a future CWD.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../src/backend/CodexRunEngine.ps1')
$passed=0;$failed=0
function Check([string]$Name,[scriptblock]$Body){
    try{& $Body;$script:passed++;Write-Host "PASS $Name"}
    catch{$script:failed++;Write-Host "FAIL ${Name}: $($_.Exception.Message)"}
}
function Assert-That([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
$current=Join-Path $PSHOME ($IsWindows ? 'pwsh.exe' : 'pwsh')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('continuum-pwsh-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temp)
try{
    $runner=Join-Path $temp 'runner with spaces.vbs'
    $job=Join-Path $temp 'job with spaces.json'
    foreach($mode in @('background','terminal','shared')){
        Check "$mode task pins the current absolute PowerShell host" {
            $arguments=Get-CodexTaskArguments -Runner $runner -JobFile $job -ExecutionMode $mode
            Assert-That ($arguments.Contains('"'+$current+'"')) 'Task action omits the active PowerShell installation.'
            Assert-That ($arguments.Contains('"'+$runner+'" "'+$job+'"')) 'Existing runner/job quoting changed.'
            Assert-That ($arguments.EndsWith(' terminal') -eq ($mode -eq 'terminal')) 'Console visibility changed.'
        }
    }
    Check 'relative or missing PowerShell paths are rejected before task registration' {
        foreach($invalid in @('pwsh.exe',(Join-Path $temp 'missing/pwsh.exe'))){
            $rejected=$false
            try{Get-CodexTaskArguments -Runner $runner -JobFile $job -PowerShellExecutable $invalid | Out-Null}catch{$rejected=$true}
            Assert-That $rejected 'An unverified host path was accepted.'
        }
    }
    Check 'an explicitly selected existing portable host is quoted without PATH lookup' {
        $portable=Join-Path $temp 'Portable PowerShell/pwsh.exe'
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $portable))
        [IO.File]::WriteAllText($portable,'fixture; never executed')
        $arguments=Get-CodexTaskArguments -Runner $runner -JobFile $job -PowerShellExecutable $portable
        Assert-That ($arguments.EndsWith('"'+$portable+'"')) 'Explicit verified host was replaced.'
    }
}finally{Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host "PowerShell host selection: $passed passed; $failed failed."
if($failed){exit 1}
