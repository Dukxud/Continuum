# Use the genuine pinned SDK to generate Windows runner sources. This does not
# compile or run Windows code and must not be reported as native acceptance.
[CmdletBinding()]
param([string]$FlutterExecutable=$env:CONTINUUM_TEST_FLUTTER)
$ErrorActionPreference='Stop'
if(-not $FlutterExecutable){
    $command=Get-Command flutter.bat -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if($command){$FlutterExecutable=$command.Source}
}
if(-not $FlutterExecutable){throw 'Set CONTINUUM_TEST_FLUTTER to the genuine Flutter 3.47.9 executable for this integration test.'}
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'src/desktop'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-runner-'+[guid]::NewGuid().ToString('N'))
$project=Join-Path $fixture 'candidate [é]/src/desktop'
[void](New-Item -ItemType Directory -Path (Join-Path $project 'scripts') -Force)
try{
    foreach($file in @('Invoke-PreviewBuild.ps1','Test-WindowsBuildPrerequisites.ps1','Initialize-WindowsRunner.ps1','Install-WindowsIcon.ps1')){
        Copy-Item -LiteralPath (Join-Path $source "scripts/$file") -Destination (Join-Path $project 'scripts')
    }
    foreach($file in @('pubspec.yaml','pubspec.lock')){Copy-Item -LiteralPath (Join-Path $source $file) -Destination $project}
    [void](New-Item -ItemType Directory -Path (Join-Path $project 'branding'))
    Copy-Item -LiteralPath (Join-Path $source 'branding/continuum.ico') -Destination (Join-Path $project 'branding')
    [void](New-Item -ItemType Directory -Path (Join-Path $project 'lib'))
    $main=Join-Path $project 'lib/main.dart'
    [IO.File]::WriteAllText($main,'// reviewed application source; do not overwrite')
    $lock=Join-Path $project 'pubspec.lock'
    $before=[IO.File]::ReadAllBytes($lock)
    $runner=Join-Path $project 'scripts/Initialize-WindowsRunner.ps1'
    & $runner -FlutterExecutable $FlutterExecutable
    if([Convert]::ToBase64String([IO.File]::ReadAllBytes($lock)) -cne [Convert]::ToBase64String($before)){
        throw 'Genuine Flutter generation changed the application lock.'
    }
    if([IO.File]::ReadAllText($main) -cne '// reviewed application source; do not overwrite'){
        throw 'Genuine Flutter generation replaced application source.'
    }
    foreach($path in @('windows/CMakeLists.txt','windows/runner/main.cpp','windows/runner/resources/app_icon.ico')){
        if(-not (Test-Path -LiteralPath (Join-Path $project $path) -PathType Leaf)){throw "Runner output missing: $path"}
    }
    & (Join-Path $project 'scripts/Install-WindowsIcon.ps1') -VerifyOnly
    Write-Host 'PASS genuine Flutter runner generation preserves lock and application source, and installs the pinned icon'

    $guard=Join-Path $project '.dart_tool/continuum-runner.lock'
    $held=[IO.File]::Open($guard,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try{
        $blocked=''
        try{& $runner -FlutterExecutable $FlutterExecutable}catch{$blocked=$_.Exception.Message}
        if(-not $blocked.Contains('runner-generation lock')){throw 'Concurrent runner generation was not rejected before snapshotting the application lock.'}
        if([Convert]::ToBase64String([IO.File]::ReadAllBytes($lock)) -cne [Convert]::ToBase64String($before)){
            throw 'A blocked second generator changed the application lock.'
        }
    }finally{$held.Dispose()}
    Write-Host 'PASS concurrent runner generation cannot snapshot or overwrite another invocation''s lock'

    # The real process boundary must also restore the exact lock after a tool
    # rewrites it and fails. Only the Flutter response is an explicit fixture.
    . (Join-Path $project 'scripts/Invoke-PreviewBuild.ps1')
    . (Join-Path $project 'scripts/Test-WindowsBuildPrerequisites.ps1')
    $actualVersion=Invoke-ContinuumBuildProcess -FilePath $FlutterExecutable -ArgumentList @('--suppress-analytics','--version','--machine') -WorkingDirectory $project
    $metadata=ConvertFrom-ContinuumPrerequisiteJson -Text $actualVersion.Stdout -Description 'Pinned SDK' -RootKind Object -RequiredProperty frameworkVersion
    $metadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $fixture 'version.json') -Encoding utf8NoBOM
    $fake=Join-Path $fixture 'fake-flutter.js'
    @'
#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
if (process.argv.includes('--version')) {
  process.stdout.write(fs.readFileSync(path.join(__dirname, 'version.json'), 'utf8'));
} else if (process.argv.includes('create')) {
  fs.writeFileSync('pubspec.lock', 'partial generated lock');
  process.stderr.write('injected runner failure after writing the lock\n');
  process.exitCode = 23;
} else process.exitCode = 24;
'@ | Set-Content -LiteralPath $fake -Encoding utf8NoBOM
    if($IsWindows){
        $fakeExecutable=Join-Path $fixture 'flutter.cmd'
        $node=(Get-Command node.exe -CommandType Application -ErrorAction Stop).Source
        ('@echo off'+"`r`n"+'"'+$node+'" "'+$fake+'" %*'+"`r`n"+'exit /b %errorlevel%') |
            Set-Content -LiteralPath $fakeExecutable -Encoding ascii
    }else{
        $fakeExecutable=$fake
        & chmod +x $fakeExecutable
        if($LASTEXITCODE -ne 0){throw 'Cannot prepare the explicit fake tool executable.'}
    }
    $failure=''
    try{& $runner -FlutterExecutable $fakeExecutable}catch{$failure=$_.Exception.Message}
    if(-not $failure.Contains('23')){throw 'Runner tool failure did not preserve its exit code.'}
    if([Convert]::ToBase64String([IO.File]::ReadAllBytes($lock)) -cne [Convert]::ToBase64String($before)){
        throw 'Failed runner generation left a rewritten dependency lock.'
    }
    Write-Host 'PASS a real failed generator process restores the exact original lock'
}finally{Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
