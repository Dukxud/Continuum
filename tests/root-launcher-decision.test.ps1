# Exercise the production folder decision on every platform. This imports only
# function definitions; the real Windows launch guard is neither changed nor run.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$launcher=Join-Path $root 'Run-Continuum.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($launcher,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw $errors[0].Message}
foreach($name in @('Get-ContinuumLaunchPlan','Get-ContinuumBuildScripts','Start-Continuum')){
    $definition=$ast.Find({param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
    },$false)
    if(-not $definition){throw "Production launcher function is missing: $name"}
    . ([scriptblock]::Create($definition.Extent.Text))
}

$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-launch-decision-'+[guid]::NewGuid().ToString('N'))
$failures=[Collections.Generic.List[string]]::new()
$passed=0
$skipped=0
$originalBackendOverride=$env:CODEX_SCHEDULER_SOURCE
function Start-Process {
    param([string]$FilePath,[string]$WorkingDirectory)
    $script:launchedPath=$FilePath
    $script:launchedDirectory=$WorkingDirectory
}
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Run-Case([string]$Name,[scriptblock]$Body){
    try{& $Body;$script:passed++;Write-Host "PASS $Name"}
    catch{$script:failures.Add($Name+': '+$_.Exception.Message);Write-Host "FAIL $Name — $($_.Exception.Message)"}
}
function New-FixtureFile([string]$Directory,[string]$Relative){
    $file=Join-Path $Directory $Relative
    [void](New-Item -ItemType Directory -Path (Split-Path -Parent $file) -Force)
    [IO.File]::WriteAllText($file,'isolated fixture; never executed')
}
function New-SourceFixture([string]$Name){
    $directory=Join-Path $fixture $Name
    foreach($relative in @(
        'src/desktop/Build-WindowsPreview.ps1','src/desktop/pubspec.yaml',
        'src/desktop/pubspec.lock','src/desktop/lib/main.dart',
        'src/desktop/scripts/Get-PreviewMetadata.ps1',
        'src/desktop/scripts/Initialize-WindowsRunner.ps1',
        'src/desktop/scripts/Install-WindowsIcon.ps1',
        'src/desktop/windows_bridge.ps1','src/backend/CodexRunEngine.ps1',
        'tests/flutter-port-source.test.ps1','tests/flutter-port-bridge.test.ps1'
    )){New-FixtureFile $directory $relative}
    return $directory
}
try{
    [void](New-Item -ItemType Directory -Path $fixture)
    $source=New-SourceFixture 'source-archive'
    Run-Case 'source ZIP defaults to building its own source' {
        Require ((Get-ContinuumLaunchPlan $source).Mode -eq 'Source') 'Source archive fell through to the pinned preview.'
    }
    Run-Case 'explicit source build accepts an archive without Git metadata' {
        Require ((Get-ContinuumLaunchPlan $source -BuildFromSource).Mode -eq 'Source') 'Explicit source archive build was not selected.'
    }
    Run-Case 'complete source wins over a stray older sibling executable' {
        New-FixtureFile $source 'codex_resume_flutter.exe'
        Require ((Get-ContinuumLaunchPlan $source).Mode -eq 'Source') 'A sibling executable hid the source tree.'
    }
    Run-Case 'a Git worktree file does not disqualify a source build' {
        New-FixtureFile $source '.git'
        Require ((Get-ContinuumLaunchPlan $source -BuildFromSource).Mode -eq 'Source') 'A worktree source folder was rejected.'
    }
    Run-Case 'runtime-only package selects its sibling executable' {
        $package=Join-Path $fixture 'runtime-package'
        New-FixtureFile $package 'codex_resume_flutter.exe'
        New-FixtureFile $package 'src/desktop/windows_bridge.ps1'
        New-FixtureFile $package 'src/backend/CodexRunEngine.ps1'
        $plan=Get-ContinuumLaunchPlan $package
        Require ($plan.Mode -eq 'Package' -and $plan.Executable -eq (Join-Path $package 'codex_resume_flutter.exe')) 'Runtime package did not select its own executable.'
    }
    Run-Case 'incomplete source cannot silently use the pinned preview' {
        $partial=Join-Path $fixture 'partial-source'
        New-FixtureFile $partial 'src/desktop/pubspec.yaml'
        $rejected=$false
        try{Get-ContinuumLaunchPlan $partial | Out-Null}catch{$rejected=$_.Exception.Message -match 'Incomplete source'}
        Require $rejected 'Incomplete source was accepted as a launcher-only download.'
    }
    Run-Case 'runtime files without an executable cannot use the pinned preview' {
        $partial=Join-Path $fixture 'partial-runtime'
        New-FixtureFile $partial 'src/desktop/windows_bridge.ps1'
        $rejected=$false
        try{Get-ContinuumLaunchPlan $partial | Out-Null}catch{$rejected=$_.Exception.Message -match 'Incomplete application package'}
        Require $rejected 'Incomplete runtime was accepted as a launcher-only download.'
    }
    Run-Case 'launcher-only distribution retains the explicitly pinned release' {
        $only=Join-Path $fixture 'launcher-only'
        New-FixtureFile $only 'Run-Continuum.ps1'
        Require ((Get-ContinuumLaunchPlan $only).Mode -eq 'PinnedRelease') 'Launcher-only release selection changed.'
    }
    $trusted=New-SourceFixture 'source-trust'
    New-FixtureFile $trusted 'Run-Continuum.cmd'
    New-FixtureFile $trusted 'Run-Continuum.ps1'
    foreach($relative in @('src/desktop/bridge','components/RuntimeBundle','components/OneTimeTasks',
        'components/GitRepository','components/JobOutcomes','components/SettingsStore','components/SharedCodexSession')){
        [void](New-Item -ItemType Directory -Path (Join-Path $trusted $relative) -Force)
    }
    Run-Case 'source trust allowlist excludes unrelated and nested scripts' {
        New-FixtureFile $trusted 'unrelated.ps1'
        New-FixtureFile $trusted 'src/backend/external/nested.ps1'
        $scripts=@(Get-ContinuumBuildScripts $trusted)
        Require ($scripts -contains (Join-Path $trusted 'src/backend/CodexRunEngine.ps1')) 'Required backend script was not included.'
        Require (-not ($scripts -contains (Join-Path $trusted 'unrelated.ps1')) -and
            -not ($scripts -contains (Join-Path $trusted 'src/backend/external/nested.ps1'))) 'Source trust escaped its explicit script allowlist.'
    }
    Run-Case 'linked source directory is rejected without following it' {
        $backend=Join-Path $trusted 'src/backend'
        $outside=Join-Path $fixture 'outside-backend'
        Move-Item -LiteralPath $backend -Destination $outside
        $linkType=if($IsWindows){'Junction'}else{'SymbolicLink'}
        [void](New-Item -ItemType $linkType -Path $backend -Target $outside)
        try{
            $rejected=$false
            try{Get-ContinuumBuildScripts $trusted | Out-Null}catch{$rejected=$_.Exception.Message -match 'linked paths'}
            Require $rejected 'A linked source directory was traversed.'
        }finally{
            (Get-Item -LiteralPath $backend -Force).Delete()
            Move-Item -LiteralPath $outside -Destination $backend
        }
    }
    $scriptPath=Join-Path $trusted 'src/backend/CodexRunEngine.ps1'
    $outsideScript=Join-Path $fixture 'outside-script.ps1'
    Move-Item -LiteralPath $scriptPath -Destination $outsideScript
    $linked=$false
    try{
        try{[void](New-Item -ItemType SymbolicLink -Path $scriptPath -Target $outsideScript);$linked=$true}
        catch{
            if(-not $IsWindows){throw}
            Write-Host 'SKIP linked-script fixture: Windows symbolic-link permission unavailable.'
            $skipped++
        }
        if($linked){
            Run-Case 'linked script is rejected before source unblocking' {
                $rejected=$false
                try{Get-ContinuumBuildScripts $trusted | Out-Null}catch{$rejected=$_.Exception.Message -match 'linked scripts'}
                Require $rejected 'A linked backend script entered the trust allowlist.'
            }
        }
    }finally{
        if($linked){(Get-Item -LiteralPath $scriptPath -Force).Delete()}
        Move-Item -LiteralPath $outsideScript -Destination $scriptPath
    }
    Run-Case 'launch provenance reports an explicit backend override without changing it' {
        $env:CODEX_SCHEDULER_SOURCE=Join-Path $fixture 'explicit-backend'
        @{version='test';sourceCommit=$null;sourceModified=$null;sourceArchive=$true} |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $trusted 'build-info.json') -Encoding utf8
        $exe=Join-Path $trusted 'codex_resume_flutter.exe'
        $messages=@(Start-Continuum -Executable $exe 6>&1) | Out-String
        Require ($messages.Contains($env:CODEX_SCHEDULER_SOURCE) -and
            $messages.Contains('CODEX_SCHEDULER_SOURCE override') -and
            $messages.Contains('source archive; commit unavailable')) 'Effective backend or archive provenance was omitted.'
        Require ($env:CODEX_SCHEDULER_SOURCE -ceq (Join-Path $fixture 'explicit-backend') -and
            $script:launchedPath -ceq $exe -and $script:launchedDirectory -ceq $trusted) 'Explicit backend override or launch target was changed.'
    }
}finally{
    $env:CODEX_SCHEDULER_SOURCE=$originalBackendOverride
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
Write-Host "Launcher decisions: $passed passed; $($failures.Count) failed; $skipped skipped."
if($failures.Count){foreach($failure in $failures){Write-Host $failure};exit 1}
