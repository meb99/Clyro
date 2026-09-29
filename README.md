<p align="center">
  <img src="Assets/clyro-icon-256.png" width="128" height="128" alt="Clyro">
</p>

<h1 align="center">Clyro</h1>

<p align="center">Wartung, Bereinigung und Systemüberwachung für macOS.</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white" alt="Swift 5">
  <img src="https://img.shields.io/badge/Lizenz-MIT-55D5B4" alt="MIT">
</p>

Clyro ist eine native SwiftUI-App, die Speicher freigibt, Programme vollständig entfernt, Routinewartung erledigt und den Zustand des Systems in Echtzeit anzeigt. Alles läuft lokal; es gibt keine Konten, keine Telemetrie und keine Hintergrund-Uploads. Die Oberfläche ist auf Deutsch und Englisch verfügbar.

## Funktionen

**Bereinigen**
Durchsucht App-, System-, Browser-, KI- und Entwickler-Caches, Protokolle, Reste deinstallierter Apps, Installationsdateien, Build-Artefakte und den Papierkorb. Die Ergebnisse sind nach Kategorien gruppiert und einzeln auswählbar. Systemweite Bereiche unter `/Library` und `/private/var` werden nur mit Administratorrechten und nur für Dateien älter als sieben Tage bereinigt.

**Apps**
Entfernt Programme samt Einstellungen, Containern, Launch Agents und Plug-ins. Zeigt verfügbare Updates für App-Store- und Sparkle-Apps sowie alle Startobjekte. Systemprogramme und Sicherheitssoftware mit eigenem Deinstallationsprogramm sind ausgenommen.

**Optimieren**
21 Wartungsaufgaben in einem Durchgang, unter anderem DNS-Cache, Spotlight, Vorschau- und Symbol-Cache, beschädigte Einstellungsdateien, Datenbanken von Mail, Safari und Nachrichten, Quarantäne-Verlauf sowie Neustarts von Dock, Menüleiste und Kontrollzentrum. Einzelne Aufgaben lassen sich in den Einstellungen abwählen.

**Analyse**
Treemap der Festplatte mit Ordnernavigation und einer Liste der größten Dateien.

**Status**
Gesundheitswert, CPU pro Kern, GPU, Arbeitsspeicher mit Speicherdruck und Swap, Akku, Festplatte mit SMART-Status, Netzwerk, Temperaturen und eine Prozessliste. Dieselben Werte stehen kompakt im Menüleistenmenü bereit.

**Weiteres**
Start bei der Anmeldung, Touch ID für `sudo`, Mitteilungen bei knappem Speicher, optionale wöchentliche Bereinigung, Whitelist, Verlauf mit Wochenübersicht.

## Installation

Fertige Versionen liegen unter [Releases](https://github.com/meb99/Clyro/releases) als DMG für Apple Silicon und Intel. Clyro in den Programme-Ordner ziehen und beim ersten Start per Rechtsklick → **Öffnen** bestätigen; die App ist nicht von Apple notarisiert.

## Aus dem Quellcode bauen

Voraussetzungen: macOS 14 oder neuer, Xcode 15 oder neuer.

```sh
git clone https://github.com/meb99/Clyro.git
open Clyro/Clyro.xcodeproj
```

Scheme **Clyro**, Ziel **My Mac**, dann `⌘R`. Die Tests laufen mit `⌘U`. Ein Apple-Developer-Konto ist nicht nötig.

## Sicherheit

Clyro löscht nur, was nach einem Scan ausgewählt wurde. Vorausgewählt sind ausschließlich Daten, die macOS oder die jeweilige App ohne Verlust neu erzeugt.

- Passwortmanager, Schlüssel (SSH, GPG), Eingabemethoden, VPN-Clients, Sicherheits- und Verwaltungssoftware, Cloud-Synchronisation und virtuelle Maschinen sind ausgenommen.
- Keine Regel verweist auf Dokumente, Schreibtisch, Fotos, Mail, Nachrichten oder den Schlüsselbund.
- Caches laufender Apps bleiben gesperrt, bis die App beendet ist.
- Daten gelten erst als verwaist, wenn keine App mit derselben Bundle-ID installiert ist und sie älter als 30 Tage sind.
- Build-Ordner mit eingecheckten Dateien, eigenen Git-Repositories oder Schlüsseldateien werden nicht angefasst.
- Jeder Löschvorgang wird in `~/Library/Logs/Clyro/operations.log` protokolliert.

Caches und Protokolle werden standardmäßig endgültig gelöscht. Wer lieber den Papierkorb nutzt, stellt das in den Einstellungen um. Deinstallieren und Analyse verschieben immer in den Papierkorb.

Die Schutzregeln sind durch Tests in `Tests/ClyroTests` abgesichert, die bei jedem Pull Request laufen.

## Projektstruktur

```text
Clyro.xcodeproj           App- und Test-Target
Sources/Clyro
├── ClyroApp.swift        Einstieg, Fenster, Menüleiste, Einstellungen
├── RootView.swift        Navigation
├── Localization.swift    Sprachwahl (DE/EN)
├── CleanupScanner.swift  Bereinigungsregeln, Schutzlisten, Scan und Löschen
├── SystemExtras.swift    Administratorbereiche, Touch ID, Autostart, Mitteilungen
├── OptimizeEngine.swift  Wartungsaufgaben
├── ToolEngines.swift     Protokoll, Build-Artefakte, App-Rückstände
├── SystemMonitor.swift   Systemwerte über Mach, IOKit und sysctl
├── ThermalSensors.swift  Temperatursensoren
└── …Views.swift          Oberflächen der einzelnen Bereiche
Resources                 Übersetzungen
Tests/ClyroTests          Tests der Schutzregeln
```

## Releases

Ein Tag der Form `v1.2.0` startet den Workflow `release.yml`. Er baut eine Universal-App, erstellt eine DMG und veröffentlicht sie als GitHub-Release.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
