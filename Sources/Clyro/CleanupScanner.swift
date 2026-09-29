import AppKit
import Combine
import Darwin
import Foundation

struct CleanupCelebration: Identifiable {
    let id = UUID()
    let bytes: Int64
}

/// Eine laufende App, die einen Teil der Bereinigung blockiert (z. B. ein geöffneter Browser).
struct BlockedApp: Hashable {
    let name: String
    let bundleID: String
}

/// Ein Eintrag im Protokoll, das während der Bereinigung mitläuft.
struct CleanLogEntry: Identifiable {
    let id = UUID()
    let text: String
    let bytes: Int64?
    let isHeader: Bool
    var trailing: String?
    var checked = false
}

struct CleanEvent: Sendable {
    let kind: CleanupKind
    let name: String
    let bytes: Int64
    let done: Int
    let freed: Int64
}

struct CleanupScanOutput {
    var categories: [CleanupCategory]
    var blockedApps: [BlockedApp]
}

/// Meldet gemessene Einträge live an die Oberfläche. Kurze Pausen sorgen dafür, dass man den Scan mitverfolgen kann.
final class ScanProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes: Int64 = 0
    private var slept: TimeInterval = 0
    private let publish: @Sendable (Int64, String) -> Void

    init(publish: @escaping @Sendable (Int64, String) -> Void) {
        self.publish = publish
    }

    func report(bytes delta: Int64, path: String) {
        lock.lock()
        bytes += max(0, delta)
        let total = bytes
        let shouldPause = slept < 3.4
        if shouldPause { slept += 0.02 }
        lock.unlock()

        publish(total, path)
        if shouldPause { Thread.sleep(forTimeInterval: 0.02) }
    }
}

@MainActor
final class CleanupScanner: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning
        case ready
        case cleaning
        case failed(String)
    }

    /// Bereinigen löscht standardmäßig endgültig. In den Einstellungen lässt sich stattdessen der Papierkorb wählen.
    static let useTrashKey = "cleanupUseTrash"

    @Published var categories: [CleanupCategory] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var history: [CleanupRecord] = []
    @Published private(set) var celebration: CleanupCelebration?
    @Published private(set) var progressBytes: Int64 = 0
    @Published private(set) var progressPath = ""
    @Published private(set) var blockedApps: [BlockedApp] = []
    @Published private(set) var cleanLog: [CleanLogEntry] = []
    @Published private(set) var cleanFreed: Int64 = 0
    @Published private(set) var cleanDone = 0
    @Published private(set) var cleanTotal = 0
    @Published private(set) var cleanCurrent = ""

    private var autoCleanPending = false
    private var autoCleanRunning = false
    private var lastLoggedKind: CleanupKind?
    private var nextMilestone = 0
    private let historyKey = "clyro.cleanup.history"
    private static let milestones: [Int64] = [1_000_000_000, 5_000_000_000, 10_000_000_000, 25_000_000_000, 50_000_000_000, 100_000_000_000]

    init() {
        loadHistory()
    }

    var usesTrash: Bool {
        UserDefaults.standard.bool(forKey: Self.useTrashKey)
    }

    var selectedBytes: Int64 {
        categories.reduce(0) { $0 + $1.selectedBytes }
    }

    var selectedItems: Int {
        categories.reduce(0) { $0 + $1.selectedCount }
    }

    var totalBytes: Int64 {
        categories.reduce(0) { $0 + $1.totalBytes }
    }

    var totalItems: Int {
        categories.reduce(0) { $0 + $1.itemCount }
    }

    /// Bytes, die sich nicht aus dem Papierkorb zurückholen lassen.
    var selectedPermanentBytes: Int64 {
        usesTrash
            ? categories.filter { $0.kind.isPermanent }.reduce(0) { $0 + $1.selectedBytes }
            : selectedBytes
    }

    func scan() {
        guard state != .scanning && state != .cleaning else { return }
        state = .scanning
        progressBytes = 0
        progressPath = ""
        let includeDeveloperData = UserDefaults.standard.object(forKey: "includeDeveloperData") as? Bool ?? true
        let started = Date()

        let box = ScanProgressBox { [weak self] bytes, path in
            Task { @MainActor in
                self?.progressBytes = bytes
                self?.progressPath = path
            }
        }

        Task {
            let output = await Task.detached(priority: .utility) {
                CleanupProbe(includeDeveloperData: includeDeveloperData, progress: box).scan()
            }.value
            await ScanTiming.hold(since: started)
            categories = output.categories
            blockedApps = output.blockedApps
            state = .ready
            if autoCleanPending {
                autoCleanPending = false
                runAutoClean()
            }
        }
    }

    /// Wöchentliches automatisches Bereinigen: Scan, dann nur empfohlene Einträge ohne Admin-Bereiche und Papierkorb.
    /// Gibt `false` zurück, wenn gerade etwas anderes läuft.
    @discardableResult
    func autoClean() -> Bool {
        guard state == .idle else { return false }
        autoCleanPending = true
        scan()
        return true
    }

    private func runAutoClean() {
        selectRecommended()
        for index in categories.indices where categories[index].kind == .adminSystem || categories[index].kind == .trash {
            categories[index].setSelected(false)
        }
        guard selectedItems > 0 else {
            close()
            return
        }
        autoCleanRunning = true
        cleanSelected()
    }

    /// Verwirft die Ergebnisse und kehrt zum Startbildschirm zurück.
    func close() {
        guard state != .scanning && state != .cleaning else { return }
        categories = []
        blockedApps = []
        state = .idle
    }

    func selectAll() {
        for index in categories.indices { categories[index].setSelected(true) }
    }

    func selectNone() {
        for index in categories.indices { categories[index].setSelected(false) }
    }

    func selectRecommended() {
        for index in categories.indices { categories[index].selectRecommended() }
    }

    func quitBlockedApps() {
        for app in blockedApps {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) {
                running.terminate()
            }
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            state = .idle
            scan()
        }
    }

    func cleanSelected() {
        let targets: [(kind: CleanupKind, item: CleanupItem)] = categories.flatMap { category in
            category.items.filter { $0.isSelected && !$0.isLocked }.map { (kind: category.kind, item: $0) }
        }
        guard !targets.isEmpty else { return }
        state = .cleaning
        let started = Date()
        let toTrash = usesTrash
        cleanLog = []
        cleanFreed = 0
        cleanDone = 0
        cleanTotal = targets.count
        cleanCurrent = ""
        lastLoggedKind = nil
        nextMilestone = 0

        // Kurze Pausen pro Eintrag, damit man das Protokoll mitlesen kann.
        let pause = max(0.02, min(0.1, 3.0 / Double(targets.count)))
        let publish: @Sendable (CleanEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.apply(event) }
        }

        Task {
            let result = await Task.detached(priority: .utility) { () async -> (moved: Int, bytes: Int64, kinds: [CleanupKind]) in
                var moved = 0
                var processed = 0
                var bytes: Int64 = 0
                var kinds: [CleanupKind] = []
                // Systembereiche brauchen Admin-Rechte: ein einziger Passwortdialog für alle zusammen.
                let adminItems = targets.filter { $0.kind == .adminSystem }.map(\.item)
                let adminDone = adminItems.isEmpty ? false : AdminCleanup.clean(adminItems)
                for target in targets {
                    processed += 1
                    let permanent = target.kind.isPermanent || !toTrash
                    var removedAny = target.kind == .adminSystem && adminDone
                    for url in target.item.targets where target.kind != .adminSystem && !CleanupWhitelist.matches(url) {
                        do {
                            if permanent {
                                try FileManager.default.removeItem(at: url)
                            } else {
                                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                            }
                            removedAny = true
                        } catch {
                            continue
                        }
                    }
                    guard removedAny else { continue }
                    ClyroLog.append("\(permanent ? "Gelöscht" : "Papierkorb"): \(target.item.url.path)")
                    moved += 1
                    bytes += max(0, target.item.bytes)
                    if !kinds.contains(target.kind) { kinds.append(target.kind) }
                    publish(CleanEvent(
                        kind: target.kind,
                        name: target.item.displayName,
                        bytes: target.item.bytes,
                        done: processed,
                        freed: bytes
                    ))
                    try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
                }
                return (moved, bytes, kinds)
            }.value

            // Die Animation soll auch bei schnellen Bereinigungen sichtbar bleiben.
            await ScanTiming.hold(since: started)

            if result.moved > 0 {
                record(bytes: result.bytes, itemCount: result.moved, kinds: result.kinds)
                celebration = CleanupCelebration(bytes: result.bytes)
            }
            if autoCleanRunning {
                autoCleanRunning = false
                ClyroNotifier.post(
                    id: "autoclean",
                    title: String(localized: "Clyro hat aufgeräumt"),
                    body: result.moved > 0
                        ? String(localized: "\(ClyroFormat.byteCount(result.bytes)) freigegeben – automatisch, nur empfohlene Einträge.")
                        : String(localized: "Es gab nichts aufzuräumen.")
                )
            }
            // Nach dem Aufräumen beginnt wieder der Startbildschirm; Ergebnisse gibt es erst nach einem neuen Scan.
            categories = []
            blockedApps = []
            state = .idle
        }
    }

    private func apply(_ event: CleanEvent) {
        if lastLoggedKind != event.kind {
            cleanLog.append(CleanLogEntry(text: event.kind.title, bytes: nil, isHeader: true))
            lastLoggedKind = event.kind
        }
        cleanLog.append(CleanLogEntry(text: event.name, bytes: event.bytes, isHeader: false))
        while nextMilestone < Self.milestones.count && event.freed >= Self.milestones[nextMilestone] {
            cleanLog.append(CleanLogEntry(
                text: String(localized: "\(ClyroFormat.byteCount(Self.milestones[nextMilestone])) überschritten"),
                bytes: nil,
                isHeader: true
            ))
            nextMilestone += 1
        }
        if cleanLog.count > 60 { cleanLog.removeFirst(cleanLog.count - 60) }
        cleanFreed = event.freed
        cleanDone = event.done
        cleanCurrent = event.name
    }

    func dismissCelebration() {
        celebration = nil
    }

    func record(bytes: Int64, itemCount: Int, kinds: [CleanupKind]) {
        guard itemCount > 0 else { return }
        history.insert(
            CleanupRecord(id: UUID(), date: Date(), bytes: bytes, itemCount: itemCount, categories: kinds),
            at: 0
        )
        history = Array(history.prefix(50))
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([CleanupRecord].self, from: data) else { return }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}
