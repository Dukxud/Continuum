# Generic one-time Windows Task Scheduler adapter. No Codex or UI dependencies.
function Register-OneTimeTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,
          [Parameter(Mandatory)][datetime]$At,
          [Parameter(Mandatory)][string]$Executable,
          [Parameter(Mandatory)][string]$Arguments,
          [Parameter(Mandatory)][string]$WorkingDirectory,
          [string]$Description = '')
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,200}$') { throw 'Invalid one-time task name.' }
    # Convert an explicit UTC instant before comparing or creating a local trigger.
    # Unspecified DateTime values are accepted as already local wall-clock time.
    if ($At.Kind -eq [DateTimeKind]::Utc) { $At = $At.ToLocalTime() }
    if (-not (Test-Path -LiteralPath $Executable -PathType Leaf)) { throw 'Task executable missing.' }
    if (-not (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) { throw 'Task working directory missing.' }
    if ($At -le (Get-Date)) { throw 'A one-time task must be in the future.' }
    # Task Scheduler stores a local wall-clock boundary without an offset.
    # A repeated/absent hour cannot describe exactly one desired instant.
    if ([TimeZoneInfo]::Local.IsAmbiguousTime($At) -or [TimeZoneInfo]::Local.IsInvalidTime($At)) {
        throw 'The selected local time is ambiguous or nonexistent because of a daylight-saving time transition.'
    }
    $action = New-ScheduledTaskAction -Execute $Executable -Argument $Arguments -WorkingDirectory $WorkingDirectory
    $trigger = New-ScheduledTaskTrigger -Once -At $At
    $principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
    $registered = $false
    try {
        Register-ScheduledTask -TaskName $Name -Description $Description -Action $action -Trigger $trigger -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
        $registered = $true
        $saved = Get-ScheduledTask -TaskName $Name -ErrorAction Stop
        $foundTime = if ($saved.Triggers.Count -eq 1 -and $saved.Triggers[0].StartBoundary) {
            ([datetime]$saved.Triggers[0].StartBoundary).ToString('yyyy-MM-dd HH:mm')
        } else { '' }
        $issues = @()
        if ($saved.State -notin @('Ready','Running')) { $issues += "Task state: $($saved.State)" }
        if ($foundTime -ne $At.ToString('yyyy-MM-dd HH:mm')) { $issues += 'Incorrect task trigger time' }
        if ($saved.Actions.Count -ne 1 -or [string]$saved.Actions[0].Execute -ine $Executable) { $issues += 'Incorrect executable' }
        if ($saved.Actions.Count -ne 1 -or [string]$saved.Actions[0].Arguments -cne $Arguments) { $issues += 'Incorrect arguments' }
        if ($saved.Actions.Count -ne 1 -or [string]$saved.Actions[0].WorkingDirectory -ine $WorkingDirectory) { $issues += 'Incorrect working directory' }
        if ($saved.Principal.LogonType -ne 'Interactive') { $issues += 'Task must run in an interactive desktop session' }
        if ($issues.Count) { throw ('Task registration differs from request: ' + ($issues -join '; ')) }
    } catch {
        if ($registered) {
            try { Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop } catch {
                throw "Task registration validation failed; rollback also failed for '$Name': $($_.Exception.Message)"
            }
        }
        throw
    }
    return $Name
}
function Disable-OneTimeTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name)
    Disable-ScheduledTask -TaskName $Name -ErrorAction Stop | Out-Null
}
function Remove-OneTimeTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Name,
          [switch]$OnlyBeforeStart)
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,200}$') { throw 'Invalid one-time task name.' }
    if ($OnlyBeforeStart) {
        # Do not confuse unregistering a Windows task with cancelling a process
        # that is already running. Enforce the pre-start condition at the
        # mutation boundary, not from an asynchronously refreshed GUI list.
        $current = Get-ScheduledTask -TaskName $Name -ErrorAction Stop
        if ($current.State -ne 'Ready') {
            throw "Task '$Name' is '$($current.State)'; cannot safely cancel it before execution."
        }
        $triggers = @($current.Triggers | Where-Object { $_.StartBoundary })
        if ($triggers.Count -ne 1) { throw "Task '$Name' has no unambiguous one-time trigger." }
        $when = [datetime]$triggers[0].StartBoundary
        if ($when -le (Get-Date).AddSeconds(90)) {
            throw "Task '$Name' is too close to its trigger for safe cancellation; inspect its run status."
        }
        $info = Get-ScheduledTaskInfo -TaskName $Name -TaskPath $current.TaskPath -ErrorAction Stop
        if ([datetime]$info.LastRunTime -ge $when.AddYears(-1)) {
            throw "Task '$Name' has execution history; do not overwrite a real run with a cancellation outcome."
        }
    }
    Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction Stop | Out-Null
}
Export-ModuleMember -Function Register-OneTimeTask,Disable-OneTimeTask,Remove-OneTimeTask
