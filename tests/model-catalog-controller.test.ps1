# Independent model-selection controller behavior, no live Codex or app launcher.
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CodexUiState.ps1')
. (Join-Path $root 'CodexRunEngine.ps1')
. (Join-Path $root 'CodexUiSelection.ps1')
$script:ui=New-CodexUiState
$modelBox=[System.Windows.Forms.ComboBox]::new()
$effortBox=[System.Windows.Forms.ComboBox]::new()
$schedule=[System.Windows.Forms.Button]::new()
try {
    $models=@(
        [pscustomobject]@{id='gpt-test';name='Default';efforts=@('low','high');defaultEffort='high';isDefault=$true},
        [pscustomobject]@{id='other';name='Alternative';efforts=@('low');defaultEffort='low';isDefault=$false}
    )
    $snapshot=[pscustomobject]@{models=$models}
    $script:ui.Selection.preferredModelId='gpt-test'
    $script:ui.Selection.preferredEffort='high'
    Apply-CodexModelCatalog -Snapshot $snapshot
    if((Get-SelectedModel) -ne 'gpt-test' -or $effortBox.SelectedItem -ne 'high'){
        throw 'Model catalog lost the persisted model and its supported effort.'
    }
    if($schedule.Enabled){throw 'A model catalog alone must never authorize scheduling before usage identity is verified.'}

    $identity='workspace-sha256:'+('a'*64)
    $script:ui.Usage.usageSnapshot=[pscustomobject]@{model='gpt-test';accountId=$identity}
    $script:ui.Usage.usageSnapshotRequestedModel='gpt-test'
    Update-SchedulingEligibility
    if(-not $schedule.Enabled){throw 'Current matching verified quota identity must allow a supported model and effort.'}

    $script:ui.Usage.usageReadFailed=$true
    Update-SchedulingEligibility
    if($schedule.Enabled){throw 'Quota-read failure left scheduling enabled.'}
    Select-AvailableEfforts
    if($schedule.Enabled){throw 'Selecting effort re-enabled scheduling after quota-read failure.'}
    $script:ui.Usage.usageReadFailed=$false
    $script:ui.Usage.usageSnapshot.accountId='not-verified'
    Update-SchedulingEligibility
    if($schedule.Enabled){throw 'Unverified workspace identity was accepted.'}
    $script:ui.Usage.usageSnapshot.accountId=$identity
    Update-SchedulingEligibility
    if(-not $schedule.Enabled){throw 'Fresh verified identity did not restore scheduling.'}
    $alternative=@($modelBox.Items | Where-Object Id -eq 'other') | Select-Object -First 1
    $modelBox.SelectedItem=$alternative
    Select-AvailableEfforts
    if($schedule.Enabled){throw 'Switching models reused the previous model quota snapshot.'}
    $script:ui.Usage.usageSnapshot=[pscustomobject]@{model='other';accountId=$identity}
    $script:ui.Usage.usageSnapshotRequestedModel='other'
    Update-SchedulingEligibility
    if(-not $schedule.Enabled){throw 'A new matching quota snapshot did not restore scheduling.'}
    Apply-CodexModelCatalog -Snapshot $snapshot
    if((Get-SelectedModel) -ne 'other'){throw 'Refreshing a valid catalog must preserve an explicit current model.'}
    if(-not $schedule.Enabled){throw 'Catalog refresh discarded current verified authority.'}

    # A failed or empty catalog must revoke prior model/effort authority.
    Apply-CodexModelCatalog -Snapshot ([pscustomobject]@{models=@()})
    if($modelBox.Items.Count -ne 0 -or $effortBox.Items.Count -ne 0 -or $schedule.Enabled){
        throw 'Empty catalog left stale model and reasoning selections enabled.'
    }
    if($script:ui.Selection.updatingModels){throw 'Model-update guard remained active after catalog cleared.'}

    Apply-CodexModelCatalog -Snapshot ([pscustomobject]@{models=@([pscustomobject]@{
        id='no-effort';name='No supported effort';efforts=@();defaultEffort=$null;isDefault=$true
    })})
    if($schedule.Enabled){throw 'Model without an advertised effort must not be schedulable.'}
    if($script:ui.Selection.updatingModels){throw 'Model-update guard remained active after a missing-effort selection.'}
    Write-Host 'One schedule-eligibility authority: catalog, current identity, quota failure, model switch, empty catalog and unsupported efforts PASS.'
} finally {
    $modelBox.Dispose()
    $effortBox.Dispose()
    $schedule.Dispose()
}
