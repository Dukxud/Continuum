# Windows Forms renderer smoke test: real pixels, preserved input state and paired actions.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'WinFormsEventGuard.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'CodexUiPixelTheme.ps1')
function Require($condition,[string]$message){if(-not $condition){throw $message}}
$form=[System.Windows.Forms.Form]::new()
$form.ClientSize=[System.Drawing.Size]::new(480,245)
try {
    $bounds=[System.Drawing.Rectangle]::new(12,20,430,48)
    $panel=Add-PixelBackplate -Parent $form -Name 'Repository' -Bounds $bounds -Fill '#E6F8F3' -Accent '#168E87'
    Require ($panel.Name -eq 'PixelField_Repository' -and -not $panel.TabStop) 'Field art must be decorative, not focusable.'
    $button=[System.Windows.Forms.Button]::new()
    $button.Bounds=[System.Drawing.Rectangle]::new(330,28,100,30)
    $button.Enabled=$false
    $form.Controls.Add($button)
    Set-PixelAction -Button $button -Accent '#168E87'
    Require (-not $button.Enabled) 'Styling re-enabled an unavailable action.'
    Require ($button.FlatStyle -eq [System.Windows.Forms.FlatStyle]::Flat) 'Theme action did not use its matching surface.'
    Require ($button.BackColor.ToArgb() -eq ([System.Drawing.ColorTranslator]::FromHtml('#DDE4EE')).ToArgb()) 'Disabled action must have a quiet neutral fill.'
    $card=[System.Windows.Forms.Panel]::new()
    $card.Bounds=[System.Drawing.Rectangle]::new(12,90,430,85)
    $form.Controls.Add($card)
    Set-PixelSurfaceStyle -Panel $card -Fill '#E7F8F2' -Accent '#219A74'
    $script:pixelTestClicks=0
    $button.Add_Click({$script:pixelTestClicks++})
    $form.Show()
    [System.Windows.Forms.Application]::DoEvents()
    $button.PerformClick()
    Require ($script:pixelTestClicks -eq 0) 'Disabled button incorrectly invoked its action.'
    $button.Enabled=$true
    Require ($button.BackColor.ToArgb() -eq ([System.Drawing.ColorTranslator]::FromHtml('#168E87')).ToArgb()) 'Enabling the action did not restore its accent.'
    $button.PerformClick()
    Require ($script:pixelTestClicks -eq 1) 'Themed button failed to invoke its original click action.'
    $button.Enabled=$false
    Require ($button.BackColor.ToArgb() -eq ([System.Drawing.ColorTranslator]::FromHtml('#DDE4EE')).ToArgb()) 'Disabled action regained a distracting bright fill.'
    $button.PerformClick()
    Require ($script:pixelTestClicks -eq 1) 'Re-disabled button invoked an extra action.'
    foreach($control in @($panel,$card)){
        $bitmap=[System.Drawing.Bitmap]::new($control.Width,$control.Height)
        try {
            $control.DrawToBitmap($bitmap,[System.Drawing.Rectangle]::new(0,0,$control.Width,$control.Height))
            Require ($bitmap.GetPixel(2,8).ToArgb() -ne $bitmap.GetPixel(30,8).ToArgb()) 'Pixel edge accent was not painted.'
            Require ($bitmap.GetPixel(50,8).ToArgb() -ne $bitmap.GetPixel(50,$control.Height-12).ToArgb()) 'Raised field must have real lighting depth.'
            Require ($bitmap.GetPixel($control.Width-8,4).ToArgb() -ne $bitmap.GetPixel($control.Width-24,4).ToArgb()) 'Corner socket detail was not painted.'
        }finally{$bitmap.Dispose()}
    }
    Require ($button.Left -gt $panel.Left -and $button.Right -lt $panel.Right) 'Action is not contained in its field group.'
    Write-Host 'Native pixel background, accent relationship, disabled action and painted surfaces PASS.'
}finally{$form.Dispose()}
Assert-NoUnhandledWinFormsErrors
