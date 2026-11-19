# Parse only conversation-owned repository evidence. Never execute rollout text.
# Supports legacy response items and Codex's item_completed projection.

function New-CodexRolloutSnapshotReader {
    param([Parameter(Mandatory)][string]$Path,
          [ValidateRange(256,16777216)][int]$MaximumLineCharacters=8388608,
          [ValidateRange(1,30000)][int]$TimeoutMilliseconds=12000)
    if(-not ('Continuum.RepositoryDiscovery.RolloutSnapshotReader' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
namespace Continuum.RepositoryDiscovery {
    // StreamReader may buffer ahead. Limit its underlying reads to the exact
    // initial byte length so CRLF, BOM and concurrent appends are handled once.
    internal sealed class SnapshotFileStream : FileStream {
        internal long SnapshotLength { get; private set; }
        internal SnapshotFileStream(string path) : base(path, FileMode.Open,
            FileAccess.Read, FileShare.ReadWrite | FileShare.Delete) {
            SnapshotLength = base.Length;
        }
        public override int Read(byte[] buffer, int offset, int count) {
            long remaining = SnapshotLength - Position;
            return remaining <= 0 ? 0 : base.Read(buffer, offset,
                (int)Math.Min(remaining, count));
        }
        public override int Read(Span<byte> buffer) {
            long remaining = SnapshotLength - Position;
            return remaining <= 0 ? 0 : base.Read(buffer.Slice(0,
                (int)Math.Min(remaining, buffer.Length)));
        }
    }
    public sealed class RolloutSnapshotReader : IDisposable {
        private readonly SnapshotFileStream stream;
        private readonly StreamReader reader;
        private readonly char[] buffer = new char[8192];
        private readonly Stopwatch clock = Stopwatch.StartNew();
        private readonly int maximumLineCharacters;
        private readonly int timeoutMilliseconds;
        private int position, count;
        private bool skipLineFeed;
        public string StoppedReason { get; private set; } = "";
        public long SnapshotLength { get { return stream.SnapshotLength; } }
        public RolloutSnapshotReader(string path, int maximumLineCharacters,
            int timeoutMilliseconds) {
            this.maximumLineCharacters = maximumLineCharacters;
            this.timeoutMilliseconds = timeoutMilliseconds;
            stream = new SnapshotFileStream(path);
            reader = new StreamReader(stream, new UTF8Encoding(false, true),
                true, 8192, false);
        }
        public string ReadLine() {
            if (StoppedReason.Length != 0) return null;
            var line = new StringBuilder();
            while (true) {
                if (clock.ElapsedMilliseconds >= timeoutMilliseconds) {
                    StoppedReason = "Repository evidence scan exceeded its time budget.";
                    return null;
                }
                if (position == count) {
                    count = reader.Read(buffer, 0, buffer.Length);
                    position = 0;
                    if (count == 0) {
                        if (stream.Position < stream.SnapshotLength)
                            StoppedReason = "The conversation rollout was truncated during discovery.";
                        return line.Length == 0 ? null : line.ToString();
                    }
                }
                if (skipLineFeed) {
                    skipLineFeed = false;
                    if (buffer[position] == '\n') {
                        position++;
                        continue;
                    }
                }
                int end = position;
                while (end < count && buffer[end] != '\r' && buffer[end] != '\n') end++;
                int length = end - position;
                if (line.Length > maximumLineCharacters - length) {
                    StoppedReason = "A conversation record exceeded the repository discovery size limit.";
                    return null;
                }
                line.Append(buffer, position, length);
                position = end;
                if (position < count) {
                    skipLineFeed = buffer[position++] == '\r';
                    return line.ToString();
                }
            }
        }
        public void Dispose() { reader.Dispose(); }
    }
}
'@ -ErrorAction Stop
    }
    return [Continuum.RepositoryDiscovery.RolloutSnapshotReader]::new(
        $Path,$MaximumLineCharacters,$TimeoutMilliseconds)
}

function ConvertTo-CodexLocalPath {
    param([AllowEmptyString()][string]$Value)
    if([string]::IsNullOrWhiteSpace($Value)){return $null}
    $path=$Value.Trim()
    if($path -match '^(?i)file:'){
        try{
            $uri=[uri]$path
            # Remote URI environments and network hosts are not local checkouts.
            if(-not $uri.IsAbsoluteUri -or -not $uri.IsFile -or
               ($uri.Host -and $uri.Host -ine 'localhost') -or $uri.Query -or $uri.Fragment){return $null}
            $path=$uri.LocalPath
        }catch{return $null}
    }
    # Codex PathUri reserves file:///%00/bad/path/<base64> for paths that
    # cannot be represented as ordinary local URIs. It is opaque metadata,
    # not a native path to pass to Test-Path or Git. A single such hint must
    # not abort discovery for the rest of this conversation.
    if($path.IndexOf([char]0) -ge 0){return $null}
    try{if(-not [IO.Path]::IsPathFullyQualified($path)){return $null}}
    catch{return $null}
    return $path
}

function Add-CodexRepositoryPath {
    param($Evidence,[string]$Value)
    $path=ConvertTo-CodexLocalPath $Value
    if($path){[void]$Evidence.Paths.Add($path)}
}

function Add-CodexRepositoryText {
    param($Evidence,[string]$Text,[switch]$UserAuthored)
    if(-not $Text){return}
    foreach($hit in [regex]::Matches($Text,
        '(?i)(?:https?://github[.]com/|git@github[.]com:|ssh://git@github[.]com/)(?<owner>[a-z0-9_.-]+)/(?<repo>[a-z0-9_.-]+)(?=[/?#\s"''\\),;:]|$)')){
        $slug=$hit.Groups['repo'].Value -replace '[.]git$',''
        [void]$Evidence.Remotes.Add(($hit.Groups['owner'].Value+'/'+$slug))
    }
    if(-not $UserAuthored){return}
    foreach($hit in [regex]::Matches($Text,'(?m)^\s*#{1,3}\s+(?<heading>[^\r\n]+)')){
        # Keep the entire project name, not "Black" from "Black Ignition".
        # Descriptive subtitles must be separated explicitly.
        $name=($hit.Groups['heading'].Value -split '\s+(?:[—–]|\s-\s|##)|\s+[-]\s+|:\s+',2)[0].Trim()
        if($name -match '^[A-Za-z][A-Za-z0-9_. -]{2,79}$'){
            [void]$Evidence.Names.Add(($name -replace '\s+','-'))
        }
    }
    foreach($hit in [regex]::Matches($Text,
        '(?i)\b(?:repo(?:sitory)?|project)\s+(?:named|called)\s+(?:["''](?<name>[A-Za-z][A-Za-z0-9_. -]{2,79})["'']|(?<name>[A-Za-z][A-Za-z0-9_.-]{2,79}))')){
        [void]$Evidence.Names.Add(($hit.Groups['name'].Value.Trim() -replace '\s+','-'))
    }
}

function Add-CodexRepositoryArguments {
    param($Evidence,$Arguments,[int]$Depth=0)
    if($null -eq $Arguments -or $Depth -gt 12){return}
    if($Arguments -is [string]){
        try{
            $parsed=ConvertFrom-Json -InputObject $Arguments -AsHashtable -ErrorAction Stop
            if($parsed -isnot [string]){Add-CodexRepositoryArguments $Evidence $parsed ($Depth+1);return}
        }catch{}
        # Arbitrary code may contain comments, string literals or quoted tool
        # output. Only structured arguments and completed tool events identify
        # an actual invocation; never infer it with a regex over source code.
        return
    }
    if($Arguments -is [System.Collections.IDictionary]){
        foreach($key in @('cwd','workdir','working_directory')){
            if($Arguments[$key] -is [string]){Add-CodexRepositoryPath $Evidence $Arguments[$key]}
        }
        foreach($key in @('repository_full_name','repo_full_name','repository_name','repository','repo')){
            $value=$Arguments[$key]
            if($value -is [string] -and $value -match '^[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+$'){
                [void]$Evidence.Remotes.Add(($value -replace '[.]git$',''))
            }
        }
        if($Arguments.owner -is [string] -and $Arguments.repo -is [string] -and
           $Arguments.owner -match '^[a-zA-Z0-9_.-]+$' -and $Arguments.repo -match '^[a-zA-Z0-9_.-]+$'){
            [void]$Evidence.Remotes.Add(($Arguments.owner+'/'+($Arguments.repo -replace '[.]git$','')))
        }
        foreach($key in @('url','repository_url')){
            if($Arguments[$key] -is [string]){Add-CodexRepositoryText $Evidence $Arguments[$key]}
        }
        # Only structured tool-wrapper fields. Arbitrary file contents, output
        # and quoted documentation are not conversation checkout evidence.
        foreach($key in @('arguments','parameters','tool_uses','calls','code')){
            if($Arguments.Contains($key)){Add-CodexRepositoryArguments $Evidence $Arguments[$key] ($Depth+1)}
        }
    }elseif($Arguments -is [System.Collections.IEnumerable]){
        foreach($item in $Arguments){Add-CodexRepositoryArguments $Evidence $item ($Depth+1)}
    }
}

function Add-CodexUserContent {
    param($Evidence,$Content)
    foreach($part in @($Content)){
        if($part -is [System.Collections.IDictionary] -and
           $part.type -in @('text','input_text') -and $part.text -is [string]){
            Add-CodexRepositoryText $Evidence $part.text -UserAuthored
        }
    }
}

function Get-CodexSessionRepositoryEvidence {
    param([Parameter(Mandatory)]$Session,[string]$CodexPreview='',
          [string]$ReportedRepositoryUrl='',
          [ValidateRange(256,16777216)][int]$MaximumLineCharacters=8388608,
          [ValidateRange(1,30000)][int]$TimeoutMilliseconds=12000)
    $evidence=[pscustomobject]@{
        Paths=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        Names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        Remotes=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        Complete=$true; Lines=0; Reason=''; Model=$null
    }
    # The exact-ID server preview is useful even for compressed/forked rollouts.
    Add-CodexRepositoryText $evidence $CodexPreview -UserAuthored
    Add-CodexRepositoryText $evidence $ReportedRepositoryUrl
    if(-not $Session.File -or -not (Test-Path -LiteralPath ([string]$Session.File) -PathType Leaf) -or
       [string]$Session.File -match '[.]zst$'){return $evidence}
    $reader=$null
    try{
        $reader=New-CodexRolloutSnapshotReader -Path ([string]$Session.File) -MaximumLineCharacters $MaximumLineCharacters -TimeoutMilliseconds $TimeoutMilliseconds
        # Stream the selected rollout through its original end. There is no
        # head/tail gap. Oversized records and timeouts stop with an explicit
        # incomplete result, never a supposedly unique root from a partial scan.
        while($null -ne ($line=$reader.ReadLine())){
            $evidence.Lines++
            if($line -notmatch '"(?:session_meta|turn_context|thread_settings_applied|user_message|item_completed|function_call|local_shell_call|custom_tool_call|message|exec_command_begin|exec_command_end|mcp_tool_call_begin|mcp_tool_call_end)"'){continue}
            try{$record=ConvertFrom-Json -InputObject $line -AsHashtable -ErrorAction Stop}catch{continue}
            $payload=$record.payload
            if($payload -isnot [System.Collections.IDictionary]){continue}
            switch([string]$record.type){
                'session_meta' {
                    if($payload.id -and [string]$payload.id -ine [string]$Session.Id){
                        $evidence.Complete=$false
                        $evidence.Reason='The conversation rollout identity changed during discovery.'
                        return $evidence
                    }
                    Add-CodexRepositoryPath $evidence ([string]$payload.cwd)
                    foreach($path in @($payload.runtime_workspace_roots)){Add-CodexRepositoryPath $evidence ([string]$path)}
                    if($payload.git){Add-CodexRepositoryText $evidence ([string]$payload.git.repository_url)}
                }
                'turn_context' {
                    Add-CodexRepositoryPath $evidence ([string]$payload.cwd)
                    if($payload.model -is [string]){$evidence.Model=[string]$payload.model}
                }
                'response_item' {
                    if($payload.type -eq 'message' -and $payload.role -eq 'user'){
                        Add-CodexUserContent $evidence $payload.content
                    }elseif($payload.type -eq 'function_call'){
                        Add-CodexRepositoryArguments $evidence $payload.arguments
                    }elseif($payload.type -eq 'local_shell_call' -and $payload.action.type -eq 'exec'){
                        # This is a persisted structured legacy response item;
                        # its working directory is separate from command text.
                        Add-CodexRepositoryPath $evidence ([string]$payload.action.working_directory)
                    }elseif($payload.type -eq 'custom_tool_call' -and
                            [string]$payload.name -match '(?:^|[._])(?:exec|exec_command|shell_command)$'){
                        Add-CodexRepositoryArguments $evidence $payload.input
                    }
                }
                'event_msg' {
                    if($payload.thread_id -and [string]$payload.thread_id -ine [string]$Session.Id){continue}
                    switch([string]$payload.type){
                        'thread_settings_applied' {
                            # A successful /cd is persisted before a new turn.
                            # The event ownership guard above also applies to
                            # copied snapshots retaining a foreign thread_id.
                            if($payload.thread_settings){
                                Add-CodexRepositoryPath $evidence ([string]$payload.thread_settings.cwd)
                                foreach($path in @($payload.thread_settings.runtime_workspace_roots)){
                                    Add-CodexRepositoryPath $evidence ([string]$path)
                                }
                            }
                        }
                        'user_message' {Add-CodexRepositoryText $evidence ([string]$payload.message) -UserAuthored}
                        'item_completed' {
                            $item=$payload.item
                            if($item -isnot [System.Collections.IDictionary]){continue}
                            switch([string]$item.type){
                                'UserMessage' {Add-CodexUserContent $evidence $item.content}
                                'CommandExecution' {Add-CodexRepositoryPath $evidence ([string]$item.cwd)}
                                'McpToolCall' {Add-CodexRepositoryArguments $evidence $item.arguments}
                                'DynamicToolCall' {Add-CodexRepositoryArguments $evidence $item.arguments}
                            }
                        }
                        {$_ -in @('exec_command_begin','exec_command_end')} {
                            Add-CodexRepositoryPath $evidence ([string]$payload.cwd)
                        }
                        {$_ -in @('mcp_tool_call_begin','mcp_tool_call_end')} {
                            if($payload.invocation){Add-CodexRepositoryArguments $evidence $payload.invocation.arguments}
                        }
                    }
                }
            }
        }
        if($reader.StoppedReason){
            $evidence.Complete=$false
            $evidence.Reason=$reader.StoppedReason
        }
    }catch{
        $evidence.Complete=$false
        $evidence.Reason='The selected conversation rollout could not be read.'
    }finally{if($reader){$reader.Dispose()}}
    return $evidence
}
