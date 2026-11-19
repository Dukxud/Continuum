# Resolve the installed Codex command consistently for metadata and execution.
# Official Windows installations can be native codex.exe or an npm shim.
# Never send a .cmd/.ps1 shim through Node or interpolate it into a shell.
function Get-CodexCliEntry {
    [CmdletBinding()]
    param()
    # Honor installation order on PATH. Globally preferring codex.exe could
    # select a different installation behind the user's active npm command.
    # Within one directory, the native executable precedes the npm shim.
    foreach($location in ([string]$env:PATH -split [regex]::Escape([string][IO.Path]::PathSeparator))){
        $location=$location.Trim().Trim('"')
        if(-not $location){continue}
        try{$directory=[IO.Path]::GetFullPath($location)}catch{continue}
        $native=Join-Path $directory 'codex.exe'
        if(Test-Path -LiteralPath $native -PathType Leaf){return $native}
        $shim=Join-Path $directory 'codex.cmd'
        if(Test-Path -LiteralPath $shim -PathType Leaf){
            $entry=Join-Path $directory 'node_modules/@openai/codex/bin/codex.js'
            if(Test-Path -LiteralPath $entry -PathType Leaf){return $entry}
            throw "The selected Codex npm installation is incomplete: $directory"
        }
    }
    throw 'Codex CLI was not found. Install Codex and restart Continuum so it receives the updated PATH.'
}

function Get-CodexMetadataArguments {
    [CmdletBinding()]
    param([string]$Entry=(Get-CodexCliEntry))
    $extension=[IO.Path]::GetExtension($Entry)
    if($extension -ieq '.exe'){return @('--cli-exe',$Entry)}
    if($extension -ieq '.js'){return @('--cli-js',$Entry)}
    throw 'Unsupported Codex entrypoint; expected the installed executable or npm JavaScript entry.'
}
