Import-Module (Join-Path $PSScriptRoot 'components/GitRepository/GitRepository.psm1') -Force -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'components/SettingsStore/SettingsStore.psm1') -Force -ErrorAction Stop
. (Join-Path $PSScriptRoot 'CodexJobStore.ps1')
# Codex Resume Scheduler - local data readers (PowerShell 7).
# Used by GUI background jobs; the scheduled CLI worker does not import this file.
# No UI controls, timers, or persistent services.

function Get-RepositoryRoot {
    param([string]$Path)
    # App Server thread/read may return no CWD. An empty optional hint must
    # fall through to session-local Git evidence, not reach the generic
    # GitRepository module's mandatory Path parameter and abort discovery.
    if([string]::IsNullOrWhiteSpace($Path)){return $null}
    return Get-GitRepositoryRoot -Path $Path
}

function Get-RecentCliSessions {
    $sessionIdPattern = '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $sessionRoot = Join-Path $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }) 'sessions'
    $sessions = @()
    if (Test-Path -LiteralPath $sessionRoot -PathType Container) {
        $rollouts = @(Get-ChildItem -LiteralPath $sessionRoot -File -Recurse -Filter 'rollout-*.jsonl' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in $rollouts) {
            try {
                $line = Get-Content -LiteralPath $item.FullName -TotalCount 1 -ErrorAction Stop
                $meta = ($line | ConvertFrom-Json).payload
                # Both interactive CLI and non-interactive exec sessions can
                # be resumed by the scheduled "codex exec resume <id>" worker.
                # Do not include IDE, subagent or unknown session sources.
                if ($meta.source -notin @('cli','exec') -or $meta.id -notmatch $sessionIdPattern) { continue }
                if (-not $seen.Add([string]$meta.id)) { continue }
                $name = if ($meta.cwd) { Split-Path -Leaf ([string]$meta.cwd) } else { 'CLI session' }
                $sessions += [pscustomobject]@{
                    Id = [string]$meta.id
                    Cwd = [string]$meta.cwd
                    File = [string]$item.FullName
                    Display = ('{0} | {1:MM/dd HH:mm} | {2}' -f $name,$item.LastWriteTime,$meta.id)
                }
                if ($sessions.Count -ge 30) { break }
            } catch { continue }
        }
    }
    return $sessions
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
    if(-not (Test-Path -LiteralPath $SessionFile -PathType Leaf)){return $null}
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
    param([string]$SessionId, [string]$SourceFolder)
    if ($SessionId -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { return $null }
    try {
        $shim = (Get-Command codex.cmd -ErrorAction Stop).Source
        $cli = Join-Path (Split-Path -Parent $shim) 'node_modules\@openai\codex\bin\codex.js'
        $helper = Join-Path $SourceFolder 'CodexUsage.js'
        if (-not (Test-Path -LiteralPath $cli -PathType Leaf) -or -not (Test-Path -LiteralPath $helper -PathType Leaf)) { return $null }
        $lines = & node.exe $helper --cli-js $cli --thread-id $SessionId
        if ($LASTEXITCODE -ne 0 -or -not $lines) { return $null }
        $result = ($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
        if ($result.ok -eq $true -and $result.threadId -eq $SessionId -and $result.cwd -is [string]) {
            return ([string]$result.cwd).Trim()
        }
    } catch { }
    return $null
}

function Find-SessionRepository {
    param($Session, [string]$ReportedCwd = $null,
          [Parameter(Mandatory)][string]$AppDirectory)
    if (-not $Session) { return $null }
    $candidates = [System.Collections.Generic.List[string]]::new()
    $reportedRoot = Get-RepositoryRoot $ReportedCwd
    $direct = Get-RepositoryRoot ([string]$Session.Cwd)
    if ($direct) { $candidates.Add($direct) }

    # A prior schedule is evidence, not proof that it targeted the right checkout.
    if (Test-Path -LiteralPath $AppDirectory -PathType Container) {
        foreach ($saved in @(Get-CodexJobPayloadFiles -Directory $AppDirectory)) {
            try {
                $job = Get-Content -LiteralPath $saved.FullName -Raw -ErrorAction Stop | ConvertFrom-Json
                if ([string]$job.sessionId -ne [string]$Session.Id) { continue }
                $root = Get-RepositoryRoot ([string]$job.repo)
                if ($root -and $root.TrimEnd([char[]]@('/','\')) -ieq ([string]$job.repo).TrimEnd([char[]]@('/','\'))) {
                    $candidates.Add($root)
                }
            } catch { continue }
        }
    }

    # Use only structured cwd/workdir fields belonging to this session.
    # CLI sessions can move from their starting repository to an isolated worktree.
    if (Test-Path -LiteralPath $Session.File -PathType Leaf) {
        $contexts = [System.Collections.Generic.List[string]]::new()
        $toolDirs = [System.Collections.Generic.List[string]]::new()
        try {
            foreach ($line in @(Get-Content -LiteralPath $Session.File -Tail 800 -ErrorAction Stop)) {
                if ($line -notmatch '"(?:cwd|workdir|arguments)"') { continue }
                try {
                    $record = $line | ConvertFrom-Json -ErrorAction Stop
                    if ($record.type -eq 'turn_context' -and -not [string]::IsNullOrWhiteSpace([string]$record.payload.cwd)) {
                        $contexts.Add([string]$record.payload.cwd)
                    } elseif ($record.type -eq 'response_item' -and $record.payload.type -eq 'function_call' -and $record.payload.arguments) {
                        $arguments = $record.payload.arguments | ConvertFrom-Json -ErrorAction Stop
                        if ($arguments.workdir -is [string] -and $arguments.workdir) { $toolDirs.Add([string]$arguments.workdir) }
                    }
                } catch { continue }
            }
            foreach ($directory in @($contexts.ToArray() | Select-Object -Last 8) + @($toolDirs.ToArray() | Select-Object -Last 12)) {
                $root = Get-RepositoryRoot $directory
                if ($root) { $candidates.Add($root) }
            }
        } catch {
            # Preserve other evidence, but never infer a root from malformed rollout text.
        }
    }

    $roots = @($candidates.ToArray() + @($reportedRoot | Where-Object { $_ }) | Sort-Object -Unique)
    if ($reportedRoot) {
        # The reported cwd is authoritative for Codex's resume prompt. Preserve
        # competing roots for the user instead of ignoring them or clearing it.
        $alternatives = @($roots | Where-Object { $_ -ine $reportedRoot })
        return [pscustomobject]@{ Root = $reportedRoot; Source = 'Codex thread/read'; ReportedCwd = $ReportedCwd;
            Candidates = $roots; AlternativeRoots = $alternatives }
    }
    if ($roots.Count -eq 1) { return [pscustomobject]@{ Root = $roots[0]; Source = 'saved conversation fallback'; Candidates = $roots; AlternativeRoots = @() } }
    if ($roots.Count -gt 1) { return [pscustomobject]@{ Root = $null; Source = 'conflicting fallback worktrees'; Candidates = $roots; AlternativeRoots = $roots } }
    return Find-ReferencedSessionRepository -Session $Session
}


# A conversation may use GitHub tools while its CLI working directory is
# outside Git. Look for a uniquely matching, verified local checkout only.
function Find-ReferencedSessionRepository {
    param([Parameter(Mandatory)]$Session,[string]$HomeDirectory=$HOME)
    if(-not (Test-Path -LiteralPath ([string]$Session.File) -PathType Leaf)){return $null}
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $remotes=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $remotePattern='(?i)(?:https?://github[.]com/|git@github[.]com:)(?<owner>[a-z0-9_.-]+)/(?<repo>[a-z0-9_.-]+)(?=[/?#\s"''\)]|$)'
    $reader=$null
    try {
        # Keep active Codex rollouts readable while the CLI writes to them.
        $stream=[IO.FileStream]::new([string]$Session.File,[IO.FileMode]::Open,
            [IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $reader=[IO.StreamReader]::new($stream)
        $lineCount=0
        while($lineCount -lt 16000 -and $reader.BaseStream.Position -lt 33554432 -and
              $null -ne ($line=$reader.ReadLine())){
            $lineCount++
            if($line -notmatch '"(?:user_message|function_call)"'){continue}
            try {
                $event=$line | ConvertFrom-Json -ErrorAction Stop
                $content=''
                $userAuthored=$false
                if($event.type -eq 'event_msg' -and $event.payload.type -eq 'user_message'){
                    $content=[string]$event.payload.message
                    $userAuthored=$true
                }elseif($event.type -eq 'response_item' -and $event.payload.type -eq 'function_call'){
                    $content=[string]$event.payload.arguments
                    if($content){
                        try{
                            $arg=$content | ConvertFrom-Json -ErrorAction Stop
                            foreach($key in @('workdir','cwd')){
                                $value=[string]$arg.$key
                                if($value -and [IO.Path]::IsPathFullyQualified($value)){
                                    [void]$paths.Add($value)
                                }
                            }
                        }catch{}
                    }
                }else{continue}
                if(-not $content){continue}
                foreach($hit in [regex]::Matches($content,$remotePattern)){
                    $name=('{0}/{1}' -f $hit.Groups['owner'].Value,
                        ($hit.Groups['repo'].Value -replace '[.]git$',''))
                    [void]$remotes.Add($name)
                }
                foreach($hit in [regex]::Matches($content,
                    '(?i)"(?:repository_full_name|repo_full_name)"\s*:\s*"(?<owner>[a-z0-9_.-]+)/(?<repo>[a-z0-9_.-]+)"')){
                    [void]$remotes.Add(('{0}/{1}' -f $hit.Groups['owner'].Value,$hit.Groups['repo'].Value))
                }
                if($userAuthored){
                    foreach($hit in [regex]::Matches($content,
                        '(?m)^\s*#{1,3}\s+(?<name>[A-Za-z][A-Za-z0-9_.-]{2,79})(?=\s|$)')){
                        [void]$names.Add($hit.Groups['name'].Value)
                    }
                    foreach($hit in [regex]::Matches($content,
                        '(?i)\b(?:repo(?:sitory)?|project)\s+(?:named|called)\s+["'']?([A-Za-z][A-Za-z0-9_.-]{2,79})')){
                        [void]$names.Add($hit.Groups[1].Value)
                    }
                }
            }catch{continue}
        }
    }catch{return $null}finally{if($reader){$reader.Dispose()}}

    $roots=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($path in $paths){
        $root=Get-RepositoryRoot $path
        if($root){[void]$roots.Add($root)}
    }
    $direct=@($roots | Sort-Object -Unique)
    if($direct.Count -eq 1){
        return [pscustomobject]@{Root=$direct[0];Source='session tool working directory';
            Candidates=$direct;AlternativeRoots=@()}
    }
    if($direct.Count -gt 1){
        return [pscustomobject]@{Root=$null;Source='conflicting session tool directories';
            Candidates=$direct;AlternativeRoots=$direct}
    }
    if(-not $names.Count -and -not $remotes.Count){return $null}

    # Search only conventional local development locations, never the entire
    # disk. A name must be present in this session, and Git verifies the root.
    $locations=@($HomeDirectory,(Join-Path $HomeDirectory 'source'),
        (Join-Path $HomeDirectory 'repos'),(Join-Path $HomeDirectory 'projects'),
        (Join-Path $HomeDirectory 'dev'),(Join-Path $HomeDirectory 'Documents\GitHub'))
    $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $matchedRoots=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($location in $locations){
        if(-not (Test-Path -LiteralPath $location -PathType Container)){continue}
        $depth=if($location -eq $HomeDirectory){1}else{2}
        $frontier=@($location)
        for($level=0;$level -lt $depth;$level++){
            $next=[Collections.Generic.List[string]]::new()
            foreach($folder in $frontier){
                foreach($child in @(Get-ChildItem -LiteralPath $folder -Directory -ErrorAction SilentlyContinue |
                        Select-Object -First 250)){
                    if($child.Name -in @('.git','node_modules','.dart_tool','.venv','build','.cache')){continue}
                    $childPath=$child.FullName
                    if(-not $seen.Add($childPath)){continue}
                    if(Test-Path -LiteralPath (Join-Path $childPath '.git')){
                        $root=Get-RepositoryRoot $childPath
                        if(-not $root){continue}
                        $identity=[IO.Path]::GetFileName($root.TrimEnd([char[]]@('/','\')))
                        $origin=''
                        try{
                            $urls=@(& git -C $root remote get-url origin 2>$null)
                            if($LASTEXITCODE -eq 0 -and $urls.Count){$origin=[string]$urls[0]}
                        }catch{}
                        $remoteMatch=$false
                        foreach($hit in [regex]::Matches($origin,$remotePattern)){
                            $remote=('{0}/{1}' -f $hit.Groups['owner'].Value,
                                ($hit.Groups['repo'].Value -replace '[.]git$',''))
                            if($remotes.Contains($remote)){$remoteMatch=$true}
                        }
                        if($remoteMatch -or $names.Contains($identity)){
                            [void]$matchedRoots.Add($root)
                        }
                    }elseif($level -lt ($depth-1)){
                        $next.Add($childPath)
                    }
                }
            }
            $frontier=@($next.ToArray())
        }
    }
    $found=@($matchedRoots | Sort-Object -Unique)
    if($found.Count -eq 1){
        return [pscustomobject]@{Root=$found[0];Source='session-referenced local Git checkout';
            Candidates=$found;AlternativeRoots=@()}
    }
    if($found.Count -gt 1){
        return [pscustomobject]@{Root=$null;Source='conflicting session-referenced checkouts';
            Candidates=$found;AlternativeRoots=$found}
    }
    return $null
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
    if ($Outcome -and $Outcome.status -in @('completed','failed','blocked','deferred','cancelled')) {
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
        if (Test-Path -LiteralPath $json) {
            try {
                $job = Get-Content -LiteralPath $json -Raw | ConvertFrom-Json
                $description = "$($job.model) / $($job.effort) | $($job.access) | $($job.message)"
                $session = [string]$job.sessionId
                $repo = [string]$job.repo
                $model = [string]$job.model
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
    if (-not $Session -or -not (Test-Path -LiteralPath $Session.File -PathType Leaf)) { return $null }
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
