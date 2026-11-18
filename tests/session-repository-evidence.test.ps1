# Regression coverage for repository evidence that survives long/modern rollouts.
# All paths and remotes are isolated fixtures. No Codex, network or task execution.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/backend/CodexData.ps1')

function Assert-True([bool]$Condition,[string]$Reason){if(-not $Condition){throw $Reason}}
function Normalize-Root([string]$Path){return $Path.Replace('\','/').TrimEnd('/')}
function Assert-Root($Found,[string]$Expected){
    Assert-True ($Found -and (Normalize-Root ([string]$Found.Root)) -ieq (Normalize-Root $Expected)) 'Expected the explicitly identified, Git-verified checkout.'
}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('session-evidence-'+[guid]::NewGuid().ToString('N'))
$failures=[Collections.Generic.List[string]]::new()
$passed=0
$noise='{"type":"event_msg","payload":{"type":"token_count"}}'

function New-Case([string]$Name){
    $base=Join-Path $fixture $Name
    $homePath=Join-Path $base 'home'
    $appPath=Join-Path $base 'app'
    [void](New-Item -ItemType Directory -Path $homePath,$appPath -Force)
    return [pscustomobject]@{Base=$base;Home=$homePath;App=$appPath;File=(Join-Path $base 'rollout.jsonl')}
}
function New-Repo([string]$Path,[string]$Remote='', [string]$RemoteName='origin'){
    [void](New-Item -ItemType Directory -Path $Path -Force)
    & git init -q -b main $Path
    if($LASTEXITCODE -ne 0){throw 'Git fixture initialization failed.'}
    if($Remote){
        & git -C $Path remote add $RemoteName $Remote
        if($LASTEXITCODE -ne 0){throw 'Git fixture remote setup failed.'}
    }
    return $Path
}
function New-Session($Case,[object[]]$Records){
    $id='00000000-0000-0000-0000-000000000001'
    $meta=@{type='session_meta';payload=@{id=$id;source='cli';cwd=$Case.Home}}
    $lines=@($meta | ConvertTo-Json -Depth 20 -Compress)
    $lines+=@(foreach($record in $Records){
        if($record -is [string]){$record}else{$record | ConvertTo-Json -Depth 20 -Compress}
    })
    [IO.File]::WriteAllLines($Case.File,[string[]]$lines,[Text.UTF8Encoding]::new($false))
    return [pscustomobject]@{Id=$id;Cwd=$Case.Home;File=$Case.File}
}
function User-Event([string]$Text){return @{type='event_msg';payload=@{type='user_message';message=$Text}}}
function User-Message([string]$Text){
    return @{type='response_item';payload=@{type='message';role='user';content=@(@{type='input_text';text=$Text})}}
}
function Completed-Item($Item,[string]$ThreadId='00000000-0000-0000-0000-000000000001'){
    return @{type='event_msg';payload=@{type='item_completed';thread_id=$ThreadId;turn_id='turn-1';started_at_ms=1;completed_at_ms=2;item=$Item}}
}
function Resolve-Case($Case,$Session,[string]$Preview=''){
    return Find-SessionRepository -Session $Session -AppDirectory $Case.App -CheckoutHome $Case.Home -CodexPreview $Preview
}
function Run-Case([string]$Name,[scriptblock]$Body){
    try{& $Body; $script:passed++; Write-Host "PASS $Name"}
    catch{$script:failures.Add($Name+': '+$_.Exception.Message);Write-Host "FAIL $Name — $($_.Exception.Message)"}
}

try{
    Run-Case 'existing event_msg URL remains supported' {
        $case=New-Case 'baseline'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/target-repository.git'
        $session=New-Session $case @((User-Event 'Review https://github.com/fixture/target-repository'))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'session metadata Git URL recovers a uniquely matching relocated checkout' {
        $case=New-Case 'metadata-remote'
        $repo=New-Repo (Join-Path $case.Home 'source/relocated-checkout') 'https://github.com/fixture/metadata-repository.git'
        $session=New-Session $case @($noise)
        $records=@(Get-Content -LiteralPath $case.File)
        $meta=$records[0]|ConvertFrom-Json
        $meta.payload|Add-Member -NotePropertyName git -NotePropertyValue @{repository_url='https://github.com/fixture/metadata-repository.git';branch='main'}
        $records[0]=$meta|ConvertTo-Json -Depth 20 -Compress
        [IO.File]::WriteAllLines($case.File,[string[]]$records,[Text.UTF8Encoding]::new($false))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'turn_context survives more than 800 newer records' {
        $case=New-Case 'old-context'
        $repo=New-Repo (Join-Path $case.Base 'checkout-outside-search-roots')
        $records=@(@{type='turn_context';payload=@{cwd=$repo}})+@(1..901|ForEach-Object{$noise})
        $session=New-Session $case $records
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'explicit repository evidence after the old 16000-line cutoff survives' {
        $case=New-Case 'long-middle'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/long-session-repository.git'
        $records=@(1..16010|ForEach-Object{$noise})+@((User-Event 'Review https://github.com/fixture/long-session-repository'))+@(1..901|ForEach-Object{$noise})
        $session=New-Session $case $records
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'response_item user message repository URL is discovery evidence' {
        $case=New-Case 'user-message'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/message-repository.git'
        $session=New-Session $case @((User-Message 'Review https://github.com/fixture/message-repository'))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    # Codex protocol TurnItem is tagged with PascalCase variants, while its
    # UserInput text parts and EventMsg discriminants are snake_case.
    # See codex-rs/protocol/src/items.rs, user_input.rs and rollout/src/list.rs.
    Run-Case 'paginated item_completed UserMessage retains repository evidence' {
        $case=New-Case 'completed-user'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/paginated-repository.git'
        $item=@{type='UserMessage';id='user-1';content=@(@{type='text';text='Review https://github.com/fixture/paginated-repository';text_elements=@()})}
        $session=New-Session $case @((Completed-Item $item))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'paginated CommandExecution cwd uses a local file URI' {
        $case=New-Case 'completed-command'
        $repo=New-Repo (Join-Path $case.Base 'outside-home/check out #one')
        $uri=[Uri]::new([IO.Path]::GetFullPath($repo),[UriKind]::Absolute).AbsoluteUri
        $item=@{type='CommandExecution';id='command-1';command=@('git','status','--short');cwd=$uri;parsed_cmd=@();source='agent';status='completed';aggregated_output='';exit_code=0}
        $session=New-Session $case @((Completed-Item $item))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'paginated McpToolCall arguments identify the referenced repository' {
        $case=New-Case 'completed-mcp'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/mcp-repository.git'
        $item=@{type='McpToolCall';id='mcp-1';server='github';tool='fetch_file';arguments=@{repository_full_name='fixture/mcp-repository';path='README.md'};status='completed';result=@{content=@()};error=$null}
        $session=New-Session $case @((Completed-Item $item))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'legacy execution event cwd remains explicit local repository evidence' {
        $case=New-Case 'legacy-execution'
        $repo=New-Repo (Join-Path $case.Base 'outside-home/checkout')
        $uri=[Uri]::new([IO.Path]::GetFullPath($repo),[UriKind]::Absolute).AbsoluteUri
        foreach($kind in @('exec_command_begin','exec_command_end')){
            $event=@{type='event_msg';payload=@{type=$kind;call_id='command-1';turn_id='turn-1';command=@('git','status','--short');cwd=$uri;parsed_cmd=@();source='agent';status='completed';aggregated_output='';exit_code=0}}
            $session=New-Session $case @($event)
            Assert-Root (Resolve-Case $case $session) $repo
        }
    }
    Run-Case 'legacy MCP invocation arguments retain repository identity' {
        $case=New-Case 'legacy-mcp'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/legacy-mcp.git'
        foreach($kind in @('mcp_tool_call_begin','mcp_tool_call_end')){
            $event=@{type='event_msg';payload=@{type=$kind;call_id='mcp-1';turn_id='turn-1';invocation=@{server='github';tool='fetch_file';arguments=@{repository_full_name='fixture/legacy-mcp';path='README.md'}}}}
            $session=New-Session $case @($event)
            Assert-Root (Resolve-Case $case $session) $repo
        }
    }
    Run-Case 'selected Codex preview retains an explicit repository URL' {
        $case=New-Case 'preview-url'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/preview-repository.git'
        $session=New-Session $case @($noise)
        Assert-Root (Resolve-Case $case $session 'Review https://github.com/fixture/preview-repository') $repo
    }
    Run-Case 'multiword project heading matches its whole repository name' {
        $case=New-Case 'multiword-heading'
        $repo=New-Repo (Join-Path $case.Home 'source/checkout') 'https://github.com/fixture/Black-Ignition.git'
        [void](New-Repo (Join-Path $case.Home 'source/other') 'https://github.com/fixture/Black-Foundry.git')
        $session=New-Session $case @((User-Event '# Black Ignition'))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'explicit remote identity can match a non-origin remote' {
        $case=New-Case 'upstream-remote'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/upstream-repository.git' 'upstream'
        $session=New-Session $case @((User-Event 'Review https://github.com/fixture/upstream-repository'))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'Git ssh URL and HTTPS reference identify the same repository' {
        $case=New-Case 'ssh-remote'
        $repo=New-Repo (Join-Path $case.Home 'source/different-folder') 'ssh://git@github.com/fixture/ssh-repository.git'
        $session=New-Session $case @((User-Event 'Review https://github.com/fixture/ssh-repository'))
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Run-Case 'two local checkouts for the same remote remain ambiguous' {
        $case=New-Case 'ambiguous'
        [void](New-Repo (Join-Path $case.Home 'source/one') 'https://github.com/fixture/shared-repository.git')
        [void](New-Repo (Join-Path $case.Home 'repos/two') 'https://github.com/fixture/shared-repository.git')
        $session=New-Session $case @((User-Event 'Review https://github.com/fixture/shared-repository'))
        $found=Resolve-Case $case $session
        Assert-True ($found -and -not $found.Root -and @($found.Candidates).Count -eq 2 -and @($found.AlternativeRoots).Count -eq 2) 'Duplicate matching checkouts must require an explicit selection.'
    }
    Run-Case 'assistant prose and malformed rollout text cannot select a checkout' {
        $case=New-Case 'untrusted'
        [void](New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/untrusted-repository.git')
        $message=@{type='response_item';payload=@{type='message';role='assistant';content=@(@{type='output_text';text='Review https://github.com/fixture/untrusted-repository'})}}
        $agent=@{type='AgentMessage';id='agent-1';content=@(@{type='Text';text='Review https://github.com/fixture/untrusted-repository'})}
        $tool=@{type='McpToolCall';id='mcp-1';server='fixture';tool='search';arguments=@{query='example'};status='completed';result=@{content=@(@{type='text';text='Review https://github.com/fixture/untrusted-repository'})}}
        $session=New-Session $case @($message,(Completed-Item $agent),(Completed-Item $tool),'not-json https://github.com/fixture/untrusted-repository')
        Assert-True ($null -eq (Resolve-Case $case $session)) 'Untrusted or malformed prose became repository authority.'
    }
    Run-Case 'completed item from another thread cannot supply repository evidence' {
        $case=New-Case 'different-thread'
        [void](New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/different-thread.git')
        $item=@{type='UserMessage';id='user-1';content=@(@{type='text';text='Review https://github.com/fixture/different-thread';text_elements=@()})}
        $session=New-Session $case @((Completed-Item $item '00000000-0000-0000-0000-000000000002'))
        Assert-True ($null -eq (Resolve-Case $case $session)) 'Evidence from another thread selected this conversation repository.'
    }
    Run-Case 'mismatched session header stops later unattributed evidence' {
        $case=New-Case 'different-header'
        [void](New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/different-header.git')
        $session=New-Session $case @((User-Event 'Review https://github.com/fixture/different-header'))
        $session.Id='00000000-0000-0000-0000-000000000002'
        $found=Resolve-Case $case $session
        Assert-True ($found -and $found.Incomplete -and -not $found.Root) 'A mismatched header allowed later records to resolve another session.'
    }
    Run-Case 'code comments and string literals cannot impersonate tool arguments' {
        $case=New-Case 'code-text'
        [void](New-Repo (Join-Path $case.Home 'source/different-folder') 'https://github.com/fixture/quoted-repository.git')
        foreach($code in @("// repository_full_name: 'fixture/quoted-repository'",'text("repository_full_name: ''fixture/quoted-repository''");')){
            $event=@{type='response_item';payload=@{type='custom_tool_call';name='exec';input=$code}}
            $session=New-Session $case @($event)
            Assert-True ($null -eq (Resolve-Case $case $session)) 'Quoted code text became an actual repository invocation.'
        }
    }
    Run-Case 'snapshot with BOM and CRLF excludes concurrently appended records' {
        $case=New-Case 'snapshot'
        [IO.File]::WriteAllText($case.File,"first`r`nsecond`r`n",[Text.UTF8Encoding]::new($true))
        $reader=New-CodexRolloutSnapshotReader -Path $case.File
        try{
            [IO.File]::AppendAllText($case.File,"appended`r`n",[Text.UTF8Encoding]::new($false))
            $lines=[Collections.Generic.List[string]]::new()
            while($null -ne ($line=$reader.ReadLine())){$lines.Add($line)}
            Assert-True ($lines.Count -eq 2 -and $lines[0] -ceq 'first' -and $lines[1] -ceq 'second') 'Discovery read beyond its original byte snapshot.'
            Assert-True (-not $reader.StoppedReason) 'A complete original snapshot was marked incomplete.'
        }finally{$reader.Dispose()}
    }
    Run-Case 'oversized rollout record produces an incomplete result' {
        $case=New-Case 'oversized'
        $session=New-Session $case @((User-Event ('Review '+('x'*2048))))
        $evidence=Get-CodexSessionRepositoryEvidence -Session $session -MaximumLineCharacters 1024
        Assert-True (-not $evidence.Complete -and $evidence.Reason -match 'size limit') 'An oversized record was silently skipped or treated as a complete scan.'
    }
    Run-Case 'evidence deadline produces an incomplete result' {
        $case=New-Case 'deadline'
        $session=New-Session $case @(1..16010|ForEach-Object{$noise})
        $evidence=Get-CodexSessionRepositoryEvidence -Session $session -TimeoutMilliseconds 1
        Assert-True (-not $evidence.Complete -and $evidence.Reason -match 'time budget') 'A time-limited scan was reported as complete.'
    }
    Run-Case 'partial directory search cannot claim a unique checkout' {
        $case=New-Case 'directory-limit'
        [void](New-Repo (Join-Path $case.Home 'source/one') 'https://github.com/fixture/bounded-search.git')
        [void](New-Repo (Join-Path $case.Home 'repos/two') 'https://github.com/fixture/bounded-search.git')
        $session=New-Session $case @((User-Event 'Review https://github.com/fixture/bounded-search'))
        $found=Find-ReferencedSessionRepository -Session $session -HomeDirectory $case.Home -MaximumDirectories 1
        Assert-True ($found -and $found.Incomplete -and -not $found.Root) 'A partial directory search selected one checkout without seeing all candidates.'
    }
    Run-Case 'remote file URI cannot become a local path' {
        $case=New-Case 'remote-uri'
        $item=@{type='CommandExecution';id='command-1';command=@('git','status');cwd='file://not-local.invalid/share/checkout';parsed_cmd=@();source='agent';status='completed';exit_code=0}
        $session=New-Session $case @((Completed-Item $item))
        $evidence=Get-CodexSessionRepositoryEvidence -Session $session
        Assert-True ($evidence.Complete -and $evidence.Paths.Count -eq 1 -and $evidence.Paths.Contains($case.Home)) 'A remote file URI was added to local checkout evidence.'
    }
    Run-Case 'legacy migration never overwrites an existing explicit association' {
        $case=New-Case 'migration-preserves'
        $oldRepo=New-Repo (Join-Path $case.Base 'old-checkout')
        $chosenRepo=New-Repo (Join-Path $case.Base 'chosen-checkout')
        $id='00000000-0000-0000-0000-000000000001'
        Save-SessionRepositoryAssociation -SessionId $id -Repository $chosenRepo -AppDirectory $case.App
        $file=Join-Path $case.App ('session-repositories/'+$id+'.json')
        $before=[IO.File]::ReadAllText($file)
        Save-SessionRepositoryAssociation -SessionId $id -Repository $oldRepo -AppDirectory $case.App -OnlyIfMissing
        Assert-True ([IO.File]::ReadAllText($file) -ceq $before) 'Migration replaced an existing explicit selection.'
        Assert-Root ([pscustomobject]@{Root=(Get-SavedSessionRepository -SessionId $id -AppDirectory $case.App)}) $chosenRepo
    }
    Run-Case 'concurrent migrations preserve an explicit same-session selection' {
        $case=New-Case 'migration-race'
        $oldRepo=New-Repo (Join-Path $case.Base 'old-checkout')
        $chosenRepo=New-Repo (Join-Path $case.Base 'chosen-checkout')
        $id='00000000-0000-0000-0000-000000000001'
        $source=Join-Path (Split-Path -Parent $PSScriptRoot) 'src/backend/CodexData.ps1'
        $barrier=[Threading.Barrier]::new(4)
        $workers=[Collections.Generic.List[object]]::new()
        try{
            foreach($index in 0..3){
                $worker=[PowerShell]::Create()
                [void]$worker.AddScript({
                    param($Source,$Barrier,$Id,$Repository,$AppDirectory,$Migration)
                    $ErrorActionPreference='Stop'
                    . $Source
                    if(-not $Barrier.SignalAndWait(10000)){throw 'Concurrent fixture did not reach its barrier.'}
                    Save-SessionRepositoryAssociation -SessionId $Id -Repository $Repository -AppDirectory $AppDirectory -OnlyIfMissing:$Migration
                }).AddArgument($source).AddArgument($barrier).AddArgument($id).AddArgument($(if($index -eq 0){$chosenRepo}else{$oldRepo})).AddArgument($case.App).AddArgument(($index -ne 0))
                $workers.Add([pscustomobject]@{Shell=$worker;Operation=$worker.BeginInvoke()})
            }
            foreach($worker in $workers){
                [void]$worker.Shell.EndInvoke($worker.Operation)
                if($worker.Shell.HadErrors){throw ($worker.Shell.Streams.Error -join '; ')}
            }
            Assert-Root ([pscustomobject]@{Root=(Get-SavedSessionRepository -SessionId $id -AppDirectory $case.App)}) $chosenRepo
        }finally{
            foreach($worker in $workers){$worker.Shell.Dispose()}
            $barrier.Dispose()
        }
    }
    Run-Case 'explicit tool cwd finds a checkout outside conventional roots' {
        $case=New-Case 'tool-cwd'
        $repo=New-Repo (Join-Path $case.Base 'outside-home/checkout')
        $arguments=@{cwd=$repo;cmd='git status --short'}|ConvertTo-Json -Compress
        $event=@{type='response_item';payload=@{type='function_call';name='exec_command';arguments=$arguments}}
        $session=New-Session $case @($event)
        Assert-Root (Resolve-Case $case $session) $repo
    }
    Write-Host "Repository evidence: $passed passed; $($failures.Count) failed."
    if($failures.Count){throw ($failures -join "`n")}
}finally{
    if(Test-Path -LiteralPath $fixture){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
}
