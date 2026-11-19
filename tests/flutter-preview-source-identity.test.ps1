# Real Git repositories/worktrees and ordinary source folders; no Windows build.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/desktop/scripts/Get-PreviewMetadata.ps1')
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-source-identity-'+[guid]::NewGuid().ToString('N'))
$failures=[Collections.Generic.List[string]]::new()
$passed=0
function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Run-Case([string]$Name,[scriptblock]$Body){
    try{& $Body;$script:passed++;Write-Host "PASS $Name"}
    catch{$script:failures.Add($Name+': '+$_.Exception.Message);Write-Host "FAIL $Name — $($_.Exception.Message)"}
}
try{
    [void](New-Item -ItemType Directory -Path $fixture)
    $archive=Join-Path $fixture 'archive'
    [void](New-Item -ItemType Directory -Path $archive)
    Run-Case 'ordinary source archive has no invented commit or clean flag' {
        $identity=Get-ContinuumSourceIdentity $archive
        Require ($identity.SourceArchive -eq $true -and $null -eq $identity.SourceCommit -and
            $null -eq $identity.SourceModified) 'An archive claimed a Git commit or tracked-clean state.'
    }
    $repository=Join-Path $fixture 'parent-repository'
    & git init -q -b main $repository
    Require ($LASTEXITCODE -eq 0) 'Cannot initialize the isolated repository.'
    [IO.File]::WriteAllText((Join-Path $repository 'tracked.txt'),'original')
    & git -C $repository add tracked.txt
    Require ($LASTEXITCODE -eq 0) 'Cannot stage the isolated fixture.'
    & git -C $repository -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm 'isolated provenance fixture'
    Require ($LASTEXITCODE -eq 0) 'Cannot commit the isolated fixture.'
    $expected=[string](& git -C $repository rev-parse HEAD)
    Require ($LASTEXITCODE -eq 0) 'Cannot read the isolated fixture commit.'
    Run-Case 'the actual Git root records its verified commit' {
        $identity=Get-ContinuumSourceIdentity $repository
        Require ($identity.SourceCommit -ceq $expected -and $identity.SourceArchive -eq $false -and
            $identity.SourceModified -eq $false) 'Clean Git root identity was incorrect.'
    }
    Run-Case 'archive inside a parent repository never borrows its commit' {
        $nested=Join-Path $repository 'downloaded-source'
        [void](New-Item -ItemType Directory -Path $nested)
        $identity=Get-ContinuumSourceIdentity $nested
        Require ($identity.SourceArchive -eq $true -and $null -eq $identity.SourceCommit) 'Source archive borrowed its parent repository commit.'
    }
    Run-Case 'tracked changes mark the build source as modified' {
        [IO.File]::WriteAllText((Join-Path $repository 'tracked.txt'),'changed')
        $identity=Get-ContinuumSourceIdentity $repository
        Require ($identity.SourceModified -eq $true) 'Tracked source changes were omitted.'
        [IO.File]::WriteAllText((Join-Path $repository 'tracked.txt'),'original')
    }
    Run-Case 'untracked source files also mark the build source as modified' {
        $new=Join-Path $repository 'new-source.dart'
        [IO.File]::WriteAllText($new,'void example() {}')
        $identity=Get-ContinuumSourceIdentity $repository
        Require ($identity.SourceModified -eq $true) 'Untracked compiled source could claim an unchanged commit.'
        Remove-Item -LiteralPath $new
    }
    Run-Case 'linked Git worktree records its own root and commit' {
        $worktree=Join-Path $fixture 'linked-worktree'
        & git -C $repository worktree add --quiet --detach $worktree HEAD
        Require ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $worktree '.git') -PathType Leaf)) 'Cannot create the isolated Git worktree.'
        $identity=Get-ContinuumSourceIdentity $worktree
        Require ($identity.SourceCommit -ceq $expected -and $identity.SourceArchive -eq $false -and
            $identity.SourceModified -eq $false) 'A valid Git worktree lost its commit identity.'
    }
    Run-Case 'broken Git metadata cannot masquerade as a verified commit' {
        $broken=Join-Path $fixture 'broken'
        [void](New-Item -ItemType Directory -Path $broken)
        [IO.File]::WriteAllText((Join-Path $broken '.git'),'gitdir: missing-git-directory')
        $rejected=$false
        try{Get-ContinuumSourceIdentity $broken | Out-Null}catch{$rejected=$true}
        Require $rejected 'Broken Git metadata claimed a usable source identity.'
    }
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
Write-Host "Preview source identity: $passed passed; $($failures.Count) failed."
if($failures.Count){foreach($failure in $failures){Write-Host $failure};exit 1}
