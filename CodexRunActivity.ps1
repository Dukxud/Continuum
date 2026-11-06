# Read-only progress summary from this Scheduler's own Codex JSON event stream.
# No execution, arbitrary file access, inferred completion percentage, or
# credential-bearing command/output text is exposed to the dashboard.
function Get-CodexRunActivity {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Directory,
          [Parameter(Mandatory)][string]$Name)

    $result=[ordered]@{
        Available=$false; Summary='Waiting for Codex events'
        Recent=@(); CompletedCommands=0; FileChanges=0
        LatestResponse=''; UpdatedAt=$null; StartedAt=$null; Timeline=@()
    }
    if($Name -cnotmatch '^CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}$'){
        return [pscustomobject]$result
    }
    $eventFile=Join-Path $Directory ($Name+'.jsonl')
    if(-not (Test-Path -LiteralPath $eventFile -PathType Leaf)){
        return [pscustomobject]$result
    }
    $reader=$null
    $stream=$null
    $recent=[Collections.Generic.List[string]]::new()
    $timeline=[Collections.Generic.List[object]]::new()
    try {
        # Live Codex sessions may still be writing. Read only the bounded tail,
        # with file-sharing compatible with an active Windows writer.
        $result.StartedAt=[DateTimeOffset]::new(
            ([IO.File]::GetCreationTimeUtc($eventFile))).ToUnixTimeSeconds()
        $stream=[IO.FileStream]::new($eventFile,[IO.FileMode]::Open,
            [IO.FileAccess]::Read,([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        $offset=[Math]::Max(0L,($stream.Length - 262144L))
        if($offset -gt 0){[void]$stream.Seek($offset,[IO.SeekOrigin]::Begin)}
        $reader=[IO.StreamReader]::new($stream,[Text.Encoding]::UTF8,$true,4096)
        if($offset -gt 0){[void]$reader.ReadLine()}
        while($null -ne ($line=$reader.ReadLine())){
            if($line.Length -gt 32768 -or $line -notmatch '"type"'){continue}
            try {$entry=$line | ConvertFrom-Json -ErrorAction Stop}
            catch {continue}  # The last JSONL line may still be incomplete.
            $kind=[string]$entry.type
            $item=$entry.item
            $itemType=if($item){[string]$item.type}else{''}
            $label=''
            switch($kind){
                'thread.started' {$label='Codex session started'}
                'turn.started' {$label='Codex turn started'}
                'turn.completed' {$label='Codex turn completed'}
                'turn.failed' {$label='Codex turn failed'}
                'error' {$label='Codex reported an error'}
                'item.started' {
                    switch($itemType){
                        'command_execution' {$label='Running command'}
                        'mcp_tool_call' {$label='Calling tool'}
                        'web_search' {$label='Searching the web'}
                        'file_change' {$label='Applying file changes'}
                        'agent_message' {$label='Preparing response'}
                        'reasoning' {$label='Reasoning'}
                    }
                }
                'item.completed' {
                    switch($itemType){
                        'command_execution' {
                            $result.CompletedCommands++
                            $exit=if($null -ne $item.exit_code){' (exit '+$item.exit_code+')'}else{''}
                            $label='Command finished'+$exit
                        }
                        'file_change' {
                            $result.FileChanges++
                            $label='File changes recorded'
                        }
                        'mcp_tool_call' {$label='Tool call completed'}
                        'web_search' {$label='Web search completed'}
                        'agent_message' {
                            $response=[regex]::Replace([string]$item.text,'[\p{Cc}\p{Cf}\s]+',' ').Trim()
                            if($response){
                                if($response.Length -gt 180){$response=$response.Substring(0,179).TrimEnd()+'…'}
                                $result.LatestResponse=$response
                                $label='Codex response updated'
                            }
                        }
                    }
                }
            }
            if($label){
                $result.Available=$true
                $result.Summary=$label
                $recent.Add($label)
                if($recent.Count -gt 3){$recent.RemoveAt(0)}
                # A timeline is a bounded list of milestones, not the noisy
                # command/reasoning starts. Never include command/output text.
                if($kind -cne 'item.started'){
                    $at=$null
                    if($entry.timestamp){
                        try{
                            $at=[DateTimeOffset]::Parse(
                                [string]$entry.timestamp,
                                [Globalization.CultureInfo]::InvariantCulture,
                                [Globalization.DateTimeStyles]::AssumeUniversal
                            ).ToUnixTimeSeconds()
                        }catch{}
                    }
                    $timeline.Add([pscustomobject]@{
                        Label=$label; Kind=$kind; At=$at
                    })
                    if($timeline.Count -gt 32){$timeline.RemoveAt(0)}
                }
            }
        }
        $result.Recent=@($recent.ToArray())
        $result.Timeline=@($timeline.ToArray())
        $result.UpdatedAt=[DateTimeOffset]::new(
            ([IO.File]::GetLastWriteTimeUtc($eventFile))).ToUnixTimeSeconds()
    } catch {
        $result.Available=$false
        $result.Summary='Activity stream temporarily unavailable'
        $result.Recent=@()
        $result.Timeline=@()
    } finally {
        if($reader){$reader.Dispose()}
        elseif($stream){$stream.Dispose()}
    }
    return [pscustomobject]$result
}
