Import-Module (Join-Path $PSScriptRoot '../../components/GitRepository/GitRepository.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot '../../components/SettingsStore/SettingsStore.psm1') -Force -ErrorAction Stop
. (Join-Path $PSScriptRoot 'CodexJobStore.ps1')
. (Join-Path $PSScriptRoot 'CodexSessionRepository.ps1')
# Codex Resume Scheduler - local data readers (PowerShell 7).
# Used by GUI background jobs; the scheduled CLI worker does not import this file.
# No UI controls, timers, or persistent services.

function Get-RepositoryRoot {
    param([string]$Path)
    # App Server thread/read may return no CWD. An empty optional hint must
    # fall through to session-local Git evidence, not reach the generic
    # GitRepository module's mandatory Path parameter and abort discovery.
    if([string]::IsNullOrWhiteSpace($Path)){return $null}
    $Path=$Path.Trim()
    if($Path.Length -ge 2 -and $Path.StartsWith('"') -and $Path.EndsWith('"')){
        $Path=$Path.Substring(1,$Path.Length-2)
    }
    return Get-GitRepositoryRoot -Path $Path
}

function Get-RecentCliSessions {
    param([string]$SourceDirectory='',[string]$SessionId='')
    $sessionIdPattern = '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $sessionRoot = Join-Path $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }) 'sessions'
    $sessions = @()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if($SourceDirectory -and -not $SessionId){
        # Codex owns compressed rollouts, fork ancestry and reverted paths.
        # Its read-only inventory supplements the plain-file offline fallback.
        $inventory=Invoke-CodexMetadataQuery -SourceDirectory $SourceDirectory -Arguments @('--sessions')
        if($inventory -and $inventory.ok -eq $true){
            foreach($thread in @($inventory.sessions)){
                if($thread.threadId -notmatch $sessionIdPattern -or $thread.source -notin @('cli','exec')){continue}
                if(-not $seen.Add([string]$thread.threadId)){continue}
                $when=if($thread.updatedAt){[DateTimeOffset]::FromUnixTimeSeconds([long]$thread.updatedAt).LocalDateTime}else{[datetime]::MinValue}
                $sessions += [pscustomobject]@{
                    Id=[string]$thread.threadId;Cwd=[string]$thread.cwd;File=[string]$thread.path
                    Source=[string]$thread.source;UpdatedAt=$when;Metadata=$thread
                    Display=('{0} | {1:MM/dd HH:mm} | {2}' -f [string]$thread.cwd,$when,$thread.threadId)
                }
            }
        }
    }
    if (Test-Path -LiteralPath $sessionRoot -PathType Container) {
        $rollouts = @(Get-ChildItem -LiteralPath $sessionRoot -File -Recurse -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $localCount=0
        foreach ($item in $rollouts) {
            try {
                $line = Get-Content -LiteralPath $item.FullName -TotalCount 1 -ErrorAction Stop
                $record = $line | ConvertFrom-Json -ErrorAction Stop
                if($record.type -ne 'session_meta'){continue}
                $meta = $record.payload
                # Both interactive CLI and non-interactive exec sessions can
                # be resumed by the scheduled "codex exec resume <id>" worker.
                # Do not include IDE, subagent or unknown session sources.
                if ($meta.source -notin @('cli','exec') -or $meta.id -notmatch $sessionIdPattern) { continue }
                if ($SessionId -and [string]$meta.id -ine $SessionId) { continue }
                if (-not $seen.Add([string]$meta.id)) { continue }
                $name = if ($meta.cwd) { Split-Path -Leaf ([string]$meta.cwd) } else { 'CLI session' }
                $sessions += [pscustomobject]@{
                    Id = [string]$meta.id
                    Cwd = [string]$meta.cwd
                    File = [string]$item.FullName
                    Source = [string]$meta.source
                    UpdatedAt = $item.LastWriteTime
                    Metadata = $null
                    Display = ('{0} | {1:MM/dd HH:mm} | {2}' -f $name,$item.LastWriteTime,$meta.id)
                }
                $localCount++
                if ($SessionId -or $localCount -ge 30) { break }
            } catch { continue }
        }
    }
    return @($sessions | Sort-Object UpdatedAt -Descending | Select-Object -First 30)
}

function Invoke-CodexMetadataQuery {
    param([Parameter(Mandatory)][string]$SourceDirectory,
          [Parameter(Mandatory)][string[]]$Arguments)
    try{
        $shim=(Get-Command codex.cmd -ErrorAction Stop).Source
        $cli=Join-Path (Split-Path -Parent $shim) 'node_modules/@openai/codex/bin/codex.js'
        $helper=Join-Path $SourceDirectory 'src/backend/CodexUsage.js'
        if(-not (Test-Path -LiteralPath $cli -PathType Leaf) -or
           -not (Test-Path -LiteralPath $helper -PathType Leaf)){return $null}
        $lines=@(& node.exe $helper --cli-js $cli @Arguments)
        if($LASTEXITCODE -ne 0 -or -not $lines.Count){return $null}
        $result=$lines[-1] | ConvertFrom-Json -ErrorAction Stop
        if($result.ok -eq $true){return $result}
    }catch{}
    return $null
}

function Get-CodexThreadMetadata {
    param([string]$SessionId,[Parameter(Mandatory)][string]$SourceDirectory)
    if($SessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){return $null}
    $result=Invoke-CodexMetadataQuery -SourceDirectory $SourceDirectory -Arguments @('--thread-id',$SessionId)
    if($result -and [string]$result.threadId -ieq $SessionId){return $result}
    return $null
}

function Get-VerifiedCliSession {
    param([string]$SessionId,[Parameter(Mandatory)][string]$SourceDirectory,
          $Metadata=$null,[switch]$MetadataQueried)
    if($SessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'){return $null}
    if(-not $MetadataQueried){$Metadata=Get-CodexThreadMetadata -SessionId $SessionId -SourceDirectory $SourceDirectory}
    if($Metadata -and [string]$Metadata.threadId -ieq $SessionId){
        if($Metadata.source -in @('cli','exec')){
            $file=[string]$Metadata.path
            if(-not $file){
                $local=@(Get-RecentCliSessions -SessionId $SessionId) | Select-Object -First 1
                if($local){$file=[string]$local.File}
            }
            return [pscustomobject]@{Id=$SessionId;Cwd=[string]$Metadata.cwd;File=$file
                Source=[string]$Metadata.source;Metadata=$Metadata}
        }
        # A positive unsupported source must not be overridden by stale files.
        if($Metadata.source){return $null}
    }
    # Older servers can omit source; an actual local CLI/exec header remains
    # verifiable even if the thread aged out of the 30-row display inventory.
    return @(Get-RecentCliSessions -SessionId $SessionId | Where-Object { $_.Id -ieq $SessionId }) | Select-Object -First 1
}


# Read only explicit user activity from the local Codex rollout. Never infer a
# conversation title from assistant output, tool calls, or injected context.
# Live sessions can be large, so inspect a bounded tail; fall back to the first
# prompt when an active turn has produced more than the sampled amount of output.
function Format-CodexSessionTitle {
    param([AllowEmptyString()][string]$Title,[switch]$AllowShort)
    $first=($Title -split '\r?\n' | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    } | Select-Object -First 1)
    $first=[regex]::Replace([string]$first,'[\p{Cc}\p{Cf}\s]+',' ').Trim()
    if(((-not $AllowShort) -and $first.Length -lt 5) -or
       $first -match '^(?:<[^>]*>|[^\p{L}\p{N}]+)$'){return $null}
    if($first.Length -gt 58){return $first.Substring(0,57).TrimEnd()+'…'}
    return $first
}

function Get-CodexSessionActivity {
    param([Parameter(Mandatory)][string]$SessionFile)
    if([string]::IsNullOrWhiteSpace($SessionFile) -or $SessionFile -match '[.]zst$' -or
       -not (Test-Path -LiteralPath $SessionFile -PathType Leaf)){return $null}
    foreach($sample in @('recent','initial')){
        try {
            $lines=if($sample -eq 'recent'){
                @(Get-Content -LiteralPath $SessionFile -Tail 160 -ErrorAction Stop)
            }else{
                @(Get-Content -LiteralPath $SessionFile -TotalCount 60 -ErrorAction Stop)
            }
        }catch{return $null}
        $last=$null
        foreach($line in $lines){
            if($line -notmatch '"type"\s*:\s*"(?:user_message|thread_goal_updated)"'){continue}
            try {
                $record=$line | ConvertFrom-Json -ErrorAction Stop
                if([string]$record.type -cne 'event_msg'){continue}
                $raw=switch([string]$record.payload.type){
                    'user_message' { [string]$record.payload.message }
                    'thread_goal_updated' { [string]$record.payload.goal.objective }
                    default { '' }
                }
                # A bare continuation instruction is not a useful subject.
                if($raw.Trim() -match '^(?i:resume|continue|go ahead|proceed|yes|ok|okay|do it)[.!\s]*$'){continue}
                $caption=Format-CodexSessionTitle $raw
                if($caption){$last=$caption}
            }catch{continue}
        }
        if($last){return $last}
    }
    return $null
}

# A read-only Codex App Server lookup supplies the same persisted cwd that Codex
# offers when resuming a conversation. A missing/error response is not evidence
# that the conversation lacks a repository; callers retain local fallbacks.
function Get-ReportedThreadDirectory {
    param([string]$SessionId,[string]$SourceFolder)
    $metadata=Get-CodexThreadMetadata -SessionId $SessionId -SourceDirectory $SourceFolder
    if($metadata){return [string]$metadata.cwd}
    return $null
}

function Find-SessionRepository {
    param($Session,[string]$ReportedCwd=$null,
          [Parameter(Mandatory)][string]$AppDirectory,
          [string]$CheckoutHome=$HOME,[string]$CodexPreview=$null,
          [string]$ReportedRepositoryUrl=$null)
    if(-not $Session){return $null}
    $candidates=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $reportedRoot=Get-RepositoryRoot $ReportedCwd
    $direct=Get-RepositoryRoot ([string]$Session.Cwd)
    if($direct){[void]$candidates.Add($direct)}
    $remembered=Get-SavedSessionRepository -SessionId ([string]$Session.Id) -AppDirectory $AppDirectory
    if($remembered){[void]$candidates.Add($remembered)}

    # Task payloads remain legacy evidence, but cancelling a task no longer
    # owns/deletes the durable conversation-to-checkout association.
    foreach($saved in @(Get-CodexJobPayloadFiles -Directory $AppDirectory)){
        try{
            $job=Get-Content -LiteralPath $saved.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
            if([string]$job.sessionId -ine [string]$Session.Id){continue}
            $root=Get-RepositoryRoot ([string]$job.repo)
            if($root -and $root.Replace('\','/').TrimEnd('/') -ieq ([string]$job.repo).Replace('\','/').TrimEnd('/')){
                [void]$candidates.Add($root)
            }
        }catch{continue}
    }

    $evidence=Get-CodexSessionRepositoryEvidence -Session $Session -CodexPreview $CodexPreview -ReportedRepositoryUrl $ReportedRepositoryUrl
    $verificationClock=[Diagnostics.Stopwatch]::StartNew()
    foreach($path in $evidence.Paths){
        if($verificationClock.Elapsed.TotalSeconds -gt 8){
            $evidence.Complete=$false
            $evidence.Reason='Repository path verification exceeded its time budget.'
            break
        }
        $root=Get-RepositoryRoot $path
        if($root){[void]$candidates.Add($root)}
    }
    if($reportedRoot){[void]$candidates.Add($reportedRoot)}
    $roots=@($candidates | Sort-Object -Unique)
    if($reportedRoot){
        return [pscustomobject]@{Root=$reportedRoot;Source='Codex thread/read';ReportedCwd=$ReportedCwd
            Candidates=$roots;AlternativeRoots=@($roots | Where-Object {$_ -ine $reportedRoot})}
    }
    if(-not $evidence.Complete){
        return [pscustomobject]@{Root=$null;Source=$evidence.Reason;Candidates=$roots;AlternativeRoots=$roots;Incomplete=$true}
    }
    if($roots.Count -eq 1){
        return [pscustomobject]@{Root=$roots[0];Source='saved conversation fallback';Candidates=$roots;AlternativeRoots=@()}
    }
    if($roots.Count -gt 1){
        return [pscustomobject]@{Root=$null;Source='conflicting fallback worktrees';Candidates=$roots;AlternativeRoots=$roots}
    }
    # Previously verified locations can be searched by this session's explicit
    # remote/name evidence without borrowing another session's association.
    $known=[Collections.Generic.List[string]]::new()
    $associationDirectory=Join-Path $AppDirectory 'session-repositories'
    if(Test-Path -LiteralPath $associationDirectory -PathType Container){
        foreach($file in @(Get-ChildItem -LiteralPath $associationDirectory -File -Filter '*.json')){
            $entry=Read-JsonSettings -Path $file.FullName
            if($entry -and $entry.schema -eq 1 -and $entry.root -is [string]){$known.Add($entry.root)}
        }
    }
    return Find-ReferencedSessionRepository -Session $Session -HomeDirectory $CheckoutHome -Evidence $evidence -KnownRoots $known.ToArray()
}


# Resolve what Windows actually knows, not what a countdown suggests.
# A zero Task Scheduler exit code without a worker outcome does NOT prove
# Codex completed the requested continuation.
function Get-CodexTaskDisplayState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$When,
        [Parameter(Mandatory)][string]$TaskState,
        $TaskInfo = $null,
        $Outcome = $null,
        [datetime]$Now = (Get-Date)
    )
    if ($TaskState -eq 'Running') { return 'Running' }
    if ($Outcome -and $Outcome.status -in @('completed','finished','failed','blocked','deferred','cancelled')) {
        return ([string]$Outcome.status).Substring(0,1).ToUpperInvariant() + ([string]$Outcome.status).Substring(1)
    }
    if ($When -gt $Now) { return 'Scheduled' }
    if ($TaskInfo) {
        $lastRun = [datetime]$TaskInfo.LastRunTime
        if ($lastRun.Year -ge 2000 -and $lastRun -ge $When.AddMinutes(-2)) {
            if ([long]$TaskInfo.LastTaskResult -eq 0) { return 'Ended (no result recorded)' }
            return "Failed (task exit $([long]$TaskInfo.LastTaskResult))"
        }
    }
    return 'Overdue (execution unconfirmed)'
}

function Get-UpcomingCodexTasks {
    param([Parameter(Mandatory)][string]$AppDirectory)
    $items = @()
    $now = Get-Date
    $recentSince = $now.AddHours(-48)
    # Only enumerate the Scheduler's named Windows tasks. Retain live and
    # recent executions so the interface can explain what happened.
    $tasks = @(Get-ScheduledTask -TaskName 'CodexResume-*' -ErrorAction SilentlyContinue) +
             @(Get-ScheduledTask -TaskName 'BP*-Codex-*' -ErrorAction SilentlyContinue)
    foreach ($task in $tasks) {
        if ($task.TaskName -notmatch '^(CodexResume-|BP\d+-Codex-(?:Resume|Test)$)') { continue }
        if ($task.State -eq 'Disabled') { continue }
        $trig = @($task.Triggers | Where-Object { $_.StartBoundary }) | Select-Object -First 1
        if (-not $trig) { continue }
        try { $when = [datetime]$trig.StartBoundary } catch { continue }
        if ($when -lt $recentSince -and $task.State -ne 'Running') { continue }
        $name = [string]$task.TaskName
        $json = Join-Path $AppDirectory ($name + '.json')
        $description = 'Existing scheduled task'
        $session = '-'
        $repo = '-'
        $model = ''
        $createdAt = $null
        $quotaContinuation = $false
        $executionMode = 'background'
        if (Test-Path -LiteralPath $json) {
            try {
                $job = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
                $description = "$($job.model) / $($job.effort) | $($job.access) | $($job.message)"
                $session = [string]$job.sessionId
                $repo = [string]$job.repo
                $model = [string]$job.model
                if([string]$job.executionMode -cin @('terminal','shared')){$executionMode=[string]$job.executionMode}
                if ([string]$job.createdAt -match '^\d{9,12}$') { $createdAt = [long]$job.createdAt }
                $quotaContinuation = $job.continuationPolicy.mode -ceq 'quota-only' -and
                    [string]$job.retryAttempt -match '^[1-3]$'
            } catch { $description = 'Scheduled task (job data unreadable)' }
        } elseif ($name -match '^BP\d+-Codex-') {
            # Older manually registered BP tasks remain visible, read-only.
            $repo = [string]$task.Actions[0].WorkingDirectory
            $match = [regex]::Match([string]$task.Actions[0].Arguments, '-File\s+"([^"]+)"')
            if ($match.Success -and (Test-Path -LiteralPath $match.Groups[1].Value -PathType Leaf)) {
                try {
                    $legacy = Get-Content -LiteralPath $match.Groups[1].Value -Raw
                    $sidMatch = [regex]::Match($legacy, 'resume\s+"([0-9a-fA-F-]{36})"')
                    if ($sidMatch.Success) { $session = $sidMatch.Groups[1].Value }
                    $effortMatch = [regex]::Match($legacy, 'model_reasoning_effort=(medium|high|xhigh)')
                    $effortName = if ($effortMatch.Success) { $effortMatch.Groups[1].Value } else { 'unspecified' }
                    $accessName = if ($legacy.Contains('--dangerously-bypass-approvals-and-sandbox')) { 'YOLO' } elseif ($legacy.Contains('--sandbox read-only')) { 'read-only' } else { 'other' }
                    $description = "$effortName | $accessName | existing BP task"
                } catch { }
            }
        }
        $taskInfo = $null
        if ($when -le $now -and $task.State -ne 'Running') {
            try {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $name -TaskPath $task.TaskPath -ErrorAction Stop
            } catch { }
        }
        $outcome = $null
        $resultPath = Join-Path $AppDirectory ($name + '.result.json')
        if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
            try { $outcome = Read-JobOutcome -Path $resultPath } catch { }
        }
        $runState = Get-CodexTaskDisplayState -When $when -TaskState ([string]$task.State) -TaskInfo $taskInfo -Outcome $outcome -Now $now
        $items += [pscustomobject]@{
            Name = $name; When = $when; Repo = $repo; Session = $session
            Description = $description; Model = $model; CreatedAt = $createdAt
            Status = $runState; QuotaContinuation = $quotaContinuation
            ExecutionMode = $executionMode
        }
    }
    # Active work must be shown FIRST; next scheduled jobs precede history.
    $active = @($items | Where-Object Status -eq 'Running' | Sort-Object When -Descending)
    $future = @($items | Where-Object Status -eq 'Scheduled' | Sort-Object When)
    $recent = @($items | Where-Object { $_.Status -notin @('Running','Scheduled') } | Sort-Object When -Descending)
    return @($active) + @($future) + @($recent)
}

function Read-SessionModel {
    param($Session)
    if (-not $Session -or [string]::IsNullOrWhiteSpace([string]$Session.File) -or
        [string]$Session.File -match '[.]zst$' -or -not (Test-Path -LiteralPath $Session.File -PathType Leaf)) { return $null }
    try {
        foreach ($line in @(Get-Content -LiteralPath $Session.File -Tail 600) | Select-Object -Last 600) {
            if ($line -notmatch '"model"') { continue }
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ($record.type -eq 'turn_context' -and $record.payload.model -is [string]) { $found = [string]$record.payload.model }
        }
        return $found
    } catch { return $null }
}

# App-specific facade over the reusable JSON settings store.
function Read-CodexUiSettings {
    param([string]$Directory)
    return Read-JsonSettings -Path (Join-Path $Directory 'settings.json')
}
function Write-CodexUiSettings {
    param([string]$Directory, $State)
    # The retained WinForms UI also writes drafts through this facade. Keep
    # its exact-ID associations durable without requiring a Flutter schema.
    $previous=Read-CodexUiSettings $Directory
    if($previous -and $previous.draft){
        Save-SessionRepositoryAssociation -SessionId ([string]$previous.draft.sessionId) -Repository ([string]$previous.draft.repo) -AppDirectory $Directory -OnlyIfMissing
    }
    if($State.draft){
        Save-SessionRepositoryAssociation -SessionId ([string]$State.draft.sessionId) -Repository ([string]$State.draft.repo) -AppDirectory $Directory
    }
    Write-JsonSettings -Path (Join-Path $Directory 'settings.json') -Value $State
}

function Get-RestoredRunTime {
    param([string]$Value, [datetime]$Now)
    $parsed = [datetime]::MinValue
    if ($Value -and [datetime]::TryParseExact($Value, 'yyyy-MM-ddTHH:mm:ss',
        [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$parsed)) {
        if ($parsed -gt $Now.AddSeconds(30)) { return $parsed }
    }
    return $null
}
