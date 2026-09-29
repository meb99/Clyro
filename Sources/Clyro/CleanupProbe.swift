import AppKit
import Darwin
import Foundation

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

struct CleanupProbe {
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
            ownerName: L10n.dynamic(rule.label)
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
        return CleanupItem(url: root, targets: targets, bytes: bytes, isSelected: true, ownerName: String(localized: "App-Protokolle"))
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
        return CleanupItem(url: root, targets: targets, bytes: bytes, isSelected: true, ownerName: String(localized: "Unvollständige Downloads"))
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
            let places = urls.map { $0.deletingLastPathComponent().lastPathComponent }.joined(separator: ", ")
            return CleanupItem(
                url: urls[0],
                targets: urls,
                bytes: bytes,
                isSelected: false,
                isRecommended: false,
                ownerName: identifier,
                detail: String(localized: "\(urls.count) Orte · \(places)")
            )
        }
    }

    // MARK: Installationsdateien

    private func installerItems(whitelist: [String]) -> [CleanupItem] {
        let roots: [(String, String)] = [
            ("Downloads", String(localized: "Downloads")), ("Desktop", String(localized: "Schreibtisch")),
            ("Documents", String(localized: "Dokumente")), ("Public", String(localized: "Öffentlich")),
            ("Library/Downloads", "Library"), ("/Users/Shared", String(localized: "Geteilt")), ("Library/Caches/Homebrew", "Homebrew"),
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
                detail: String(localized: "\(artifact.locationName) · \(artifact.ageDays) Tage")
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
