# Validate presentation preferences before writing application settings.

function Save-FlutterPreferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Request,
        [Parameter(Mandatory)][string]$AppDirectory
    )

    $draft=$Request.draft
    if(-not $draft){throw 'No draft supplied.'}
    $access=[string]$draft.access
    if($access -cnotin @('workspace-write','read-only','yolo')){throw 'Invalid access mode.'}
    if($null -ne $draft.autoResumeOnLimit -and $draft.autoResumeOnLimit -isnot [bool]){throw 'Invalid saved quota continuation option.'}
    $executionMode=if($draft.executionMode){[string]$draft.executionMode}else{'background'}
    if($executionMode -cnotin @('background','terminal','shared')){throw 'Invalid saved execution mode.'}
    if($executionMode -in @('terminal','shared') -and $draft.autoResumeOnLimit -eq $true){
        throw 'Automatic quota continuation requires Background execution.'
    }
    foreach($flag in @('microMode','alwaysOnTop')){
        if($null -ne $Request.$flag -and $Request.$flag -isnot [bool]){throw "Invalid window preference: $flag"}
    }
    $previous=Read-CodexUiSettings $AppDirectory
    $safeDraft=[pscustomobject]@{
        sessionId=[string]$draft.sessionId;repo=[string]$draft.repo
        model=[string]$draft.model;effort=[string]$draft.effort
        access=$access;message=[string]$draft.message;runAt=[string]$draft.runAt
        executionMode=$executionMode
        autoResumeOnLimit=($draft.autoResumeOnLimit -eq $true)
    }
    $appearance=if($Request.barAppearance){$Request.barAppearance}elseif($previous){$previous.barAppearance}else{$null}
    if($appearance){
        $validColors=@('green','blue','cyan','violet','amber','red')
        foreach($kind in @('quota','weekly','time','working')){
            $color=[string]$appearance.$kind
            if($color -cnotin $validColors -and $color -cnotmatch '^#[0-9a-fA-F]{6}$'){
                throw "Invalid appearance color for $kind."
            }
        }
        foreach($kind in @('finish','lighting')){
            if($appearance.$kind -notin @(0,1,2)){throw "Invalid appearance $kind."}
        }
        if($appearance.shimmer -isnot [int] -and $appearance.shimmer -isnot [long]){throw 'Reflection strength must be integral.'}
        if([int]$appearance.shimmer -lt 0 -or [int]$appearance.shimmer -gt 200){throw 'Invalid reflection strength.'}
        if($appearance.speed -isnot [int] -and $appearance.speed -isnot [long]){throw 'Reflection speed must be integral.'}
        if([int]$appearance.speed -lt 25 -or [int]$appearance.speed -gt 300){throw 'Invalid reflection speed.'}
        if($appearance.aero -isnot [bool]){throw 'Invalid Aero Liquid setting.'}
    }
    # A saved draft is not the repository history. Preserve verified
    # associations by exact conversation ID when the operator changes threads.
    $sessionRepositories=@{}
    if($previous -and $previous.sessionRepositories){
        foreach($entry in $previous.sessionRepositories.PSObject.Properties){
            $id=[string]$entry.Name
            $path=[string]$entry.Value
            if($id -match '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -and
               $path -and [IO.Path]::IsPathFullyQualified($path)){
                $sessionRepositories[$id]=$path
            }
        }
    }
    # The previous draft may predate this new map. Migrate it on the first
    # save after upgrade, even when that save selects a different conversation.
    foreach($choice in @($previous.draft,$draft)){
        if(-not $choice){continue}
        $id=[string]$choice.sessionId
        $path=[string]$choice.repo
        if($id -notmatch '^[0-9a-fA-F]{8}-(?:[0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$' -or
           [string]::IsNullOrWhiteSpace($path)){continue}
        # Only a verified Git checkout becomes reusable evidence; incomplete
        # path edits may still be retained in the single current draft.
        $verified=Get-RepositoryRoot $path
        if($verified){$sessionRepositories[$id]=$verified}
    }
    $settings=[pscustomobject]@{
        version=1;lastAccess=$access
        sessionRepositories=$sessionRepositories
        compactMode=($Request.compactMode -eq $true -or $Request.microMode -eq $true)
        microMode=($Request.microMode -eq $true)
        alwaysOnTop=($Request.alwaysOnTop -eq $true)
        barAppearance=$appearance
        draft=$safeDraft
    }
    Write-CodexUiSettings -Directory $AppDirectory -State $settings
    return @{saved=$true}
}
