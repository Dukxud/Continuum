# Components

This directory contains ten independently importable PowerShell modules and the application's Codex-specific Shared session host.

## Reusable modules

| Module | Purpose | Requirements |
| --- | --- | --- |
| [AeroProgress](AeroProgress/README.md) | WebGL2 progress surface in Windows Forms | Windows, STA UI thread, WebView2 runtime and SDK |
| [Countdown](Countdown/Countdown.psd1) | Elapsed percentage and time-to-run text | PowerShell 7 |
| [FlowingProgress](FlowingProgress/FlowingProgress.psd1) | WPF compositor-animated progress surface | Windows, STA UI thread, WPF and WindowsFormsIntegration |
| [GitRepository](GitRepository/GitRepository.psd1) | Read-only repository root and branch inspection | PowerShell 7, Git |
| [JobOutcomes](JobOutcomes/JobOutcomes.psd1) | Validated, atomic outcome records | PowerShell 7, SettingsStore |
| [OneTimeTasks](OneTimeTasks/OneTimeTasks.psd1) | One-time task registration and conservative cancellation | Windows Task Scheduler |
| [ProgressHost](ProgressHost/ProgressHost.psd1) | Renderer-neutral fallback ownership and lifecycle | Windows, STA UI thread |
| [RuntimeBundle](RuntimeBundle/RuntimeBundle.psd1) | Content-addressed runtime snapshots and verification | PowerShell 7 |
| [SettingsStore](SettingsStore/SettingsStore.psd1) | Atomic local JSON preferences | PowerShell 7 |
| [WindowShell](WindowShell/WindowShell.psd1) | Native Windows Forms windows and controls | Windows, STA UI thread |

The generic modules do not require Codex, application settings, or a session identifier. Copy only the folders needed by your application; copy SettingsStore alongside JobOutcomes. Windows UI modules need a functioning message loop.

The standalone reusable-kit ZIP includes these ten modules. AeroProgress's HTML renderer and Microsoft WebView2 SDK files are packaged inside its own folder. The kit excludes the application-specific Shared host.

## Use a module

Import the module manifest from your own application:

```powershell
Import-Module .\components\Countdown\Countdown.psd1
Get-CountdownText -DueAt (Get-Date).AddMinutes(8) -Now (Get-Date)
```

SettingsStore leaves the schema to its caller:

```powershell
Import-Module .\components\SettingsStore\SettingsStore.psd1
Write-JsonSettings -Path "$env:LOCALAPPDATA\MyApp\settings.json" -Value @{ theme = 'blue' }
Read-JsonSettings -Path "$env:LOCALAPPDATA\MyApp\settings.json"
```

RuntimeBundle snapshots only the files named by the caller:

```powershell
Import-Module .\components\RuntimeBundle\RuntimeBundle.psd1
$runtime = Publish-ImmutableRuntime -SourceDirectory . -DestinationDirectory "$env:LOCALAPPDATA\MyApp\runtimes" -RelativeFiles @('worker.ps1')
Assert-RuntimeFingerprint -Directory $runtime.Directory -RelativeFiles @('worker.ps1') -ExpectedFingerprint $runtime.Fingerprint
```

## Contracts worth preserving

- **Persistence:** SettingsStore handles replaceable, single-writer preferences. Missing or malformed JSON returns null. The caller owns validation, schema upgrades, and recovery; the module does not provide concurrent transactions or historical recovery.
- **Runtime identity:** fingerprints detect changed files. They do not authenticate the publisher or defend against the same Windows user changing both files and local metadata.
- **Scheduling:** OneTimeTasks accepts the caller's executable, arguments, working directory, name, and trigger. It uses the signed-in interactive-user principal. Registration does not establish successful execution.
- **Cancellation:** `Remove-OneTimeTask -OnlyBeforeStart` rereads state and last-run information, requiring Ready, no previous run, and one trigger at least 90 seconds away. It cannot atomically prevent all scheduling races or terminate a running worker. Unguarded removal is an explicit maintenance operation.
- **Time:** Countdown compares UTC instants. OneTimeTasks converts explicit UTC values to local triggers, treats unspecified values as local, and rejects ambiguous or nonexistent daylight-saving times.
- **Renderer ownership:** ProgressHost owns primary/fallback disposal; its caller decides when a renderer has failed. AeroProgress and FlowingProgress do not reserve the caller's `Control.Tag`.
- **Native loading:** AeroProgress loads the WebView2 loader from an explicit path without changing global `PATH`. Changing an already-loaded native SDK can require restarting the host.

FlowingProgress exposes value and color setters without replacing the hosted control. AeroProgress exposes `Get-AeroProgressViewStatus` for readiness and failure inspection. See each manifest for the exported API.

## Application-specific host

[SharedCodexSession](SharedCodexSession) owns a Codex App Server and authenticates the desktop and native terminal clients. It is a separate Node.js component, not one of the reusable PowerShell modules. Its scheduled-turn lifecycle and later-turn limitations are documented in the [Shared session contract](https://github.com/Dukxud/codex-resume-scheduler/blob/main/docs/SHARED-NATIVE-TUI.md).

See the [architecture guide](https://github.com/Dukxud/codex-resume-scheduler/blob/main/docs/ARCHITECTURE.md) for application adapters and the [test guide](https://github.com/Dukxud/codex-resume-scheduler/blob/main/tests/README.md) for independent-consumer and packaged-renderer checks. Scheduling tests use an isolated fake task provider; they do not execute existing user jobs.
