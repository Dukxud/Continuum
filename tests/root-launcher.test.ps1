# Native Windows launch routing with fixture builders and intercepted launches.
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This test requires Windows.' }

$root = Split-Path -Parent $PSScriptRoot
$launcher = Join-Path $root 'Run-Continuum.ps1'
$batch = Join-Path $root 'Run-Continuum.cmd'
if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Missing root PowerShell launcher.' }
if (-not (Test-Path -LiteralPath $batch -PathType Leaf)) { throw 'Missing double-click root launcher.' }
if ((Get-Content -LiteralPath $batch -Raw) -notmatch 'Run-Continuum\.ps1') {
    throw 'Double-click entry point does not call the PowerShell launcher.'
}

$originalLocalAppData = $env:LOCALAPPDATA
$originalBackendOverride = $env:CODEX_SCHEDULER_SOURCE
$tempRoot = Join-Path $env:TEMP ('continuum-launcher-test-' + [guid]::NewGuid().ToString('N'))
$script:launches = [System.Collections.Generic.List[string]]::new()
try {
    $env:LOCALAPPDATA = Join-Path $tempRoot 'profile'
    # Cache/download cases deliberately use a launcher-only folder. Running
    # the repository's own launcher now builds its actual source by default.
    $launcherOnly=Join-Path $tempRoot 'launcher-only'
    [void](New-Item -ItemType Directory -Path $launcherOnly -Force)
    Copy-Item -LiteralPath $launcher,$batch -Destination $launcherOnly
    $standaloneLauncher=Join-Path $launcherOnly 'Run-Continuum.ps1'
    $package = 'Continuum-Windows-v0.1.0+1-UNSIGNED-PREVIEW'
    $exe = Join-Path $env:LOCALAPPDATA ('Continuum\Previews\v0.1.0-preview.1\' + $package + '\codex_resume_flutter.exe')
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $exe) -Force)
    Set-Content -LiteralPath $exe -Value 'test fixture, never executed'

    & {
        function Invoke-WebRequest { throw 'Cached launch unexpectedly used the network.' }
        function Start-Process {
            param([string]$FilePath,[string]$WorkingDirectory)
            $script:launches.Add($FilePath)
        }
        . $standaloneLauncher
    }
    if ($script:launches.Count -ne 1 -or $script:launches[0] -cne $exe) {
        throw 'Cached launcher did not open the expected executable.'
    }

    Remove-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'Continuum\Previews\v0.1.0-preview.1') -Recurse -Force
    $script:launches.Clear()
    & {
        function Invoke-WebRequest {
            param([string]$Uri,[string]$OutFile)
            [IO.File]::WriteAllText($OutFile, 'tampered download')
        }
        function Expand-Archive { throw 'A mismatched download must never be extracted.' }
        function Start-Process { throw 'A mismatched download must never be launched.' }
        $rejected = $false
        try { . $standaloneLauncher }
        catch {
            if ($_.Exception.Message -notmatch 'SHA-256 does not match') { throw }
            $rejected = $true
        }
        if (-not $rejected) { throw 'Mismatched preview ZIP was accepted.' }
    }
    if ($script:launches.Count -ne 0) { throw 'Hash mismatch caused a launch.' }
    # A CI preview includes this same launcher, and must run the packaged
    # candidate rather than the pinned, older public release or cache.
    $local = Join-Path $tempRoot 'pr-preview'
    $localExe = Join-Path $local 'codex_resume_flutter.exe'
    $localBridge = Join-Path $local 'src\desktop\windows_bridge.ps1'
    $localWorker = Join-Path $local 'src\backend\Invoke-CodexJob.ps1'
    [void](New-Item -ItemType Directory -Path (Join-Path $local 'data'),(Split-Path -Parent $localBridge),(Split-Path -Parent $localWorker) -Force)
    Copy-Item -LiteralPath $launcher,$batch -Destination $local -ErrorAction Stop
    Set-Content -LiteralPath $localExe -Value 'CI preview fixture binary'
    Set-Content -LiteralPath (Join-Path $local 'flutter_windows.dll') -Value 'CI preview fixture DLL'
    Set-Content -LiteralPath $localBridge -Value 'CI preview fixture bridge'
    Set-Content -LiteralPath $localWorker -Value 'CI preview fixture worker'
    $manifest = @(
        Get-ChildItem -LiteralPath $local -Recurse -File |
            Sort-Object FullName |
            ForEach-Object {
                $relative = [IO.Path]::GetRelativePath($local,$_.FullName).Replace('\','/')
                "$((Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash)  $relative"
            }
    )
    $manifest | Set-Content -LiteralPath (Join-Path $local 'SHA256SUMS.txt') -Encoding utf8

    # Capture the subprocess target on disk; script-scoped mocks can resolve
    # different $script: variables when the launcher lives in another folder.
    $capture = Join-Path $tempRoot 'launched-executable.txt'
    $env:CONTINUUM_TEST_LAUNCH_CAPTURE = $capture
    try {
        & {
            function Invoke-WebRequest { throw 'Packaged preview unexpectedly downloaded a release.' }
            function Start-Process {
                param([string]$FilePath,[string]$WorkingDirectory)
                [IO.File]::WriteAllText($env:CONTINUUM_TEST_LAUNCH_CAPTURE,$FilePath)
            }
            . (Join-Path $local 'Run-Continuum.ps1')
        }
        $actual=if(Test-Path -LiteralPath $capture){[IO.File]::ReadAllText($capture)}else{''}
        if(-not $actual -or [IO.Path]::GetFullPath($actual) -ine [IO.Path]::GetFullPath($localExe)){
            throw "Packaged launch chose '$actual', expected '$localExe'."
        }

        # Earlier PR artifacts omit the later-added launcher from their
        # manifest. Adding the sidecar must not redirect them to old releases.
        $withoutSidecars=@($manifest | Where-Object {
            $_ -notmatch '  Run-Continuum[.](?:cmd|ps1)$'
        })
        $withoutSidecars | Set-Content -LiteralPath (Join-Path $local 'SHA256SUMS.txt') -Encoding utf8
        Remove-Item -LiteralPath $capture
        & {
            function Invoke-WebRequest { throw 'Legacy review sidecar unexpectedly downloaded a release.' }
            function Start-Process {
                param([string]$FilePath,[string]$WorkingDirectory)
                [IO.File]::WriteAllText($env:CONTINUUM_TEST_LAUNCH_CAPTURE,$FilePath)
            }
            . (Join-Path $local 'Run-Continuum.ps1')
        }
        $actual=if(Test-Path -LiteralPath $capture){[IO.File]::ReadAllText($capture)}else{''}
        if(-not $actual -or [IO.Path]::GetFullPath($actual) -ine [IO.Path]::GetFullPath($localExe)){
            throw "Legacy review artifact with launcher sidecar chose '$actual', expected '$localExe'."
        }
    } finally {
        Remove-Item Env:CONTINUUM_TEST_LAUNCH_CAPTURE -ErrorAction SilentlyContinue
    }

    Set-Content -LiteralPath $localBridge -Value 'TAMPERED'
    $script:launches.Clear()
    & {
        function Start-Process { throw 'A tampered packaged preview must never launch.' }
        $rejected = $false
        try { . (Join-Path $local 'Run-Continuum.ps1') }
        catch {
            if($_.Exception.Message -notmatch 'Local preview checksum failed'){throw}
            $rejected = $true
        }
        if(-not $rejected){throw 'A tampered local preview was accepted.'}
    }
    if($script:launches.Count -ne 0){throw 'Tampered packaged preview caused a launch.'}

    # A complete source ZIP uses the build entrypoint without requiring .git.
    # This fixture builder writes an inert EXE; no Flutter command runs here.
    $sourceFolder=Join-Path $tempRoot 'source-archive'
    [void](New-Item -ItemType Directory -Path $sourceFolder -Force)
    Copy-Item -LiteralPath $launcher,$batch -Destination $sourceFolder
    foreach($relative in @('src/desktop/pubspec.yaml','src/desktop/pubspec.lock',
        'src/desktop/lib/main.dart','src/desktop/windows_bridge.ps1',
        'src/backend/CodexRunEngine.ps1','src/desktop/scripts/Get-PreviewMetadata.ps1',
        'src/desktop/scripts/Initialize-WindowsRunner.ps1','src/desktop/scripts/Install-WindowsIcon.ps1',
        'tests/flutter-port-source.test.ps1','tests/flutter-port-bridge.test.ps1')){
        $file=Join-Path $sourceFolder $relative
        [void](New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force)
        [IO.File]::WriteAllText($file,'fixture file; never executed')
    }
    foreach($relative in @('src/desktop/bridge','components/RuntimeBundle','components/OneTimeTasks',
        'components/GitRepository','components/JobOutcomes','components/SettingsStore','components/SharedCodexSession')){
        [void](New-Item -ItemType Directory -Path (Join-Path $sourceFolder $relative) -Force)
    }
    @'
param([string]$OutputDirectory)
$package=Join-Path $OutputDirectory 'isolated-built-preview'
[void](New-Item -ItemType Directory -Path $package -Force)
[IO.File]::WriteAllText((Join-Path $package 'codex_resume_flutter.exe'),'fixture executable; never executed')
@{version='0.0.0-test';sourceCommit=$null;sourceModified=$null;sourceArchive=$true} |
    ConvertTo-Json | Set-Content -LiteralPath (Join-Path $package 'build-info.json') -Encoding utf8
[IO.File]::WriteAllText($env:CONTINUUM_TEST_BUILD_CAPTURE,$OutputDirectory)
$global:LASTEXITCODE=0
'@ | Set-Content -LiteralPath (Join-Path $sourceFolder 'src/desktop/Build-WindowsPreview.ps1') -Encoding utf8
    $sourceLauncher=Join-Path $sourceFolder 'Run-Continuum.ps1'
    $env:CONTINUUM_TEST_BUILD_CAPTURE=Join-Path $tempRoot 'source-build-output.txt'
    $env:CONTINUUM_TEST_LAUNCH_CAPTURE=$capture
    try{
        foreach($scenario in @('archive-default','archive-with-old-exe','explicit-archive')){
            if($scenario -eq 'archive-with-old-exe'){
                [IO.File]::WriteAllText((Join-Path $sourceFolder 'codex_resume_flutter.exe'),'old sibling executable')
            }
            Remove-Item -LiteralPath $capture,$env:CONTINUUM_TEST_BUILD_CAPTURE -ErrorAction SilentlyContinue
            & {
                function flutter.bat { throw 'Fixture launcher must call its builder, not Flutter directly.' }
                function git.exe { throw 'Fixture launcher unexpectedly invoked Git.' }
                function node.exe { throw 'Fixture launcher unexpectedly invoked Node.' }
                function Invoke-WebRequest { throw 'A source build must never download the pinned release.' }
                function Start-Process {
                    param([string]$FilePath,[string]$WorkingDirectory)
                    [IO.File]::WriteAllText($env:CONTINUUM_TEST_LAUNCH_CAPTURE,$FilePath)
                }
                if($scenario -eq 'explicit-archive'){. $sourceLauncher -BuildFromSource}
                else{. $sourceLauncher}
            }
            if(-not (Test-Path -LiteralPath $env:CONTINUUM_TEST_BUILD_CAPTURE)){throw "Source builder was not used: $scenario"}
            $builtAt=[IO.File]::ReadAllText($env:CONTINUUM_TEST_BUILD_CAPTURE)
            $builtExe=Join-Path $builtAt 'isolated-built-preview/codex_resume_flutter.exe'
            if([IO.File]::ReadAllText($capture) -cne $builtExe){throw "Source launcher selected a stale executable: $scenario"}
        }

        # The explicit override remains effective and is visible in provenance.
        $env:CODEX_SCHEDULER_SOURCE=Join-Path $tempRoot 'operator-backend'
        $messages=@(& {
            function flutter.bat {}
            function git.exe {}
            function node.exe {}
            function Start-Process {
                param([string]$FilePath,[string]$WorkingDirectory)
                [IO.File]::WriteAllText($env:CONTINUUM_TEST_LAUNCH_CAPTURE,$FilePath)
            }
            . $sourceLauncher
        } 6>&1)
        if(($messages | Out-String) -notmatch 'CODEX_SCHEDULER_SOURCE override' -or
            $env:CODEX_SCHEDULER_SOURCE -cne (Join-Path $tempRoot 'operator-backend')){
            throw 'Backend override was not retained and reported.'
        }

        & {
            function Get-Command { param([string]$Name,[string]$ErrorAction) return $null }
            function Start-Process { throw 'A source build without prerequisites must not launch.' }
            function Invoke-WebRequest { throw 'Missing build prerequisites must not trigger a pinned download.' }
            $rejected=$false
            try{. $sourceLauncher}catch{$rejected=$_.Exception.Message -match 'Missing from PATH:'}
            if(-not $rejected){throw 'Missing source-build prerequisites were not reported.'}
        }
    }finally{
        Remove-Item Env:CONTINUUM_TEST_BUILD_CAPTURE,Env:CONTINUUM_TEST_LAUNCH_CAPTURE -ErrorAction SilentlyContinue
    }
    Write-Host 'PASS — source archive routing, prerequisites, backend provenance, cached/local package launch and tamper rejection.'
}
finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $env:CODEX_SCHEDULER_SOURCE = $originalBackendOverride
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
