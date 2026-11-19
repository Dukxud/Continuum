# Real Git / Codex PathUri regressions for optional hints that must not abort
# repository selection. No Codex process, network access or scheduled task.
# Codex PathUri deliberately serializes unrepresentable paths as
# file:///%00/bad/path/<base64>; it is not an ordinary local checkout URI.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/backend/CodexData.ps1')

function Require([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
function Normalize([string]$Path){return $Path.Replace('\','/').TrimEnd('/')}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('repository-runtime-paths-'+[guid]::NewGuid().ToString('N'))
$outside=Join-Path $fixture 'outside-git'
$app=Join-Path $fixture 'app'
$repo=Join-Path $fixture 'checkout'
$file=Join-Path $fixture 'rollout.jsonl'
$id='00000000-0000-0000-0000-000000000041'
# A real-shaped opaque PathUri: the suffix is base64url of original path bytes.
$opaque='file:///%00/bad/path/L3RtcC9hAGI'
$invalidNative=$fixture+[IO.Path]::DirectorySeparatorChar+'bad'+[char]0+'hint'
$failures=[Collections.Generic.List[string]]::new()
$passed=0
function Run-Case([string]$Name,[scriptblock]$Body){
    try{& $Body;$script:passed++;Write-Host "PASS $Name"}
    catch{$script:failures.Add($Name+': '+$_.Exception.Message);Write-Host "FAIL $Name — $($_.Exception.Message)"}
}
function Write-Rollout([object[]]$Records){
    $header=@{type='session_meta';payload=@{id=$id;source='cli';cwd=$outside}}
    @($header)+$Records|ForEach-Object{$_|ConvertTo-Json -Depth 15 -Compress}|
        Set-Content -LiteralPath $file -Encoding utf8
    return [pscustomobject]@{Id=$id;Cwd=$outside;File=$file}
}
function New-SettingsEvent([string]$Cwd,[string]$ThreadId=$id,[string[]]$WorkspaceRoots=@()){
    # ThreadSettingsSnapshot is retained in both Codex rollout history modes.
    # This matches the public protocol shape, including legacy optional ID.
    $payload=@{type='thread_settings_applied';thread_settings=@{
        model='gpt-5.2-codex';model_provider_id='openai';approval_policy='never';approvals_reviewer='user'
        permission_profile=@{type='disabled'};cwd=$Cwd;runtime_workspace_roots=$WorkspaceRoots
        collaboration_mode=@{mode='default';settings=@{
            model='gpt-5.2-codex';reasoning_effort='high';developer_instructions=$null}}
        disabled_plugin_ids=@()}}
    if($ThreadId){$payload.thread_id=$ThreadId}
    return @{type='event_msg';payload=$payload}
}
try{
    [void](New-Item -ItemType Directory -Path $outside,$app,$repo -Force)
    & git init -q -b main $repo
    Require ($LASTEXITCODE -eq 0) 'The disposable Git fixture could not be created.'

    Run-Case 'Codex opaque file URI does not become a native path' {
        $path=ConvertTo-CodexLocalPath $opaque
        Require ($null -eq $path) 'The opaque PathUri sentinel was decoded as a local checkout path.'
    }
    Run-Case 'invalid native NUL hint does not throw from Git root inspection' {
        $found=Get-RepositoryRoot $invalidNative
        Require ($null -eq $found) 'An invalid native hint unexpectedly identified a Git root.'
    }
    Run-Case 'opaque command CWD does not discard a valid alternative' {
        $command=@{type='event_msg';payload=@{type='item_completed';thread_id=$id;turn_id='turn-1'
            item=@{type='CommandExecution';id='command-1';command=@('git','status');cwd=$opaque
                parsed_cmd=@();source='agent';status='completed';aggregated_output='';exit_code=0}}}
        $session=Write-Rollout @($command,@{type='turn_context';payload=@{cwd=$repo}})
        $found=Find-SessionRepository -Session $session -AppDirectory $app -CheckoutHome $outside
        Require ($found -and (Normalize $found.Root) -eq (Normalize $repo)) 'Valid conversation evidence did not resolve after an opaque command hint.'
    }
    Run-Case 'invalid reported CWD does not discard valid conversation evidence' {
        $session=Write-Rollout @(@{type='turn_context';payload=@{cwd=$repo}})
        $found=Find-SessionRepository -Session $session -ReportedCwd $invalidNative -AppDirectory $app -CheckoutHome $outside
        Require ($found -and (Normalize $found.Root) -eq (Normalize $repo)) 'Valid conversation evidence did not resolve after an invalid reported hint.'
    }
    Run-Case 'persisted local_shell_call supplies its explicit working directory' {
        # ResponseItem::LocalShellCall and LocalShellExecAction are serialized
        # in snake_case and retained by Codex's rollout persistence policy.
        $call=@{type='response_item';payload=@{type='local_shell_call';call_id='shell-1';status='completed'
            action=@{type='exec';command=@('git','status');working_directory=$repo
                timeout_ms=1000;env=$null;user=$null}}}
        $session=Write-Rollout @($call)
        $found=Find-SessionRepository -Session $session -AppDirectory $app -CheckoutHome $outside
        Require ($found -and (Normalize $found.Root) -eq (Normalize $repo)) 'The persisted local shell working directory was ignored.'
    }
    Run-Case 'persisted thread settings supply the selected conversation CWD' {
        $session=Write-Rollout @((New-SettingsEvent -Cwd $repo))
        $found=Find-SessionRepository -Session $session -AppDirectory $app -CheckoutHome $outside
        Require ($found -and (Normalize $found.Root) -eq (Normalize $repo)) 'The persisted thread settings CWD was ignored.'
    }
    Run-Case 'legacy persisted thread settings may omit the owner ID' {
        $session=Write-Rollout @((New-SettingsEvent -Cwd $repo -ThreadId ''))
        $found=Find-SessionRepository -Session $session -AppDirectory $app -CheckoutHome $outside
        Require ($found -and (Normalize $found.Root) -eq (Normalize $repo)) 'Legacy settings without thread_id were ignored.'
    }
    Run-Case 'persisted thread settings supply explicit runtime workspace roots' {
        $session=Write-Rollout @((New-SettingsEvent -Cwd $outside -WorkspaceRoots @($repo)))
        $found=Find-SessionRepository -Session $session -AppDirectory $app -CheckoutHome $outside
        Require ($found -and (Normalize $found.Root) -eq (Normalize $repo)) 'The explicit runtime workspace root was ignored.'
    }
    Run-Case 'copied thread settings from another owner cannot supply a root' {
        $session=Write-Rollout @((New-SettingsEvent -Cwd $repo -WorkspaceRoots @($repo) -ThreadId '00000000-0000-0000-0000-000000000042'))
        $found=Find-SessionRepository -Session $session -AppDirectory $app -CheckoutHome $outside
        Require (-not $found) 'Foreign-owned persisted settings leaked a repository into this conversation.'
    }
    Run-Case 'selection reuses the supplied snapshot after the live file changes' {
        $session=Write-Rollout @(@{type='turn_context';payload=@{cwd=$repo;model='model-before-change'}})
        $evidence=Get-CodexSessionRepositoryEvidence -Session $session
        # A later file replacement would fail its identity check if reread.
        # Selection must consistently use the snapshot it already acquired.
        @{type='session_meta';payload=@{id='00000000-0000-0000-0000-000000000042';source='cli';cwd=$outside}}|
            ConvertTo-Json -Depth 10 -Compress|Set-Content -LiteralPath $file -Encoding utf8
        $found=Find-SessionRepository -Session $session -Evidence $evidence -AppDirectory $app -CheckoutHome $outside
        Require ($found -and (Normalize $found.Root) -eq (Normalize $repo)) 'Selection discarded its supplied snapshot or rescanned changed history.'
        Require ($evidence.Complete) 'The previously complete snapshot was changed by a second history read.'
    }
    Run-Case 'one evidence pass captures the latest turn-context model' {
        $session=Write-Rollout @(
            @{type='turn_context';payload=@{cwd=$outside;model='model-old'}},
            @{type='turn_context';payload=@{cwd=$repo;model='model-current'}},
            @{type='response_item';payload=@{type='message';role='assistant';content=@(
                @{type='output_text';text='{"type":"turn_context","payload":{"model":"model-spoof"}}'})}})
        $evidence=Get-CodexSessionRepositoryEvidence -Session $session
        Require ($evidence.Complete -and $evidence.Model -eq 'model-current') 'The latest structured model was not retained or quoted prose replaced it.'
        Require ($evidence.Paths.Contains($repo)) 'Model extraction lost repository evidence from the same pass.'
    }
    Run-Case 'an expired selection budget cannot return a partial fallback root' {
        $session=Write-Rollout @(@{type='turn_context';payload=@{cwd=$repo}})
        $evidence=Get-CodexSessionRepositoryEvidence -Session $session
        $clock=[Diagnostics.Stopwatch]::StartNew()
        [Threading.Thread]::Sleep(5)
        $found=Find-SessionRepository -Session $session -Evidence $evidence -LookupClock $clock -LookupTimeoutMilliseconds 1 -AppDirectory $app -CheckoutHome $outside
        Require ($found -and $found.Incomplete -and -not $found.Root) 'Expired discovery returned an automatic fallback root instead of an incomplete result.'
    }
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force}
}
Write-Host "Repository runtime paths: $passed passed; $($failures.Count) failed."
if($failures.Count){foreach($failure in $failures){Write-Host $failure};exit 1}
