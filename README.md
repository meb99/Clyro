<p align="center">
  <img src="Assets/ClyroIcon.svg" width="112" alt="Clyro Icon">
</p>

# Clyro

**Mac care, made clear.**

Clyro ist ein nativer, lokaler macOS-Systemmonitor und vorsichtiger Cleaner. Das Projekt ist von der Klarheit moderner Mac-Werkzeuge inspiriert, hat aber ein eigenes visuelles System und setzt auf verständliche Erklärungen statt auf mysteriöse „Optimierung“.

![macOS](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-55D5B4)

## Funktionen

Clyro folgt dem Funktionsumfang und den Abläufen von [Mole](https://github.com/tw93/mole) – mit eigenem Code, eigenen Texten und eigener Optik. Die App hat genau fünf Seiten:

- **Bereinigen:** Scan mit Live-Anzeige, danach aufklappbare Kategorien mit Auswahl je Eintrag („Alle · Keine · Empfohlene“). Kategorien: App-Caches, System-Caches, Sonstiges (Protokolle, Diagnoseberichte, App-Zustände), Entwicklerwerkzeuge, KI-Werkzeuge, Browser, Reste deinstallierter Apps, Installationsdateien, Projekt-Artefakte und Papierkorb. Laufende Apps sperren ihren Cache („… belegen Cache · Beenden“). Wie Mole wird endgültig gelöscht; in den Einstellungen lässt sich der Papierkorb wählen.
- **Apps:** Deinstallieren mit über 40 Rückstands-Orten (Container, Gruppencontainer, Launch Agents, ByHost-Einstellungen, Plug-ins …), Updates für App-Store- und Sparkle-Apps, Autostart-Übersicht. Apple-Apps wie Xcode, Keynote oder iMovie lassen sich entfernen, Systemapps nicht.
- **Optimieren:** 21 Wartungsaufgaben ohne Rückfrage – DNS, Spotlight, Vorschau- und Symbol-Cache, alte App-Zustände, defekte Einstellungen, Datenbanken von Mail/Safari/Nachrichten, .DS_Store-Schutz, alte Tuning-Schalter, Seitenleisten-Listen, Startobjekte, Quarantäne-Verlauf, Mitteilungs- und Nutzungsdatenbank sowie Fehlerbehebungen (Eingabeumschaltung, Spotlight, Mitteilungszentrale, Zwischenablage, Kontrollzentrum, Menüleiste, Dock). Einzelne Aufgaben lassen sich ausschließen.
- **Analyse:** Treemap der Festplatte mit Ordnerliste, Hineinklicken, Rechtsklick für Finder oder Papierkorb.
- **Status:** Gesundheitswert nach Moles Schwellen (CPU, Arbeitsspeicher, Speicherdruck, Festplatte, SMART, Temperatur, I/O, Akku, Laufzeit), CPU mit Kern-Balken, GPU, Arbeitsspeicher mit Druck und Swap, Akku mit Gesundheit, Zyklen und Hauptverbraucher, Festplatte, Netzwerk, CPU- und GPU-Temperatur mit 5-Minuten-Spitze, Prozessliste mit MEM, % CPU, PWR und PID.

Jede Löschung steht im Aktivitätsprotokoll unter `~/Library/Logs/Clyro/operations.log`. Clyro arbeitet lokal; nur die Update-Suche fragt auf Knopfdruck den App Store und die Update-Server der Hersteller.

## Starten

Voraussetzungen:

- Mac mit macOS 14 oder neuer
- Xcode 15 oder neuer

1. Repository oder ZIP herunterladen und entpacken.
2. **`Clyro.xcodeproj` öffnen** – nicht einzelne Swift-Dateien.
3. Oben als Scheme **Clyro** und als Ziel **My Mac** auswählen.
4. Mit `⌘R` starten.

Die korrigierte Version ist ein echtes macOS-App-Projekt mit der Bundle-ID `dev.meb99.Clyro`. Dadurch kann macOS die App korrekt bei seinen Diensten registrieren; insbesondere tritt die Warnung `missing main bundle identifier` nicht mehr durch einen Swift-Package-Start auf.

Build 3 liest CPU, Arbeitsspeicher, Laufwerke, Netzwerk, Batterie und Prozesse direkt über native macOS-Schnittstellen aus. Externe Terminal-Kommandos sind für das Dashboard nicht mehr erforderlich. Außerdem verwendet Clyro wieder eine normale macOS-Titelleiste und begrenzt die Breite des Dashboards, damit die Oberfläche auch im Vollbild nicht auseinandergezogen wird.

Zum lokalen Ausprobieren ist kein kostenpflichtiger Apple-Developer-Account nötig.

## Sicherheitsprinzip

Clyro zeigt zuerst, was gefunden wurde. Gelöscht wird nur, was in der Ergebnisliste ausgewählt ist. Standardmäßig sind nur wiederherstellbare Caches, Protokolle und KI-/Browser-Caches vorausgewählt; Entwicklerwerkzeuge, Reste deinstallierter Apps, Installationsdateien und der Papierkorb nicht.

- Passwortmanager, Eingabemethoden, VPN-Clients, Sicherheits- und Verwaltungssoftware, Lizenzdaten und virtuelle Maschinen werden nie pauschal geleert.
- Caches laufender Apps sind gesperrt, bis die App beendet ist.
- Reste gelten nur als verwaist, wenn keine App mit dieser Bundle-ID installiert ist und sie älter als 30 Tage sind.
- Build-Ordner mit Git-Repositories, eingecheckten Dateien oder Deployment-Schlüsseln bleiben unangetastet.
- Eigene Schutzregeln lassen sich in der Whitelist eintragen.

Clyro ist eine frühe Entwicklungsversion. Vor Tests mit wichtigen Daten sollte ein aktuelles Backup vorhanden sein.

## Architektur

```text
Clyro.xcodeproj          Echtes macOS-App-Target und Bundle-ID
Info.plist               App-Metadaten
Sources/Clyro
├── ClyroApp.swift       App-Einstieg
├── Models.swift         Datenmodelle
├── Theme.swift          Farben, Typografie und Formatierung
├── SystemMonitor.swift  Live-Systemwerte
├── CleanupScanner.swift Sicherer Dateiscan und Papierkorb
├── Components.swift     Wiederverwendbare UI-Komponenten
├── RootView.swift       Navigation und Sidebar
├── DashboardView.swift  Systemübersicht
└── FeatureViews.swift   Cleaner, Apps, Autostart, Verlauf, Einstellungen
```

## Nächste Schritte

- App-Daten pro Anwendung zusammenführen
- sichere App-Deinstallation mit vollständiger Vorschau
- Hintergrundelemente aktivieren und deaktivieren
- bessere Speicheranalyse
- App-Icon, Onboarding und signierte DMG-Version
- Unit-Tests für Parser und Cleaner-Regeln

## Hinweis

Clyro ist ein eigenständiges Lern- und Open-Source-Projekt. Namen, Quellcode, Icons und Marken anderer Apps werden nicht übernommen.

## Lizenz

MIT
