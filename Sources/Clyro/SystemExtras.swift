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

/// Systemweite Orte, die nur mit Administratorrechten bereinigt werden: nur Dateien älter als eine Frist, nie ganze Ordner.
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
        Family(id: "caches", title: String(localized: "System-Caches"), root: "/Library/Caches", patterns: ["*.cache", "*.tmp", "*.log"], days: 7, depth: 5),
        Family(id: "crash", title: String(localized: "System-Absturzberichte"), root: "/Library/Logs/DiagnosticReports", patterns: ["*"], days: 7, depth: 1),
        Family(id: "syslog", title: String(localized: "Systemprotokolle"), root: "/private/var/log", patterns: ["*.log", "*.gz", "*.asl"], days: 7, depth: 3),
        Family(id: "adobe", title: String(localized: "Adobe-Protokolle"), root: "/Library/Logs/Adobe", patterns: ["*"], days: 7, depth: 5),
        Family(id: "creativecloud", title: String(localized: "Creative-Cloud-Protokolle"), root: "/Library/Logs/CreativeCloud", patterns: ["*"], days: 7, depth: 5),
        Family(id: "diagnostics", title: String(localized: "Diagnosedaten"), root: "/private/var/db/diagnostics", patterns: ["*"], days: 7, depth: 5),
        Family(id: "powerlog", title: String(localized: "Energieprotokolle"), root: "/private/var/db/powerlog", patterns: ["*"], days: 7, depth: 5),
        Family(id: "memory", title: String(localized: "Speicherberichte"), root: "/private/var/db/reportmemoryexception/MemoryLimitViolations", patterns: ["*"], days: 30, depth: 5)
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
                detail: String(localized: "\(family.root) · älter als \(family.days) Tage")
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
                ownerName: String(localized: "Lokale Time-Machine-Schnappschüsse"),
                detail: String(localized: "\(snapshots.count) Schnappschüsse · Größe unbekannt · Wiederherstellungspunkte gehen verloren")
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
        return AdminShell.run(script, prompt: String(localized: "Clyro möchte systemweite Caches und Protokolle bereinigen."))
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
            ? String(localized: "Clyro möchte Touch ID für sudo im Terminal einrichten.")
            : String(localized: "Clyro möchte Touch ID für sudo wieder entfernen.")
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
                    title: String(localized: "Wenig Speicher frei"),
                    body: String(localized: "Nur noch \(ClyroFormat.byteCount(free)) frei. Ein Scan zeigt, was sich entfernen lässt.")
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
                    title: String(localized: "Bereinigung empfohlen"),
                    body: cleaner.history.isEmpty
                        ? String(localized: "Es wurde noch keine Bereinigung durchgeführt.")
                        : String(localized: "Die letzte Bereinigung ist über \(days) Tage her.")
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

/// Entfernt die Reste von Apps, die im Finder in den Papierkorb gelegt wurden.
///
/// Clyro merkt sich die installierten Apps und beobachtet die Programme-Ordner. Verschwindet eine App dauerhaft,
/// wandern ihre Einstellungen, Caches und Container ebenfalls in den Papierkorb und lassen sich von dort zurückholen.
/// Apps, die gelöscht wurden, während Clyro nicht lief, werden beim nächsten Start erkannt.
@MainActor
final class AppRemovalWatcher {
    static let shared = AppRemovalWatcher()
    static let enabledKey = "removeLeftoversAutomatically"
    private static let snapshotKey = "installedAppsSnapshot"

    private struct Entry: Codable, Hashable {
        let path: String
        let bundleIdentifier: String
        let name: String
        let version: String
    }

    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: Task<Void, Never>?
    private weak var cleaner: CleanupScanner?

    private nonisolated static var roots: [URL] {
        [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
    }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    func start(cleaner: CleanupScanner) {
        self.cleaner = cleaner
        guard sources.isEmpty else { return }
        if isEnabled { ClyroNotifier.requestAuthorization() }
        for root in Self.roots {
            let descriptor = open(root.path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor,
                eventMask: [.write, .rename, .delete],
                queue: .main
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor in self?.scheduleCheck(after: 10) }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            sources.append(source)
        }
        scheduleCheck(after: 5)
    }

    /// Wartet kurz, damit Updates (alte App raus, neue rein) nicht als Löschen gelten.
    private func scheduleCheck(after seconds: Double) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.check()
        }
    }

    private func check() async {
        let current = await Task.detached(priority: .utility) { Self.installedEntries() }.value
        let previous = loadSnapshot()
        saveSnapshot(current)
        // Beim allerersten Start gibt es nichts zu vergleichen.
        guard isEnabled, let previous else { return }

        let paths = Set(current.map(\.path))
        let identifiers = Set(current.map(\.bundleIdentifier))
        let removed = previous.filter { !paths.contains($0.path) && !identifiers.contains($0.bundleIdentifier) }
        for entry in removed {
            await removeLeftovers(of: entry)
        }
    }

    private func removeLeftovers(of entry: Entry) async {
        // Ohne Bundle-ID ließen sich Reste nur über den Namen raten – das ist zu unsicher.
        guard !entry.bundleIdentifier.isEmpty, entry.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        let app = InstalledApplication(
            url: URL(fileURLWithPath: entry.path),
            name: entry.name,
            version: entry.version,
            bundleIdentifier: entry.bundleIdentifier,
            sizeBytes: 0
        )
        guard !AppRemnantProbe.isProtected(app) else { return }

        let result = await Task.detached(priority: .utility) {
            AppRemnantProbe.trash(AppRemnantProbe.remnants(for: app))
        }.value
        guard result.movedItems > 0 else { return }

        cleaner?.record(bytes: result.bytes, itemCount: result.movedItems, kinds: [.appRemnants])
        ClyroNotifier.post(
            id: "leftovers",
            title: String(localized: "Reste von \(entry.name) entfernt"),
            body: String(localized: "\(ClyroFormat.byteCount(result.bytes)) an Einstellungen und Caches liegen jetzt im Papierkorb.")
        )
    }

    private nonisolated static func installedEntries() -> [Entry] {
        var entries: [Entry] = []
        for root in roots {
            let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { continue }
                let info = bundle.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (info?["CFBundleShortVersionString"] as? String) ?? "–"
                entries.append(Entry(path: url.path, bundleIdentifier: identifier, name: name, version: version))
            }
        }
        return entries
    }

    private func loadSnapshot() -> [Entry]? {
        guard let data = UserDefaults.standard.data(forKey: Self.snapshotKey) else { return nil }
        return try? JSONDecoder().decode([Entry].self, from: data)
    }

    private func saveSnapshot(_ entries: [Entry]) {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: Self.snapshotKey)
    }
}
