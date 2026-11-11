# Legacy Windows Forms interface

This is the original PowerShell/WinForms frontend for Codex Resume Scheduler. The current Continuum interface is the [Flutter application](../../src/desktop/). Both frontends use the active [backend](../../src/backend/) and [reusable components](../../components/).

From a complete Windows checkout, the legacy launcher is:

~~~powershell
wscript.exe .\legacy\winforms\Start-Codex-Scheduler.vbs
~~~

The launcher opens the legacy GUI and can read local conversation and usage metadata. Windows, standard PowerShell 7, Node.js, Git, and an installed Codex CLI are required. The optional WebView2 renderer uses the SDK staged by `scripts/Prepare-AeroWebView2.ps1`; native rendering is available as a fallback.

`scripts/Package-CodexScheduler.ps1 -Preview` packages this frontend with the backend in the same directory layout. It is separate from the current [Flutter preview builder](../../src/desktop/Build-WindowsPreview.ps1). Legacy packages are launched through `legacy/winforms/Start-Codex-Scheduler.vbs` inside the extracted package.

The original design and reviews are in [project history](../../docs/history/README.md).
