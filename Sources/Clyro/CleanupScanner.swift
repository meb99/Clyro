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

    /// Wie Mole: Bereinigen löscht endgültig. In den Einstellungen lässt sich stattdessen der Papierkorb wählen.
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
                    title: "Clyro hat aufgeräumt",
                    body: result.moved > 0
                        ? "\(ClyroFormat.byteCount(result.bytes)) freigegeben – automatisch, nur empfohlene Einträge."
                        : "Es gab nichts aufzuräumen."
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
                text: "\(ClyroFormat.byteCount(Self.milestones[nextMilestone])) überschritten",
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

// MARK: - Whitelist

enum CleanupWhitelist {
    static let defaultsKey = "cleanupWhitelist"

    /// Ein Eintrag pro Zeile: ein Name (z. B. com.spotify.client) oder ein Pfad mit Platzhaltern (z. B. ~/Library/Caches/Foo*).
    static func entries() -> [String] {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func matches(_ url: URL) -> Bool {
        matches(url, entries: entries())
    }

    static func matches(_ url: URL, entries: [String]) -> Bool {
        guard !entries.isEmpty else { return false }
        let path = url.standardizedFileURL.path
        let components = path.split(separator: "/").map { $0.lowercased() }
        for entry in entries {
            if entry.contains("/") {
                let pattern = (entry as NSString).expandingTildeInPath
                if path == pattern || path.hasPrefix(pattern.hasSuffix("/") ? pattern : pattern + "/") { return true }
                if fnmatch(pattern, path, 0) == 0 { return true }
            } else {
                let name = entry.lowercased()
                if components.contains(where: { $0 == name || fnmatch(name, $0, 0) == 0 }) { return true }
            }
        }
        return false
    }
}

// MARK: - Regeln

/// Eine Gruppe von Pfaden, die als ein Eintrag in einer Kategorie erscheint.
/// Pfade sind relativ zum Home-Ordner (oder absolut) und dürfen `*` enthalten. Endet ein Pfad auf `/*`,
/// wird der Inhalt des Ordners gelöscht, der Ordner selbst bleibt.
private struct CleanupRule {
    let kind: CleanupKind
    let label: String
    let paths: [String]
    var owners: [String] = []
    var recommended = true
}

private enum CleanupRules {
    static let browsers: [CleanupRule] = [
        CleanupRule(kind: .browserCaches, label: "Safari-Cache", paths: ["Library/Caches/com.apple.Safari/*"],
                    owners: ["com.apple.Safari"]),
        CleanupRule(kind: .browserCaches, label: "Chrome-Cache", paths: CleanupRules.chromium("Library/Application Support/Google/Chrome")
                        + ["Library/Caches/Google/Chrome/*",
                           "Library/Application Support/Google/Chrome/*/Application Cache/*",
                           "Library/Application Support/Google/Chrome/OptGuideOnDeviceModel/*",
                           "Library/Application Support/Google/GoogleUpdater/crx_cache/*"],
                    owners: ["com.google.Chrome"]),
        CleanupRule(kind: .browserCaches, label: "Chromium-Cache", paths: ["Library/Caches/Chromium/*"],
                    owners: ["org.chromium.Chromium"]),
        CleanupRule(kind: .browserCaches, label: "Edge-Cache", paths: CleanupRules.chromium("Library/Application Support/Microsoft Edge")
                        + ["Library/Caches/com.microsoft.edgemac/*", "Library/Caches/Microsoft Edge/*"],
                    owners: ["com.microsoft.edgemac"]),
        CleanupRule(kind: .browserCaches, label: "Arc-Cache", paths: CleanupRules.chromium("Library/Application Support/Arc/User Data")
                        + ["Library/Caches/company.thebrowser.Browser/*"],
                    owners: ["company.thebrowser.Browser"]),
        CleanupRule(kind: .browserCaches, label: "Dia-Cache", paths: CleanupRules.chromium("Library/Application Support/Dia/User Data")
                        + ["Library/Caches/company.thebrowser.dia/*", "Library/Caches/Dia/User Data/*/Cache/*",
                           "Library/Caches/Dia/User Data/*/Code Cache/*"],
                    owners: ["company.thebrowser.dia"]),
        CleanupRule(kind: .browserCaches, label: "Brave-Cache", paths: CleanupRules.chromium("Library/Application Support/BraveSoftware/Brave-Browser")
                        + ["Library/Caches/BraveSoftware/Brave-Browser/*"],
                    owners: ["com.brave.Browser"]),
        CleanupRule(kind: .browserCaches, label: "Firefox-Cache", paths: ["Library/Caches/Firefox/*",
                                                                          "Library/Application Support/Firefox/Profiles/*/cache2/*"],
                    owners: ["org.mozilla.firefox"]),
        CleanupRule(kind: .browserCaches, label: "Opera-Cache", paths: ["Library/Caches/com.operasoftware.Opera/*"],
                    owners: ["com.operasoftware.Opera"]),
        CleanupRule(kind: .browserCaches, label: "Vivaldi-Cache", paths: CleanupRules.chromium("Library/Application Support/Vivaldi")
                        + ["Library/Caches/com.vivaldi.Vivaldi/*"],
                    owners: ["com.vivaldi.Vivaldi"]),
        CleanupRule(kind: .browserCaches, label: "Zen-Cache", paths: ["Library/Caches/zen/*"], owners: ["app.zen-browser.zen"]),
        CleanupRule(kind: .browserCaches, label: "Orion-Cache", paths: ["Library/Caches/com.kagi.kagimacOS/*"],
                    owners: ["com.kagi.kagimacOS"]),
        CleanupRule(kind: .browserCaches, label: "Helium-Cache", paths: CleanupRules.chromium("Library/Application Support/net.imput.helium")
                        + ["Library/Caches/net.imput.helium/*"],
                    owners: ["net.imput.helium"]),
        CleanupRule(kind: .browserCaches, label: "Comet-Cache", paths: ["Library/Caches/Comet/*"], owners: ["ai.perplexity.comet"]),
        CleanupRule(kind: .browserCaches, label: "Yandex-Cache", paths: ["Library/Caches/Yandex/YandexBrowser/*"],
                    owners: ["ru.yandex.desktop.yandex-browser"])
    ]

    /// Wiederherstellbare Chromium-Caches innerhalb eines Profilordners.
    static func chromium(_ root: String) -> [String] {
        ["Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "GraphiteDawnCache"]
            .map { "\(root)/*/\($0)/*" }
            + ["ShaderCache", "GrShaderCache", "GraphiteDawnCache", "component_crx_cache", "extensions_crx_cache", "Crashpad/completed"]
            .map { "\(root)/\($0)/*" }
    }

    static let ai: [CleanupRule] = [
        CleanupRule(kind: .aiTools, label: "ChatGPT-Cache", paths: ["Library/Caches/com.openai.chat/*"], owners: ["com.openai.chat"]),
        CleanupRule(kind: .aiTools, label: "Claude-Cache", paths: [
            "Library/Caches/com.anthropic.claudefordesktop/*",
            "Library/Application Support/Claude/Cache/*",
            "Library/Application Support/Claude/Code Cache/*",
            "Library/Application Support/Claude/GPUCache/*",
            "Library/Application Support/Claude/DawnGraphiteCache/*",
            "Library/Application Support/Claude/DawnWebGPUCache/*",
            "Library/Application Support/Claude/sentry/*"
        ], owners: ["com.anthropic.claudefordesktop"]),
        CleanupRule(kind: .aiTools, label: "Claude-Protokolle", paths: ["Library/Logs/Claude/*"]),
        CleanupRule(kind: .aiTools, label: "Codex-Browsercache", paths: [
            "Library/Caches/Codex/Default/Cache/*",
            "Library/Caches/Codex/Default/Code Cache/*",
            "Library/Caches/Codex/codex-browser-app/Cache/*",
            "Library/Caches/Codex/codex-browser-app/Code Cache/*"
        ], owners: ["com.openai.codex"]),
        CleanupRule(kind: .aiTools, label: "LM-Studio-Cache", paths: ["Library/Caches/com.lmstudio.lmstudio/*"],
                    owners: ["com.lmstudio.lmstudio"]),
        CleanupRule(kind: .aiTools, label: "Antigravity-Cache", paths: [
            "Library/Application Support/Antigravity/Cache/*",
            "Library/Application Support/Antigravity/Code Cache/*",
            "Library/Application Support/Antigravity/GPUCache/*"
        ]),
        CleanupRule(kind: .aiTools, label: "Qoder-Cache", paths: [
            "Library/Application Support/Qoder/Cache/*",
            "Library/Application Support/Qoder/CachedData/*",
            "Library/Application Support/Qoder/Code Cache/*",
            "Library/Application Support/Qoder/GPUCache/*",
            "Library/Application Support/Qoder/logs/*"
        ]),
        CleanupRule(kind: .aiTools, label: "OpenCode-Cache", paths: [".cache/opencode/*"]),
        CleanupRule(kind: .aiTools, label: "Prisma-Cache", paths: [".cache/prisma/*"])
    ]

    static let developer: [CleanupRule] = [
        CleanupRule(kind: .developerData, label: "Xcode DerivedData", paths: ["Library/Developer/Xcode/DerivedData/*"],
                    owners: ["com.apple.dt.Xcode"]),
        CleanupRule(kind: .developerData, label: "Simulator-Caches", paths: ["Library/Developer/CoreSimulator/Caches/*"],
                    owners: ["com.apple.iphonesimulator"]),
        CleanupRule(kind: .developerData, label: "Swift Package Manager", paths: ["Library/Caches/org.swift.swiftpm/*",
                                                                                  ".cache/swift-package-manager/*"]),
        CleanupRule(kind: .developerData, label: "CocoaPods", paths: ["Library/Caches/CocoaPods/*"]),
        CleanupRule(kind: .developerData, label: "npm", paths: [".npm/_cacache/*", ".npm/_logs/*", ".tnpm/_cacache/*"]),
        CleanupRule(kind: .developerData, label: "Yarn", paths: [".yarn/cache/*", "Library/Caches/Yarn/*"]),
        CleanupRule(kind: .developerData, label: "pnpm", paths: ["Library/pnpm/store/*", ".local/share/pnpm/store/*"]),
        CleanupRule(kind: .developerData, label: "Bun", paths: [".bun/install/cache/*"]),
        CleanupRule(kind: .developerData, label: "Node-Werkzeuge", paths: [
            ".cache/typescript/*", ".cache/electron/*", ".cache/node-gyp/*", ".node-gyp/*",
            ".turbo/cache/*", ".vite/cache/*", ".cache/vite/*", ".cache/webpack/*", ".parcel-cache/*",
            ".cache/eslint/*", ".cache/prettier/*", ".cache/puppeteer/*"
        ]),
        CleanupRule(kind: .developerData, label: "Python (pip, Poetry, uv)", paths: [
            "Library/Caches/pip/*", ".cache/pip/*", ".cache/poetry/*", "Library/Caches/pypoetry/artifacts/*",
            "Library/Caches/pypoetry/cache/*", ".cache/uv/*", ".pyenv/cache/*", ".cache/ruff/*", ".cache/mypy/*",
            ".jupyter/runtime/*"
        ]),
        CleanupRule(kind: .developerData, label: "Go Build-Cache", paths: ["Library/Caches/go-build/*"]),
        CleanupRule(kind: .developerData, label: "Rust (Cargo)", paths: [".cargo/registry/cache/*"]),
        CleanupRule(kind: .developerData, label: "Ruby (Gems, Bundler)", paths: [".gem/specs/*", ".bundle/cache/*", ".rbenv/cache/*"]),
        CleanupRule(kind: .developerData, label: "Gradle", paths: [".gradle/caches/*"]),
        CleanupRule(kind: .developerData, label: "Android", paths: [".android/build-cache/*", ".android/cache/*",
                                                                    "Library/Caches/Google/AndroidStudio*/*", ".cache/flutter/*"]),
        CleanupRule(kind: .developerData, label: "PHP Composer", paths: ["Library/Caches/composer/*", ".composer/cache/*"]),
        CleanupRule(kind: .developerData, label: "Homebrew", paths: ["Library/Caches/Homebrew/downloads/*"]),
        CleanupRule(kind: .developerData, label: "Container & Cloud", paths: [
            ".docker/buildx/cache/*", ".kube/cache/*", ".local/share/containers/storage/tmp/*",
            ".aws/cli/cache/*", ".config/gcloud/logs/*", ".azure/logs/*", ".cache/terraform/*", ".cache/bazel/*", ".cache/zig/*"
        ]),
        CleanupRule(kind: .developerData, label: "VS Code", paths: [
            "Library/Application Support/Code/Cache/*", "Library/Application Support/Code/CachedData/*",
            "Library/Application Support/Code/CachedExtensions/*", "Library/Application Support/Code/CachedExtensionVSIXs/*",
            "Library/Application Support/Code/logs/*", "Library/Application Support/Code/WebStorage/*/CacheStorage/*"
        ], owners: ["com.microsoft.VSCode"]),
        CleanupRule(kind: .developerData, label: "Cursor", paths: [
            "Library/Application Support/Cursor/Cache/*", "Library/Application Support/Cursor/CachedData/*",
            "Library/Application Support/Cursor/CachedExtensionVSIXs/*", "Library/Application Support/Cursor/Code Cache/*",
            "Library/Application Support/Cursor/GPUCache/*", "Library/Application Support/Cursor/logs/*"
        ], owners: ["com.todesktop.230313mzl4w4u92"]),
        CleanupRule(kind: .developerData, label: "Zed", paths: ["Library/Caches/Zed/*", "Library/Logs/Zed/*",
                                                                "Library/Application Support/Zed/node/cache/*"],
                    owners: ["dev.zed.Zed"]),
        CleanupRule(kind: .developerData, label: "Sublime Text", paths: ["Library/Caches/com.sublimetext.*/*"]),
        CleanupRule(kind: .developerData, label: "JetBrains-Protokolle", paths: ["Library/Logs/JetBrains/*"]),
        CleanupRule(kind: .developerData, label: "Entwickler-Apps", paths: [
            "Library/Caches/com.postmanlabs.mac/*", "Library/Caches/com.konghq.insomnia/*",
            "Library/Caches/com.tinyapp.TablePlus/*", "Library/Caches/com.sequel-ace.sequel-ace/*",
            "Library/Caches/com.github.GitHubDesktop/*", "Library/Caches/com.mongodb.compass/*",
            "Library/Caches/com.charlesproxy.charles/*", "Library/Caches/com.proxyman.NSProxy/*",
            "Library/Caches/com.unity3d.*/*"
        ]),
        CleanupRule(kind: .developerData, label: "Shell & Git", paths: [
            ".oh-my-zsh/cache/*", ".cache/pre-commit/*", ".zcompdump*", ".gitconfig.bak*", ".cache/curl/*", ".cache/wget/*"
        ])
    ]

    static let system: [CleanupRule] = [
        CleanupRule(kind: .systemCaches, label: "Quick-Look-Miniaturen", paths: [
            "Library/Caches/com.apple.QuickLook.thumbnailcache", "Library/Caches/Quick Look/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "Symbol-Cache", paths: ["Library/Caches/com.apple.iconservices*"]),
        CleanupRule(kind: .systemCaches, label: "WebKit-Netzwerkcache", paths: ["Library/Caches/com.apple.WebKit.Networking/*"]),
        CleanupRule(kind: .systemCaches, label: "Foto-Analyse-Cache", paths: [
            "Library/Caches/com.apple.photoanalysisd",
            "Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/*",
            "Library/Containers/com.apple.mediaanalysisd/Data/tmp/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "App Store & Medien", paths: [
            "Library/Containers/com.apple.AppStore/Data/Library/Caches/*",
            "Library/Caches/com.apple.AppleMediaServices/*",
            "Library/Containers/com.apple.AppleMediaServicesUI.UtilityExtension/Data/tmp/*",
            "Library/Containers/com.apple.AMPArtworkAgent/Data/Library/Caches/*",
            "Library/Caches/com.apple.amp.mediasevicesd"
        ]),
        CleanupRule(kind: .systemCaches, label: "Karten & Orte", paths: [
            "Library/Caches/GeoServices/*", "Library/Containers/com.apple.geod/Data/tmp/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "Hilfe & Vorschläge", paths: [
            "Library/Caches/com.apple.helpd/*", "Library/Suggestions/*",
            "Library/Caches/com.apple.duetexpertd/*", "Library/Caches/com.apple.parsecd/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "Hintergrundbilder & Memoji", paths: [
            "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/*",
            "Library/Containers/com.apple.wallpaper.extension.aerials/Data/tmp/*",
            "Library/Containers/com.apple.AvatarUI.AvatarPickerMemojiPicker/Data/Library/Caches/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "Weitere Systemdienste", paths: [
            "Library/Caches/com.apple.akd",
            "Library/Caches/com.apple.python/*",
            "Library/Caches/com.apple.rosetta.update",
            "Library/Containers/com.apple.stocks/Data/Library/Caches/*",
            "Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/*",
            "Library/Containers/com.apple.NeptuneOneExtension/Data/Library/Caches/*",
            "Library/Containers/com.apple.configurator.xpc.InternetService/Data/tmp/*",
            "Library/Application Support/AddressBook/Sources/*/Photos.cache"
        ])
    ]

    static let other: [CleanupRule] = [
        CleanupRule(kind: .other, label: "Diagnoseberichte", paths: ["Library/Logs/DiagnosticReports/*", "Library/DiagnosticReports/*"]),
        CleanupRule(kind: .other, label: "Gespeicherte App-Zustände", paths: ["Library/Saved Application State/*"]),
        CleanupRule(kind: .other, label: "Absturzberichte", paths: [
            "Library/Caches/SentryCrash/*", "Library/Caches/KSCrash/*", "Library/Caches/com.crashlytics.data/*"
        ]),
        CleanupRule(kind: .other, label: "Nachrichten-Vorschauen", paths: [
            "Library/Messages/StickerCache/*",
            "Library/Messages/Caches/Previews/Attachments/*",
            "Library/Messages/Caches/Previews/StickerCache/*"
        ])
    ]

    /// App-Caches außerhalb von ~/Library/Caches, die Mole gezielt leert.
    static let appSupport: [CleanupRule] = [
        CleanupRule(kind: .caches, label: "Discord", paths: ["Library/Application Support/discord/Cache/*",
                                                             "Library/Application Support/discord/Code Cache/*"],
                    owners: ["com.hnc.Discord"]),
        CleanupRule(kind: .caches, label: "Slack", paths: ["Library/Application Support/Slack/Cache/*",
                                                           "Library/Application Support/Slack/Code Cache/*"],
                    owners: ["com.tinyspeck.slackmacgap"]),
        CleanupRule(kind: .caches, label: "Microsoft Teams (klassisch)", paths: [
            "Library/Application Support/Microsoft/Teams/Cache/*",
            "Library/Application Support/Microsoft/Teams/Code Cache/*",
            "Library/Application Support/Microsoft/Teams/GPUCache/*",
            "Library/Application Support/Microsoft/Teams/logs/*"
        ], owners: ["com.microsoft.teams"]),
        CleanupRule(kind: .caches, label: "Steam", paths: [
            "Library/Application Support/Steam/htmlcache/*", "Library/Application Support/Steam/appcache/*",
            "Library/Application Support/Steam/depotcache/*", "Library/Application Support/Steam/steamapps/shadercache/*",
            "Library/Application Support/Steam/logs/*"
        ], owners: ["com.valvesoftware.steam"]),
        CleanupRule(kind: .caches, label: "Battle.net", paths: ["Library/Application Support/Battle.net/Cache/*"],
                    owners: ["net.battle.app"]),
        CleanupRule(kind: .caches, label: "Minecraft", paths: [
            "Library/Application Support/minecraft/logs/*", "Library/Application Support/minecraft/webcache/*",
            "Library/Application Support/minecraft/webcache2/*", "Library/Application Support/minecraft/crash-reports/*"
        ]),
        CleanupRule(kind: .caches, label: "Adobe", paths: [
            "Library/Caches/Adobe/*", "Library/Caches/com.adobe.*/*",
            "Library/Application Support/Adobe/Common/Media Cache Files/*"
        ]),
        CleanupRule(kind: .caches, label: "DaVinci Resolve CacheClip", paths: ["Movies/CacheClip/*"],
                    owners: ["com.blackmagic-design.DaVinciResolve"]),
        CleanupRule(kind: .caches, label: "Spotify", paths: ["Library/Application Support/Spotify/PersistentCache/Storage/*"],
                    owners: ["com.spotify.client"])
    ]
}

// MARK: - Schutzlisten

private enum CleanupProtection {
    /// Ordnernamen in ~/Library/Caches und ~/Library/Containers, die nie pauschal geleert werden
    /// (Eingabemethoden, Passwortmanager, Sicherheit, VPN, Lizenzen, virtuelle Maschinen …).
    static let protectedPatterns: [String] = [
        "com.apple.*", "*inputmethod*", "*ime", "com.sogou.*", "im.rime.*", "com.googlecode.rimeime.*",
        "com.nektony.*", "com.macpaw.*", "com.freemacsoft.appcleaner", "com.daisydiskapp.*",
        "com.1password.*", "com.agilebits.*", "com.lastpass.*", "com.dashlane.*", "com.bitwarden.*",
        "org.keepassxc.*", "com.keepassx.*", "com.authy.*", "com.yubico.*",
        "com.jetbrains.*", "jetbrains*", "com.microsoft.vscode*", "com.todesktop.*", "cursor",
        "com.anthropic.claude*", "claude", "com.openai.*", "chatgpt", "codex", "com.ollama.ollama", "ollama",
        "com.lmstudio.lmstudio",
        "*clash*", "*surge*", "*v2ray*", "*openvpn*", "*wireguard*", "*tailscale*", "*zerotier*", "*nordvpn*",
        "*expressvpn*", "*protonvpn*", "*mullvad*", "*surfshark*", "*windscribe*", "*cloudflare*warp*", "*1dot1dot1dot1*",
        "com.docker.*", "dev.orbstack.*", "com.getutm.utm", "com.utmapp.utm", "com.vmware.fusion", "com.parallels.*",
        "adobe", "adobe *", "* adobe*", "com.adobe.*",
        "com.crowdstrike.*", "com.sentinelone.*", "com.sentinel-labs.*", "com.eset.*", "com.jamf.*", "com.jamfsoftware.*",
        "com.paloaltonetworks.*", "com.cisco.anyconnect*", "com.cisco.secureclient*",
        "com.native-instruments*", "com.paceap.*", "com.avid.*", "com.izotope.*", "com.lasersoft-imaging.*",
        "com.displaylink.*", "ms-playwright", "app.cotypist.cotypist", "familycircle", "gippseudonymousid",
        "cctclearcutlogger", "homebrew", "mole", "clyro", "dev.meb99.clyro",
        // Cloud-Sync und Backup
        "com.dropbox.*", "com.getdropbox.*", "*dropbox*", "ws.agile.*", "com.backblaze.*", "*backblaze*", "com.box.desktop*",
        "com.microsoft.onedrive*", "com.microsoft.syncreporter", "*onedrive*", "com.google.googledrive", "com.google.keystone*",
        "*googledrive*", "com.amazon.drive", "com.synology.*", "com.shirtpocket.*", "com.digidna.imazing*",
        // Werkzeuge und Menüleisten-Apps
        "com.bjango.istatmenus*", "eu.exelban.stats", "com.monitorcontrol.*", "com.bresink.system-toolkit.*", "com.macitbetter.*",
        "com.hegenberg.*", "com.manytricks.*", "com.if.amphetamine", "com.lwouis.alt-tab-macos", "com.surteesstudios.bartender",
        "com.raycast.*", "com.raycast-x.*", "com.blacktree.quicksilver", "com.stairways.keyboardmaestro.*",
        "org.pqrs.karabiner-elements", "com.knollsoft.*", "com.amethyst.amethyst", "com.pointum.hazeover",
        "com.lightheadsw.caffeine", "com.contextual.contexts", "com.gaosun.eul", "net.matthewpalmer.vanilla",
        "com.pilotmoon.scroll-reverser", "com.happenapps.quitter",
        // Terminals und Git-Clients
        "com.googlecode.iterm2", "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "com.hyper.hyper",
        "com.termius-dmg", "com.sublimemerge", "com.torusknot.sourcetreenotmas", "com.git-tower.tower*", "com.fork.fork",
        "com.axosoft.gitkraken", "com.gitfox.gitfox",
        // Schreiben, Notizen, Aufgaben, Dateien
        "com.typora.*", "abnerworks.typora", "com.ulyssesapp.*", "com.literatureandlatte.*", "com.dayoneapp.*",
        "com.onenote.mac", "com.omnigroup.*", "com.goodnotes.goodnotes", "com.marginnote.*", "com.roamresearch.*",
        "com.reflect.reflectapp", "com.inkdrop.*", "com.coteditor.coteditor", "com.macromates.textmate", "com.panic.*",
        "com.uranusjr.macdown", "com.culturedcode.*", "com.ticktick.*", "com.microsoft.to-do", "com.trello.trello",
        "com.asana.nativeapp", "com.clickup.*", "com.monday.desktop", "com.airtable.airtable", "com.linear.linear",
        "com.binarynights.forklift*", "com.noodlesoft.hazel", "com.cyberduck.cyberduck", "io.filezilla.filezilla",
        "com.cisco.webexmeetings", "com.ringcentral.ringcentral", "com.postbox-inc.postbox",
        // Kreativ- und Audiosoftware
        "com.pixelmatorteam.*", "com.affinitydesigner.*", "com.affinityphoto.*", "com.affinitypublisher.*", "com.linearity.curve",
        "com.canva.canvadesktop", "com.autodesk.*", "com.fabfilter.*", "com.framerx.*", "com.zeplin.*", "com.invisionapp.*",
        "com.principle.*",
        // Bildschirm, Fernzugriff, Geräte
        "com.tunabellysoftware.*", "com.techsmith.*", "com.kap.kap", "com.getkap.*", "com.linebreak.cloudapp",
        "com.droplr.droplr-mac", "com.realvnc.*", "com.logmein.*", "org.chromium.chromoting*", "com.google.chrome_remote_desktop*",
        "com.citrix.*", "org.xquartz.*", "com.fujitsu.pfu.scansnap*",
        // Datenbanken und API-Werkzeuge ohne eigene Regel
        "com.valentina-db.*", "com.dbvis.dbvisualizer", "com.pgadmin.pgadmin4", "com.telerik.fiddler", "com.usebruno.app",
        // Wissenschaft, Finanzen, Lizenzen, Updater
        "com.mathworks.*", "com.ibm.spss.*", "com.wolfram.*", "com.stata.*", "org.rstudio.*", "com.tableausoftware.*",
        "com.quicken.*", "com.sas.*", "com.kolide.*", "com.setapp.desktopclient", "com.paddle.paddle*", "com.devmate.*",
        "org.sparkle-project.sparkle*", "homebrew.mxcl.*",
        // Weitere KI-Apps mit lokalen Daten
        "co.supertool.chatbox", "page.jan.jan", "com.huggingface.huggingchat", "gemini", "com.perplexity.perplexity",
        "com.drawthings.drawthings", "com.divamgupta.diffusionbee", "com.exafunction.windsurf", "com.quora.poe.electron",
        // Bildschirmschoner und virtuelle Maschinen
        "*aerial.saver", "com.johncoates.aerial*", "*fliqlo*", "com.orbstack.orbstack", "dev.kdrag0n.macvirt",
        "org.virtualbox.app.virtualbox", "com.vagrant.*"
    ]

    /// Zusätzlich nie als verwaist gewertet (Schlüssel, Signaturen, Microsoft-Dienste).
    private static let orphanNeverDelete: [String] = [
        "*1password*", "*keychain*", "*bitwarden*", "*lastpass*", "*keepass*", "*dashlane*", "*enpass*",
        "*ssh*", "*gpg*", "*gnupg*", "com.microsoft.*", "com.docker.*", "com.tencent.*"
    ]

    static func isProtected(_ name: String) -> Bool {
        let lower = name.lowercased()
        return protectedPatterns.contains { fnmatch($0, lower, 0) == 0 }
    }

    /// Namen, die nie als Rest einer deinstallierten App gelten.
    static func isProtectedBundle(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("org.cups.") { return true }
        if orphanNeverDelete.contains(where: { fnmatch($0, lower, 0) == 0 }) { return true }
        return isProtected(lower)
    }
}

// MARK: - Scanner

private final class Claims {
    private var paths: [String] = []

    func claim(_ url: URL) {
        paths.append(url.standardizedFileURL.path)
    }

    /// `true`, wenn `url` selbst, ein übergeordneter oder ein untergeordneter Ort schon vergeben ist.
    func overlaps(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return paths.contains { claimed in
            claimed == path || claimed.hasPrefix(path + "/") || path.hasPrefix(claimed + "/")
        }
    }

    func contains(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return paths.contains { claimed in claimed == path || path.hasPrefix(claimed + "/") }
    }
}

private struct CleanupProbe {
    let includeDeveloperData: Bool
    let progress: ScanProgressBox

    private let fm = FileManager.default
    private var home: URL { fm.homeDirectoryForCurrentUser }

    init(includeDeveloperData: Bool, progress: ScanProgressBox) {
        self.includeDeveloperData = includeDeveloperData
        self.progress = progress
    }

    func scan() -> CleanupScanOutput {
        let whitelist = CleanupWhitelist.entries()
        let claims = Claims()
        var buckets: [CleanupKind: [CleanupItem]] = [:]
        var blocked: [String: BlockedApp] = [:]

        func add(_ item: CleanupItem?, to kind: CleanupKind) {
            guard let item else { return }
            buckets[kind, default: []].append(item)
            if item.isLocked, let owner = item.ownerBundle {
                blocked[owner] = BlockedApp(name: RunningApps.name(of: owner) ?? owner, bundleID: owner)
            }
        }

        var rules = CleanupRules.browsers + CleanupRules.ai
        if includeDeveloperData { rules += CleanupRules.developer }
        rules += CleanupRules.system + CleanupRules.other + CleanupRules.appSupport

        for rule in rules {
            add(item(for: rule, claims: claims, whitelist: whitelist), to: rule.kind)
        }

        // Pauschal: Protokolle und App-Caches (nach den gezielten Regeln, damit nichts doppelt erscheint).
        add(logsItem(claims: claims, whitelist: whitelist), to: .other)
        add(incompleteDownloadsItem(whitelist: whitelist), to: .other)
        for item in cacheSweep(claims: claims, whitelist: whitelist) { add(item, to: .caches) }
        for item in containerCacheSweep(claims: claims, whitelist: whitelist) { add(item, to: .caches) }

        for item in orphanedItems(claims: claims, whitelist: whitelist) { add(item, to: .appRemnants) }
        for item in installerItems(whitelist: whitelist) { add(item, to: .installers) }
        for item in projectItems(whitelist: whitelist) { add(item, to: .projectArtifacts) }
        for item in trashItems() { add(item, to: .trash) }
        for item in AdminCleanup.items(whitelist: whitelist) { add(item, to: .adminSystem) }

        let categories = CleanupKind.displayOrder.compactMap { kind -> CleanupCategory? in
            guard var items = buckets[kind], !items.isEmpty else { return nil }
            items.sort { $0.bytes > $1.bytes }
            return CleanupCategory(kind: kind, items: items)
        }
        return CleanupScanOutput(categories: categories, blockedApps: blocked.values.sorted { $0.name < $1.name })
    }

    // MARK: Regeln auswerten

    private func item(for rule: CleanupRule, claims: Claims, whitelist: [String]) -> CleanupItem? {
        var targets: [URL] = []
        var anchor: URL?
        for pattern in rule.paths {
            let deletesChildren = pattern.hasSuffix("/*")
            let base = deletesChildren ? String(pattern.dropLast(2)) : pattern
            for match in Glob.expand(base, home: home) {
                if CleanupWhitelist.matches(match, entries: whitelist) { continue }
                if claims.contains(match) { continue }
                claims.claim(match)
                anchor = anchor ?? match
                if deletesChildren {
                    targets += Glob.children(of: match).filter { !CleanupWhitelist.matches($0, entries: whitelist) }
                } else if !Glob.isSymlink(match) {
                    targets.append(match)
                }
            }
        }
        guard let anchor, !targets.isEmpty else { return nil }
        let bytes = measure(targets)
        guard bytes > 0 else { return nil }

        let runningOwner = rule.owners.first { RunningApps.isRunning($0) }
        let locked = runningOwner != nil
        var item = CleanupItem(
            url: anchor,
            targets: targets,
            bytes: bytes,
            isSelected: rule.recommended && !locked,
            isLocked: locked,
            isRecommended: rule.recommended,
            ownerName: rule.label
        )
        item.ownerBundle = runningOwner
        return item
    }

    private func logsItem(claims: Claims, whitelist: [String]) -> CleanupItem? {
        let root = home.appendingPathComponent("Library/Logs")
        let targets = Glob.children(of: root).filter { url in
            let name = url.lastPathComponent
            return !["clyro", "mole", "diagnosticreports"].contains(name.lowercased())
                && !claims.overlaps(url)
                && !CleanupWhitelist.matches(url, entries: whitelist)
        }
        guard !targets.isEmpty else { return nil }
        let bytes = measure(targets)
        guard bytes > 0 else { return nil }
        return CleanupItem(url: root, targets: targets, bytes: bytes, isSelected: true, ownerName: "App-Protokolle")
    }

    private func incompleteDownloadsItem(whitelist: [String]) -> CleanupItem? {
        let root = home.appendingPathComponent("Downloads")
        let threshold = Date().addingTimeInterval(-86_400)
        let targets = Glob.children(of: root).filter { url in
            ["download", "crdownload", "part"].contains(url.pathExtension.lowercased())
                && (FileScan.modified(url) ?? .distantFuture) < threshold
                && !CleanupWhitelist.matches(url, entries: whitelist)
        }
        guard !targets.isEmpty else { return nil }
        let bytes = measure(targets)
        guard bytes > 0 else { return nil }
        return CleanupItem(url: root, targets: targets, bytes: bytes, isSelected: true, ownerName: "Unvollständige Downloads")
    }

    /// Jeder Ordner in ~/Library/Caches wird ein eigener Eintrag. Gelöscht wird sein Inhalt.
    private func cacheSweep(claims: Claims, whitelist: [String]) -> [CleanupItem] {
        let root = home.appendingPathComponent("Library/Caches")
        return Glob.children(of: root).compactMap { folder in
            let name = folder.lastPathComponent
            guard !Glob.isSymlink(folder),
                  !CleanupProtection.isProtected(name),
                  !claims.overlaps(folder),
                  !CleanupWhitelist.matches(folder, entries: whitelist) else { return nil }
            let targets = Glob.isDirectory(folder)
                ? Glob.children(of: folder).filter { !CleanupWhitelist.matches($0, entries: whitelist) }
                : [folder]
            return cacheItem(folder: folder, bundle: name, targets: targets)
        }
    }

    /// Caches sandboxed Apps unter ~/Library/Containers/<App>/Data/Library/Caches.
    private func containerCacheSweep(claims: Claims, whitelist: [String]) -> [CleanupItem] {
        let root = home.appendingPathComponent("Library/Containers")
        return Glob.children(of: root).compactMap { container in
            let bundle = container.lastPathComponent
            guard !CleanupProtection.isProtected(bundle),
                  !CleanupWhitelist.matches(container, entries: whitelist) else { return nil }
            let caches = container.appendingPathComponent("Data/Library/Caches")
            guard Glob.isDirectory(caches), !claims.overlaps(caches) else { return nil }
            let targets = Glob.children(of: caches).filter { !CleanupWhitelist.matches($0, entries: whitelist) }
            return cacheItem(folder: caches, bundle: bundle, targets: targets)
        }
    }

    private func cacheItem(folder: URL, bundle: String, targets: [URL]) -> CleanupItem? {
        guard !targets.isEmpty else { return nil }
        let bytes = measure(targets)
        guard bytes > 0 else { return nil }
        let owner = RunningApps.owner(forFolder: bundle)
        var item = CleanupItem(
            url: folder,
            targets: targets,
            bytes: bytes,
            isSelected: owner == nil,
            isLocked: owner != nil,
            ownerName: AppNames.name(for: bundle)
        )
        item.ownerBundle = owner
        return item
    }

    // MARK: Reste deinstallierter Apps

    private func orphanedItems(claims: Claims, whitelist: [String]) -> [CleanupItem] {
        let library = home.appendingPathComponent("Library")
        let installed = InstalledBundles.identifiers()
        let threshold = Date().addingTimeInterval(-30 * 86_400)
        let sources: [(folder: String, suffix: String)] = [
            ("Application Support", ""), ("Caches", ""), ("Logs", ""), ("Containers", ""),
            ("HTTPStorages", ""), ("WebKit", ""), ("Preferences", ".plist"), ("Saved Application State", ".savedState")
        ]

        var grouped: [String: [URL]] = [:]
        for source in sources {
            for url in Glob.children(of: library.appendingPathComponent(source.folder)) {
                var identifier = url.lastPathComponent
                if !source.suffix.isEmpty {
                    guard identifier.hasSuffix(source.suffix) else { continue }
                    identifier = String(identifier.dropLast(source.suffix.count))
                }
                guard BundleID.isReverseDNS(identifier),
                      !CleanupProtection.isProtectedBundle(identifier),
                      !InstalledBundles.isInstalled(identifier, installed: installed),
                      !Glob.isSymlink(url),
                      !claims.overlaps(url),
                      !CleanupWhitelist.matches(url, entries: whitelist),
                      (FileScan.modified(url) ?? .distantFuture) < threshold else { continue }
                grouped[identifier, default: []].append(url)
            }
        }

        return grouped.compactMap { identifier, urls in
            let bytes = measure(urls)
            guard bytes > 0 else { return nil }
            return CleanupItem(
                url: urls[0],
                targets: urls,
                bytes: bytes,
                isSelected: false,
                isRecommended: false,
                ownerName: identifier,
                detail: "\(urls.count) Ort(e) · \(urls.map { $0.deletingLastPathComponent().lastPathComponent }.joined(separator: ", "))"
            )
        }
    }

    // MARK: Installationsdateien

    private func installerItems(whitelist: [String]) -> [CleanupItem] {
        let roots: [(String, String)] = [
            ("Downloads", "Downloads"), ("Desktop", "Schreibtisch"), ("Documents", "Dokumente"), ("Public", "Öffentlich"),
            ("Library/Downloads", "Library"), ("/Users/Shared", "Geteilt"), ("Library/Caches/Homebrew", "Homebrew"),
            ("Library/Mobile Documents/com~apple~CloudDocs/Downloads", "iCloud"),
            ("Library/Containers/com.apple.mail/Data/Library/Mail Downloads", "Mail"),
            ("Library/Application Support/Telegram Desktop", "Telegram"), ("Downloads/Telegram Desktop", "Telegram")
        ]
        var seen = Set<String>()
        var items: [CleanupItem] = []
        for (path, source) in roots {
            let root = path.hasPrefix("/") ? URL(fileURLWithPath: path) : home.appendingPathComponent(path)
            for file in Installers.find(in: root, depth: 2) where seen.insert(file.path).inserted {
                guard !CleanupWhitelist.matches(file, entries: whitelist) else { continue }
                let bytes = FileProbe.sizeOfItem(at: file)
                progress.report(bytes: bytes, path: file.path)
                guard bytes > 0 else { continue }
                items.append(CleanupItem(
                    url: file, targets: [file], bytes: bytes,
                    isSelected: false, isRecommended: false,
                    ownerName: file.lastPathComponent, detail: source
                ))
            }
        }
        return items
    }

    // MARK: Projekt-Artefakte

    private func projectItems(whitelist: [String]) -> [CleanupItem] {
        ProjectPurgeProbe.scan().compactMap { artifact in
            guard !CleanupWhitelist.matches(artifact.url, entries: whitelist) else { return nil }
            progress.report(bytes: artifact.sizeBytes, path: artifact.url.path)
            let settled = artifact.ageDays >= 7
            return CleanupItem(
                url: artifact.url,
                targets: [artifact.url],
                bytes: artifact.sizeBytes,
                isSelected: settled,
                isRecommended: settled,
                ownerName: "\(artifact.projectName) · \(artifact.kind.title)",
                detail: "\(artifact.locationName) · \(artifact.ageDays) Tage"
            )
        }
    }

    // MARK: Papierkorb

    private func trashItems() -> [CleanupItem] {
        Glob.children(of: home.appendingPathComponent(".Trash")).compactMap { url in
            let bytes = FileProbe.sizeOfItem(at: url)
            progress.report(bytes: bytes, path: url.path)
            guard bytes > 0 else { return nil }
            return CleanupItem(url: url, targets: [url], bytes: bytes, isSelected: false, isRecommended: false)
        }
    }

    private func measure(_ urls: [URL]) -> Int64 {
        var total: Int64 = 0
        for url in urls {
            let bytes = FileProbe.sizeOfItem(at: url)
            total += bytes
            progress.report(bytes: bytes, path: url.path)
        }
        return total
    }
}

// MARK: - Hilfen

enum Glob {
    /// Löst einen Pfad mit `*`-Platzhaltern auf. Relative Pfade beziehen sich auf den Home-Ordner.
    static func expand(_ pattern: String, home: URL) -> [URL] {
        let absolute = pattern.hasPrefix("/") ? pattern : home.path + "/" + pattern
        var current: [String] = ["/"]
        for component in absolute.split(separator: "/").map(String.init) {
            var next: [String] = []
            for base in current {
                if component.contains("*") || component.contains("?") {
                    let entries = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
                    for entry in entries where fnmatch(component, entry, 0) == 0 {
                        next.append((base as NSString).appendingPathComponent(entry))
                    }
                } else {
                    let path = (base as NSString).appendingPathComponent(component)
                    if FileManager.default.fileExists(atPath: path) { next.append(path) }
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current.map { URL(fileURLWithPath: $0) }
    }

    static func children(of directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [])) ?? [])
            .filter { $0.lastPathComponent != ".DS_Store" && $0.lastPathComponent != ".localized" }
    }

    static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

enum BundleID {
    private static let topLevelDomains: Set<String> = ["com", "org", "net", "io", "dev", "app", "co", "me", "ai", "de", "uk", "us", "tv", "cc", "so", "sh"]

    static func isReverseDNS(_ identifier: String) -> Bool {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 3, topLevelDomains.contains(parts[0].lowercased()) else { return false }
        return identifier.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
    }
}

enum RunningApps {
    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    static func name(of bundleID: String) -> String? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
    }

    /// Findet die laufende App, zu der ein Cache-Ordner gehört (gleiche oder übergeordnete Bundle-ID).
    static func owner(forFolder name: String) -> String? {
        guard BundleID.isReverseDNS(name) else { return nil }
        let lower = name.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            guard let identifier = app.bundleIdentifier?.lowercased() else { continue }
            if identifier == lower || lower.hasPrefix(identifier + ".") {
                return app.bundleIdentifier
            }
        }
        return nil
    }
}

enum AppNames {
    /// Anzeigename einer App zu einem Ordnernamen, falls er eine Bundle-ID ist.
    static func name(for folder: String) -> String {
        guard BundleID.isReverseDNS(folder),
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folder) else { return folder }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum InstalledBundles {
    static func identifiers() -> Set<String> {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            "/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
            "/Applications/Setapp", home.appendingPathComponent("Applications").path
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }

        var identifiers = Set<String>()
        for root in roots {
            for url in Glob.children(of: root) {
                let apps = url.pathExtension == "app" ? [url] : Glob.children(of: url).filter { $0.pathExtension == "app" }
                for app in apps {
                    if let identifier = Bundle(url: app)?.bundleIdentifier { identifiers.insert(identifier.lowercased()) }
                }
            }
        }
        return identifiers
    }

    static func isInstalled(_ identifier: String, installed: Set<String>) -> Bool {
        let lower = identifier.lowercased()
        if installed.contains(lower) { return true }
        // Helfer und Erweiterungen (com.foo.app.helper) gehören zur Haupt-App (com.foo.app) und umgekehrt.
        if installed.contains(where: { lower.hasPrefix($0 + ".") || $0.hasPrefix(lower + ".") }) { return true }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil
    }
}

enum Installers {
    private static let extensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    static func find(in root: URL, depth: Int) -> [URL] {
        guard depth >= 0, Glob.isDirectory(root) else { return [] }
        var results: [URL] = []
        for url in Glob.children(of: root) where !Glob.isSymlink(url) {
            let ext = url.pathExtension.lowercased()
            if extensions.contains(ext) {
                results.append(url)
            } else if ext == "zip" {
                if isInstallerZip(url) { results.append(url) }
            } else if Glob.isDirectory(url), !["app", "photoslibrary", "musiclibrary"].contains(ext), depth > 0 {
                results += find(in: url, depth: depth - 1)
            }
        }
        return results
    }

    /// Eine ZIP-Datei zählt als Installer, wenn in den ersten 50 Einträgen eine App, ein Paket oder ein Image liegt.
    private static func isInstallerZip(_ url: URL) -> Bool {
        let listing = Shell.run("/usr/bin/zipinfo", ["-1", url.path], timeout: 5)
        guard listing.ok else { return false }
        return listing.output.split(separator: "\n").prefix(50).contains { line in
            line.range(of: #"\.(app|pkg|dmg|xip)(/|$)"#, options: .regularExpression) != nil
        }
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
            options: [],
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
