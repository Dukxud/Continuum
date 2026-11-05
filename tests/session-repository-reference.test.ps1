# Read-only session-to-checkout discovery. Uses isolated real Git repositories.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexData.ps1')
function Assert-True([bool]$Condition,[string]$Reason){if(-not $Condition){throw $Reason}}
function Normalize-Root([string]$Path){return $Path.Replace('\','/').TrimEnd('/')}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('session-repository-'+[guid]::NewGuid().ToString('N'))
$testHome=Join-Path $fixture 'home'
$app=Join-Path $fixture 'app'
[void](New-Item -ItemType Directory -Path $testHome,$app -Force)
try{
    function New-TestRepo([string]$Relative) {
        $dir=Join-Path $testHome $Relative
        [void](New-Item -ItemType Directory -Path $dir -Force)
        & git init -b main $dir | Out-Null
        if($LASTEXITCODE -ne 0){throw 'Unable to initialize isolated Git checkout.'}
        return $dir
    }
    function New-Session([string]$Name,[string]$Prompt) {
        $file=Join-Path $fixture ($Name+'.jsonl')
        $intro=@{type='session_meta';payload=@{
            id='00000000-0000-0000-0000-000000000001';source='cli';cwd=$testHome
        }} | ConvertTo-Json -Depth 7 -Compress
        $user=@{type='event_msg';payload=@{type='user_message';message=$Prompt}} |
            ConvertTo-Json -Depth 7 -Compress
        @($intro,$user) | Set-Content -LiteralPath $file -Encoding utf8
        return [pscustomobject]@{Id='00000000-0000-0000-0000-000000000001';Cwd=$testHome;File=$file}
    }

    # Reproduce BLACK-PUDDLE: neither checkout folder nor remote slug is
    # literally "AIVault", but the verified origin has that full project
    # name as its first hyphen-delimited component.
    $aiv=New-TestRepo 'source\aivault-phase1-firewall-free'
    & git -C $aiv remote add origin 'https://github.com/Dukxud/aivault-opensearch-ai-dev.git'
    if($LASTEXITCODE -ne 0){throw 'Unable to set up AIVault real-shape remote.'}
    $session=New-Session 'aiv' '# AIVault — Independent Adversarial Architecture Review'
    # The useful user instruction can be much older than the tail window.
    1..830 | ForEach-Object { '{"type":"event_msg","payload":{"type":"token_count"}}' } |
        Add-Content -LiteralPath $session.File -Encoding utf8
    $found=Find-SessionRepository $session -AppDirectory $app -CheckoutHome $testHome
    Assert-True ((Normalize-Root $found.Root) -ieq (Normalize-Root $aiv)) 'AIVault project heading did not locate its verified local checkout.'
    Assert-True ($found.Source -eq 'session-referenced local Git checkout') 'Untrusted provenance was reported.'
    $short=New-Session 'short' '# AIV — Independent Architecture'
    Assert-True ($null -eq (Find-SessionRepository $short -AppDirectory $app -CheckoutHome $testHome)) 'Three-letter project abbreviation must not match a longer Git remote prefix.'
    $unrelatedSimilar=New-TestRepo 'source\aivaultish-other'
    & git -C $unrelatedSimilar remote add origin 'https://github.com/Dukxud/aivaultish-other.git'
    if($LASTEXITCODE -ne 0){throw 'Unable to configure similarly named unrelated remote.'}
    $unique=Find-SessionRepository $session -AppDirectory $app -CheckoutHome $testHome
    Assert-True ((Normalize-Root $unique.Root) -ieq (Normalize-Root $aiv)) 'Substring-only repo name incorrectly matched AIVault project.'

    $different=New-TestRepo 'source\Unrelated'
    $wrong=New-Session 'unrelated' 'Investigate an unrelated repository.'
    Assert-True ($null -eq (Find-SessionRepository $wrong -AppDirectory $app -CheckoutHome $testHome)) 'Unrelated session borrowed a random local checkout.'

    # A repo URL in an explicit user request matches the Git remote even when
    # the folder name is different. No network, clone or bare-name guessing.
    $remoteRepo=New-TestRepo 'source\CheckoutWithDifferentName'
    & git -C $remoteRepo remote add origin 'https://github.com/test-owner/target-repo.git'
    if($LASTEXITCODE -ne 0){throw 'Unable to configure isolated Git remote.'}
    $remoteSession=New-Session 'remote' 'Review https://github.com/test-owner/target-repo'
    $found=Find-SessionRepository $remoteSession -AppDirectory $app -CheckoutHome $testHome
    Assert-True ((Normalize-Root $found.Root) -ieq (Normalize-Root $remoteRepo)) 'GitHub URL did not match a verified remote checkout.'
    $notCloned=New-Session 'uncloned' 'Review https://github.com/test-owner/no-checkout'
    Assert-True ($null -eq (Find-SessionRepository $notCloned -AppDirectory $app -CheckoutHome $testHome)) 'Remote-only reference invented a local checkout.'

    # Two real checkouts that both match must be surfaced as a conflict.
    $otherAiv=New-TestRepo 'repos\AIVault'
    $ambiguous=Find-SessionRepository $session -AppDirectory $app -CheckoutHome $testHome
    Assert-True ($null -eq $ambiguous.Root -and @($ambiguous.Candidates).Count -eq 2) 'Ambiguous checkouts were automatically chosen.'
    Assert-True (@($ambiguous.AlternativeRoots).Count -eq 2) 'Conflict details were lost.'

    # Codex can hold a rollout open. Reader must permit simultaneous writes.
    $open=[IO.FileStream]::new($remoteSession.File,[IO.FileMode]::Open,
        [IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try{
        $concurrent=Find-SessionRepository $remoteSession -AppDirectory $app -CheckoutHome $testHome
        Assert-True ((Normalize-Root $concurrent.Root) -ieq (Normalize-Root $remoteRepo)) 'Reading a live session failed despite shared read support.'
    }finally{$open.Dispose()}
    Write-Host 'Automatic repository discovery: unique, remote, conflict, long-session, live-read and no-guess PASS.' -ForegroundColor Green
}finally{
    if(Test-Path -LiteralPath $fixture){
        Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}
