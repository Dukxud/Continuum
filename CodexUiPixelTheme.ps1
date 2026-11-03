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
        if($w -lt 18 -or $h -lt 18){return}
        $graphics=$e.Graphics
        $graphics.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::None

        # Light-catching top plane and a darker bottom edge make a shallow
        # raised surface; crisp pixels are reserved for its perimeter.
        $gradient=[System.Drawing.Drawing2D.LinearGradientBrush]::new(
            [System.Drawing.Rectangle]::new(0,0,$w,$h),
            [System.Windows.Forms.ControlPaint]::Light($background,[float].30),
            $background,[float]90)
        $border=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(124,$highlight))
        $topLine=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(185,[System.Drawing.Color]::White))
        $bottomLine=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(65,$highlight))
        $rail=[System.Drawing.SolidBrush]::new($highlight)
        $quiet=[System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(78,$highlight))
        $cutout=[System.Drawing.SolidBrush]::new($background)
        try{
            $graphics.FillRectangle($gradient,0,0,$w,$h)
            $graphics.DrawRectangle($border,0,0,$w-1,$h-1)
            $graphics.DrawLine($topLine,5,2,$w-16,2)
            $graphics.DrawLine($bottomLine,5,$h-3,$w-12,$h-3)

            # Stepped edge notch, like a tiny 8-bit socket.
            $graphics.FillRectangle($rail,0,0,4,$h)
            for($y=12;$y -lt $h-5;$y+=22){
                $graphics.FillRectangle($cutout,0,$y,4,5)
                $graphics.FillRectangle($quiet,5,$y+1,3,3)
            }
            $graphics.FillRectangle($rail,8,0,13,2)
            $graphics.FillRectangle($rail,$w-10,2,6,4)
            $graphics.FillRectangle($quiet,$w-15,7,5,4)
            # A few intentional pixel markers replace the old dotted border.
            for($x=27;$x -lt $w-20;$x+=116){
                $graphics.FillRectangle($quiet,$x,$h-5,4,2)
                $graphics.FillRectangle($quiet,$x+6,$h-5,2,2)
            }
        }finally{
            $gradient.Dispose()
            $border.Dispose()
            $topLine.Dispose()
            $bottomLine.Dispose()
            $rail.Dispose()
            $quiet.Dispose()
            $cutout.Dispose()
        }
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
    $Button.Add_Paint({
        param($sender,$e)
        if(-not $sender.Enabled -or $sender.Width -lt 16 -or $sender.Height -lt 12){return}
        $shine=[System.Drawing.Pen]::new([System.Drawing.Color]::FromArgb(100,[System.Drawing.Color]::White))
        $corner=[System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb(130,[System.Drawing.Color]::White))
        try{
            $e.Graphics.DrawLine($shine,4,2,$sender.Width-5,2)
            $e.Graphics.FillRectangle($corner,3,$sender.Height-7,3,3)
            $e.Graphics.FillRectangle($corner,$sender.Width-7,4,3,3)
        }finally{$shine.Dispose();$corner.Dispose()}
    })
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
