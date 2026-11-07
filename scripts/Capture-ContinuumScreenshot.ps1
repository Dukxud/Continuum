# Captures a chosen visible Windows top-level window to a PRIVATE local folder.
# Does not start Codex, alter scheduled tasks, upload, or redact content.
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('full','monitor','micro','appearance-colors','appearance-optics','shared-live','native-tui','shared-completed','recent-results')]
    [string]$Name,
    [string]$WindowTitleRegex='Continuum|Codex Resume Scheduler',
    [string]$OutputDirectory=(Join-Path $HOME 'Pictures\Continuum-QA')
)
$ErrorActionPreference='Stop'
if(-not $IsWindows){throw 'Windows desktop required'}
Add-Type -AssemblyName System.Drawing -ErrorAction Stop
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class ContinuumCaptureWindows {
  [StructLayout(LayoutKind.Sequential)] public struct RECT {public int Left,Top,Right,Bottom;}
  public delegate bool Callback(IntPtr hwnd, IntPtr state);
  [DllImport("user32.dll")] public static extern bool EnumWindows(Callback cb, IntPtr state);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder text, int max);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT rect);
  public static List<Tuple<IntPtr,string,RECT>> VisibleWindows() {
    var list=new List<Tuple<IntPtr,string,RECT>>();
    EnumWindows((h,s)=>{
      if(!IsWindowVisible(h))return true;
      var text=new StringBuilder(512);GetWindowText(h,text,text.Capacity);
      RECT r; if(text.Length>0 && GetWindowRect(h,out r) && r.Right>r.Left && r.Bottom>r.Top)
        list.Add(Tuple.Create(h,text.ToString(),r));
      return true;
    },IntPtr.Zero);
    return list;
  }
}
'@ -ErrorAction Stop
$windows=@([ContinuumCaptureWindows]::VisibleWindows() | Where-Object {
    $_.Item2 -match $WindowTitleRegex
})
if($windows.Count -ne 1){
    $names=if($windows.Count){($windows | ForEach-Object {$_.Item2}) -join '; '}else{'none'}
    throw "Expected exactly one visible matching window; found $($windows.Count): $names. Specify a narrower -WindowTitleRegex."
}
$w=$windows[0].Item3
$width=$w.Right-$w.Left
$height=$w.Bottom-$w.Top
if($width -lt 180 -or $height -lt 120 -or $width -gt 10000 -or $height -gt 10000){
    throw 'Window bounds are invalid for screenshot capture'
}
[void](New-Item -ItemType Directory -Path $OutputDirectory -Force)
$destination=Join-Path $OutputDirectory ("continuum-"+$Name+".png")
if(Test-Path -LiteralPath $destination){throw "Screenshot exists; refusing to overwrite: $destination"}
$bmp=[System.Drawing.Bitmap]::new($width,$height)
try {
    $g=[System.Drawing.Graphics]::FromImage($bmp)
    try { $g.CopyFromScreen($w.Left,$w.Top,0,0,$bmp.Size) }
    finally { $g.Dispose() }
    $bmp.Save($destination,[System.Drawing.Imaging.ImageFormat]::Png)
} finally { $bmp.Dispose() }
Write-Host "PRIVATE screenshot: $destination" -ForegroundColor Green
Write-Warning 'Review and redact all private content before uploading this image to a public repository.'
