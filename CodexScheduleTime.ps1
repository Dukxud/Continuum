# Local wall-clock scheduling helpers. Pure, testable and independent of UI.
function Get-CodexSuggestedRunTime {
    param([datetime]$Now=(Get-Date))
    $candidate=$Now.AddMinutes(2)
    $rounded=[datetime]::new($candidate.Year,$candidate.Month,$candidate.Day,
        $candidate.Hour,$candidate.Minute,0)
    if($candidate -gt $rounded){$rounded=$rounded.AddMinutes(1)}
    return $rounded
}
function Step-CodexScheduledRunTime {
    param([Parameter(Mandatory)][datetime]$Time,
          [int]$Direction,
          [datetime]$Now=(Get-Date))
    if($Direction -notin @(-1,1)){throw 'Run time step must be exactly one minute.'}
    $candidate=$Time.AddMinutes($Direction)
    if($candidate -lt $Now.AddSeconds(30)){return $Time}
    return $candidate
}
