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

Clyro folgt dem Funktionsumfang und den Abläufen von [Mole](https://github.com/tw93/mole) – mit eigenem Code, eigenen Texten und eigener Optik. Statt Planeten begleitet dich ein Baum durch die Jahreszeiten: Bereinigen ist Winter, Optimieren Frühling, Apps Sommer und Analyse Herbst.

Die App hat genau fünf Seiten:

- **Bereinigen:** Scan mit Live-Anzeige, danach aufklappbare Kategorien mit Auswahl je Eintrag („Alle · Keine · Empfohlene“). Kategorien: App-Caches, System-Caches, Systembereiche (Admin), Sonstiges, Entwicklerwerkzeuge, KI-Werkzeuge, Browser, Reste deinstallierter Apps, Installationsdateien, Projekt-Artefakte und Papierkorb. Laufende Apps sperren ihren Cache („… belegen Cache · Beenden“). Wie Mole wird endgültig gelöscht; in den Einstellungen lässt sich der Papierkorb wählen.
- **Systembereiche (Admin):** systemweite Caches, Protokolle, Absturzberichte und Diagnosedaten, die älter als 7 Tage sind. macOS fragt einmal nach dem Passwort. Lokale Time-Machine-Schnappschüsse sind optional und nicht vorausgewählt.
- **Apps:** Deinstallieren mit über 40 Rückstands-Orten (Container, Gruppencontainer, Launch Agents, ByHost-Einstellungen, Plug-ins …), Updates für App-Store- und Sparkle-Apps, Autostart-Übersicht. Apple-Apps wie Xcode, Keynote oder iMovie lassen sich entfernen, Systemapps nicht.
- **Optimieren:** 21 Wartungsaufgaben ohne Rückfrage – DNS, Spotlight, Vorschau- und Symbol-Cache, alte App-Zustände, defekte Einstellungen, Datenbanken von Mail/Safari/Nachrichten, .DS_Store-Schutz, Quarantäne-Verlauf, Mitteilungs- und Nutzungsdatenbank sowie Fehlerbehebungen für Dock, Menüleiste, Kontrollzentrum und mehr. Einzelne Aufgaben lassen sich ausschließen.
- **Analyse:** Treemap der Festplatte mit Ordnerliste, Hineinklicken und Rechtsklick für Finder oder Papierkorb. Umschalter zu „Große Dateien“.
- **Status:** Gesundheitswert nach Moles Schwellen, CPU mit Kern-Balken, GPU, Arbeitsspeicher mit Druck und Swap, Akku, Festplatte, Netzwerk, Temperatur und Prozessliste mit MEM, % CPU, PWR und PID.

Dazu kommen:

- **Menüleiste:** Ein Blatt öffnet eine kompakte Übersicht mit allen Werten, Top-Prozessen, „Wachhalten“ und dem Bereinigungsverlauf.
- **Dein Wald:** Jede Bereinigung pflanzt einen Baum – je mehr frei wurde, desto größer. Dazu ein Diagramm „Freigegeben pro Woche“.
- **Einstellungen:** Start bei Anmeldung, Touch ID für `sudo`, Erinnerungen bei wenig Speicher oder langer Pause, wöchentliches automatisches Bereinigen (nur empfohlene Einträge), Whitelist, Projektordner und Optimierungsaufgaben.

Jede Löschung steht im Aktivitätsprotokoll unter `~/Library/Logs/Clyro/operations.log`. Clyro arbeitet lokal; nur die Update-Suche fragt auf Knopfdruck den App Store und die Update-Server der Hersteller.

## Starten

Voraussetzungen:

- Mac mit macOS 14 oder neuer
- Xcode 15 oder neuer

1. Repository oder ZIP herunterladen und entpacken.
2. **`Clyro.xcodeproj` öffnen** – nicht einzelne Swift-Dateien.
3. Oben als Scheme **Clyro** und als Ziel **My Mac** auswählen.
4. Mit `⌘R` starten, mit `⌘U` die Tests ausführen.

Zum lokalen Ausprobieren ist kein kostenpflichtiger Apple-Developer-Account nötig.

## Sicherheitsprinzip

Clyro zeigt zuerst, was gefunden wurde. Gelöscht wird nur, was in der Ergebnisliste ausgewählt ist. Standardmäßig sind nur wiederherstellbare Caches, Protokolle und KI-/Browser-Caches vorausgewählt; Entwicklerwerkzeuge, Reste deinstallierter Apps, Installationsdateien und der Papierkorb nicht.

- Passwortmanager, Eingabemethoden, VPN-Clients, Sicherheits- und Verwaltungssoftware, Lizenzdaten und virtuelle Maschinen werden nie pauschal geleert.
- Keine Regel zeigt auf persönliche Daten wie Dokumente, Schreibtisch, Mail, Nachrichten, Fotos oder den Schlüsselbund.
- Caches laufender Apps sind gesperrt, bis die App beendet ist.
- Reste gelten nur als verwaist, wenn keine App mit dieser Bundle-ID installiert ist und sie älter als 30 Tage sind.
- Build-Ordner mit Git-Repositories, eingecheckten Dateien oder Deployment-Schlüsseln bleiben unangetastet.
- Eigene Schutzregeln lassen sich in der Whitelist eintragen.

Diese Regeln sind durch Tests abgesichert (`Tests/ClyroTests`), die bei jedem Pull Request in der CI laufen.

Clyro ist eine frühe Entwicklungsversion. Vor Tests mit wichtigen Daten sollte ein aktuelles Backup vorhanden sein.

## Architektur

```text
Clyro.xcodeproj            App-Target, Test-Target und Bundle-ID
Info.plist                 App-Metadaten
Sources/Clyro
├── ClyroApp.swift         App-Einstieg, Fenster, Menüleiste, Einstellungen
├── RootView.swift         Obere Leiste mit den fünf Seiten
├── Models.swift           Datenmodelle
├── Theme.swift            Farben, Typografie und Formatierung
├── Components.swift       Wiederverwendbare Bausteine
├── GardenScene.swift      Jahreszeiten-Baum und gemeinsamer Startbildschirm
├── Growth.swift           Kleiner Baum für den Gesundheitswert
├── ForestViews.swift      Dein Wald und Wochen-Diagramm
├── CleanupScanner.swift   Bereinigen: Regeln, Schutzlisten, Scan und Löschen
├── CleanupViews.swift     Bereinigen: Oberfläche
├── SystemExtras.swift     Admin-Bereinigung, Touch ID, Autostart, Erinnerungen
├── AppsViews.swift        Apps: Deinstallieren
├── UpdatesView.swift      Apps: Updates
├── ToolEngines.swift      Protokoll, Projekt-Artefakte, App-Rückstände
├── OptimizeEngine.swift   Optimieren: Wartungsaufgaben
├── OptimizeViews.swift    Optimieren: Oberfläche
├── ExplorerViews.swift    Analyse: Treemap und Ordner
├── FeatureViews.swift     Große Dateien, Autostart, Verlauf, Einstellungen
├── DashboardView.swift    Status
├── MenuBarView.swift      Menüleisten-Übersicht
├── SystemMonitor.swift    Live-Systemwerte
└── ThermalSensors.swift   Temperatursensoren
Tests/ClyroTests           Tests für Schutzlisten und Löschregeln
```

## Nächste Schritte

- Englische Oberfläche und fertige App zum Herunterladen
- Eigenes App-Icon im Jahreszeiten-Stil
- Kurze Einführung beim ersten Start

## Hinweis

Clyro ist ein eigenständiges Lern- und Open-Source-Projekt. Namen, Quellcode, Icons und Marken anderer Apps werden nicht übernommen.

## Lizenz

MIT
