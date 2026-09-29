import AppKit
import Combine
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
        if shouldPause { slept += 0.035 }
        lock.unlock()

        publish(total, path)
        if shouldPause { Thread.sleep(forTimeInterval: 0.035) }
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

    @Published var categories: [CleanupCategory] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var history: [CleanupRecord] = []
    @Published private(set) var celebration: CleanupCelebration?
    @Published private(set) var progressBytes: Int64 = 0
    @Published private(set) var progressPath = ""
    @Published private(set) var blockedApps: [BlockedApp] = []

    private let historyKey = "clyro.cleanup.history"

    init() {
        loadHistory()
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

    /// Bytes, die endgültig gelöscht werden (Papierkorb leeren) und nicht zurückgeholt werden können.
    var selectedPermanentBytes: Int64 {
        categories.filter { $0.kind.isPermanent }.reduce(0) { $0 + $1.selectedBytes }
    }

    func scan() {
        guard state != .scanning && state != .cleaning else { return }
        state = .scanning
        progressBytes = 0
        progressPath = ""
        let includeDeveloperData = UserDefaults.standard.object(forKey: "includeDeveloperData") as? Bool ?? true
        let whitelist = CleanupWhitelist.current()
        let started = Date()

        let box = ScanProgressBox { [weak self] bytes, path in
            Task { @MainActor in
                self?.progressBytes = bytes
                self?.progressPath = path
            }
        }

        Task {
            let output = await Task.detached(priority: .utility) {
                CleanupProbe.scan(includeDeveloperData: includeDeveloperData, whitelist: whitelist, progress: box)
            }.value
            await ScanTiming.hold(since: started)
            categories = output.categories
            blockedApps = output.blockedApps
            state = .ready
        }
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

        Task {
            let result = await Task.detached(priority: .utility) { () -> (moved: Int, bytes: Int64, kinds: [CleanupKind]) in
                var moved = 0
                var bytes: Int64 = 0
                var kinds: [CleanupKind] = []
                for target in targets {
                    do {
                        if target.kind.isPermanent {
                            try FileManager.default.removeItem(at: target.item.url)
                            ClyroLog.append("Papierkorb geleert: \(target.item.url.path)")
                        } else {
                            try FileManager.default.trashItem(at: target.item.url, resultingItemURL: nil)
                            ClyroLog.append("Bereinigen: \(target.item.url.path)")
                        }
                        moved += 1
                        bytes += max(0, target.item.bytes)
                        if !kinds.contains(target.kind) { kinds.append(target.kind) }
                    } catch {
                        continue
                    }
                }
                return (moved, bytes, kinds)
            }.value

            // Die Gießanimation soll auch bei schnellen Bereinigungen sichtbar bleiben.
            await ScanTiming.hold(since: started)

            if result.moved > 0 {
                record(bytes: result.bytes, itemCount: result.moved, kinds: result.kinds)
                celebration = CleanupCelebration(bytes: result.bytes)
            }
            // Nach dem Aufräumen beginnt wieder der Startbildschirm; Ergebnisse gibt es erst nach einem neuen Scan.
            categories = []
            blockedApps = []
            state = .idle
        }
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

enum CleanupWhitelist {
    static let defaultsKey = "cleanupWhitelist"

    /// Ein Eintrag pro Zeile: Ordner- oder Dateinamen, die Clyro nie zum Bereinigen vorschlägt.
    static func current() -> Set<String> {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return Set(raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }
}

private enum CleanupProbe {
    static func scan(includeDeveloperData: Bool, whitelist: Set<String>, progress: ScanProgressBox) -> CleanupScanOutput {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let caches = home.appendingPathComponent("Library/Caches")
        var categories: [CleanupCategory] = []

        categories.append(make(
            .caches,
            urls: cacheEntries(root: caches, days: 14, whitelist: whitelist) { name in
                !name.hasPrefix("com.apple.") && !specialCacheFolders.contains(name)
            },
            recommended: true,
            progress: progress
        ))
        categories.append(make(
            .systemCaches,
            urls: cacheEntries(root: caches, days: 14, whitelist: whitelist) { name in
                name.hasPrefix("com.apple.") && name != "com.apple.safari"
            },
            recommended: true,
            progress: progress
        ))
        categories.append(make(
            .logs,
            urls: cacheEntries(root: home.appendingPathComponent("Library/Logs"), days: 14, whitelist: whitelist) { _ in true },
            recommended: true,
            progress: progress
        ))

        let browsers = browserCaches(home: home, whitelist: whitelist, progress: progress)
        categories.append(browsers.category)

        categories.append(make(
            .installers,
            urls: installerURLs(home: home, whitelist: whitelist),
            recommended: true,
            progress: progress
        ))
        categories.append(make(
            .packageCaches,
            urls: packageCacheURLs(home: home, whitelist: whitelist),
            recommended: true,
            progress: progress
        ))
        if includeDeveloperData {
            categories.append(make(
                .developerData,
                urls: cacheEntries(
                    root: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                    days: 14,
                    whitelist: whitelist
                ) { _ in true },
                recommended: true,
                progress: progress
            ))
        }
        categories.append(make(
            .appRemnants,
            urls: orphanedURLs(home: home, whitelist: whitelist),
            recommended: false,
            progress: progress
        ))
        categories.append(make(
            .trash,
            urls: topLevelItems(at: home.appendingPathComponent(".Trash")),
            recommended: false,
            progress: progress
        ))

        return CleanupScanOutput(
            categories: categories.filter { !$0.items.isEmpty },
            blockedApps: browsers.blocked
        )
    }

    // MARK: - Kategorien

    private static func make(
        _ kind: CleanupKind,
        urls: [URL],
        recommended: Bool,
        progress: ScanProgressBox
    ) -> CleanupCategory {
        var items: [CleanupItem] = []
        for url in urls {
            let bytes = FileProbe.sizeOfItem(at: url)
            progress.report(bytes: bytes, path: url.path)
            guard bytes > 0 else { continue }
            items.append(CleanupItem(url: url, bytes: bytes, isSelected: recommended, isRecommended: recommended))
        }
        items.sort { $0.bytes > $1.bytes }
        return CleanupCategory(kind: kind, items: items)
    }

    /// Ordner in ~/Library/Caches, die eine eigene Kategorie haben und deshalb nicht doppelt auftauchen sollen.
    private static let specialCacheFolders: Set<String> = [
        "com.apple.safari", "google", "bravesoftware", "microsoft edge", "firefox",
        "com.operasoftware.opera", "company.thebrowser.browser", "homebrew"
    ]

    private static func browserCaches(
        home: URL,
        whitelist: Set<String>,
        progress: ScanProgressBox
    ) -> (category: CleanupCategory, blocked: [BlockedApp]) {
        let browsers: [(name: String, bundleID: String, path: String)] = [
            ("Safari", "com.apple.Safari", "Library/Caches/com.apple.Safari"),
            ("Chrome", "com.google.Chrome", "Library/Caches/Google/Chrome"),
            ("Edge", "com.microsoft.edgemac", "Library/Caches/Microsoft Edge"),
            ("Brave", "com.brave.Browser", "Library/Caches/BraveSoftware"),
            ("Firefox", "org.mozilla.firefox", "Library/Caches/Firefox"),
            ("Opera", "com.operasoftware.Opera", "Library/Caches/com.operasoftware.Opera"),
            ("Arc", "company.thebrowser.Browser", "Library/Caches/company.thebrowser.Browser")
        ]

        var items: [CleanupItem] = []
        var blocked: [BlockedApp] = []
        for browser in browsers {
            let url = home.appendingPathComponent(browser.path)
            guard FileManager.default.fileExists(atPath: url.path),
                  !whitelist.contains(url.lastPathComponent.lowercased()) else { continue }
            let bytes = FileProbe.sizeOfItem(at: url)
            progress.report(bytes: bytes, path: url.path)
            guard bytes > 0 else { continue }

            let running = !NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty
            if running { blocked.append(BlockedApp(name: browser.name, bundleID: browser.bundleID)) }
            items.append(CleanupItem(
                url: url,
                bytes: bytes,
                isSelected: !running,
                isLocked: running,
                isRecommended: !running,
                ownerName: "\(browser.name)-Cache"
            ))
        }
        items.sort { $0.bytes > $1.bytes }
        return (CleanupCategory(kind: .browserCaches, items: items), blocked)
    }

    /// Einstellungen und Daten von Apps, die nicht mehr installiert sind. Bewusst vorsichtig und nie vorausgewählt.
    private static func orphanedURLs(home: URL, whitelist: Set<String>) -> [URL] {
        let library = home.appendingPathComponent("Library")
        let threshold = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let installedPrefixes = installedVendorPrefixes()
        let topLevelDomains: Set<String> = ["com", "org", "net", "io", "dev", "app", "co", "me", "ai"]
        let sources: [(folder: String, suffix: String)] = [
            ("Application Support", ""),
            ("Preferences", ".plist"),
            ("Saved Application State", ".savedState")
        ]

        var urls: [URL] = []
        for source in sources {
            let root = library.appendingPathComponent(source.folder, isDirectory: true)
            for url in topLevelItems(at: root) {
                var identifier = url.lastPathComponent
                if !source.suffix.isEmpty {
                    guard identifier.hasSuffix(source.suffix) else { continue }
                    identifier = String(identifier.dropLast(source.suffix.count))
                }
                let parts = identifier.split(separator: ".").map(String.init)
                guard parts.count >= 3,
                      topLevelDomains.contains(parts[0].lowercased()),
                      identifier.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
                      !identifier.lowercased().hasPrefix("com.apple."),
                      !whitelist.contains(url.lastPathComponent.lowercased()),
                      !installedPrefixes.contains("\(parts[0]).\(parts[1])".lowercased()),
                      NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) == nil else { continue }
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
                guard values?.isSymbolicLink != true,
                      (values?.contentModificationDate ?? .distantFuture) < threshold else { continue }
                urls.append(url)
            }
        }
        return urls
    }

    /// Hersteller-Präfixe (z. B. "com.google") aller installierten Apps; deren Zusatzprogramme gelten nie als verwaist.
    private static func installedVendorPrefixes() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        var prefixes = Set<String>()
        for root in roots {
            for url in topLevelItems(at: root) {
                let candidates = url.pathExtension == "app" ? [url] : topLevelItems(at: url).filter { $0.pathExtension == "app" }
                for app in candidates {
                    guard let identifier = Bundle(url: app)?.bundleIdentifier else { continue }
                    let parts = identifier.split(separator: ".")
                    if parts.count >= 2 { prefixes.insert("\(parts[0]).\(parts[1])".lowercased()) }
                }
            }
        }
        return prefixes
    }

    private static func packageCacheURLs(home: URL, whitelist: Set<String>) -> [URL] {
        let threshold = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let roots = [
            ".npm/_cacache", ".cache/pip", ".gradle/caches",
            "Library/pnpm/store", ".local/share/pnpm/store",
            "Library/Caches/Homebrew/downloads"
        ].map { home.appendingPathComponent($0) }
        return roots.filter { url in
            guard !whitelist.contains(url.lastPathComponent.lowercased()),
                  FileManager.default.fileExists(atPath: url.path) else { return false }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (values?.contentModificationDate ?? .distantFuture) < threshold
        }
    }

    private static func installerURLs(home: URL, whitelist: Set<String>) -> [URL] {
        let threshold = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip", "zip"]
        let roots = [
            "Downloads",
            "Desktop",
            "Library/Mobile Documents/com~apple~CloudDocs/Downloads",
            "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
        ].map { home.appendingPathComponent($0) }

        return roots.flatMap { topLevelItems(at: $0) }.filter { url in
            guard !whitelist.contains(url.lastPathComponent.lowercased()),
                  extensions.contains(url.pathExtension.lowercased()) else { return false }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            return values?.isRegularFile == true && (values?.contentModificationDate ?? .distantFuture) < threshold
        }
    }

    /// Oberste Einträge eines Ordners, die älter als `days` Tage sind und `include` erfüllen (Name in Kleinbuchstaben).
    private static func cacheEntries(
        root: URL,
        days: Int,
        whitelist: Set<String>,
        where include: (String) -> Bool
    ) -> [URL] {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return topLevelItems(at: root).filter { url in
            let name = url.lastPathComponent.lowercased()
            guard !whitelist.contains(name), include(name) else { return false }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            return values?.isSymbolicLink != true && (values?.contentModificationDate ?? .distantFuture) < threshold
        }
    }

    private static func topLevelItems(at root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

enum FileProbe {
    static func sizeOfItem(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let rootValues = try? url.resourceValues(forKeys: keys), rootValues.isSymbolicLink != true else { return 0 }
        if rootValues.isRegularFile == true {
            return Int64(rootValues.totalFileAllocatedSize ?? rootValues.fileAllocatedSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
