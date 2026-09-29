import AppKit
import Combine
import Foundation

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

    private let historyKey = "clyro.cleanup.history"

    init() {
        loadHistory()
    }

    var selectedBytes: Int64 {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.bytes }
    }

    var selectedItems: Int {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.itemCount }
    }

    func scan() {
        guard state != .scanning && state != .cleaning else { return }
        state = .scanning
        let includeDeveloperData = UserDefaults.standard.object(forKey: "includeDeveloperData") as? Bool ?? true
        let whitelist = CleanupWhitelist.current()

        Task {
            let results = await Task.detached(priority: .utility) {
                CleanupProbe.scan(includeDeveloperData: includeDeveloperData, whitelist: whitelist)
            }.value
            categories = results
            state = .ready
        }
    }

    func cleanSelected() {
        let selected = categories.filter(\.isSelected)
        let paths = selected.flatMap(\.paths)
        guard !paths.isEmpty else { return }
        state = .cleaning

        Task {
            let result = await Task.detached(priority: .utility) {
                var moved = 0
                var bytes: Int64 = 0
                for category in selected {
                    for url in category.paths {
                        let estimatedSize = FileProbe.sizeOfItem(at: url)
                        do {
                            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                            ClyroLog.append("Bereinigen: \(url.path)")
                            moved += 1
                            bytes += max(0, estimatedSize)
                        } catch {
                            continue
                        }
                    }
                }
                return (moved, bytes)
            }.value

            if result.0 > 0 {
                let estimatedBytes = result.1 > 0 ? result.1 : selected.reduce(0) { $0 + $1.bytes }
                let record = CleanupRecord(
                    id: UUID(),
                    date: Date(),
                    bytes: estimatedBytes,
                    itemCount: result.0,
                    categories: selected.map(\.kind)
                )
                history.insert(record, at: 0)
                history = Array(history.prefix(50))
                saveHistory()
            }
            state = .idle
            scan()
        }
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

    func reveal(_ category: CleanupCategory) {
        guard let first = category.paths.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([first])
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
    static func scan(includeDeveloperData: Bool, whitelist: Set<String>) -> [CleanupCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var categories = [
            category(
                .caches,
                root: home.appendingPathComponent("Library/Caches"),
                olderThanDays: 14,
                whitelist: whitelist,
                excluding: specialCacheFolders
            ),
            browserCaches(home: home, whitelist: whitelist),
            category(.logs, root: home.appendingPathComponent("Library/Logs"), olderThanDays: 14, whitelist: whitelist),
            filteredCategory(
                .installers,
                roots: [
                    "Downloads",
                    "Desktop",
                    "Library/Mobile Documents/com~apple~CloudDocs/Downloads",
                    "Library/Containers/com.apple.mail/Data/Library/Mail Downloads"
                ].map { home.appendingPathComponent($0) },
                olderThanDays: 30,
                extensions: ["dmg", "pkg", "mpkg", "iso", "xip", "zip"],
                whitelist: whitelist
            ),
            packageCaches(home: home, whitelist: whitelist),
            orphanedData(home: home, whitelist: whitelist)
        ]
        if includeDeveloperData {
            categories.append(category(
                .developerData,
                root: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                olderThanDays: 14,
                whitelist: whitelist
            ))
        }
        return categories
    }

    /// Ordner in ~/Library/Caches, die eine eigene Kategorie haben und deshalb nicht doppelt auftauchen sollen.
    private static let specialCacheFolders: Set<String> = [
        "com.apple.safari", "google", "bravesoftware", "microsoft edge", "firefox",
        "com.operasoftware.opera", "company.thebrowser.browser", "homebrew"
    ]

    private static func browserCaches(home: URL, whitelist: Set<String>) -> CleanupCategory {
        let browsers: [(bundleID: String, path: String)] = [
            ("com.apple.Safari", "Library/Caches/com.apple.Safari"),
            ("com.google.Chrome", "Library/Caches/Google/Chrome"),
            ("com.microsoft.edgemac", "Library/Caches/Microsoft Edge"),
            ("com.brave.Browser", "Library/Caches/BraveSoftware"),
            ("org.mozilla.firefox", "Library/Caches/Firefox"),
            ("com.operasoftware.Opera", "Library/Caches/com.operasoftware.Opera"),
            ("company.thebrowser.Browser", "Library/Caches/company.thebrowser.Browser")
        ]
        let urls = browsers.compactMap { browser -> URL? in
            let url = home.appendingPathComponent(browser.path)
            guard FileManager.default.fileExists(atPath: url.path),
                  !whitelist.contains(url.lastPathComponent.lowercased()),
                  NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).isEmpty else { return nil }
            return url
        }
        let bytes = urls.reduce(Int64(0)) { $0 + FileProbe.sizeOfItem(at: $1) }
        return CleanupCategory(kind: .browserCaches, bytes: bytes, itemCount: urls.count, paths: urls, isSelected: bytes > 0)
    }

    /// Einstellungen und Daten von Apps, die nicht mehr installiert sind. Bewusst vorsichtig und nie vorausgewählt.
    private static func orphanedData(home: URL, whitelist: Set<String>) -> CleanupCategory {
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
        let bytes = urls.reduce(Int64(0)) { $0 + FileProbe.sizeOfItem(at: $1) }
        return CleanupCategory(kind: .appRemnants, bytes: bytes, itemCount: urls.count, paths: urls, isSelected: false)
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

    private static func packageCaches(home: URL, whitelist: Set<String>) -> CleanupCategory {
        let threshold = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let roots = [
            ".npm/_cacache", ".cache/pip", ".gradle/caches",
            "Library/pnpm/store", ".local/share/pnpm/store",
            "Library/Caches/Homebrew/downloads"
        ].map { home.appendingPathComponent($0) }
        let urls = roots.filter { url in
            guard !whitelist.contains(url.lastPathComponent.lowercased()),
                  FileManager.default.fileExists(atPath: url.path) else { return false }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return (values?.contentModificationDate ?? .distantFuture) < threshold
        }
        let bytes = urls.reduce(Int64(0)) { $0 + FileProbe.sizeOfItem(at: $1) }
        return CleanupCategory(kind: .packageCaches, bytes: bytes, itemCount: urls.count, paths: urls, isSelected: bytes > 0)
    }

    private static func category(
        _ kind: CleanupKind,
        root: URL,
        olderThanDays days: Int,
        whitelist: Set<String>,
        excluding: Set<String> = []
    ) -> CleanupCategory {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let urls = topLevelItems(at: root).filter { url in
            guard !whitelist.contains(url.lastPathComponent.lowercased()),
                  !excluding.contains(url.lastPathComponent.lowercased()) else { return false }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            return values?.isSymbolicLink != true && (values?.contentModificationDate ?? .distantFuture) < threshold
        }
        let bytes = urls.reduce(Int64(0)) { $0 + FileProbe.sizeOfItem(at: $1) }
        return CleanupCategory(kind: kind, bytes: bytes, itemCount: urls.count, paths: urls, isSelected: bytes > 0)
    }

    private static func filteredCategory(
        _ kind: CleanupKind,
        roots: [URL],
        olderThanDays days: Int,
        extensions: Set<String>,
        whitelist: Set<String>
    ) -> CleanupCategory {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let urls = roots.flatMap { topLevelItems(at: $0) }.filter { url in
            guard !whitelist.contains(url.lastPathComponent.lowercased()) else { return false }
            guard extensions.contains(url.pathExtension.lowercased()) else { return false }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            return values?.isRegularFile == true && (values?.contentModificationDate ?? .distantFuture) < threshold
        }
        let bytes = urls.reduce(Int64(0)) { $0 + FileProbe.sizeOfItem(at: $1) }
        return CleanupCategory(kind: kind, bytes: bytes, itemCount: urls.count, paths: urls, isSelected: bytes > 0)
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
