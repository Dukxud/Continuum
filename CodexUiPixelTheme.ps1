# Code-drawn pixel surfaces. Native controls retain all editing and keyboard behavior.
function Set-PixelSurfaceStyle {
    param([System.Windows.Forms.Panel]$Panel,[string]$Fill,[string]$Accent)
    $background=[System.Drawing.ColorTranslator]::FromHtml($Fill)
    $highlight=[System.Drawing.ColorTranslator]::FromHtml($Accent)
    $Panel.BackColor=$background
    $Panel.Add_Paint({
        param($sender,$e)
        $w=$sender.ClientSize.Width
        $h=$sender.ClientSize.Height
        if($w -lt 8 -or $h -lt 8){return}
        $e.Graphics.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::None
        $line=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(92,$highlight))
        $rail=[System.Drawing.SolidBrush]::new($highlight)
        $stitch=[System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(42,$highlight))
        $cutout=[System.Drawing.SolidBrush]::new($background)
        try {
            $e.Graphics.DrawRectangle($line,0,0,$w-1,$h-1)
            $e.Graphics.FillRectangle($rail,0,0,4,$h)
            for($y=7;$y -lt $h-3;$y+=12){$e.Graphics.FillRectangle($cutout,0,$y,4,4)}
            for($x=16;$x -lt $w-15;$x+=24){
                $e.Graphics.FillRectangle($stitch,$x,2,4,3)
                $e.Graphics.FillRectangle($stitch,$x+8,$h-5,3,3)
            }
            $e.Graphics.FillRectangle($rail,$w-9,2,4,4)
            $e.Graphics.FillRectangle($stitch,$w-14,7,4,4)
        }finally{$line.Dispose();$rail.Dispose();$stitch.Dispose();$cutout.Dispose()}
    }.GetNewClosure())
}

function Add-PixelBackplate {
    param([System.Windows.Forms.Control]$Parent,[string]$Name,
          [System.Drawing.Rectangle]$Bounds,[string]$Fill,[string]$Accent)
    $surface=[System.Windows.Forms.Panel]::new()
    $surface.Name="PixelField_$Name"
    $surface.AccessibleName="$Name field group"
    $surface.TabStop=$false
    $surface.Bounds=$Bounds
    Set-PixelSurfaceStyle -Panel $surface -Fill $Fill -Accent $Accent
    $Parent.Controls.Add($surface)
    $surface.SendToBack()
    return $surface
}

function Set-PixelAction {
    param([System.Windows.Forms.Button]$Button,[string]$Accent)
    $color=[System.Drawing.ColorTranslator]::FromHtml($Accent)
    $Button.UseVisualStyleBackColor=$false
    $Button.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
    $Button.FlatAppearance.BorderSize=1
    $Button.FlatAppearance.BorderColor=[System.Windows.Forms.ControlPaint]::Dark($color)
    $Button.FlatAppearance.MouseOverBackColor=[System.Windows.Forms.ControlPaint]::Light($color)
    $Button.FlatAppearance.MouseDownBackColor=[System.Windows.Forms.ControlPaint]::Dark($color)
    $Button.BackColor=$color
    $Button.ForeColor=[System.Drawing.Color]::White
    $Button.Cursor=[System.Windows.Forms.Cursors]::Hand
}

function Initialize-SchedulerPixelTheme {
    param([System.Windows.Forms.Form]$Form,[object[]]$Inputs,[hashtable]$Actions,
          [object[]]$UsageCards,[System.Windows.Forms.Label]$Heading,
          [System.Windows.Forms.Label]$UsageHeading,[System.Windows.Forms.Label]$PendingHeading)
    $Form.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#F0F5FB')
    $ink=[System.Drawing.ColorTranslator]::FromHtml('#253A58')
    foreach($label in @($Heading,$UsageHeading,$PendingHeading)){$label.ForeColor=$ink}
    foreach($input in $Inputs){
        $input.BackColor=[System.Drawing.ColorTranslator]::FromHtml('#FBFDFF')
        $input.ForeColor=$ink
    }
    # The entire input-action relationship shares one tinted, pixel-edged panel.
    $bands=@(
        @{Name='Conversation';Y=54;Height=46;Fill='#E8F1FF';Accent='#547FD2'}
        @{Name='Repository';Y=102;Height=44;Fill='#E6F8F3';Accent='#168E87'}
        @{Name='RunTime';Y=148;Height=44;Fill='#F1ECFF';Accent='#785AC5'}
        @{Name='Options';Y=194;Height=40;Fill='#FFF3E4';Accent='#C98737'}
        @{Name='Instruction';Y=238;Height=71;Fill='#E8F5FC';Accent='#2887B5'}
    )
    foreach($band in $bands){
        [void](Add-PixelBackplate -Parent $Form -Name $band.Name -Bounds ([System.Drawing.Rectangle]::new(10,$band.Y,898,$band.Height)) -Fill $band.Fill -Accent $band.Accent)
    }
    # Match label backgrounds to their shared field backplates, avoiding
    # opaque default-label rectangles cutting through the pixel texture.
    $labelBands=@{
        'Conversation'='#E8F1FF';'Repository root'='#E6F8F3'
        'Run at (local)'='#F1ECFF';'Model'='#FFF3E4'
        'Reasoning'='#FFF3E4';'Access'='#FFF3E4'
        'Instruction'='#E8F5FC'
    }
    foreach($control in $Form.Controls){
        if($control -is [System.Windows.Forms.Label] -and $labelBands.ContainsKey($control.Text)){
            $control.BackColor=[System.Drawing.ColorTranslator]::FromHtml($labelBands[$control.Text])
            $control.ForeColor=$ink
        }
    }
    $colors=@{
        Browse='#168E87';Minus='#785AC5';Plus='#785AC5'
        Now='#785AC5';Reset='#785AC5';Schedule='#2887B5'
        Cancel='#B86265';Logs='#547FD2';Recent='#466BAA'
    }
    foreach($key in $colors.Keys){Set-PixelAction -Button $Actions[$key] -Accent $colors[$key]}
    $Actions['Browse'].AccessibleName='Browse for the repository root'
    $Actions['Schedule'].AccessibleName='Schedule the instruction in this field'
    Set-PixelSurfaceStyle -Panel $UsageCards[0].Panel -Fill '#E7F8F2' -Accent '#219A74'
    Set-PixelSurfaceStyle -Panel $UsageCards[1].Panel -Fill '#E7F5FC' -Accent '#188FB5'
}
