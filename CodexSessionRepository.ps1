# Conversation-specific, read-only local Git discovery. Requires Get-RepositoryRoot from CodexData.ps1.
# A conversation may use GitHub tools while its CLI working directory is
# outside Git. Look for a uniquely matching, verified local checkout only.
function Find-ReferencedSessionRepository {
    param([Parameter(Mandatory)]$Session,[string]$HomeDirectory=$HOME,
          [string]$CodexPreview=$null)
    if(-not (Test-Path -LiteralPath ([string]$Session.File) -PathType Leaf)){return $null}
    $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $remotes=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $remotePattern='(?i)(?:https?://github[.]com/|git@github[.]com:)(?<owner>[a-z0-9_.-]+)/(?<repo>[a-z0-9_.-]+)(?=[/?#\s"''\)]|$)'
    # The Codex App Server's thread/list preview comes from the selected
    # conversation, even when an on-disk rollout omits that user message.
    # Only a leading, explicit project heading may identify a remote alias.
    # Never interpret arbitrary prose or the abbreviated thread name as a repo.
    if($CodexPreview){
        $heading=[regex]::Match($CodexPreview,
            '(?m)^\s*#{1,3}\s+(?<name>[A-Za-z][A-Za-z0-9_.-]{2,79})(?=\s|$)')
        if($heading.Success){[void]$names.Add($heading.Groups['name'].Value)}
    }
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
                        $projectAliasMatch=$false
                        foreach($hit in [regex]::Matches($origin,$remotePattern)){
                            $remote=('{0}/{1}' -f $hit.Groups['owner'].Value,
                                ($hit.Groups['repo'].Value -replace '[.]git$',''))
                            if($remotes.Contains($remote)){$remoteMatch=$true}
                            # The checkout and GitHub repository can have different
                            # names. A user-authored project heading such as
                            # "AIVault" may identify "aivault-opensearch-ai-dev".
                            # Match whole leading components only, never loose
                            # substrings or short acronyms (e.g. AIV).
                            foreach($project in $names){
                                if($project.Length -lt 5){continue}
                                if($remote.Split('/')[-1] -match
                                    ('(?i)^'+[regex]::Escape($project)+'(?:[-_.]|$)')){
                                    $projectAliasMatch=$true
                                }
                            }
                        }
                        if($remoteMatch -or $names.Contains($identity) -or $projectAliasMatch){
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
