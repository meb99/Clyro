import AppKit
import Foundation

// MARK: - Hilfsprozesse

/// Startet ein Systemwerkzeug ohne Shell, liest die Ausgabe und bricht nach `timeout` Sekunden ab.
enum Shell {
    struct Result {
        let status: Int32
        let output: String
        var ok: Bool { status == 0 }
    }

    static func run(_ path: String, _ arguments: [String], timeout: TimeInterval = 30) -> Result {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return Result(status: 127, output: "")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let collected = OutputBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            collected.append(handle.availableData)
        }
        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return Result(status: 126, output: error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        collected.append(pipe.fileHandleForReading.readDataToEndOfFile())
        return Result(status: process.terminationStatus, output: collected.text)
    }

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        var text: String {
            lock.lock()
            defer { lock.unlock() }
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }
}

// MARK: - Aufgaben

enum OptimizeResult: Hashable {
    case applied
    case unchanged
    case skipped
    case unavailable
    case failed
}

struct OptimizeReport: Hashable {
    let result: OptimizeResult
    let message: String
}

struct OptimizeTask: Identifiable {
    let id: String
    let group: String
    let title: String
    let detail: String
    let work: @Sendable (_ dryRun: Bool) -> OptimizeReport
}

enum OptimizeCatalog {
    static let excludedKey = "optimizeExcludedTasks"

    /// Meldung für Datenbanken, die macOS ohne Festplattenvollzugriff sperrt.
    static let noAccessMessage = String(localized: "Datenbank nicht zugänglich")

    /// Meldung für Datenbanken, die es auf dieser macOS-Version nicht (mehr) gibt.
    static let notPresentMessage = String(localized: "Auf diesem Mac nicht vorhanden")

    /// Aufgaben, die spürbar länger dauern; die Oberfläche weist währenddessen darauf hin.
    static let slowIDs: Set<String> = ["disk-verify", "launch-services", "databases", "tm-snapshots"]

    static var excluded: Set<String> {
        Set((UserDefaults.standard.string(forKey: excludedKey) ?? "").split(separator: ",").map(String.init))
    }

    static func setExcluded(_ id: String, _ isExcluded: Bool) {
        var values = excluded
        if isExcluded { values.insert(id) } else { values.remove(id) }
        UserDefaults.standard.set(values.sorted().joined(separator: ","), forKey: excludedKey)
    }

    static let tasks: [OptimizeTask] = [
        OptimizeTask(id: "dns", group: String(localized: "Netzwerk & Suche"), title: String(localized: "DNS-Cache leeren"),
                     detail: String(localized: "Löst veraltete Adressen, wenn Webseiten oder Server umgezogen sind.")) { dry in
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            let result = Shell.run("/usr/bin/dscacheutil", ["-flushcache"])
            return result.ok
                ? OptimizeReport(result: .applied, message: String(localized: "DNS-Cache geleert"))
                : OptimizeReport(result: .failed, message: String(localized: "DNS-Cache ließ sich nicht leeren"))
        },
        OptimizeTask(id: "spotlight-status", group: String(localized: "Netzwerk & Suche"), title: String(localized: "Spotlight-Index prüfen"),
                     detail: String(localized: "Prüft, ob die Suche aktiv ist. Verändert nichts.")) { _ in
            let result = Shell.run("/usr/bin/mdutil", ["-s", "/"], timeout: 10)
            guard result.ok else { return OptimizeReport(result: .unavailable, message: String(localized: "Status nicht lesbar")) }
            if result.output.localizedCaseInsensitiveContains("disabled") {
                return OptimizeReport(result: .unchanged, message: String(localized: "Spotlight ist deaktiviert"))
            }
            return OptimizeReport(result: .unchanged, message: String(localized: "Spotlight-Index geprüft"))
        },
        OptimizeTask(id: "finder-cache", group: String(localized: "Finder"), title: String(localized: "Vorschau- und Symbol-Cache auffrischen"),
                     detail: String(localized: "Erneuert Quick-Look-Miniaturen und den Symbol-Cache.")) { dry in
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            var failures = 0
            if !Shell.run("/usr/bin/qlmanage", ["-r", "cache"]).ok { failures += 1 }
            if !Shell.run("/usr/bin/qlmanage", ["-r"]).ok { failures += 1 }
            let caches = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches")
            for name in ["com.apple.QuickLook.thumbnailcache", "com.apple.iconservices.store", "com.apple.iconservices"] {
                let url = caches.appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                if (try? FileManager.default.removeItem(at: url)) == nil { failures += 1 }
            }
            return failures == 0
                ? OptimizeReport(result: .applied, message: String(localized: "Miniaturen und Symbole erneuert"))
                : OptimizeReport(result: .failed, message: String(localized: "\(failures) Schritt(e) fehlgeschlagen"))
        },
        OptimizeTask(id: "dsstore", group: String(localized: "Finder"), title: String(localized: ".DS_Store auf Netz- und USB-Laufwerken verhindern"),
                     detail: String(localized: "Finder legt auf fremden Laufwerken keine .DS_Store-Dateien mehr an.")) { dry in
            let keys = ["DSDontWriteNetworkStores", "DSDontWriteUSBStores"]
            let missing = keys.filter { !Defaults.isTrue("com.apple.desktopservices", $0) }
            if missing.isEmpty { return OptimizeReport(result: .unchanged, message: String(localized: "Bereits aktiv")) }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            let failed = missing.filter { !Shell.run("/usr/bin/defaults", ["write", "com.apple.desktopservices", $0, "-bool", "true"]).ok }
            return failed.isEmpty
                ? OptimizeReport(result: .applied, message: String(localized: "Für Netz- und USB-Laufwerke aktiviert"))
                : OptimizeReport(result: .failed, message: String(localized: "Einstellung ließ sich nicht setzen"))
        },
        OptimizeTask(id: "saved-states", group: String(localized: "Apps"), title: String(localized: "Alte App-Zustände entfernen"),
                     detail: String(localized: "Löscht gespeicherte Fensterzustände, die älter als 30 Tage sind.")) { dry in
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Saved Application State")
            let threshold = Date().addingTimeInterval(-30 * 86_400)
            let old = FileScan.children(of: root).filter {
                $0.pathExtension == "savedState" && (FileScan.modified($0) ?? .distantFuture) < threshold
            }
            if old.isEmpty { return OptimizeReport(result: .unchanged, message: String(localized: "Keine alten Zustände")) }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau: \(old.count) Zustände")) }
            let removed = old.filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
            return OptimizeReport(result: removed > 0 ? .applied : .failed, message: String(localized: "\(removed) alte Zustände entfernt"))
        },
        OptimizeTask(id: "broken-prefs", group: String(localized: "Apps"), title: String(localized: "Defekte Einstellungen reparieren"),
                     detail: String(localized: "Entfernt beschädigte Einstellungsdateien. Die App legt sie neu an.")) { dry in
            let prefs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
            let candidates = FileScan.children(of: prefs).filter { $0.pathExtension == "plist" && !Defaults.isProtectedPreference($0, protectLoginWindow: true) }
                + FileScan.children(of: prefs.appendingPathComponent("ByHost")).filter { $0.pathExtension == "plist" && !Defaults.isProtectedPreference($0, protectLoginWindow: false) }
            let deadline = Date().addingTimeInterval(15)
            var broken: [URL] = []
            for url in candidates where Date() < deadline {
                guard !CleanupWhitelist.matches(url), !Plist.isValid(url) else { continue }
                broken.append(url)
            }
            if broken.isEmpty { return OptimizeReport(result: .unchanged, message: String(localized: "Alle Einstellungsdateien gültig")) }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau: \(broken.count) defekt")) }
            let removed = broken.filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
            return OptimizeReport(result: .applied, message: String(localized: "\(removed) defekte Dateien repariert"))
        },
        OptimizeTask(id: "databases", group: String(localized: "Apps"), title: String(localized: "Datenbanken optimieren"),
                     detail: String(localized: "Verdichtet die Datenbanken von Mail, Safari und Nachrichten.")) { dry in
            let blocking = [("com.apple.mail", "Mail"), ("com.apple.Safari", "Safari"), ("com.apple.MobileSMS", "Nachrichten")]
                .filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.0).isEmpty }
                .map(\.1)
            if !blocking.isEmpty {
                return OptimizeReport(result: .skipped, message: String(localized: "Erst schließen: \(blocking.joined(separator: ", "))"))
            }
            let home = FileManager.default.homeDirectoryForCurrentUser
            var databases = ["Library/Messages/chat.db", "Library/Safari/History.db", "Library/Safari/TopSites.db"]
                .map { home.appendingPathComponent($0) }
            let mail = home.appendingPathComponent("Library/Mail")
            for version in FileScan.children(of: mail) where version.lastPathComponent.hasPrefix("V") {
                databases.append(version.appendingPathComponent("MailData/Envelope Index"))
            }
            let states = databases.map { ($0, FileAccess.state(of: $0)) }
            databases = states.filter { $0.1 == .readable }.map(\.0)
            if databases.isEmpty {
                // Wer Mail, Safari und Nachrichten nie genutzt hat, hat auch nichts zu verdichten.
                return states.contains { $0.1 == .locked }
                    ? OptimizeReport(result: .unavailable, message: OptimizeCatalog.noAccessMessage)
                    : OptimizeReport(result: .unchanged, message: String(localized: "Keine Datenbanken vorhanden"))
            }

            var compacted = 0
            var optimal = 0
            for database in databases {
                guard FileProbe.sizeOfItem(at: database) <= 100_000_000 else { continue }
                let info = Shell.run("/usr/bin/sqlite3", [database.path, "PRAGMA freelist_count;"], timeout: 10)
                guard info.ok, let free = Int(info.output.split(separator: "\n").last ?? "") else { continue }
                if free == 0 { optimal += 1; continue }
                if dry { compacted += 1; continue }
                let check = Shell.run("/usr/bin/sqlite3", [database.path, "PRAGMA integrity_check;"], timeout: 30)
                guard check.ok, check.output == "ok" else { continue }
                if Shell.run("/usr/bin/sqlite3", [database.path, "VACUUM;"], timeout: 60).ok { compacted += 1 }
            }
            if compacted > 0 { return OptimizeReport(result: .applied, message: String(localized: "\(compacted) Datenbanken verdichtet")) }
            return OptimizeReport(result: .unchanged, message: optimal > 0 ? String(localized: "Bereits optimal") : String(localized: "Nichts zu verdichten"))
        },
        OptimizeTask(id: "legacy", group: String(localized: "Apps"), title: String(localized: "Alte Tuning-Einstellungen entfernen"),
                     detail: String(localized: "Entfernt versteckte App-Nap- und Image-Prüf-Schalter alter Tuning-Tools.")) { dry in
            var found: [(String, String)] = []
            if Defaults.isTrue("-g", "NSAppSleepDisabled") { found.append(("-g", "NSAppSleepDisabled")) }
            for key in ["skip-verify", "skip-verify-locked", "skip-verify-remote"] where Defaults.isTrue("com.apple.frameworks.diskimages", key) {
                found.append(("com.apple.frameworks.diskimages", key))
            }
            if found.isEmpty { return OptimizeReport(result: .unchanged, message: String(localized: "Keine alten Schalter gefunden")) }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau: \(found.count) Schalter")) }
            let removed = found.filter { Shell.run("/usr/bin/defaults", ["delete", $0.0, $0.1]).ok }.count
            return OptimizeReport(result: removed > 0 ? .applied : .failed, message: String(localized: "\(removed) Schalter entfernt"))
        },
        OptimizeTask(id: "shared-lists", group: String(localized: "Apps"), title: String(localized: "Seitenleisten- und Verlaufslisten reparieren"),
                     detail: String(localized: "Entfernt beschädigte Favoriten- und Zuletzt-benutzt-Listen des Finders.")) { dry in
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
            guard FileManager.default.fileExists(atPath: root.path) else {
                return OptimizeReport(result: .unavailable, message: String(localized: "Keine Listen gefunden"))
            }
            let broken = FileScan.recursive(root) { ["sfl2", "sfl3"].contains($0.pathExtension) }
                .filter { !$0.path.contains("ApplicationRecentDocuments") && !Plist.isValid($0) }
            if broken.isEmpty { return OptimizeReport(result: .unchanged, message: String(localized: "Alle Listen in Ordnung")) }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau: \(broken.count) defekt")) }
            let removed = broken.filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
            return OptimizeReport(result: .applied, message: String(localized: "\(removed) Listen repariert"))
        },
        OptimizeTask(id: "launch-agents", group: String(localized: "Apps"), title: String(localized: "Startobjekte prüfen"),
                     detail: String(localized: "Findet Launch Agents, deren Programm nicht mehr existiert. Verändert nichts.")) { _ in
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
            let broken = FileScan.children(of: root).filter { url in
                guard url.pathExtension == "plist",
                      let data = try? Data(contentsOf: url),
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
                let program = (plist["Program"] as? String) ?? ((plist["ProgramArguments"] as? [String])?.first)
                guard let program, program.hasPrefix("/") else { return false }
                return !FileManager.default.fileExists(atPath: program)
            }
            return broken.isEmpty
                ? OptimizeReport(result: .unchanged, message: String(localized: "Alle Startobjekte in Ordnung"))
                : OptimizeReport(result: .unchanged, message: String(localized: "\(broken.count) verweisen auf fehlende Programme"))
        },
        OptimizeTask(id: "quarantine", group: String(localized: "Datenschutz"), title: String(localized: "Quarantäne-Verlauf leeren"),
                     detail: String(localized: "Löscht die Liste, welche Downloads Gatekeeper sich gemerkt hat.")) { dry in
            let database = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
            guard FileManager.default.fileExists(atPath: database.path) else {
                return OptimizeReport(result: .unchanged, message: String(localized: "Verlauf bereits leer"))
            }
            let count = Shell.run("/usr/bin/sqlite3", [database.path, "SELECT COUNT(*) FROM LSQuarantineEvent;"], timeout: 10)
            guard count.ok, let rows = Int(count.output) else {
                return OptimizeReport(result: .unavailable, message: String(localized: "Verlauf nicht lesbar"))
            }
            if rows == 0 { return OptimizeReport(result: .unchanged, message: String(localized: "Verlauf bereits leer")) }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau: \(rows) Einträge")) }
            let cleared = Shell.run("/usr/bin/sqlite3", [database.path, "DELETE FROM LSQuarantineEvent; VACUUM;"], timeout: 30)
            return cleared.ok
                ? OptimizeReport(result: .applied, message: String(localized: "\(rows) Einträge gelöscht"))
                : OptimizeReport(result: .failed, message: String(localized: "Verlauf ließ sich nicht leeren"))
        },
        OptimizeTask(id: "notifications", group: String(localized: "Datenschutz"), title: String(localized: "Mitteilungsdatenbank verkleinern"),
                     detail: String(localized: "Entfernt zugestellte Mitteilungen, die älter als 30 Tage sind.")) { dry in
            let found = FileAccess.firstReadable(MaintenancePaths.notificationCandidates())
            guard let database = found.url else {
                return found.locked
                    ? OptimizeReport(result: .unavailable, message: OptimizeCatalog.noAccessMessage)
                    : OptimizeReport(result: .unchanged, message: OptimizeCatalog.notPresentMessage)
            }
            let size = FileProbe.sizeOfItem(at: database)
            if size < 50 * 1_048_576 {
                return OptimizeReport(result: .unchanged, message: String(localized: "Datenbank ist schlank (\(ClyroFormat.byteCount(size)))"))
            }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            let cleaned = Shell.run("/usr/bin/sqlite3", [database.path,
                "DELETE FROM record WHERE delivered_date < strftime('%s','now','-30 days'); VACUUM;"], timeout: 60)
            guard cleaned.ok else { return OptimizeReport(result: .failed, message: String(localized: "Datenbank ist gesperrt")) }
            _ = Shell.run("/usr/bin/killall", ["NotificationCenter"])
            return OptimizeReport(result: .applied, message: String(localized: "Verkleinert (war \(ClyroFormat.byteCount(size)))"))
        },
        OptimizeTask(id: "usage-data", group: String(localized: "Datenschutz"), title: String(localized: "Alte Nutzungsdaten entfernen"),
                     detail: String(localized: "Löscht Nutzungsverläufe, die älter als 90 Tage sind.")) { dry in
            let database = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
            switch FileAccess.state(of: database) {
            case .missing: return OptimizeReport(result: .unchanged, message: OptimizeCatalog.notPresentMessage)
            case .locked: return OptimizeReport(result: .unavailable, message: OptimizeCatalog.noAccessMessage)
            case .readable: break
            }
            let size = FileProbe.sizeOfItem(at: database)
            if size < 100 * 1_048_576 {
                return OptimizeReport(result: .unchanged, message: String(localized: "Datenbank ist schlank (\(ClyroFormat.byteCount(size)))"))
            }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            let cleaned = Shell.run("/usr/bin/sqlite3", [database.path,
                "DELETE FROM ZOBJECT WHERE ZCREATIONDATE < (strftime('%s','now','-90 days') - strftime('%s','2001-01-01')); VACUUM;"], timeout: 60)
            return cleaned.ok
                ? OptimizeReport(result: .applied, message: String(localized: "Verkleinert (war \(ClyroFormat.byteCount(size)))"))
                : OptimizeReport(result: .failed, message: String(localized: "Datenbank ist gesperrt"))
        },
        OptimizeTask(id: "tm-snapshots", group: String(localized: "Speicher"), title: String(localized: "Lokale Time-Machine-Snapshots ausdünnen"),
                     detail: String(localized: "Gibt Speicher frei, den ältere lokale Snapshots belegen. Backups auf externen Laufwerken bleiben unberührt.")) { dry in
            let before = TimeMachineSnapshots.count()
            guard let before else {
                return OptimizeReport(result: .unavailable, message: String(localized: "Time Machine nicht verfügbar"))
            }
            if before == 0 { return OptimizeReport(result: .unchanged, message: String(localized: "Keine lokalen Snapshots")) }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau: \(before) Snapshots")) }
            let freeBefore = TimeMachineSnapshots.freeBytes()
            let thin = Shell.run("/usr/bin/tmutil", ["thinlocalsnapshots", "/", "999999999999", "4"], timeout: 180)
            guard thin.ok else {
                return OptimizeReport(result: .failed, message: String(localized: "Snapshots ließen sich nicht ausdünnen"))
            }
            let removed = max(0, before - (TimeMachineSnapshots.count() ?? before))
            let freed = max(0, TimeMachineSnapshots.freeBytes() - freeBefore)
            return removed > 0
                ? OptimizeReport(result: .applied, message: String(localized: "\(removed) Snapshots entfernt · \(ClyroFormat.byteCount(freed)) frei"))
                : OptimizeReport(result: .unchanged, message: String(localized: "Snapshots werden noch gebraucht"))
        },
        OptimizeTask(id: "disk-verify", group: String(localized: "Speicher"), title: String(localized: "Startvolume prüfen"),
                     detail: String(localized: "Prüft das Dateisystem wie die Erste Hilfe im Festplattendienstprogramm, nur lesend. Verändert nichts.")) { dry in
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            let result = Shell.run("/usr/sbin/diskutil", ["verifyVolume", "/"], timeout: 900)
            let output = result.output.lowercased()
            if result.ok && (output.contains("appears to be ok") || output.contains("seems to be ok")) {
                return OptimizeReport(result: .unchanged, message: String(localized: "Keine Fehler gefunden"))
            }
            if output.contains("permission") || output.contains("root") || output.contains("not privileged") {
                return OptimizeReport(result: .unavailable, message: String(localized: "Braucht Administratorrechte – Festplattendienstprogramm → Erste Hilfe nutzen"))
            }
            return result.ok
                ? OptimizeReport(result: .unchanged, message: String(localized: "Geprüft"))
                : OptimizeReport(result: .failed, message: String(localized: "Fehler gefunden – bitte im Festplattendienstprogramm Erste Hilfe ausführen"))
        },
        OptimizeTask(id: "launch-services", group: String(localized: "System"), title: String(localized: "„Öffnen mit“-Liste reparieren"),
                     detail: String(localized: "Baut die Launch-Services-Datenbank neu auf. Behebt doppelte oder veraltete Einträge und falsche App-Zuordnungen.")) { dry in
            let tool = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            guard FileManager.default.isExecutableFile(atPath: tool) else {
                return OptimizeReport(result: .unavailable, message: String(localized: "Werkzeug nicht gefunden"))
            }
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            let result = Shell.run(tool, ["-r", "-domain", "local", "-domain", "system", "-domain", "user"], timeout: 300)
            return result.ok
                ? OptimizeReport(result: .applied, message: String(localized: "Neu aufgebaut"))
                : OptimizeReport(result: .failed, message: String(localized: "Neuaufbau fehlgeschlagen"))
        },
        OptimizeTask(id: "font-cache", group: String(localized: "System"), title: String(localized: "Schriften-Cache leeren"),
                     detail: String(localized: "Hilft bei falsch dargestellten oder fehlenden Schriften. Vollständig wirksam nach einem Neustart.")) { dry in
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            guard Shell.run("/usr/bin/atsutil", ["databases", "-removeUser"], timeout: 30).ok else {
                return OptimizeReport(result: .failed, message: String(localized: "Schriften-Cache ließ sich nicht leeren"))
            }
            _ = Shell.run("/usr/bin/atsutil", ["server", "-shutdown"], timeout: 10)
            _ = Shell.run("/usr/bin/atsutil", ["server", "-ping"], timeout: 10)
            return OptimizeReport(result: .applied, message: String(localized: "Geleert – nach dem nächsten Neustart vollständig wirksam"))
        },
        restart("input", String(localized: "Eingabeumschaltung neu starten"), process: "TextInputMenuAgent"),
        restart("spotlight", String(localized: "Spotlight neu starten"), process: "Spotlight"),
        restart("notification-center", String(localized: "Mitteilungszentrale neu starten"), process: "NotificationCenter"),
        restart("pasteboard", String(localized: "Universelle Zwischenablage neu starten"), process: "pboard"),
        restart("control-center", String(localized: "Kontrollzentrum neu starten"), process: "ControlCenter"),
        restart("menubar", String(localized: "Menüleiste neu starten"), process: "SystemUIServer"),
        restart("dock", String(localized: "Dock neu starten"), process: "Dock")
    ]

    /// Aufgaben für die wöchentliche automatische Wartung: ohne Neustarts von Dock oder Menüleiste,
    /// ohne Passwortabfrage und ohne spürbare Unterbrechung.
    static let automaticIDs: Set<String> = [
        "dns", "finder-cache", "dsstore", "saved-states", "broken-prefs", "databases", "legacy", "shared-lists",
        "quarantine", "notifications", "usage-data", "tm-snapshots", "disk-verify"
    ]

    private static func restart(_ id: String, _ title: String, process: String) -> OptimizeTask {
        OptimizeTask(id: id, group: String(localized: "Fehlerbehebungen"), title: title,
                     detail: String(localized: "Startet \(process) neu, falls es hängt.")) { dry in
            if dry { return OptimizeReport(result: .applied, message: String(localized: "Vorschau")) }
            let result = Shell.run("/usr/bin/killall", [process], timeout: 10)
            return result.ok
                ? OptimizeReport(result: .applied, message: String(localized: "Neu gestartet"))
                : OptimizeReport(result: .unchanged, message: String(localized: "War nicht aktiv"))
        }
    }

    static func run(_ task: OptimizeTask, dryRun: Bool) -> OptimizeReport {
        if excluded.contains(task.id) {
            return OptimizeReport(result: .skipped, message: String(localized: "Ausgeschlossen"))
        }
        let report = task.work(dryRun)
        if !dryRun && report.result == .applied {
            ClyroLog.append("Optimieren: \(task.title) – \(report.message)")
        }
        return report
    }
}

// MARK: - Kleine Helfer

enum TimeMachineSnapshots {
    /// Anzahl der lokalen Time-Machine-Snapshots auf dem Startvolume, `nil` wenn tmutil nicht antwortet.
    static func count() -> Int? {
        let result = Shell.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"], timeout: 20)
        guard result.ok else { return nil }
        return result.output.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine.") }.count
    }

    static func freeBytes() -> Int64 {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return Int64(values?.volumeAvailableCapacity ?? 0)
    }
}

enum Defaults {
    static func isTrue(_ domain: String, _ key: String) -> Bool {
        let result = Shell.run("/usr/bin/defaults", ["read", domain, key], timeout: 5)
        guard result.ok else { return false }
        return ["1", "true", "yes"].contains(result.output.lowercased())
    }

    static func isProtectedPreference(_ url: URL, protectLoginWindow: Bool) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix("com.apple.") || name.hasPrefix(".GlobalPreferences") { return true }
        return protectLoginWindow && name == "loginwindow.plist"
    }
}

enum Plist {
    static func isValid(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return false }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) != nil
    }
}

enum FileScan {
    static func children(of directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
            options: []
        )) ?? []
    }

    static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    static func recursive(_ root: URL, where include: (URL) -> Bool) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }
        var results: [URL] = []
        for case let url as URL in enumerator where include(url) {
            results.append(url)
        }
        return results
    }
}

/// Unterscheidet Dateien, die es auf dieser macOS-Version nicht gibt, von solchen, die macOS ohne
/// Festplattenvollzugriff sperrt. Nur ein echter Öffnungsversuch zeigt die Sperre zuverlässig.
enum FileAccess {
    enum State {
        case missing
        case locked
        case readable
    }

    static func state(of url: URL) -> State {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .locked }
        try? handle.close()
        return .readable
    }

    /// Die erste lesbare Datei, sonst ob mindestens eine gesperrt ist.
    static func firstReadable(_ candidates: [URL]) -> (url: URL?, locked: Bool) {
        var locked = false
        for url in candidates {
            switch state(of: url) {
            case .readable: return (url, false)
            case .locked: locked = true
            case .missing: continue
            }
        }
        return (nil, locked)
    }
}

enum MaintenancePaths {
    static func notificationCandidates() -> [URL] {
        var candidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
        ]
        let darwin = Shell.run("/usr/bin/getconf", ["DARWIN_USER_DIR"], timeout: 5)
        if darwin.ok {
            candidates.append(URL(fileURLWithPath: darwin.output).appendingPathComponent("com.apple.notificationcenter/db2/db"))
        }
        return candidates
    }
}
