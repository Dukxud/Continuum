# Local wall-clock scheduling helpers. Pure, testable and independent of UI.
function Get-CodexSuggestedRunTime {
    param([datetime]$Now=(Get-Date))
    $candidate=$Now.AddMinutes(2)
    $rounded=[datetime]::new($candidate.Year,$candidate.Month,$candidate.Day,
        $candidate.Hour,$candidate.Minute,0)
    if($candidate -gt $rounded){$rounded=$rounded.AddMinutes(1)}
    return $rounded
}
# Return the first selectable whole minute, honoring the same 30-second
# scheduling minimum as the registration command.
function Get-CodexEarliestRunTime {
    param([datetime]$Now=(Get-Date))
    $minimum=$Now.AddSeconds(30)
    $rounded=[datetime]::new($minimum.Year,$minimum.Month,$minimum.Day,
        $minimum.Hour,$minimum.Minute,0)
    if($minimum -gt $rounded){$rounded=$rounded.AddMinutes(1)}
    return $rounded
}
function Step-CodexScheduledRunTime {
    param([Parameter(Mandatory)][datetime]$Time,
          [int]$Direction,
          [datetime]$Now=(Get-Date))
    if($Direction -notin @(-1,1)){throw 'Run time step must be exactly one minute.'}
    $candidate=$Time.AddMinutes($Direction)
    $earliest=Get-CodexEarliestRunTime -Now $Now
    if($candidate -ge $earliest){return $candidate}
    # An expired manually selected time may be hours or days behind. Plus
    # recovers in one click, without requiring repeated one-minute presses.
    if($Direction -eq 1){return $earliest}
    return $Time
}
