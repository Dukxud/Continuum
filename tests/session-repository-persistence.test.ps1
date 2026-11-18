# Regression: a verified session-to-repository association survives switching
# conversations, cancelling its scheduled job, and reopening the settings.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'src/backend/CodexData.ps1')
. (Join-Path $root 'src/desktop/bridge/Preferences.ps1')
function Require([bool]$Condition,[string]$Reason){if(-not $Condition){throw $Reason}}
function Normalize([string]$Path){return $Path.Replace('\','/').TrimEnd('/')}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('continuum-session-memory-'+[guid]::NewGuid().ToString('N'))
$app=Join-Path $fixture 'app'
$homeFolder=Join-Path $fixture 'home'
$outside=Join-Path $fixture 'outside'
[void](New-Item -ItemType Directory -Path $app,$homeFolder,$outside -Force)
try{
    # The checkout is deliberately outside the fallback scan of the session home.
    $repo=Join-Path $fixture 'external-checkout'
    [void](New-Item -ItemType Directory -Path $repo)
    & git init -b main $repo | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Unable to create a real Git test checkout.'}
    $firstId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $secondId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    $rollout=Join-Path $fixture 'rollout.jsonl'
    @(
        (@{type='session_meta';payload=@{id=$firstId;source='cli';cwd=$outside}} | ConvertTo-Json -Compress -Depth 6),
        (@{type='event_msg';payload=@{type='user_message';message='Resume the existing work.'}} | ConvertTo-Json -Compress -Depth 6)
    ) | Set-Content -LiteralPath $rollout -Encoding utf8
    $first=[pscustomobject]@{Id=$firstId;Cwd=$outside;File=$rollout}
    $secondRollout=Join-Path $fixture 'second-rollout.jsonl'
    @{type='session_meta';payload=@{id=$secondId;source='cli';cwd=$outside}} |
        ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $secondRollout -Encoding utf8
    $second=[pscustomobject]@{Id=$secondId;Cwd=$outside;File=$secondRollout}
    Require ($null -eq (Find-SessionRepository $first -AppDirectory $app -CheckoutHome $homeFolder)) 'Fixture must begin with an undiscoverable checkout.'

    function Save-Choice([string]$Id,[string]$Repo,[string]$Directory=$app){
        $draft=[pscustomobject]@{
            sessionId=$Id;repo=$Repo;model='gpt-test';effort='high'
            access='read-only';message='Resume.';runAt='2026-11-20T15:40:00'
            executionMode='terminal';autoResumeOnLimit=$false
        }
        [void](Save-FlutterPreferences -Request ([pscustomobject]@{
            draft=$draft;compactMode=$false;microMode=$false;alwaysOnTop=$false
        }) -AppDirectory $Directory)
    }
    Save-Choice $firstId $repo
    $stored=Read-CodexUiSettings $app
    Require ((Normalize ([string]$stored.sessionRepositories.$firstId)) -ieq (Normalize $repo)) 'First verified selection was not recorded by session ID.'

    # The next selection has no verified checkout. Its autosave must not
    # overwrite the previous conversation's established repository.
    Save-Choice $secondId ''
    $stored=Read-CodexUiSettings $app
    Require ([string]::IsNullOrEmpty([string]$stored.draft.repo)) 'Current empty repository draft was not preserved.'
    Require ((Normalize ([string]$stored.sessionRepositories.$firstId)) -ieq (Normalize $repo)) 'Switching conversations erased the prior association.'

    # A one-draft installation must migrate the previous saved pairing on
    # its first switch after upgrading, without first resaving the old thread.
    $legacy=Join-Path $fixture 'legacy-app'
    Write-JsonSettings -Path (Join-Path $legacy 'settings.json') -Value ([pscustomobject]@{
        version=1
        draft=[pscustomobject]@{sessionId=$firstId;repo=$repo}
    })
    Save-Choice $secondId '' $legacy
    $legacyFound=Find-SessionRepository $first -AppDirectory $legacy -CheckoutHome $homeFolder
    Require ($null -ne $legacyFound -and (Normalize $legacyFound.Root) -ieq (Normalize $repo)) 'Switching after upgrade lost the earlier single-draft association.'

    # Legacy UI writers replace settings.json without Flutter's map. Separate
    # association files must retain the root across that replacement as well.
    Write-CodexUiSettings -Directory $app -State ([pscustomobject]@{
        version=1;draft=[pscustomobject]@{sessionId=$secondId;repo=''}
    })
    $afterLegacyWrite=Find-SessionRepository $first -AppDirectory $app -CheckoutHome $homeFolder
    Require ((Normalize $afterLegacyWrite.Root) -ieq (Normalize $repo)) 'A legacy settings writer erased the durable session association.'

    # Simulate cancellation deleting the only scheduled job payload.
    $job=Join-Path $app 'CodexResume-20261118-1534-abcdef12.json'
    @{sessionId=$firstId;repo=$repo} | ConvertTo-Json -Compress |
        Set-Content -LiteralPath $job -Encoding utf8
    Remove-Item -LiteralPath $job -Force
    $restored=Find-SessionRepository $first -AppDirectory $app -CheckoutHome $homeFolder
    Require ($null -ne $restored -and (Normalize $restored.Root) -ieq (Normalize $repo)) 'Restored conversation lost the repository after the job was deleted.'
    Require ($restored.Source -eq 'saved conversation fallback') 'Restored association incorrectly depended on a job file or name guess.'
    Require ($null -eq (Find-SessionRepository $second -AppDirectory $app -CheckoutHome $homeFolder)) 'A different conversation inherited another session repository.'

    # New, authoritative Codex cwd evidence must outrank the saved mapping.
    $new=Join-Path $fixture 'current-checkout'
    [void](New-Item -ItemType Directory -Path $new)
    & git init -b main $new | Out-Null
    if($LASTEXITCODE -ne 0){throw 'Unable to create an alternate Git checkout.'}
    $overridden=Find-SessionRepository $first -ReportedCwd $new -AppDirectory $app -CheckoutHome $homeFolder
    Require ((Normalize $overridden.Root) -ieq (Normalize $new)) 'Saved association overrode the authoritative current Codex directory.'
    Require (@($overridden.AlternativeRoots).Count -eq 1) 'Competing historical checkout was not surfaced.'

    Remove-Item -LiteralPath $repo -Recurse -Force
    Require ($null -eq (Find-SessionRepository $first -AppDirectory $app -CheckoutHome $homeFolder)) 'A missing historical checkout was silently reused.'
    Write-Host 'PASS — association survives draft switch, job deletion and settings reload; rejects cross-session and stale roots; current Codex cwd wins.'
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
}
