# Documentation

Continuum schedules and monitors saved Codex conversations on Windows. Start with the guides below, or read the [project overview](../README.md).

## Use Continuum

| Guide | What you will find |
| --- | --- |
| [Getting started](GETTING-STARTED.md) | Prerequisites, a source build, and the exact launch command |
| [User guide](USER-GUIDE.md) | Scheduling, execution modes, usage windows, appearance, and results |
| [Troubleshooting](TROUBLESHOOTING.md) | Setup checks, version identification, and common symptoms |
| [Security and privacy](SECURITY-AND-PRIVACY.md) | Permissions, local data, credentials, and unsigned previews |

## Understand the implementation

| Guide | What you will find |
| --- | --- |
| [Architecture](ARCHITECTURE.md) | UI, bridge, worker, and persistence boundaries |
| [Flutter developer guide](../flutter_port/README.md) | Source layout, local checks, and Windows builds |
| [Reusable components](../components/README.md) | Independent PowerShell modules and example consumers |
| [Shared sessions](SHARED-NATIVE-TUI.md) | One App Server, authenticated clients, and lifecycle limits |
| [Quota presentation](QUOTA-PRESENTATION.md) | Rendering the usage windows returned for the selected model |
| [Quota continuation](QUOTA-CONTINUATION-DESIGN.md) | Optional Background retries and their eligibility checks |
| [Contributing](CONTRIBUTING.md) | Change scope, verification, and pull requests |

## Status and verification

Feature development is paused. These records distinguish automated checks, native observations, and work that still needs verification.

| Record | Purpose |
| --- | --- |
| [Current state](CURRENT-STATE.md) | Baseline commits, exact preview paths, and maintainer handoff |
| [Windows acceptance](CONTINUUM-WINDOWS-ACCEPTANCE.md) | Recorded results and outstanding native scenarios |
| [Screenshots](SCREENSHOTS.md) | Dated visual evidence and capture guidance |
| [Release policy](RELEASE-POLICY.md) | Preview packaging and production release requirements |

## Project history

The [history index](history/README.md) collects the WinForms documentation, migration audits, and earlier reviews. Those records describe their original candidates; current behavior and verification are documented above.
