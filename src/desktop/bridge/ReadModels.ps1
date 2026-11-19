# Read-only projections for the Flutter JSON API. Context is supplied by the caller.

# Presentation-only labels: preserve the WinForms session reader and its
# full stable IDs, while making the Flutter chooser distinguish projects.
function Get-FlutterSessionChoices {
    param([Parameter(Mandatory)][string]$SourceDirectory,[string]$AppDirectory='',
          [switch]$IncludeActivity)
    $choices=@(Get-RecentCliSessions -SourceDirectory $SourceDirectory)
    $threads=@{}
    foreach($choice in $choices){
        if($choice.Metadata){$threads[[string]$choice.Id]=$choice.Metadata}
    }
    $missing=@($choices | Where-Object {-not $threads.ContainsKey([string]$_.Id)})
    if($IncludeActivity -and $missing.Count){
        # Use one metadata-only Codex App Server for all session titles.
        # This is optional presentation work, never a scheduling authority.
        try {
            $cli=Get-CodexCliEntry
            $helper=Join-Path $SourceDirectory 'src/backend/CodexUsage.js'
            if((Test-Path -LiteralPath $cli -PathType Leaf) -and
               (Test-Path -LiteralPath $helper -PathType Leaf)){
                $ids=@($missing | ForEach-Object { [string]$_.Id })
                $arguments=@($helper)+@(Get-CodexMetadataArguments -Entry $cli)+@('--thread-ids',($ids -join ','))
                $lines=@(& node.exe @arguments)
                if($LASTEXITCODE -eq 0 -and $lines.Count){
                    $reply=($lines | Select-Object -Last 1) |
                        ConvertFrom-Json -AsHashtable -ErrorAction Stop
                    if($reply.ok -eq $true -and $reply.threads -is [System.Collections.IDictionary]){
                        foreach($id in $reply.threads.Keys){$threads[$id]=$reply.threads[$id]}
                    }
                }
            }
        }catch{
            # Use local user activity or stable folder/time identity below.
        }
    }
    $rootCache=@{}
    foreach($session in $choices){
        try {
            $cwd=[string]$session.Cwd
            $root=$null
            if($AppDirectory){
                $root=Get-SavedSessionRepository -SessionId ([string]$session.Id) -AppDirectory $AppDirectory
            }
            if(-not [string]::IsNullOrWhiteSpace($cwd)){
                if(-not $rootCache.ContainsKey($cwd)){
                    $rootCache[$cwd]=Get-RepositoryRoot $cwd
                }
                if(-not $root){$root=$rootCache[$cwd]}
            }
            $folder=if($cwd){Split-Path -Leaf ($cwd.TrimEnd([char[]]@('/','\')))}else{'unknown folder'}
            $title=if($root){
                'Git: '+(Split-Path -Leaf ($root.TrimEnd([char[]]@('/','\'))))
            }else{'Outside Git: '+$folder}
            $when=if($session.UpdatedAt){[datetime]$session.UpdatedAt}
                elseif($session.File -and (Test-Path -LiteralPath $session.File -PathType Leaf)){
                    (Get-Item -LiteralPath $session.File -ErrorAction Stop).LastWriteTime
                }else{[datetime]::MinValue}
            $id=[string]$session.Id
            $date=$when.ToString('d MMM HH:mm',[Globalization.CultureInfo]::InvariantCulture)
            # Activity excerpts are optional. Never scan large live Codex
            # rollouts as part of the critical startup data load.
            $activity=$null
            if($IncludeActivity){
                $detail=if($threads.Contains($id)){$threads[$id]}else{$session.Metadata}
                if($detail -and $detail.name){
                    $activity=Format-CodexSessionTitle -Title ([string]$detail.name) -AllowShort
                }
                if(-not $activity -and $detail -and $detail.preview){
                    $activity=Format-CodexSessionTitle -Title ([string]$detail.preview) -AllowShort
                }
                if(-not $activity -and $session.File){
                    $activity=Get-CodexSessionActivity -SessionFile ([string]$session.File)
                }
            }
            $identity=('{0} | {1} | {2}' -f $title,$date,$id.Substring($id.Length-8))
            $session.Display=if($activity){$activity+' | '+$identity}else{$identity}
        }catch{
            # A disappearing/invalid session file must not hide the choice.
            # Its original reader label remains usable.
        }
        $session
    }
}
function Get-CodexPickerPreview {
    param([Parameter(Mandatory)][string]$SessionId, [Parameter(Mandatory)][string]$SourceDirectory)
    # Non-mutating metadata. This is optional and must never bypass Git
    # verification or a conflicting repository result.
    try {
        $cli=Get-CodexCliEntry
        $helper=Join-Path $SourceDirectory 'src/backend/CodexUsage.js'
        if(-not (Test-Path -LiteralPath $cli -PathType Leaf) -or
           -not (Test-Path -LiteralPath $helper -PathType Leaf)){return $null}
        $arguments=@($helper)+@(Get-CodexMetadataArguments -Entry $cli)+@('--thread-ids',$SessionId)
        $lines=@(& node.exe @arguments)
        if($LASTEXITCODE -ne 0 -or -not $lines.Count){return $null}
        $data=($lines | Select-Object -Last 1) | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if($data.ok -ne $true -or -not $data.threads.Contains($SessionId)){return $null}
        return [string]$data.threads[$SessionId].preview
    }catch{return $null}
}
function Get-FlutterHistory {
    param([Parameter(Mandatory)][string]$AppDirectory, [object[]]$Tasks=@())
    $recentTasks=@($Tasks)
    $records=@(Get-CodexRunHistory -Directory $AppDirectory -Limit 100)
    $known=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach($entry in $records){[void]$known.Add([string]$entry.Name)}
    $hidden=Get-HiddenCodexRunNames -Directory $AppDirectory
    foreach($task in $recentTasks){
        $name=[string]$task.Name
        if($task.Status -in @('Scheduled','Running') -or $known.Contains($name) -or $hidden.Contains($name)){continue}
        $records+= [pscustomobject]@{
            Name=$name;When=$task.When;Status=$task.Status;ExitCode=$null
            Attempt=$null;NextJob='';Message='Windows Task Scheduler record; no saved worker outcome available.'
        }
        [void]$known.Add($name)
    }
    return @($records | Sort-Object When -Descending)
}
# Only running Scheduler jobs expose their own event summaries. There
# are no extra processes or raw command/output disclosures in the poll.
function Get-FlutterRunActivities {
    param([Parameter(Mandatory)][string]$AppDirectory, [object[]]$Tasks=@())
    $activities=@{}
    foreach($task in @($Tasks | Where-Object { $_.Status -eq 'Running' } |
            Select-Object -First 8)){
        $name=[string]$task.Name
        if($name -cmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}$'){
            if($task.ExecutionMode -eq 'terminal'){
                # The TUI owns its real console; it does not emit the
                # background JSONL format. Never fabricate live events.
                $activities[$name]=@{
                    Available=$false
                    Summary='Native Codex terminal active — answer questions there'
                    Recent=@(); Timeline=@(); StartedAt=$null
                    UpdatedAt=$null; CompletedCommands=0; FileChanges=0
                }
            }else{
                $activities[$name]=Get-CodexRunActivity -Directory $AppDirectory -Name $name
            }
        }
    }
    return $activities
}
