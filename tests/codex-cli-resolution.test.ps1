# Real command discovery and process launch with an isolated PATH. The copied
# native executable is Node acting as a local argv/exit-code fixture; no Codex
# account, model request, scheduled task, or Windows platform spoof is involved.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/backend/CodexCli.ps1')
. (Join-Path $root 'src/backend/CodexTerminalRun.ps1')
$originalPath=$env:PATH
$node=(Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$chmod=if(-not $IsWindows){(Get-Command chmod -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source}else{''}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum cli paths '+[guid]::NewGuid().ToString('N'))
$nativeDirectory=Join-Path $fixture 'native install with spaces'
$npmDirectory=Join-Path $fixture 'npm install with spaces'
$nodeDirectory=Join-Path $fixture 'node runtime'
$emptyDirectory=Join-Path $fixture 'empty path'
$native=Join-Path $nativeDirectory 'codex.exe'
$npmEntry=Join-Path $npmDirectory 'node_modules/@openai/codex/bin/codex.js'
$shim=Join-Path $npmDirectory 'codex.cmd'
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Copy-FixtureExecutable([string]$Destination){
    try{[void](New-Item -ItemType HardLink -Path $Destination -Target $node -ErrorAction Stop)}
    catch{Copy-Item -LiteralPath $node -Destination $Destination -ErrorAction Stop}
    if(-not $IsWindows){
        & $chmod +x $Destination
        Require ($LASTEXITCODE -eq 0) 'Could not mark the native fixture executable.'
    }
}
function Assert-Arguments([string]$Capture,[string[]]$Expected){
    $actual=@(Get-Content -LiteralPath $Capture -Raw | ConvertFrom-Json)
    Require ($actual.Count -eq $Expected.Count) 'Terminal launch changed the number of arguments.'
    for($i=0;$i -lt $Expected.Count;$i++){
        Require ($actual[$i] -ceq $Expected[$i]) "Terminal launch changed argument $i."
    }
}
try{
    [void](New-Item -ItemType Directory -Path $nativeDirectory,$nodeDirectory,$emptyDirectory,(Split-Path -Parent $npmEntry) -Force)
    Copy-FixtureExecutable $native
    Copy-FixtureExecutable (Join-Path $nodeDirectory 'node.exe')
    if($IsWindows){'@exit /b 99' | Set-Content -LiteralPath $shim -Encoding ascii}
    else{
        "#!/bin/sh`nexit 99" | Set-Content -LiteralPath $shim -Encoding ascii
        & $chmod +x $shim
        Require ($LASTEXITCODE -eq 0) 'Could not mark the npm shim discoverable.'
    }
    @'
const fs = require('node:fs');
const [capture, code, ...values] = process.argv.slice(2);
fs.writeFileSync(capture, JSON.stringify(values));
process.exit(Number(code));
'@ | Set-Content -LiteralPath $npmEntry -Encoding utf8

    $env:PATH=$nativeDirectory
    $entry=Get-CodexCliEntry
    Require ($entry -ceq [IO.Path]::GetFullPath($native)) 'A standalone native installation was not resolved.'
    $arguments=@(Get-CodexMetadataArguments)
    Require ($arguments.Count -eq 2 -and $arguments[0] -ceq '--cli-exe' -and $arguments[1] -ceq $native) 'Native metadata arguments lost their flag or spaced path.'

    $env:PATH=$npmDirectory
    $entry=Get-CodexCliEntry
    Require ($entry -ceq [IO.Path]::GetFullPath($npmEntry)) 'An npm shim did not resolve its actual JavaScript entry.'
    $arguments=@(Get-CodexMetadataArguments -Entry $entry)
    Require ($arguments.Count -eq 2 -and $arguments[0] -ceq '--cli-js' -and $arguments[1] -ceq $npmEntry) 'Npm metadata arguments lost their flag or spaced path.'

    $env:PATH=$npmDirectory+[IO.Path]::PathSeparator+$nativeDirectory
    Require ((Get-CodexCliEntry) -ceq $npmEntry) 'A later native installation overrode the active npm installation on PATH.'
    $env:PATH=$nativeDirectory+[IO.Path]::PathSeparator+$npmDirectory
    Require ((Get-CodexCliEntry) -ceq $native) 'A later npm installation overrode the active native installation on PATH.'
    $sameDirectoryNative=Join-Path $npmDirectory 'codex.exe'
    Copy-FixtureExecutable $sameDirectoryNative
    $env:PATH='"'+$npmDirectory+'"'
    Require ((Get-CodexCliEntry) -ceq $sameDirectoryNative) 'Native Codex did not precede the npm shim in the same quoted PATH directory.'
    Remove-Item -LiteralPath $sameDirectoryNative -Force
    $hiddenEntry=Join-Path $fixture 'temporarily hidden entry.js'
    Move-Item -LiteralPath $npmEntry -Destination $hiddenEntry
    $env:PATH=$npmDirectory+[IO.Path]::PathSeparator+$nativeDirectory
    $incomplete=''
    try{[void](Get-CodexCliEntry)}catch{$incomplete=$_.Exception.Message}
    Require ($incomplete -like 'The selected Codex npm installation is incomplete:*') 'A broken active npm install silently selected a different later native installation.'
    Move-Item -LiteralPath $hiddenEntry -Destination $npmEntry

    $env:PATH=$emptyDirectory
    $missing=''
    try{[void](Get-CodexCliEntry)}catch{$missing=$_.Exception.Message}
    Require ($missing -like 'Codex CLI was not found.*restart Continuum*PATH*') 'A missing install did not report its actionable installation/PATH error.'
    . (Join-Path $root 'src/backend/CodexData.ps1')
    $id='0199aaaa-1234-4567-89ab-0000e116d411'
    $metadata=Get-CodexThreadMetadata -SessionId $id -SourceDirectory $root
    Require ($null -eq $metadata) 'Optional metadata lookup did not remain compatible without an error reference.'
    $diagnostic=$null
    $metadata=Get-CodexThreadMetadata -SessionId $id -SourceDirectory $root -Failure ([ref]$diagnostic)
    Require ($null -eq $metadata -and $diagnostic -like 'Codex CLI was not found.*') 'Metadata lookup lost its explicit installation failure diagnostic.'
    Require ($null -eq (Get-ReportedThreadDirectory -SessionId $id -SourceFolder $root)) 'The legacy metadata caller failed without an optional error reference.'
    $unsupported=''
    try{[void](Get-CodexMetadataArguments -Entry $shim)}catch{$unsupported=$_.Exception.Message}
    Require ($unsupported -like 'Unsupported Codex entrypoint*') 'A shell shim was accepted as a native metadata entry.'

    $payload=@('C:\a path\repository','message & "quoted"; $literal',( "first line"+[Environment]::NewLine+"second line" ))
    $nativeCapture=Join-Path $fixture 'native captured args.json'
    $env:PATH=$nativeDirectory
    $exitCode=Invoke-CodexTerminal -CliEntry $native -Arguments (@($npmEntry,$nativeCapture,'37')+$payload)
    Require ($exitCode -eq 37) 'Native terminal launch lost the real child exit code.'
    Assert-Arguments $nativeCapture $payload

    $javascriptCapture=Join-Path $fixture 'javascript captured args.json'
    $env:PATH=$nodeDirectory+[IO.Path]::PathSeparator+$npmDirectory
    $exitCode=Invoke-CodexTerminal -CliEntry $npmEntry -Arguments (@($javascriptCapture,'23')+$payload)
    Require ($exitCode -eq 23) 'JavaScript terminal launch lost the real child exit code.'
    Assert-Arguments $javascriptCapture $payload
    Write-Host 'PASS: actual native/npm PATH order, same-directory precedence, broken-install isolation, optional metadata diagnostics, preserved spaced arguments, and direct/native versus Node terminal exit codes.'
}finally{
    $env:PATH=$originalPath
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
}
