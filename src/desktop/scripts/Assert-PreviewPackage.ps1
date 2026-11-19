# One package contract for build staging, extracted archives and every launch.
# This validates a distribution; it never executes or unblocks its contents.
function Get-ContinuumPreviewRequiredFiles {
    [CmdletBinding()]
    param([ValidateSet('Current','PinnedPreview1')][string]$Profile='Current')

    # Flutter's Windows CMake installation copies ICU, the AOT image, assets
    # and each linked plugin beside the runner. An empty data folder cannot run.
    $required=@(
        'codex_resume_flutter.exe','flutter_windows.dll',
        'window_manager_plugin.dll','screen_retriever_windows_plugin.dll',
        'data/app.so','data/icudtl.dat',
        'data/flutter_assets/AssetManifest.bin','data/flutter_assets/FontManifest.json',
        'data/flutter_assets/fonts/MaterialIcons-Regular.otf',
        'data/flutter_assets/shaders/aero_liquid.frag',
        'build-info.json','LICENSE','PREVIEW-NOTES.txt',
        'src/desktop/windows_bridge.ps1',
        'src/desktop/bridge/ReadModels.ps1','src/desktop/bridge/Scheduling.ps1',
        'src/desktop/bridge/SharedSessions.ps1','src/desktop/bridge/Preferences.ps1',
        'src/backend/Invoke-CodexJob.ps1','src/backend/CodexRunEngine.ps1',
        'src/backend/CodexData.ps1','src/backend/CodexJobStore.ps1',
        'src/backend/CodexSessionRepository.ps1','src/backend/CodexRunActivity.ps1',
        'src/backend/CodexUsage.js','src/backend/CodexQuotaContinuation.ps1',
        'src/backend/CodexTerminalRun.ps1','src/backend/CodexRunJob.vbs',
        'components/RuntimeBundle/RuntimeBundle.psm1',
        'components/OneTimeTasks/OneTimeTasks.psm1',
        'components/GitRepository/GitRepository.psm1',
        'components/JobOutcomes/JobOutcomes.psm1',
        'components/SettingsStore/SettingsStore.psm1',
        'components/SharedCodexSession/main.mjs','components/SharedCodexSession/host.mjs',
        'components/SharedCodexSession/client.mjs','components/SharedCodexSession/remote.mjs',
        'components/SharedCodexSession/protocol.mjs'
    )
    foreach($color in @('amber','blue','cyan','green','red','violet')){
        $required+='data/flutter_assets/assets/native/'+$color+'.png'
    }
    if($Profile -eq 'Current'){
        $required+=@('src/backend/CodexCli.ps1','src/backend/CodexRepositoryEvidence.ps1',
            'Run-Continuum.cmd','Run-Continuum.ps1',
            'src/desktop/scripts/Assert-PreviewPackage.ps1')
    }
    return $required
}

function Assert-ContinuumPreviewPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Directory,
        [ValidateSet('Current','PinnedPreview1')][string]$Profile='Current'
    )
    $base=[IO.Path]::GetFullPath($Directory)
    $root=Get-Item -LiteralPath $base -Force -ErrorAction Stop
    if(-not $root.PSIsContainer -or
       ($root.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
        throw 'Preview package must be a complete extracted directory, not a linked path.'
    }

    # Enumerate without following junctions or directory links. Otherwise a
    # checksum could appear valid while packaging/unblocking another tree.
    $files=[Collections.Generic.Dictionary[string,IO.FileInfo]]::new([StringComparer]::OrdinalIgnoreCase)
    $folders=[Collections.Generic.Stack[string]]::new()
    $folders.Push($base)
    while($folders.Count){
        foreach($item in @(Get-ChildItem -LiteralPath $folders.Pop() -Force -ErrorAction Stop)){
            if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){
                throw "Preview package contains a linked path: $($item.FullName)"
            }
            if($item.PSIsContainer){$folders.Push($item.FullName);continue}
            $relative=[IO.Path]::GetRelativePath($base,$item.FullName).Replace('\','/')
            if(-not $files.TryAdd($relative,$item)){
                throw "Preview package has duplicate Windows file names: $relative"
            }
        }
    }
    if(-not $files.ContainsKey('SHA256SUMS.txt')){throw 'Preview checksum manifest missing; extract the complete package.'}
    $manifest=$files['SHA256SUMS.txt'].FullName
    if($Profile -eq 'PinnedPreview1'){
        # The exact published ZIP (08be6c6c...2a656f9) was independently
        # extracted to obtain this digest. The legacy dependency list is only
        # valid for that fixed artifact, never as a fallback for another build.
        $pinnedManifest='cdc7fb8dd787fb9bf2163bdc4b5a90d8f1a8b1fefe9ce9418ce985235d3971f5'
        if((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ine $pinnedManifest){
            throw 'Pinned Preview 1 checksum manifest differs from the published release. Nothing was launched.'
        }
    }
    $entries=@([IO.File]::ReadAllLines($manifest))
    if(-not $entries.Count){throw 'Preview checksum manifest is empty.'}
    $verified=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $paths=[Collections.Generic.List[string]]::new()
    foreach($entry in $entries){
        $match=[regex]::Match($entry,'^([0-9a-fA-F]{64})  (.+)$')
        if(-not $match.Success){throw 'Malformed preview checksum entry.'}
        $relative=$match.Groups[2].Value
        if($relative -match '[\\:\x00-\x1F]' -or $relative.StartsWith('/') -or
           @($relative.Split('/') | Where-Object {$_ -in @('','.','..')}).Count -gt 0 -or
           $relative -ieq 'SHA256SUMS.txt' -or -not $verified.Add($relative)){
            throw "Unsafe or duplicated preview checksum path: $relative"
        }
        if(-not $files.ContainsKey($relative)){throw "Preview package file missing: $relative. Extract the complete package."}
        $path=$files[$relative].FullName
        if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $match.Groups[1].Value){
            throw "Preview package checksum failed: $relative. Nothing was launched."
        }
        $paths.Add($path)
    }
    foreach($relative in $files.Keys){
        if($relative -ine 'SHA256SUMS.txt' -and -not $verified.Contains($relative)){
            throw "Preview file is not covered by its checksum manifest: $relative"
        }
    }
    foreach($relative in @(Get-ContinuumPreviewRequiredFiles -Profile $Profile)){
        if(-not $verified.Contains($relative)){
            throw "Preview package is incomplete; required file missing from manifest: $relative"
        }
        if($files[$relative].Length -eq 0){throw "Preview required file is empty: $relative"}
    }
    try{$identity=[IO.File]::ReadAllText($files['build-info.json'].FullName) | ConvertFrom-Json -AsHashtable -ErrorAction Stop}
    catch{throw 'Preview build-info.json is not valid JSON.'}
    if($identity -isnot [Collections.IDictionary] -or $identity['application'] -cne 'Continuum' -or
       [string]$identity['version'] -cnotmatch '^\d+\.\d+\.\d+(?:\+\d+)?$'){
        throw 'Preview build identity is missing or invalid.'
    }
    return [pscustomobject]@{
        Directory=$base
        Executable=$files['codex_resume_flutter.exe'].FullName
        FileCount=$verified.Count
        VerifiedPaths=$paths.ToArray()
        Profile=$Profile
    }
}
