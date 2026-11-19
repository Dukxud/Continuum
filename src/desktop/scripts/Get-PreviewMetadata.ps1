# The Flutter package version is the authority for the native app and its ZIP.
function Get-ContinuumPreviewMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PubspecPath)

    $pubspec = Get-Content -LiteralPath $PubspecPath -Raw -ErrorAction Stop
    $versionMatches = [regex]::Matches($pubspec, '(?m)^version:\s*(\d+\.\d+\.\d+(?:\+\d+)?)\s*$')
    if ($versionMatches.Count -ne 1) {
        throw 'pubspec.yaml must contain one numeric version, optionally followed by a build number.'
    }
    $version = $versionMatches[0].Groups[1].Value
    [pscustomobject]@{
        Version = $version
        PackageName = "Continuum-Windows-v$version-UNSIGNED-PREVIEW"
    }
}

# A source ZIP can live inside an unrelated repository. Git's upward search
# must never assign that parent's commit to the application being built.
function Get-ContinuumSourceIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SourceDirectory)
    $source=[IO.Path]::GetFullPath($SourceDirectory).TrimEnd([char[]]@('/','\'))
    if(-not (Test-Path -LiteralPath (Join-Path $source '.git'))){
        return [pscustomobject]@{SourceCommit=$null;SourceModified=$null;SourceArchive=$true}
    }
    $git=Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
    $PSNativeCommandUseErrorActionPreference=$false
    $top=@(& $git.Source -C $source rev-parse --show-toplevel 2>$null)
    if($LASTEXITCODE -ne 0 -or $top.Count -ne 1){throw 'Cannot verify the source Git root for this preview.'}
    $actual=[IO.Path]::GetFullPath([string]$top[0]).TrimEnd([char[]]@('/','\'))
    $comparison=if($IsWindows){[StringComparison]::OrdinalIgnoreCase}else{[StringComparison]::Ordinal}
    if(-not [string]::Equals($actual,$source,$comparison)){
        throw 'Git identified a different source root; refusing to record an unrelated commit.'
    }
    $head=@(& $git.Source -C $source rev-parse --verify HEAD 2>$null)
    if($LASTEXITCODE -ne 0 -or $head.Count -ne 1 -or [string]$head[0] -notmatch '^(?:[0-9a-f]{40}|[0-9a-f]{64})$'){
        throw 'Cannot identify the source commit for this preview.'
    }
    $changes=@(& $git.Source -C $source status --porcelain --untracked-files=normal 2>$null)
    if($LASTEXITCODE -ne 0){throw 'Cannot identify local source changes.'}
    return [pscustomobject]@{
        SourceCommit=[string]$head[0]
        SourceModified=($changes.Count -gt 0)
        SourceArchive=$false
    }
}
