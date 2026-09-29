import AppKit
import Foundation
import ServiceManagement
import UserNotifications

// MARK: - Admin-Rechte

/// Führt ein Shell-Skript mit Administratorrechten aus. macOS zeigt dafür einmal den Passwortdialog.
enum AdminShell {
    static func run(_ script: String, prompt: String) -> Bool {
        let source = "do shell script \"\(escape(script))\" with prompt \"\(escape(prompt))\" with administrator privileges"
        return Shell.run("/usr/bin/osascript", ["-e", source], timeout: 900).ok
    }

    /// Setzt einen Wert in einfache Anführungszeichen, sicher für die Shell.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - Systembereiche (Admin)

/// Systemweite Orte, die Mole mit sudo bereinigt: nur Dateien älter als eine Frist, nie ganze Ordner.
enum AdminCleanup {
    struct Family {
        let id: String
        let title: String
        let root: String
        let patterns: [String]
        let days: Int
        let depth: Int
    }

    static let families: [Family] = [
        Family(id: "caches", title: "System-Caches", root: "/Library/Caches", patterns: ["*.cache", "*.tmp", "*.log"], days: 7, depth: 5),
        Family(id: "crash", title: "System-Absturzberichte", root: "/Library/Logs/DiagnosticReports", patterns: ["*"], days: 7, depth: 1),
        Family(id: "syslog", title: "Systemprotokolle", root: "/private/var/log", patterns: ["*.log", "*.gz", "*.asl"], days: 7, depth: 3),
        Family(id: "adobe", title: "Adobe-Protokolle", root: "/Library/Logs/Adobe", patterns: ["*"], days: 7, depth: 5),
        Family(id: "creativecloud", title: "Creative-Cloud-Protokolle", root: "/Library/Logs/CreativeCloud", patterns: ["*"], days: 7, depth: 5),
        Family(id: "diagnostics", title: "Diagnosedaten", root: "/private/var/db/diagnostics", patterns: ["*"], days: 7, depth: 5),
        Family(id: "powerlog", title: "Energieprotokolle", root: "/private/var/db/powerlog", patterns: ["*"], days: 7, depth: 5),
        Family(id: "memory", title: "Speicherberichte", root: "/private/var/db/reportmemoryexception/MemoryLimitViolations", patterns: ["*"], days: 30, depth: 5)
    ]

    /// Stellvertreter-Adresse für die lokalen Time-Machine-Schnappschüsse.
    static let snapshotsURL = URL(fileURLWithPath: "/.clyro-local-snapshots")

    /// Findet die Einträge für die Ergebnisliste. Größen sind Schätzungen aus dem, was ohne Admin lesbar ist.
    static func items(whitelist: [String]) -> [CleanupItem] {
        var result: [CleanupItem] = []
        for family in families {
            let url = URL(fileURLWithPath: family.root)
            guard FileManager.default.fileExists(atPath: family.root),
                  !CleanupWhitelist.matches(url, entries: whitelist) else { continue }
            let bytes = estimate(family)
            guard bytes > 0 else { continue }
            result.append(CleanupItem(
                url: url,
                targets: [url],
                bytes: bytes,
                isSelected: true,
                ownerName: family.title,
                detail: "\(family.root) · älter als \(family.days) Tage"
            ))
        }

        let snapshots = localSnapshotDates()
        if !snapshots.isEmpty {
            result.append(CleanupItem(
                url: snapshotsURL,
                targets: [snapshotsURL],
                bytes: 0,
                isSelected: false,
                isRecommended: false,
                ownerName: "Lokale Time-Machine-Schnappschüsse",
                detail: "\(snapshots.count) Schnappschüsse · Größe unbekannt · Wiederherstellungspunkte gehen verloren"
            ))
        }
        return result
    }

    /// Löscht alle ausgewählten Admin-Einträge mit einem einzigen Passwortdialog.
    static func clean(_ items: [CleanupItem]) -> Bool {
        var lines: [String] = []
        for item in items {
            if item.url == snapshotsURL {
                lines.append("for d in $(/usr/bin/tmutil listlocalsnapshotdates / | /usr/bin/grep -E '^[0-9]{4}-'); do /usr/bin/tmutil deletelocalsnapshots \"$d\" >/dev/null 2>&1; done")
                continue
            }
            guard let family = families.first(where: { $0.root == item.url.path }) else { continue }
            let names = family.patterns.map { "-name \(AdminShell.quote($0))" }.joined(separator: " -o ")
            lines.append("/usr/bin/find \(AdminShell.quote(family.root)) -xdev -mindepth 1 -maxdepth \(family.depth) -type f \\( \(names) \\) -mtime +\(family.days) -delete 2>/dev/null")
        }
        guard !lines.isEmpty else { return false }
        let script = lines.joined(separator: "; ") + "; exit 0"
        return AdminShell.run(script, prompt: "Clyro möchte systemweite Caches und Protokolle bereinigen.")
    }

    private static func estimate(_ family: Family) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: family.root),
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        let cutoff = Date().addingTimeInterval(-Double(family.days) * 86_400)
        let deadline = Date().addingTimeInterval(4)
        var total: Int64 = 0
        while let url = enumerator.nextObject() as? URL {
            if Date() > deadline { break }
            if enumerator.level > family.depth {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            guard let modified = values.contentModificationDate, modified < cutoff else { continue }
            let name = url.lastPathComponent
            guard family.patterns.contains(where: { fnmatch($0, name, 0) == 0 }) else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    private static func localSnapshotDates() -> [String] {
        let result = Shell.run("/usr/bin/tmutil", ["listlocalsnapshotdates", "/"], timeout: 8)
        guard result.ok else { return [] }
        return result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil }
    }
}

// MARK: - Touch ID für sudo

/// Wie `mo touchid`: trägt pam_tid in /etc/pam.d/sudo_local ein. Diese Datei überlebt macOS-Updates.
enum TouchIDSudo {
    static let path = "/etc/pam.d/sudo_local"

    static var isEnabled: Bool {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
        return text.split(separator: "\n").contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("auth") && trimmed.contains("pam_tid.so")
        }
    }

    static func setEnabled(_ enabled: Bool) -> Bool {
        let file = AdminShell.quote(path)
        let script: String
        if enabled {
            script = "/usr/bin/grep -qE '^[[:space:]]*auth.*pam_tid\\.so' \(file) 2>/dev/null || /usr/bin/printf 'auth       sufficient     pam_tid.so\\n' >> \(file)"
        } else {
            script = "[ -f \(file) ] && /usr/bin/sed -i '' -E '/^[[:space:]]*auth.*pam_tid\\.so/d' \(file); exit 0"
        }
        let prompt = enabled
            ? "Clyro möchte Touch ID für sudo im Terminal einrichten."
            : "Clyro möchte Touch ID für sudo wieder entfernen."
        return AdminShell.run(script, prompt: prompt)
    }
}

// MARK: - Start bei Anmeldung

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Mitteilungen

enum ClyroNotifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: "\(id)-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Erinnerungen bei wenig Speicher oder langer Pause und – auf Wunsch – wöchentliches automatisches Bereinigen.
@MainActor
final class ReminderService {
    static let shared = ReminderService()

    static let lowDiskKey = "reminderLowDisk"
    static let lowDiskGBKey = "reminderLowDiskGB"
    static let staleKey = "reminderStale"
    static let staleDaysKey = "reminderStaleDays"
    static let autoCleanKey = "autoCleanWeekly"

    private static let lastDiskKey = "reminderLastDisk"
    private static let lastStaleKey = "reminderLastStale"
    private static let lastAutoKey = "autoCleanLast"

    private weak var monitor: SystemMonitor?
    private weak var cleaner: CleanupScanner?
    private var timer: Timer?

    func start(monitor: SystemMonitor, cleaner: CleanupScanner) {
        self.monitor = monitor
        self.cleaner = cleaner
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            check()
        }
    }

    func check() {
        let defaults = UserDefaults.standard
        let now = Date()

        if defaults.bool(forKey: Self.lowDiskKey), let snapshot = monitor?.snapshot, snapshot.diskTotalBytes > 0 {
            let limitGB = defaults.object(forKey: Self.lowDiskGBKey) as? Int ?? 20
            let free = max(0, snapshot.diskTotalBytes - snapshot.diskUsedBytes)
            if free < Int64(limitGB) * 1_000_000_000, isDue(Self.lastDiskKey, every: 86_400) {
                ClyroNotifier.post(
                    id: "disk",
                    title: "Wenig Speicher frei",
                    body: "Nur noch \(ClyroFormat.byteCount(free)) frei. Ein Scan in Clyro schafft meist schnell Platz."
                )
                defaults.set(now, forKey: Self.lastDiskKey)
            }
        }

        if defaults.bool(forKey: Self.staleKey), let cleaner {
            let days = defaults.object(forKey: Self.staleDaysKey) as? Int ?? 14
            let last = cleaner.history.first?.date ?? .distantPast
            if now.timeIntervalSince(last) > Double(days) * 86_400, isDue(Self.lastStaleKey, every: 3 * 86_400) {
                ClyroNotifier.post(
                    id: "stale",
                    title: "Zeit für etwas Pflege",
                    body: cleaner.history.isEmpty
                        ? "Du hast mit Clyro noch nicht bereinigt."
                        : "Die letzte Bereinigung ist über \(days) Tage her."
                )
                defaults.set(now, forKey: Self.lastStaleKey)
            }
        }

        if defaults.bool(forKey: Self.autoCleanKey), let cleaner, isDue(Self.lastAutoKey, every: 7 * 86_400) {
            if cleaner.autoClean() {
                defaults.set(now, forKey: Self.lastAutoKey)
            }
        }
    }

    private func isDue(_ key: String, every interval: TimeInterval) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: key) as? Date else { return true }
        return Date().timeIntervalSince(last) > interval
    }
}
