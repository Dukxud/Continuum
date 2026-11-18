# Conversation-specific, read-only local Git discovery.
# Application associations are separate from the replaceable UI draft.
. (Join-Path $PSScriptRoot 'CodexRepositoryEvidence.ps1')

function Get-SavedSessionRepository {
    param([string]$SessionId,[Parameter(Mandatory)][string]$AppDirectory)
    if($SessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){return $null}
    $file=Join-Path $AppDirectory ('session-repositories/'+$SessionId.ToLowerInvariant()+'.json')
    $entry=Read-JsonSettings -Path $file
    $path=$null
    if($entry -and $entry.schema -eq 1 -and [string]$entry.sessionId -ieq $SessionId){
        $path=[string]$entry.root
    }else{
        # Read legacy associations directly on upgrade, before the first save.
        $settings=Read-JsonSettings -Path (Join-Path $AppDirectory 'settings.json')
        if($settings -and $settings.sessionRepositories){
            $saved=$settings.sessionRepositories.PSObject.Properties[$SessionId]
            if($saved -and $saved.Value -is [string]){$path=$saved.Value}
        }
        if(-not $path -and $settings -and [string]$settings.draft.sessionId -ieq $SessionId){
            $path=[string]$settings.draft.repo
        }
    }
    $path=([string]$path).Trim().Trim('"')
    if(-not $path -or -not [IO.Path]::IsPathFullyQualified($path)){return $null}
    $root=Get-RepositoryRoot $path
    if($root -and $root.Replace('\','/').TrimEnd('/') -ieq $path.Replace('\','/').TrimEnd('/')){return $root}
    return $null
}

function Save-SessionRepositoryAssociation {
    param([string]$SessionId,[string]$Repository,
          [Parameter(Mandatory)][string]$AppDirectory,[switch]$OnlyIfMissing)
    if($SessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){return}
    $file=Join-Path $AppDirectory ('session-repositories/'+$SessionId.ToLowerInvariant()+'.json')
    # Fast path only; the atomic no-replace move below still handles races.
    if($OnlyIfMissing -and (Test-Path -LiteralPath $file -PathType Leaf)){return}
    $Repository=([string]$Repository).Trim().Trim('"')
    if(-not $Repository -or -not [IO.Path]::IsPathFullyQualified($Repository)){return}
    $root=Get-RepositoryRoot $Repository
    if(-not $root){return}
    # One atomic file per exact ID: overlapping saves for different sessions
    # cannot replace one shared map, and legacy UI/settings writers cannot erase it.
    $state=[pscustomobject]@{
        schema=1;sessionId=$SessionId.ToLowerInvariant();root=$root
    }
    if(-not $OnlyIfMissing){Write-JsonSettings -Path $file -Value $state;return}
    # Legacy task/draft migration cannot overwrite an explicit selection that
    # arrives after a missing-file check. Publish with atomic no-replace semantics.
    $directory=Split-Path -Parent $file
    [void](New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop)
    $temporary=Join-Path $directory ('.association-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try{
        $state|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $temporary -Encoding utf8 -ErrorAction Stop
        try{[IO.File]::Move($temporary,$file,$false)}
        catch [IO.IOException]{if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw}}
    }finally{
        if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue}
    }
}

function Find-ReferencedSessionRepository {
    param([Parameter(Mandatory)]$Session,[string]$HomeDirectory=$HOME,
          [string]$CodexPreview=$null,$Evidence=$null,[string[]]$KnownRoots=@(),
          [ValidateRange(1,30000)][int]$TimeoutMilliseconds=10000,
          [ValidateRange(1,100000)][int]$MaximumDirectories=20000)
    if(-not $Evidence){$Evidence=Get-CodexSessionRepositoryEvidence -Session $Session -CodexPreview $CodexPreview}
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $incomplete={
        param([string[]]$Candidates=@(),[string]$Reason='Local repository discovery exceeded its time budget.')
        $partial=@($Candidates|Sort-Object -Unique)
        return [pscustomobject]@{Root=$null;Source=$Reason;Candidates=$partial;AlternativeRoots=$partial;Incomplete=$true}
    }
    $roots=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $Evidence.Paths){
        if($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds){return (& $incomplete -Candidates @($roots))}
        $root=Get-RepositoryRoot $path
        if($root){[void]$roots.Add($root)}
    }
    if($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds){return (& $incomplete -Candidates @($roots))}
    $direct=@($roots | Sort-Object -Unique)
    if(-not $Evidence.Complete){
        return [pscustomobject]@{Root=$null;Source=$Evidence.Reason;Candidates=$direct;AlternativeRoots=$direct;Incomplete=$true}
    }
    if($direct.Count -eq 1){
        return [pscustomobject]@{Root=$direct[0];Source='session tool working directory';Candidates=$direct;AlternativeRoots=@()}
    }
    if($direct.Count -gt 1){
        return [pscustomobject]@{Root=$null;Source='conflicting session tool directories';Candidates=$direct;AlternativeRoots=$direct}
    }
    if(-not $Evidence.Names.Count -and -not $Evidence.Remotes.Count){return $null}

    # Include explicitly known checkout roots, plus bounded conventional roots.
    # There is no drive-wide search and a folder name alone cannot authorize Git.
    $locations=@($HomeDirectory,(Join-Path $HomeDirectory 'source'),
        (Join-Path $HomeDirectory 'repos'),(Join-Path $HomeDirectory 'projects'),
        (Join-Path $HomeDirectory 'dev'),(Join-Path $HomeDirectory 'Documents/GitHub'),
        (Join-Path $HomeDirectory 'Desktop'))
    $checkouts=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($known in $KnownRoots){
        if($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds){return (& $incomplete)}
        $root=Get-RepositoryRoot $known
        if($root){[void]$checkouts.Add($root)}
    }
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($location in $locations){
        if($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds){return (& $incomplete)}
        if(-not (Test-Path -LiteralPath $location -PathType Container)){continue}
        $depth=if($location -eq $HomeDirectory){1}else{2}
        $frontier=@($location)
        for($level=0;$level -lt $depth;$level++){
            $next=[Collections.Generic.List[string]]::new()
            foreach($folder in $frontier){
                $enumerator=$null
                try{
                    # Enumerate lazily; materializing a huge directory listing
                    # before checking the deadline defeats the search bound.
                    $enumerator=[IO.Directory]::EnumerateDirectories($folder).GetEnumerator()
                    while($enumerator.MoveNext()){
                        if($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds){return (& $incomplete)}
                        $child=[IO.DirectoryInfo]::new($enumerator.Current)
                        if($child.Name -in @('.git','node_modules','.dart_tool','.venv','build','.cache') -or
                           ($child.Attributes -band [IO.FileAttributes]::ReparsePoint)){continue}
                        if(-not $seen.Add($child.FullName)){continue}
                        if($seen.Count -gt $MaximumDirectories){
                            return (& $incomplete -Reason 'Local repository discovery exceeded its directory limit.')
                        }
                        if(Test-Path -LiteralPath (Join-Path $child.FullName '.git')){
                            [void]$checkouts.Add($child.FullName)
                        }elseif($level -lt ($depth-1)){$next.Add($child.FullName)}
                    }
                }catch [UnauthorizedAccessException]{
                    # Ignore inaccessible locations, as the original bounded
                    # conventional-directory search did; never elevate access.
                }catch [IO.IOException]{
                    # A concurrently removed directory is not a checkout.
                }finally{if($enumerator -is [IDisposable]){$enumerator.Dispose()}}
            }
            $frontier=@($next.ToArray())
        }
    }
    $matched=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($checkout in $checkouts){
        if($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds){return (& $incomplete -Candidates @($matched))}
        $root=Get-RepositoryRoot $checkout
        if(-not $root){continue}
        $identity=[IO.Path]::GetFileName($root.TrimEnd([char[]]@('/','\')))
        $match=$Evidence.Names.Contains($identity)
        $remoteEvidence=[pscustomobject]@{
            Remotes=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        }
        try{
            # All configured remotes are local Git metadata. No fetch/network.
            $urls=@(& git -C $root config --get-regexp '^remote\..*\.url$' 2>$null)
            if($LASTEXITCODE -eq 0){
                foreach($url in $urls){Add-CodexRepositoryText $remoteEvidence ([string]$url)}
            }
        }catch{}
        foreach($remote in $remoteEvidence.Remotes){
            if($Evidence.Remotes.Contains($remote)){$match=$true}
            foreach($name in $Evidence.Names){
                # Whole project components only, never loose abbreviations.
                if($name.Length -ge 5 -and $remote.Split('/')[-1] -match
                   ('(?i)^'+[regex]::Escape($name)+'(?:[-_.]|$)')){$match=$true}
            }
        }
        if($match){[void]$matched.Add($root)}
    }
    if($clock.ElapsedMilliseconds -ge $TimeoutMilliseconds){return (& $incomplete -Candidates @($matched))}
    $found=@($matched | Sort-Object -Unique)
    if($found.Count -eq 1){
        return [pscustomobject]@{Root=$found[0];Source='session-referenced local Git checkout';Candidates=$found;AlternativeRoots=@()}
    }
    if($found.Count -gt 1){
        return [pscustomobject]@{Root=$null;Source='conflicting session-referenced checkouts';Candidates=$found;AlternativeRoots=$found}
    }
    return $null
}
