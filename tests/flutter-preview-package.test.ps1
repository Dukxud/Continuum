# Actual ZIP round trips and a child bridge from the extracted payload.
# Native binaries are inert fixtures; this does not claim a Windows app launch.
[CmdletBinding()]
param([string]$PinnedPreviewDirectory='')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/desktop/scripts/Assert-PreviewPackage.ps1')
# Import the platform-independent archive writer from the real builder. The
# Windows build guard is left intact and is not evaluated by this test.
$tokens=$null;$parseErrors=$null
$builder=[Management.Automation.Language.Parser]::ParseFile(
    (Join-Path $root 'src/desktop/Build-WindowsPreview.ps1'),[ref]$tokens,[ref]$parseErrors)
if(@($parseErrors).Count){throw $parseErrors[0].Message}
$archiveWriter=$builder.Find({param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'New-ContinuumPackageArchive'
},$false)
if(-not $archiveWriter){throw 'Production archive writer was not found.'}
. ([scriptblock]::Create($archiveWriter.Extent.Text))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-preview-package-'+[guid]::NewGuid().ToString('N'))
$passed=0
$failures=[Collections.Generic.List[string]]::new()
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Run-Case([string]$Name,[scriptblock]$Body){
    try{& $Body;$script:passed++;Write-Host "PASS $Name"}
    catch{$script:failures.Add($Name+': '+$_.Exception.Message);Write-Host "FAIL $Name — $($_.Exception.Message)"}
}
function Write-Manifest([string]$Directory){
    $lines=@(Get-ChildItem -LiteralPath $Directory -File -Recurse -Force |
        Where-Object {$_.Name -ne 'SHA256SUMS.txt'} | Sort-Object FullName | ForEach-Object {
            $relative=[IO.Path]::GetRelativePath($Directory,$_.FullName).Replace('\','/')
            "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)  $relative"
        })
    $lines | Set-Content -LiteralPath (Join-Path $Directory 'SHA256SUMS.txt') -Encoding utf8
}
function New-PackageFixture([string]$Name){
    $directory=Join-Path $fixture $Name
    foreach($relative in @(Get-ContinuumPreviewRequiredFiles)){
        $path=Join-Path $directory $relative
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force)
        $source=Join-Path $root $relative
        if(Test-Path -LiteralPath $source -PathType Leaf){Copy-Item -LiteralPath $source -Destination $path}
        else{[IO.File]::WriteAllText($path,'inert package fixture; never execute as a native program')}
    }
    @{application='Continuum';version='0.1.0+1';sourceCommit=$null;sourceModified=$null;sourceArchive=$true} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $directory 'build-info.json') -Encoding utf8
    Write-Manifest $directory
    return $directory
}
function Require-Rejection([string]$Directory,[string]$Pattern){
    $message=''
    try{Assert-ContinuumPreviewPackage -Directory $Directory | Out-Null}catch{$message=$_.Exception.Message}
    Require ($message -match $Pattern) "Expected '$Pattern', received '$message'."
}
try{
    [void](New-Item -ItemType Directory -Path $fixture)
    $complete=New-PackageFixture 'complete payload with spaces'
    Run-Case 'complete package verifies one-to-one coverage and executable location' {
        $verified=Assert-ContinuumPreviewPackage -Directory $complete
        Require ($verified.FileCount -gt 40 -and $verified.VerifiedPaths.Count -eq $verified.FileCount) 'Incomplete verification result.'
        Require ($verified.Executable -ceq (Join-Path $complete 'codex_resume_flutter.exe')) 'Executable is not from the verified directory.'
    }
    Run-Case 'actual extracted ZIP satisfies the same runtime contract' {
        $archive=Join-Path $fixture 'preview.zip'
        [void](New-ContinuumPackageArchive -SourceDirectory $complete -DestinationPath $archive)
        $extract=Join-Path $fixture 'extracted'
        Expand-Archive -LiteralPath $archive -DestinationPath $extract
        $script:extracted=Join-Path $extract (Split-Path -Leaf $complete)
        $verified=Assert-ContinuumPreviewPackage -Directory $script:extracted
        Require ($verified.FileCount -eq (Assert-ContinuumPreviewPackage $complete).FileCount) 'Compression changed the file inventory.'
    }
    Run-Case 'extracted package imports its actual complete backend and saves preferences' {
        Require ([bool]$script:extracted) 'Archive fixture was not extracted.'
        $start=[Diagnostics.ProcessStartInfo]::new()
        $start.FileName=(Get-Process -Id $PID).Path
        $start.UseShellExecute=$false
        $start.RedirectStandardOutput=$true
        $start.RedirectStandardError=$true
        $start.WorkingDirectory=$script:extracted
        $start.Environment['LOCALAPPDATA']=Join-Path $fixture 'isolated-appdata'
        $start.Environment['CODEX_HOME']=Join-Path $fixture 'isolated-codex'
        $payload=@{draft=@{access='read-only';message='fixture preference';repo='';sessionId=''}} | ConvertTo-Json -Compress
        $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
        foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive','-File',
            (Join-Path $script:extracted 'src/desktop/windows_bridge.ps1'),'-Action','save','-Payload',$encoded)){
            $start.ArgumentList.Add($argument)
        }
        $process=[Diagnostics.Process]::Start($start)
        try{
            $stdout=$process.StandardOutput.ReadToEndAsync()
            $stderr=$process.StandardError.ReadToEndAsync()
            if(-not $process.WaitForExit(15000)){$process.Kill($true);throw 'Extracted bridge did not complete within 15 seconds.'}
            $response=($stdout.GetAwaiter().GetResult().Trim() -split '\r?\n' | Select-Object -Last 1) | ConvertFrom-Json
            $diagnostic=$stderr.GetAwaiter().GetResult()
            Require ($process.ExitCode -eq 0 -and $response.ok -eq $true -and $response.result.saved -eq $true) "Extracted bridge did not save: $diagnostic"
            Require (Test-Path -LiteralPath (Join-Path $fixture 'isolated-appdata/CodexResumeScheduler/settings.json')) 'Extracted backend wrote no isolated preferences.'
        }finally{$process.Dispose()}
    }
    foreach($relative in @('data/app.so','data/icudtl.dat','window_manager_plugin.dll',
        'screen_retriever_windows_plugin.dll','src/backend/CodexCli.ps1',
        'src/backend/CodexRepositoryEvidence.ps1','src/desktop/bridge/ReadModels.ps1',
        'components/SettingsStore/SettingsStore.psm1','components/SharedCodexSession/host.mjs')){
        Run-Case "rehashed incomplete package is rejected: $relative" {
            $broken=New-PackageFixture ('missing-'+[guid]::NewGuid().ToString('N'))
            Remove-Item -LiteralPath (Join-Path $broken $relative)
            Write-Manifest $broken
            Require-Rejection $broken 'required file missing from manifest'
        }
    }
    Run-Case 'an empty data directory is not a Flutter release payload' {
        $broken=New-PackageFixture 'empty-data'
        Remove-Item -LiteralPath (Join-Path $broken 'data') -Recurse -Force
        [void](New-Item -ItemType Directory -Path (Join-Path $broken 'data'))
        Write-Manifest $broken
        Require-Rejection $broken 'required file missing from manifest: data/app.so'
    }
    Run-Case 'zero-byte required runtime is rejected even with a matching checksum' {
        $broken=New-PackageFixture 'empty-aot'
        [IO.File]::WriteAllBytes((Join-Path $broken 'data/app.so'),[byte[]]@())
        Write-Manifest $broken
        Require-Rejection $broken 'required file is empty: data/app.so'
    }
    Run-Case 'duplicate entry cannot hide an omitted file with an equal manifest count' {
        $broken=New-PackageFixture 'equal-count'
        $manifest=Join-Path $broken 'SHA256SUMS.txt'
        $lines=[IO.File]::ReadAllLines($manifest)
        $lines[1]=$lines[0]
        [IO.File]::WriteAllLines($manifest,$lines)
        Require-Rejection $broken 'duplicated preview checksum path'
    }
    Run-Case 'an unmanifested dependency is rejected' {
        $broken=New-PackageFixture 'extra-module'
        [IO.File]::WriteAllText((Join-Path $broken 'src/backend/untracked-module.ps1'),'extra')
        Require-Rejection $broken 'not covered by its checksum manifest'
    }
    Run-Case 'corruption after extraction is rejected' {
        $broken=New-PackageFixture 'corrupt'
        [IO.File]::WriteAllText((Join-Path $broken 'src/desktop/bridge/ReadModels.ps1'),'truncated')
        Require-Rejection $broken 'checksum failed: src/desktop/bridge/ReadModels.ps1'
    }
    Run-Case 'a missing checksum manifest is rejected' {
        $broken=New-PackageFixture 'missing-manifest'
        Remove-Item -LiteralPath (Join-Path $broken 'SHA256SUMS.txt')
        Require-Rejection $broken 'checksum manifest missing'
    }
    foreach($path in @('../outside','data/../outside','data//app.so','data/./app.so','C:/outside','data\app.so')){
        Run-Case "noncanonical manifest path is rejected: $path" {
            $broken=New-PackageFixture ('path-'+[guid]::NewGuid().ToString('N'))
            Add-Content -LiteralPath (Join-Path $broken 'SHA256SUMS.txt') -Value (('0'*64)+'  '+$path)
            Require-Rejection $broken 'Unsafe or duplicated'
        }
    }
    Run-Case 'invalid build provenance is rejected after checksum verification' {
        $broken=New-PackageFixture 'invalid-identity'
        [IO.File]::WriteAllText((Join-Path $broken 'build-info.json'),'[]')
        Write-Manifest $broken
        Require-Rejection $broken 'build identity is missing or invalid'
    }
    Run-Case 'legacy profile cannot weaken verification for another build' {
        $message=''
        try{Assert-ContinuumPreviewPackage $complete -Profile PinnedPreview1 | Out-Null}catch{$message=$_.Exception.Message}
        Require ($message -match 'differs from the published release') 'A current or arbitrary package used the legacy dependency contract.'
    }
    if($PinnedPreviewDirectory){
        Run-Case 'the actual digest-verified public Preview 1 artifact validates without new dependencies' {
            $verified=Assert-ContinuumPreviewPackage -Directory $PinnedPreviewDirectory -Profile PinnedPreview1
            Require ($verified.FileCount -eq 53) 'Published Preview 1 inventory differs from its verified manifest.'
        }
    }else{Write-Host 'SKIP actual public Preview 1 artifact: supply -PinnedPreviewDirectory to its independently ZIP-hash-verified extraction.'}
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
Write-Host "Preview package: $passed passed; $($failures.Count) failed. Native Windows execution was not exercised."
if($failures.Count){foreach($failure in $failures){Write-Host $failure};exit 1}
