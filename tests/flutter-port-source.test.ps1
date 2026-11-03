# Source and boundary smoke checks without requiring Flutter on existing CI hosts.
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$folder=Join-Path $root 'flutter_port'
$bridge=Join-Path $folder 'windows_bridge.ps1'
$tokens=$null;$errors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($bridge,[ref]$tokens,[ref]$errors)
if(@($errors).Count){throw "Flutter bridge does not parse: $($errors[0].Message)"}
foreach($relative in @('pubspec.yaml','lib/main.dart','lib/aero_bar.dart',
        'lib/bridge.dart','lib/scheduler_controller.dart','test/widget_test.dart',
        'test/logic_test.dart','Run-WindowsReview.ps1','README.md')){
    if(-not (Test-Path -LiteralPath (Join-Path $folder $relative) -PathType Leaf)){throw "Missing Flutter file: $relative"}
}
$source=Get-Content -LiteralPath $bridge -Raw
foreach($contract in @('Test-CanonicalWorkspaceIdentity','Assert-ModelEffortSupported',
    'Publish-ImmutableRuntime','Register-OneTimeTask','Remove-OneTimeTask',
    'Get-CodexRunEvidence','Get-CodexRunHistory','Get-CodexCliJs')){
    if(-not $source.Contains($contract)){throw "Flutter Windows adapter lost safety contract: $contract"}
}
if($source -match 'Register-ScheduledTask|codex exec resume|autoResume\s*='){throw 'Flutter bridge duplicated worker policy.'}
Write-Host 'Flutter bridge syntax, source inventory and security boundary PASS.'
