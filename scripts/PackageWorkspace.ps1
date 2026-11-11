# Isolated staging and no-overwrite publication for the legacy/component ZIP builders.
function New-PackageWorkspace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._+-]*$')][string]$Name,
        [Parameter(Mandatory)][string]$OutputDirectory
    )
    $output = [IO.Path]::GetFullPath($OutputDirectory)
    $archive = Join-Path $output "$Name.zip"
    if (Test-Path -LiteralPath $archive) { throw "Package already exists: $archive" }
    $temporaryParent = [IO.Path]::GetFullPath($(if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [IO.Path]::GetTempPath() }))
    $staging = Join-Path $temporaryParent ('continuum-package-' + [guid]::NewGuid().ToString('N'))
    $directory = Join-Path $staging $Name
    [void](New-Item -ItemType Directory -Path $directory -Force -ErrorAction Stop)
    [pscustomobject]@{
        Root = $staging
        TemporaryParent = $temporaryParent
        Directory = $directory
        OutputDirectory = $output
        Archive = $archive
    }
}

function Complete-PackageWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Workspace)

    if (Test-Path -LiteralPath $Workspace.Archive) { throw "Package already exists: $($Workspace.Archive)" }
    $stagedArchive = Join-Path $Workspace.Root 'package.zip'
    Compress-Archive -LiteralPath $Workspace.Directory -DestinationPath $stagedArchive -ErrorAction Stop
    [void](New-Item -ItemType Directory -Path $Workspace.OutputDirectory -Force -ErrorAction Stop)
    Move-Item -LiteralPath $stagedArchive -Destination $Workspace.Archive -ErrorAction Stop
    return $Workspace.Archive
}

function Remove-PackageWorkspace {
    [CmdletBinding()]
    param([Parameter(Mandatory)][object]$Workspace)

    $resolved = [IO.Path]::GetFullPath($Workspace.Root)
    $parent = [IO.Path]::GetFullPath($Workspace.TemporaryParent).TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ((Split-Path -Parent $resolved) -ine $parent -or (Split-Path -Leaf $resolved) -notlike 'continuum-package-*') {
        throw 'Refusing to remove a directory outside the package staging area.'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction Stop
}
