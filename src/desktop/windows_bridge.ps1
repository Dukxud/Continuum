# Flutter Windows adapter. JSON-in/JSON-out; no UI globals or shared server.
# The existing verified worker owns all execution and account safety checks.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('load','labels','pending','usage','select','schedule','cancel','evidence','hide','save','browse','shared-status','shared-answer','shared-open')][string]$Action,
    [string]$Payload = ''
)
$ErrorActionPreference='Stop'
try {
    $source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $appDir=Join-Path $env:LOCALAPPDATA 'CodexResumeScheduler'
    # ConvertFrom-Json otherwise turns ISO strings into DateTime and loses the
    # exact wire format. PowerShell 7.5+ can explicitly preserve JSON strings.
    # Older PowerShell 7 versions retain the already-parsed local DateTime below.
    $request=if($Payload){
        $json=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Payload))
        if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){
            ConvertFrom-Json -InputObject $json -DateKind String -ErrorAction Stop
        }else{
            ConvertFrom-Json -InputObject $json -ErrorAction Stop
        }
    }else{[pscustomobject]@{}}
    . (Join-Path $source 'src/backend/CodexRunEngine.ps1')
    . (Join-Path $source 'src/backend/CodexData.ps1')
    . (Join-Path $source 'src/backend/CodexRunActivity.ps1')
    foreach ($commandFile in @('ReadModels.ps1', 'Scheduling.ps1', 'SharedSessions.ps1', 'Preferences.ps1')) {
        . (Join-Path $PSScriptRoot "bridge/$commandFile")
    }
    $result=$null
    switch($Action){
        'load' {
            $tasks=@(Get-UpcomingCodexTasks -AppDirectory $appDir)
            $result=@{
                sessions=@(Get-FlutterSessionChoices -SourceDirectory $source -AppDirectory $appDir)
                pending=$tasks
                activities=(Get-FlutterRunActivities -AppDirectory $appDir -Tasks $tasks)
                history=@(Get-FlutterHistory -AppDirectory $appDir -Tasks $tasks)
                settings=Read-CodexUiSettings $appDir
                logDirectory=$appDir
            }
        }
        'labels' {
            $result=@{sessions=@(Get-FlutterSessionChoices -SourceDirectory $source -AppDirectory $appDir -IncludeActivity)}
        }
        'pending' {
            $tasks=@(Get-UpcomingCodexTasks -AppDirectory $appDir)
            $result=@{
                pending=$tasks
                activities=(Get-FlutterRunActivities -AppDirectory $appDir -Tasks $tasks)
                history=@(Get-FlutterHistory -AppDirectory $appDir -Tasks $tasks)
            }
        }
        'usage' {
            $model=[string]$request.model
            if($model -and $model -notmatch '^[a-zA-Z0-9][a-zA-Z0-9._-]{0,100}$'){throw 'Invalid model identifier.'}
            $helper=Join-Path $source 'src/backend/CodexUsage.js'
            $cli=Get-CodexCliEntry
            $arguments=@($helper)+@(Get-CodexMetadataArguments -Entry $cli)
            if($model){$arguments+=@('--model',$model)}
            $lines=@(& node.exe @arguments)
            if($LASTEXITCODE -ne 0 -or -not $lines){throw 'Codex account and model query failed.'}
            $snapshot=($lines | Select-Object -Last 1) | ConvertFrom-Json -ErrorAction Stop
            if(-not $snapshot.ok){throw "Codex usage unavailable: $($snapshot.error)"}
            $result=$snapshot
        }
        'select' {
            $lookupClock=[Diagnostics.Stopwatch]::StartNew()
            $lookupBudget=40000
            if(-not (Get-Command git -ErrorAction SilentlyContinue)){throw 'Git is not available to Continuum. Install Git or restart Continuum after updating PATH.'}
            $id=[string]$request.sessionId
            $metadataFailure=$null
            $metadata=Get-CodexThreadMetadata -SessionId $id -SourceDirectory $source -Failure ([ref]$metadataFailure)
            $session=Get-VerifiedCliSession -SessionId $id -SourceDirectory $source -Metadata $metadata -MetadataQueried
            if(-not $session){
                $reason=if($metadataFailure){' '+$metadataFailure}else{''}
                throw ('Selected CLI conversation could not be verified.'+$reason)
            }
            $cwd=if($metadata){[string]$metadata.cwd}else{''}
            $preview=if($metadata){[string]$metadata.preview}else{''}
            $origin=if($metadata -and $metadata.gitInfo){[string]$metadata.gitInfo.originUrl}else{''}
            if(-not $preview -and -not $origin){
                # Compatibility fallback when an older server's exact read
                # omits preview. Obtain it before the single rollout scan,
                # instead of scanning the entire conversation a second time.
                $preview=Get-CodexPickerPreview -SourceDirectory $source -SessionId $id
            }
            $readBudget=[int][Math]::Max(1,[Math]::Min(12000,$lookupBudget-$lookupClock.ElapsedMilliseconds))
            $evidence=Get-CodexSessionRepositoryEvidence -Session $session -CodexPreview $preview -ReportedRepositoryUrl $origin -TimeoutMilliseconds $readBudget
            $found=Find-SessionRepository -Session $session -ReportedCwd $cwd -AppDirectory $appDir -Evidence $evidence -LookupClock $lookupClock -LookupTimeoutMilliseconds $lookupBudget
            if($request.repository){
                # A restored manual choice is revalidated, not silently
                # replaced by an automatic hint. Invalid paths fall through.
                $selected=Get-RepositoryRoot ([string]$request.repository)
                if($selected){
                    $alternatives=@($found.Candidates | Where-Object {$_ -and $_ -ine $selected})
                    $found=[pscustomobject]@{Root=$selected;Source='saved repository selection'
                        Candidates=@($selected)+$alternatives;AlternativeRoots=$alternatives}
                }
            }
            # Model association is optional and comes from the same bounded
            # snapshot. A second unbounded tail read must not delay the repo.
            $associatedModel=if($evidence.Complete){$evidence.Model}else{$null}
            $result=@{sessionId=$id;model=$associatedModel;found=$found}
        }
        'schedule' {
            $result=Register-FlutterSchedule -Request $request -SourceDirectory $source -AppDirectory $appDir
        }
        'shared-status' {
            $result=Get-FlutterSharedStatus -Request $request -SourceDirectory $source -AppDirectory $appDir
        }
        'shared-open' {
            $result=Open-FlutterSharedTerminal -Request $request -SourceDirectory $source -AppDirectory $appDir
        }
        'shared-answer' {
            $result=Send-FlutterSharedAnswer -Request $request -SourceDirectory $source -AppDirectory $appDir
        }
        'cancel' {
            $result=Remove-FlutterSchedule -Name ([string]$request.name) -AppDirectory $appDir
        }
        'evidence' {
            $name=[string]$request.name
            if($name -cnotmatch '^(?:CodexResume-[0-9]{8}-[0-9]{4}-[0-9a-fA-F]{8}|BP[0-9]+-Codex-(?:Resume|Test))$'){
                throw 'Invalid history identifier.'
            }
            $result=Get-CodexRunEvidence -Directory $appDir -Name $name
        }
        'hide' {
            $name=[string]$request.name
            Hide-CodexRunRecord -Directory $appDir -Name $name
            $result=@{hidden=$name}
        }
        'save' {
            $result=Save-FlutterPreferences -Request $request -AppDirectory $appDir
        }
        'browse' {
            Add-Type -AssemblyName System.Windows.Forms
            $dialog=[Windows.Forms.FolderBrowserDialog]::new()
            $dialog.Description='Select the Git repository for this conversation'
            try {
                $result=if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){
                    $root=Get-RepositoryRoot ([string]$dialog.SelectedPath)
                    if(-not $root){throw 'Select a folder inside an existing Git repository.'}
                    @{path=[string]$root}
                }else{@{path=''}}
            }finally{$dialog.Dispose()}
        }
    }
    [Console]::Out.WriteLine((@{ok=$true;result=$result} | ConvertTo-Json -Depth 20 -Compress))
} catch {
    [Console]::Out.WriteLine((@{ok=$false;error=$_.Exception.Message} | ConvertTo-Json -Depth 6 -Compress))
    exit 1
}
