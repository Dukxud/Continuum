# Shared guard for in-process WinForms acceptance tests.
# Windows Forms can show an unhandled-event dialog without failing pwsh.
# Convert such hidden test failures into a nonzero process exit.
Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
$script:winFormsEventErrors = [System.Collections.Generic.List[string]]::new()
$script:winFormsEventHandler = [System.Threading.ThreadExceptionEventHandler]{
    param($sender, [System.Threading.ThreadExceptionEventArgs]$eventArgs)
    $script:winFormsEventErrors.Add([string]$eventArgs.Exception.ToString())
}
[System.Windows.Forms.Application]::add_ThreadException($script:winFormsEventHandler)

function Assert-NoUnhandledWinFormsErrors {
    try {
        if ($script:winFormsEventErrors.Count -gt 0) {
            throw ('Unhandled Windows Forms event exceptions: ' + ($script:winFormsEventErrors -join '; '))
        }
    } finally {
        [System.Windows.Forms.Application]::remove_ThreadException($script:winFormsEventHandler)
    }
}
