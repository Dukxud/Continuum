# Actual Windows CMD/PowerShell routing. Application binaries are inert fixtures;
# this verifies entrypoint decisions and integrity checks, not a compiled UI.
[CmdletBinding()]
param([string]$PinnedPreviewDirectory='')
$ErrorActionPreference='Stop'
if(-not $IsWindows){Write-Host 'SKIP native Windows CMD/PowerShell launcher integration: this host is not Windows.';return}
$root=Split-Path -Parent $PSScriptRoot
$launcher=Join-Path $root 'Run-Continuum.ps1'
$batch=Join-Path $root 'Run-Continuum.cmd'
$helperRelative='src/desktop/scripts/Assert-PreviewPackage.ps1'
. (Join-Path $root $helperRelative)
$tempRoot=Join-Path ([IO.Path]::GetTempPath()) ('continuum-native-launcher-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $tempRoot)
$originalLocalAppData=$env:LOCALAPPDATA
$originalBackendOverride=$env:CODEX_SCHEDULER_SOURCE
$originalBuildTemplate=$env:CONTINUUM_TEST_BUILT_TEMPLATE
$originalCapture=$env:CONTINUUM_TEST_LAUNCH_CAPTURE
$passed=0;$skipped=0
function Check([string]$Name,[scriptblock]$Body){& $Body;$script:passed++;Write-Host "PASS $Name"}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Write-Manifest([string]$Directory){
    $lines=@(Get-ChildItem -LiteralPath $Directory -File -Recurse -Force |
        Where-Object Name -NE 'SHA256SUMS.txt' | Sort-Object FullName | ForEach-Object {
            (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash+'  '+[IO.Path]::GetRelativePath($Directory,$_.FullName).Replace('\','/')
        })
    Set-Content -LiteralPath (Join-Path $Directory 'SHA256SUMS.txt') -Value $lines -Encoding utf8
}
function New-Package([string]$Name){
    $directory=Join-Path $tempRoot $Name
    foreach($relative in @(Get-ContinuumPreviewRequiredFiles)){
        $path=Join-Path $directory $relative
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
        $source=Join-Path $root $relative
        if(Test-Path -LiteralPath $source -PathType Leaf){Copy-Item -LiteralPath $source -Destination $path}
        else{[IO.File]::WriteAllText($path,'inert fixture; never execute as a native program')}
    }
    @{application='Continuum';version='0.1.0+1';sourceCommit=$null;sourceModified=$null;sourceArchive=$true} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'build-info.json') -Encoding utf8
    Write-Manifest $directory
    return $directory
}
function Invoke-InterceptedLauncher([string]$Path){
    function Invoke-WebRequest {throw 'Unexpected network operation.'}
    function Start-Process {
        param([string]$FilePath,[string]$WorkingDirectory)
        [IO.File]::WriteAllText($env:CONTINUUM_TEST_LAUNCH_CAPTURE,$FilePath)
    }
    . $Path
}
function Require-LaunchFailure([string]$Path,[string]$Expected){
    Remove-Item -LiteralPath $env:CONTINUUM_TEST_LAUNCH_CAPTURE -ErrorAction SilentlyContinue
    $failure='';try{Invoke-InterceptedLauncher $Path}catch{$failure=$_.Exception.Message}
    Require ($failure.Contains($Expected)) "Expected '$Expected', received '$failure'."
    Require (-not (Test-Path -LiteralPath $env:CONTINUUM_TEST_LAUNCH_CAPTURE)) 'A rejected package was launched.'
}
try{
    $env:LOCALAPPDATA=Join-Path $tempRoot 'profile'
    $capture=Join-Path $tempRoot 'launched.txt';$env:CONTINUUM_TEST_LAUNCH_CAPTURE=$capture
    $only=Join-Path $tempRoot 'launcher-only'
    $helper=Join-Path $only $helperRelative
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $helper) -Force)
    Copy-Item -LiteralPath $launcher,$batch -Destination $only
    Copy-Item -LiteralPath (Join-Path $root $helperRelative) -Destination $helper
    $standalone=Join-Path $only 'Run-Continuum.ps1'
    $cache=Join-Path $env:LOCALAPPDATA 'Continuum/Previews/v0.1.0-preview.1'
    $cachePackage=Join-Path $cache 'Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW'
    Check 'an EXE-only pinned cache is rejected without a launch or network request' {
        [void](New-Item -ItemType Directory -Path $cachePackage -Force)
        Set-Content -LiteralPath (Join-Path $cachePackage 'codex_resume_flutter.exe') 'inert fixture'
        Require-LaunchFailure $standalone 'checksum manifest missing'
        Remove-Item -LiteralPath $cache -Recurse -Force
    }
    if($PinnedPreviewDirectory){
        Check 'the exact published cache is reverified before launch' {
            Assert-ContinuumPreviewPackage -Directory $PinnedPreviewDirectory -Profile PinnedPreview1 | Out-Null
            [void](New-Item -ItemType Directory -Path $cachePackage -Force)
            foreach($entry in @(Get-ChildItem -LiteralPath $PinnedPreviewDirectory -Force)){
                Copy-Item -LiteralPath $entry.FullName -Destination $cachePackage -Recurse
            }
            Invoke-InterceptedLauncher $standalone
            Require ([IO.File]::ReadAllText($capture) -ceq (Join-Path $cachePackage 'codex_resume_flutter.exe')) 'Verified cache selected another executable.'
            Remove-Item -LiteralPath $cache -Recurse -Force
        }
    }else{$skipped++;Write-Host 'SKIP exact public Preview 1 positive cache: supply -PinnedPreviewDirectory to its independently verified extraction.'}
    Check 'a mismatched release download is rejected before extraction or launch' {
        & {
            function Invoke-WebRequest {param($Uri,$OutFile);[IO.File]::WriteAllText($OutFile,'tampered download')}
            function Expand-Archive {throw 'Mismatched download reached extraction.'}
            function Start-Process {throw 'Mismatched download reached launch.'}
            $failure='';try{. $standalone}catch{$failure=$_.Exception.Message}
            Require ($failure.Contains('SHA-256 does not match')) "Wrong download failure: $failure"
        }
    }
    $package=New-Package 'complete [review] package'
    Check 'complete current package launches its verified sibling without a download' {
        Invoke-InterceptedLauncher (Join-Path $package 'Run-Continuum.ps1')
        Require ([IO.File]::ReadAllText($capture) -ceq (Join-Path $package 'codex_resume_flutter.exe')) 'Current package selected another executable.'
    }
    Check 'changed package code is rejected before application launch' {
        $tampered=New-Package 'tampered package'
        Add-Content -LiteralPath (Join-Path $tampered 'src/desktop/windows_bridge.ps1') 'changed'
        Require-LaunchFailure (Join-Path $tampered 'Run-Continuum.ps1') 'Preview package checksum failed'
    }
    Check 'empty Flutter data is rejected even with a regenerated manifest' {
        $incomplete=New-Package 'empty data package'
        Remove-Item -LiteralPath (Join-Path $incomplete 'data') -Recurse -Force
        [void](New-Item -ItemType Directory -Path (Join-Path $incomplete 'data'))
        Write-Manifest $incomplete
        Require-LaunchFailure (Join-Path $incomplete 'Run-Continuum.ps1') 'required file missing from manifest: data/app.so'
    }
    Check 'changed verifier is rejected before it can be loaded' {
        $tampered=New-Package 'tampered verifier'
        Add-Content -LiteralPath (Join-Path $tampered $helperRelative) "`nthrow 'Verifier was executed before its hash check.'"
        Require-LaunchFailure (Join-Path $tampered 'Run-Continuum.ps1') 'checksum failed: src/desktop/scripts/Assert-PreviewPackage.ps1'
    }

    $source=Join-Path $tempRoot 'source archive [review]'
    [void](New-Item -ItemType Directory -Path $source -Force)
    Copy-Item -LiteralPath $launcher,$batch -Destination $source
    foreach($relative in @('src/desktop/pubspec.yaml','src/desktop/pubspec.lock','src/desktop/lib/main.dart',
        'src/desktop/windows_bridge.ps1','src/backend/CodexRunEngine.ps1',
        'src/desktop/scripts/Get-PreviewMetadata.ps1','src/desktop/scripts/Initialize-WindowsRunner.ps1',
        'src/desktop/scripts/Install-WindowsIcon.ps1','src/desktop/scripts/Test-WindowsBuildPrerequisites.ps1',
        'src/desktop/scripts/Invoke-PreviewBuild.ps1','tests/flutter-port-source.test.ps1',
        'tests/flutter-port-bridge.test.ps1','tests/windows-task-host.test.ps1','tests/flutter-windows-icon.test.ps1')){
        $path=Join-Path $source $relative
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
        Set-Content -LiteralPath $path 'fixture; never executed'
    }
    Copy-Item -LiteralPath (Join-Path $root $helperRelative) -Destination (Join-Path $source $helperRelative)
    foreach($relative in @('src/desktop/bridge','components/RuntimeBundle','components/OneTimeTasks',
        'components/GitRepository','components/JobOutcomes','components/SettingsStore','components/SharedCodexSession')){
        [void](New-Item -ItemType Directory -Path (Join-Path $source $relative) -Force)
    }
    $builder=Join-Path $source 'src/desktop/Build-WindowsPreview.ps1'
    @'
param([string]$OutputDirectory)
$destination=Join-Path $OutputDirectory 'fixture-built-preview'
[void](New-Item -ItemType Directory -Path $destination -Force)
foreach($entry in @(Get-ChildItem -LiteralPath $env:CONTINUUM_TEST_BUILT_TEMPLATE -Force)){
    Copy-Item -LiteralPath $entry.FullName -Destination $destination -Recurse
}
# Intentionally no native process and no LASTEXITCODE assignment.
'@ | Set-Content -LiteralPath $builder -Encoding utf8
    $env:CONTINUUM_TEST_BUILT_TEMPLATE=$package
    Check 'source ZIP builds and launches its full package despite stale native exit status' {
        $global:LASTEXITCODE=91
        Invoke-InterceptedLauncher (Join-Path $source 'Run-Continuum.ps1')
        $actual=[IO.File]::ReadAllText($capture)
        Require ($actual.StartsWith((Join-Path $env:LOCALAPPDATA 'Continuum/SourceBuilds')) -and $actual.EndsWith('\fixture-built-preview\codex_resume_flutter.exe')) 'Source build did not launch its own complete package.'
    }
    Check 'an explicit backend override remains intact and visible in launch provenance' {
        $env:CODEX_SCHEDULER_SOURCE=Join-Path $tempRoot 'operator-backend'
        $messages=@(Invoke-InterceptedLauncher (Join-Path $source 'Run-Continuum.ps1') 6>&1) | Out-String
        Require ($messages.Contains('CODEX_SCHEDULER_SOURCE override') -and $env:CODEX_SCHEDULER_SOURCE -ceq (Join-Path $tempRoot 'operator-backend')) 'Backend override was hidden or replaced.'
    }
    Check 'source prerequisite failure survives the launcher without a fallback download' {
        Set-Content -LiteralPath $builder "param([string]`$OutputDirectory)`nthrow 'Windows denied symbolic links (error 1314). Run: start ms-settings:developers'"
        Require-LaunchFailure (Join-Path $source 'Run-Continuum.ps1') 'start ms-settings:developers'
    }

    Check 'real cmd bootstrap ignores a CWD decoy and preserves the selected child exit code' {
        $bootstrap=Join-Path $tempRoot 'bootstrap with spaces ! [review]'
        [void](New-Item -ItemType Directory -Path $bootstrap)
        Copy-Item -LiteralPath $batch -Destination $bootstrap
        Set-Content -LiteralPath (Join-Path $bootstrap 'pwsh.exe') 'CWD decoy, never execute'
        @'
[IO.File]::WriteAllText($env:CONTINUUM_TEST_LAUNCH_CAPTURE,(Join-Path $PSHOME 'pwsh.exe'))
exit 23
'@ | Set-Content -LiteralPath (Join-Path $bootstrap 'Run-Continuum.ps1') -Encoding utf8
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=Join-Path $env:SystemRoot 'System32/cmd.exe'
        $start.UseShellExecute=$false;$start.WorkingDirectory=$bootstrap
        $start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true;$start.RedirectStandardInput=$true
        $start.Environment['PATH']=$PSHOME
        foreach($argument in @('/d','/v:on','/c','Run-Continuum.cmd')){$start.ArgumentList.Add($argument)}
        $child=[Diagnostics.Process]::Start($start)
        try{
            $stdout=$child.StandardOutput.ReadToEndAsync();$stderr=$child.StandardError.ReadToEndAsync()
            $child.StandardInput.WriteLine('');$child.StandardInput.Close()
            if(-not $child.WaitForExit(20000)){$child.Kill($true);throw 'Native CMD bootstrap did not finish.'}
            $output=$stdout.GetAwaiter().GetResult()+$stderr.GetAwaiter().GetResult()
            Require ($child.ExitCode -eq 23) "Native CMD did not preserve child exit 23: $($child.ExitCode); $output"
            Require ([IO.File]::ReadAllText($capture) -ieq (Join-Path $PSHOME 'pwsh.exe')) 'Native CMD selected the decoy or another host.'
        }finally{$child.Dispose()}
    }
    Write-Host "Native launcher: $passed passed; $skipped skipped. No compiled application or source build was run."
}finally{
    $env:LOCALAPPDATA=$originalLocalAppData
    $env:CODEX_SCHEDULER_SOURCE=$originalBackendOverride
    $env:CONTINUUM_TEST_BUILT_TEMPLATE=$originalBuildTemplate
    $env:CONTINUUM_TEST_LAUNCH_CAPTURE=$originalCapture
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
