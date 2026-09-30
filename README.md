<p align="center">
  <img src="Assets/clyro-icon-256.png" width="128" height="128" alt="Clyro">
</p>

<h1 align="center">Clyro</h1>

<p align="center"><b>English</b> · <a href="README.de.md">Deutsch</a></p>

<p align="center">Maintenance, cleanup and system monitoring for macOS.</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white" alt="Swift 5">
  <img src="https://img.shields.io/badge/License-MIT-55D5B4" alt="MIT">
</p>

Clyro is a native SwiftUI app that frees up storage, removes applications completely, runs routine maintenance and shows the state of your system in real time. Everything runs locally: no accounts, no telemetry, no background uploads. The interface is available in English and German.

## Features

**Clean Up**
Scans app, system, browser, AI and developer caches, logs, leftovers of removed apps, installers, build artifacts and the Trash. Results are grouped by category and can be selected individually. System-wide locations under `/Library` and `/private/var` are only cleaned with administrator rights and only for files older than seven days.

**Apps**
Removes applications together with their preferences, containers, launch agents and plug-ins. Shows available updates for App Store and Sparkle apps as well as all login items. System apps and security software that ships its own uninstaller are excluded.

**Optimize**
24 maintenance tasks in one pass, including the DNS cache, Spotlight, preview, icon and font caches, local Time Machine snapshots, a read-only check of the startup volume, the Open With list, corrupted preference files, the Mail, Safari and Messages databases, quarantine history, and restarts of the Dock, menu bar and Control Center. Individual tasks can be turned off in Settings, and the safe ones can run automatically once a week.

**Analyze**
A treemap of your disk with folder navigation and a list of the largest files.

**Status**
Health score, per-core CPU, GPU, memory with pressure and swap, battery, disk with SMART status, network, temperatures and a process list. The same values are available compactly in the menu bar.

**More**
Open at login, Touch ID for `sudo`, notifications when storage runs low, optional weekly cleanup, whitelist, and a history with a weekly overview. Clyro checks for new versions once a day and installs them itself after you confirm.

**Keyboard and accessibility**
`⌘1` to `⌘5` switch between sections, `↩` starts a scan, `⌘R` scans again, `⌘,` opens Settings. All controls are labeled for VoiceOver.

## Installation

Download the DMG for Apple Silicon and Intel from [Releases](https://github.com/meb99/Clyro/releases). Drag Clyro into the Applications folder. The app is not notarized by Apple, so macOS blocks the first launch. On macOS 15 or later, open Clyro once, then go to System Settings → Privacy & Security and click **Open Anyway**. On macOS 14, right-click the app and choose **Open**.

## Building from source

Requirements: macOS 14 or later, Xcode 15 or later.

```sh
git clone https://github.com/meb99/Clyro.git
open Clyro/Clyro.xcodeproj
```

Select the **Clyro** scheme and **My Mac**, then press `⌘R`. Run the tests with `⌘U`. No Apple Developer account is required.

## Safety

Clyro only deletes what you select after a scan. Only data that macOS or the owning app recreates without loss is preselected.

- Password managers, keys (SSH, GPG), input methods, VPN clients, security and management software, cloud sync and virtual machines are excluded.
- No rule points to Documents, Desktop, Photos, Mail, Messages or the keychain.
- Caches of running apps stay locked until the app quits.
- Data only counts as orphaned if no app with the same bundle ID is installed and it is older than 30 days.
- Build folders with tracked files, their own Git repositories or key files are left alone.
- Every deletion is logged in `~/Library/Logs/Clyro/operations.log`.

Caches and logs are deleted permanently by default. If you prefer the Trash, change it in Settings. Uninstall and Analyze always move items to the Trash.

The safety rules are covered by tests in `Tests/ClyroTests`, which run on every pull request.

## Project structure

```text
Clyro.xcodeproj           App and test targets
Sources/Clyro
├── ClyroApp.swift        Entry point, window, menu bar, settings
├── RootView.swift        Navigation
├── Localization.swift    Language selection (EN/DE)
├── CleanupScanner.swift  Scan and delete flow
├── CleanupRules.swift    Cleanup rules, protection lists, whitelist
├── CleanupProbe.swift    Scanning of the individual categories
├── SystemExtras.swift    Admin locations, Touch ID, login item, notifications
├── UpdateService.swift   Update check and installation
├── OptimizeEngine.swift  Maintenance tasks
├── ToolEngines.swift     Log, build artifacts, app leftovers
├── SystemMonitor.swift   System metrics via Mach, IOKit and sysctl
├── ThermalSensors.swift  Temperature sensors
└── …Views.swift          User interface of each section
Resources                 Translations
Tests/ClyroTests          Tests for the safety rules
```

## Releases

The `release.yml` workflow builds a universal app, packages it as a DMG and publishes it as a GitHub release. It runs on tags like `v1.2.0` or manually via *Actions → Release → Run workflow* with a version number, in which case the tag is created automatically. Release notes live in `docs/releases/<version>.md`.

## License

MIT, see [LICENSE](LICENSE).
