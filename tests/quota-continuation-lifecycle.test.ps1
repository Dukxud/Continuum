# Isolated parent -> quota deferral -> registered child -> resumed execution.
# Uses a fake Codex App Server and an in-memory Task Scheduler; no real jobs.
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
. (Join-Path $source 'CodexRunEngine.ps1')
function Require($ok,[string]$why){if(-not $ok){throw $why}}

$temp=Join-Path ([IO.Path]::GetTempPath()) ('quota-lifecycle-'+[guid]::NewGuid().ToString('N'))
$originalPath=$env:PATH
$oldDeny=$env:CODEX_STUB_DENY
$oldMarker=$env:CODEX_STUB_EXECUTIONS
$startingDirectory=(Get-Location).Path
try {
    $bin=Join-Path $temp 'bin'
    $cliDir=Join-Path $bin 'node_modules/@openai/codex/bin'
    [void](New-Item -ItemType Directory -Path $cliDir -Force)
    @'
'use strict';
const fs = require('node:fs');
if (process.argv.includes('app-server')) {
  require('node:readline').createInterface({input:process.stdin}).on('line', line => {
    const m=JSON.parse(line);
    const send=result=>process.stdout.write(JSON.stringify({id:m.id,result})+'\n');
    if(m.method==='initialize')send({});
    if(m.method==='account/read')send({workspaceRouting:{chatgptAccountId:'acct-1'}});
    if(m.method==='model/list')send({data:[{model:'test-model',displayName:'Stub',supportedReasoningEfforts:[{reasoningEffort:'high'}],isDefault:true}],nextCursor:null});
    if(m.method==='account/rateLimits/read'){
      const denied=process.env.CODEX_STUB_DENY==='1';
      send({accountId:'acct-1',ordinaryUsageAllowed:!denied,rateLimits:{limitId:'test-model',normalModelSlug:'test-model',
        primary:{usedPercent:denied?100:0,resetsAt:Math.floor(Date.now()/1000)+3600,windowDurationMins:300}}});
    }
    if(m.method==='thread/read')send({thread:{id:m.params.threadId,cwd:process.cwd()}});
  });
} else if (process.argv.includes('exec')) {
  fs.appendFileSync(process.env.CODEX_STUB_EXECUTIONS,'executed\n');
  console.log(JSON.stringify({type:'turn.completed'}));
} else process.exitCode=2;
'@ | Set-Content -LiteralPath (Join-Path $cliDir 'codex.js') -Encoding utf8
    @'
@echo off
node "%~dp0node_modules\@openai\codex\bin\codex.js" %*
exit /b %errorlevel%
'@ | Set-Content -LiteralPath (Join-Path $bin 'codex.cmd') -Encoding ascii
    $env:PATH="$bin;$originalPath"
    $env:CODEX_STUB_EXECUTIONS=Join-Path $temp 'codex-executions.txt'

    $repo=Join-Path $temp 'workspace'
    [void](New-Item -ItemType Directory -Path $repo -Force)
    & git -C $repo init --quiet -b feature
    Require ($LASTEXITCODE -eq 0) 'Isolated Git checkout failed.'
    $repoRoot=([string](& git -C $repo rev-parse --show-toplevel)).Trim()
    $runtime=Publish-ImmutableRuntime -SourceDirectory $source -DestinationDirectory (Join-Path $temp 'runtimes') -RelativeFiles (Get-CodexRuntimeFiles)
    $id='workspace-sha256:'+([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes('codex-workspace-v1:acct-1')))).ToLowerInvariant()
    $parent='CodexResume-20261104-1420-1234abcd'
    $jobFile=Join-Path $temp ($parent+'.json')
    [pscustomobject]@{
        sessionId='00000000-0000-0000-0000-000000000001'
        repo=$repoRoot;branch='feature';model='test-model';effort='high'
        access='read-only';message='Inspect unfinished tests.'
        continuationPolicy=@{schema=1;mode='quota-only';maxContinuations=3}
        retryAttempt=0;accountId=$id;runtimeFingerprint=$runtime.Fingerprint
        log=(Join-Path $temp ($parent+'.log'))
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jobFile -Encoding utf8

    $script:tasks=@{}
    function Get-ScheduledTask {
        [CmdletBinding()]
        param([string]$TaskName)
        if($TaskName -eq 'CodexResume-*'){return @($script:tasks.Values)}
        if($script:tasks.ContainsKey($TaskName)){return $script:tasks[$TaskName]}
        return $null
    }
    function Register-OneTimeTask {
        [CmdletBinding()]
        param([string]$Name,[datetime]$At,[string]$Executable,[string]$Arguments,
              [string]$WorkingDirectory,[string]$Description)
        if($script:tasks.ContainsKey($Name)){throw 'Duplicate Scheduler registration.'}
        $script:tasks[$Name]=[pscustomobject]@{
            TaskName=$Name;State='Ready'
            Triggers=@([pscustomobject]@{StartBoundary=$At.ToString('o')})
            Actions=@([pscustomobject]@{Execute=$Executable;Arguments=$Arguments;WorkingDirectory=$WorkingDirectory})
        }
        return $Name
    }

    $env:CODEX_STUB_DENY='1'
    Require ((Invoke-CodexScheduledJob -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime.Directory) -eq 0) 'Quota-exhausted parent did not defer.'
    $parentOutcome=Read-JobOutcome -Path (Join-Path $temp ($parent+'.result.json'))
    Require ($parentOutcome.status -eq 'deferred' -and $script:tasks.Count -eq 1 -and $parentOutcome.nextJob) 'Parent missing one registered child.'
    Require (-not (Test-Path -LiteralPath $env:CODEX_STUB_EXECUTIONS)) 'Codex ran despite exhausted quota.'
    $childName=[string]$parentOutcome.nextJob
    $childFile=Join-Path $temp ($childName+'.json')
    Require (Test-Path -LiteralPath $childFile -PathType Leaf) 'Deferred child payload missing.'

    # Crash/replay reconciliation must not execute the parent or create a child.
    Require ((Invoke-CodexScheduledJob -JobFile $jobFile -AppDirectory $temp -RuntimeDirectory $runtime.Directory) -eq 0) 'Existing parent intent failed reconciliation.'
    Require ($script:tasks.Count -eq 1 -and -not (Test-Path -LiteralPath $env:CODEX_STUB_EXECUTIONS)) 'Parent replay duplicated execution.'

    $env:CODEX_STUB_DENY='0'
    Require ((Invoke-CodexScheduledJob -JobFile $childFile -AppDirectory $temp -RuntimeDirectory $runtime.Directory) -eq 0) 'Child failed after quota reset.'
    $childOutcome=Read-JobOutcome -Path (Join-Path $temp ($childName+'.result.json'))
    Require ($childOutcome.status -eq 'completed' -and $childOutcome.attempt -eq 1) 'Child completion not recorded.'
    Require (@(Get-Content -LiteralPath $env:CODEX_STUB_EXECUTIONS).Count -eq 1) 'Codex execution count differs from one.'

    Write-Host 'Quota lifecycle: deferred parent, one verified child, replay protection, successful resume PASS.' -ForegroundColor Green
}finally{
    Set-Location -LiteralPath $startingDirectory
    $env:PATH=$originalPath
    $env:CODEX_STUB_DENY=$oldDeny
    $env:CODEX_STUB_EXECUTIONS=$oldMarker
    if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue}
}
