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

    static var excluded: Set<String> {
        Set((UserDefaults.standard.string(forKey: excludedKey) ?? "").split(separator: ",").map(String.init))
    }

    static func setExcluded(_ id: String, _ isExcluded: Bool) {
        var values = excluded
        if isExcluded { values.insert(id) } else { values.remove(id) }
        UserDefaults.standard.set(values.sorted().joined(separator: ","), forKey: excludedKey)
    }

    static let tasks: [OptimizeTask] = [
        OptimizeTask(id: "dns", group: "Netzwerk & Suche", title: "DNS-Cache leeren",
                     detail: "Löst veraltete Adressen, wenn Webseiten oder Server umgezogen sind.") { dry in
            if dry { return OptimizeReport(result: .applied, message: "Vorschau") }
            let result = Shell.run("/usr/bin/dscacheutil", ["-flushcache"])
            return result.ok
                ? OptimizeReport(result: .applied, message: "DNS-Cache geleert")
                : OptimizeReport(result: .failed, message: "DNS-Cache ließ sich nicht leeren")
        },
        OptimizeTask(id: "spotlight-status", group: "Netzwerk & Suche", title: "Spotlight-Index prüfen",
                     detail: "Prüft, ob die Suche aktiv ist. Verändert nichts.") { _ in
            let result = Shell.run("/usr/bin/mdutil", ["-s", "/"], timeout: 10)
            guard result.ok else { return OptimizeReport(result: .unavailable, message: "Status nicht lesbar") }
            if result.output.localizedCaseInsensitiveContains("disabled") {
                return OptimizeReport(result: .unchanged, message: "Spotlight ist deaktiviert")
            }
            return OptimizeReport(result: .unchanged, message: "Spotlight-Index geprüft")
        },
        OptimizeTask(id: "finder-cache", group: "Finder", title: "Vorschau- und Symbol-Cache auffrischen",
                     detail: "Erneuert Quick-Look-Miniaturen und den Symbol-Cache.") { dry in
            if dry { return OptimizeReport(result: .applied, message: "Vorschau") }
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
                ? OptimizeReport(result: .applied, message: "Miniaturen und Symbole erneuert")
                : OptimizeReport(result: .failed, message: "\(failures) Schritt(e) fehlgeschlagen")
        },
        OptimizeTask(id: "dsstore", group: "Finder", title: ".DS_Store auf Netz- und USB-Laufwerken verhindern",
                     detail: "Finder legt auf fremden Laufwerken keine .DS_Store-Dateien mehr an.") { dry in
            let keys = ["DSDontWriteNetworkStores", "DSDontWriteUSBStores"]
            let missing = keys.filter { !Defaults.isTrue("com.apple.desktopservices", $0) }
            if missing.isEmpty { return OptimizeReport(result: .unchanged, message: "Bereits aktiv") }
            if dry { return OptimizeReport(result: .applied, message: "Vorschau") }
            let failed = missing.filter { !Shell.run("/usr/bin/defaults", ["write", "com.apple.desktopservices", $0, "-bool", "true"]).ok }
            return failed.isEmpty
                ? OptimizeReport(result: .applied, message: "Für Netz- und USB-Laufwerke aktiviert")
                : OptimizeReport(result: .failed, message: "Einstellung ließ sich nicht setzen")
        },
        OptimizeTask(id: "saved-states", group: "Apps", title: "Alte App-Zustände entfernen",
                     detail: "Löscht gespeicherte Fensterzustände, die älter als 30 Tage sind.") { dry in
            let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Saved Application State")
            let threshold = Date().addingTimeInterval(-30 * 86_400)
            let old = FileScan.children(of: root).filter {
                $0.pathExtension == "savedState" && (FileScan.modified($0) ?? .distantFuture) < threshold
            }
            if old.isEmpty { return OptimizeReport(result: .unchanged, message: "Keine alten Zustände") }
            if dry { return OptimizeReport(result: .applied, message: "Vorschau: \(old.count) Zustände") }
            let removed = old.filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
            return OptimizeReport(result: removed > 0 ? .applied : .failed, message: "\(removed) alte Zustände entfernt")
        },
        OptimizeTask(id: "broken-prefs", group: "Apps", title: "Defekte Einstellungen reparieren",
                     detail: "Entfernt beschädigte Einstellungsdateien. Die App legt sie neu an.") { dry in
            let prefs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences")
            let candidates = FileScan.children(of: prefs).filter { $0.pathExtension == "plist" && !Defaults.isProtectedPreference($0, protectLoginWindow: true) }
                + FileScan.children(of: prefs.appendingPathComponent("ByHost")).filter { $0.pathExtension == "plist" && !Defaults.isProtectedPreference($0, protectLoginWindow: false) }
            let deadline = Date().addingTimeInterval(15)
            var broken: [URL] = []
            for url in candidates where Date() < deadline {
                guard !CleanupWhitelist.matches(url), !Plist.isValid(url) else { continue }
                broken.append(url)
            }
            if broken.isEmpty { return OptimizeReport(result: .unchanged, message: "Alle Einstellungsdateien gültig") }
            if dry { return OptimizeReport(result: .applied, message: "Vorschau: \(broken.count) defekt") }
            let removed = broken.filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
            return OptimizeReport(result: .applied, message: "\(removed) defekte Dateien repariert")
        },
        OptimizeTask(id: "databases", group: "Apps", title: "Datenbanken optimieren",
                     detail: "Verdichtet die Datenbanken von Mail, Safari und Nachrichten.") { dry in
            let blocking = [("com.apple.mail", "Mail"), ("com.apple.Safari", "Safari"), ("com.apple.MobileSMS", "Nachrichten")]
                .filter { !NSRunningApplication.runningApplications(withBundleIdentifier: $0.0).isEmpty }
                .map(\.1)
            if !blocking.isEmpty {
                return OptimizeReport(result: .skipped, message: "Erst schließen: \(blocking.joined(separator: ", "))")
            }
            let home = FileManager.default.homeDirectoryForCurrentUser
            var databases = ["Library/Messages/chat.db", "Library/Safari/History.db", "Library/Safari/TopSites.db"]
                .map { home.appendingPathComponent($0) }
            let mail = home.appendingPathComponent("Library/Mail")
            for version in FileScan.children(of: mail) where version.lastPathComponent.hasPrefix("V") {
                databases.append(version.appendingPathComponent("MailData/Envelope Index"))
            }
            databases = databases.filter { FileManager.default.isReadableFile(atPath: $0.path) }
            if databases.isEmpty { return OptimizeReport(result: .unavailable, message: "Keine Datenbanken zugänglich") }

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
            if compacted > 0 { return OptimizeReport(result: .applied, message: "\(compacted) Datenbanken verdichtet") }
            return OptimizeReport(result: .unchanged, message: optimal > 0 ? "Bereits optimal" : "Nichts zu verdichten")
        },
        OptimizeTask(id: "legacy", group: "Apps", title: "Alte Tuning-Einstellungen entfernen",
                     detail: "Entfernt versteckte App-Nap- und Image-Prüf-Schalter alter Tuning-Tools.") { dry in
            var found: [(String, String)] = []
            if Defaults.isTrue("-g", "NSAppSleepDisabled") { found.append(("-g", "NSAppSleepDisabled")) }
            for key in ["skip-verify", "skip-verify-locked", "skip-verify-remote"] where Defaults.isTrue("com.apple.frameworks.diskimages", key) {
                found.append(("com.apple.frameworks.diskimages", key))
            }
            if found.isEmpty { return OptimizeReport(result: .unchanged, message: "Keine alten Schalter gefunden") }
            if dry { return OptimizeReport(result: .applied, message: "Vorschau: \(found.count) Schalter") }
            let removed = found.filter { Shell.run("/usr/bin/defaults", ["delete", $0.0, $0.1]).ok }.count
            return OptimizeReport(result: removed > 0 ? .applied : .failed, message: "\(removed) Schalter entfernt")
        },
        OptimizeTask(id: "shared-lists", group: "Apps", title: "Seitenleisten- und Verlaufslisten reparieren",
                     detail: "Entfernt beschädigte Favoriten- und Zuletzt-benutzt-Listen des Finders.") { dry in
            let root = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/com.apple.sharedfilelist")
            guard FileManager.default.fileExists(atPath: root.path) else {
                return OptimizeReport(result: .unavailable, message: "Keine Listen gefunden")
            }
            let broken = FileScan.recursive(root) { ["sfl2", "sfl3"].contains($0.pathExtension) }
                .filter { !$0.path.contains("ApplicationRecentDocuments") && !Plist.isValid($0) }
            if broken.isEmpty { return OptimizeReport(result: .unchanged, message: "Alle Listen in Ordnung") }
            if dry { return OptimizeReport(result: .applied, message: "Vorschau: \(broken.count) defekt") }
            let removed = broken.filter { (try? FileManager.default.removeItem(at: $0)) != nil }.count
            return OptimizeReport(result: .applied, message: "\(removed) Listen repariert")
        },
        OptimizeTask(id: "launch-agents", group: "Apps", title: "Startobjekte prüfen",
                     detail: "Findet Launch Agents, deren Programm nicht mehr existiert. Verändert nichts.") { _ in
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
                ? OptimizeReport(result: .unchanged, message: "Alle Startobjekte in Ordnung")
                : OptimizeReport(result: .unchanged, message: "\(broken.count) verweisen auf fehlende Programme")
        },
        OptimizeTask(id: "quarantine", group: "Datenschutz", title: "Quarantäne-Verlauf leeren",
                     detail: "Löscht die Liste, welche Downloads Gatekeeper sich gemerkt hat.") { dry in
            let database = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Preferences/com.apple.LaunchServices.QuarantineEventsV2")
            guard FileManager.default.fileExists(atPath: database.path) else {
                return OptimizeReport(result: .unchanged, message: "Verlauf bereits leer")
            }
            let count = Shell.run("/usr/bin/sqlite3", [database.path, "SELECT COUNT(*) FROM LSQuarantineEvent;"], timeout: 10)
            guard count.ok, let rows = Int(count.output) else {
                return OptimizeReport(result: .unavailable, message: "Verlauf nicht lesbar")
            }
            if rows == 0 { return OptimizeReport(result: .unchanged, message: "Verlauf bereits leer") }
            if dry { return OptimizeReport(result: .applied, message: "Vorschau: \(rows) Einträge") }
            let cleared = Shell.run("/usr/bin/sqlite3", [database.path, "DELETE FROM LSQuarantineEvent; VACUUM;"], timeout: 30)
            return cleared.ok
                ? OptimizeReport(result: .applied, message: "\(rows) Einträge gelöscht")
                : OptimizeReport(result: .failed, message: "Verlauf ließ sich nicht leeren")
        },
        OptimizeTask(id: "notifications", group: "Datenschutz", title: "Mitteilungsdatenbank verkleinern",
                     detail: "Entfernt zugestellte Mitteilungen, die älter als 30 Tage sind.") { dry in
            guard let database = MaintenancePaths.notificationDatabase() else {
                return OptimizeReport(result: .unavailable, message: "Datenbank nicht zugänglich")
            }
            let size = FileProbe.sizeOfItem(at: database)
            if size < 50 * 1_048_576 {
                return OptimizeReport(result: .unchanged, message: "Datenbank ist schlank (\(ClyroFormat.byteCount(size)))")
            }
            if dry { return OptimizeReport(result: .applied, message: "Vorschau") }
            let cleaned = Shell.run("/usr/bin/sqlite3", [database.path,
                "DELETE FROM record WHERE delivered_date < strftime('%s','now','-30 days'); VACUUM;"], timeout: 60)
            guard cleaned.ok else { return OptimizeReport(result: .failed, message: "Datenbank ist gesperrt") }
            _ = Shell.run("/usr/bin/killall", ["NotificationCenter"])
            return OptimizeReport(result: .applied, message: "Verkleinert (war \(ClyroFormat.byteCount(size)))")
        },
        OptimizeTask(id: "usage-data", group: "Datenschutz", title: "Alte Nutzungsdaten entfernen",
                     detail: "Löscht Nutzungsverläufe, die älter als 90 Tage sind.") { dry in
            let database = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Knowledge/knowledgeC.db")
            guard FileManager.default.isReadableFile(atPath: database.path) else {
                return OptimizeReport(result: .unavailable, message: "Datenbank nicht zugänglich")
            }
            let size = FileProbe.sizeOfItem(at: database)
            if size < 100 * 1_048_576 {
                return OptimizeReport(result: .unchanged, message: "Datenbank ist schlank (\(ClyroFormat.byteCount(size)))")
            }
            if dry { return OptimizeReport(result: .applied, message: "Vorschau") }
            let cleaned = Shell.run("/usr/bin/sqlite3", [database.path,
                "DELETE FROM ZOBJECT WHERE ZCREATIONDATE < (strftime('%s','now','-90 days') - strftime('%s','2001-01-01')); VACUUM;"], timeout: 60)
            return cleaned.ok
                ? OptimizeReport(result: .applied, message: "Verkleinert (war \(ClyroFormat.byteCount(size)))")
                : OptimizeReport(result: .failed, message: "Datenbank ist gesperrt")
        },
        restart("input", "Eingabeumschaltung neu starten", process: "TextInputMenuAgent"),
        restart("spotlight", "Spotlight neu starten", process: "Spotlight"),
        restart("notification-center", "Mitteilungszentrale neu starten", process: "NotificationCenter"),
        restart("pasteboard", "Universelle Zwischenablage neu starten", process: "pboard"),
        restart("control-center", "Kontrollzentrum neu starten", process: "ControlCenter"),
        restart("menubar", "Menüleiste neu starten", process: "SystemUIServer"),
        restart("dock", "Dock neu starten", process: "Dock")
    ]

    private static func restart(_ id: String, _ title: String, process: String) -> OptimizeTask {
        OptimizeTask(id: id, group: "Fehlerbehebungen", title: title,
                     detail: "Startet \(process) neu, falls es hängt.") { dry in
            if dry { return OptimizeReport(result: .applied, message: "Vorschau") }
            let result = Shell.run("/usr/bin/killall", [process], timeout: 10)
            return result.ok
                ? OptimizeReport(result: .applied, message: "Neu gestartet")
                : OptimizeReport(result: .unchanged, message: "War nicht aktiv")
        }
    }

    static func run(_ task: OptimizeTask, dryRun: Bool) -> OptimizeReport {
        if excluded.contains(task.id) {
            return OptimizeReport(result: .skipped, message: "Ausgeschlossen")
        }
        let report = task.work(dryRun)
        if !dryRun && report.result == .applied {
            ClyroLog.append("Optimieren: \(task.title) – \(report.message)")
        }
        return report
    }
}

// MARK: - Kleine Helfer

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

enum MaintenancePaths {
    static func notificationDatabase() -> URL? {
        let group = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
        if FileManager.default.isReadableFile(atPath: group.path) { return group }

        let darwin = Shell.run("/usr/bin/getconf", ["DARWIN_USER_DIR"], timeout: 5)
        if darwin.ok {
            let legacy = URL(fileURLWithPath: darwin.output).appendingPathComponent("com.apple.notificationcenter/db2/db")
            if FileManager.default.isReadableFile(atPath: legacy.path) { return legacy }
        }
        return nil
    }
}
