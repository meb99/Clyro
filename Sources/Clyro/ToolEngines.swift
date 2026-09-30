import AppKit
import Foundation

// MARK: - Aktivitätsprotokoll

/// Jede Änderung an Dateien wird lokal protokolliert: ~/Library/Logs/Clyro/operations.log
enum ClyroLog {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Clyro/operations.log")
    }

    static func append(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date()))\t\(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
}

// MARK: - Projekte (Purge)

struct ArtifactKind: Hashable {
    let folder: String

    var title: String { folder }

    var icon: String {
        switch folder {
        case "node_modules", "vendor", "Pods": "shippingbox.fill"
        case "target", "build", "dist", "bin", "obj", ".build", "DerivedData", "zig-out": "hammer.fill"
        case "venv", ".venv", "__pycache__", ".tox", ".nox": "cube.fill"
        default: "archivebox.fill"
        }
    }
}

struct ProjectArtifact: Identifiable, Hashable {
    let url: URL
    let kind: ArtifactKind
    let projectName: String
    let sizeBytes: Int64
    let modifiedAt: Date

    var id: URL { url }

    var locationName: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.deletingLastPathComponent().path.replacingOccurrences(of: home, with: "~")
    }

    var ageDays: Int {
        Calendar.current.dateComponents([.day], from: modifiedAt, to: Date()).day ?? 0
    }
}

/// Findet wiederherstellbare Build-Ordner in Projektordnern (wie `mo purge`).
enum ProjectPurgeProbe {
    static let targets: Set<String> = [
        "node_modules", "target", "build", "dist", "venv", ".venv", ".pytest_cache", ".mypy_cache", ".tox", ".nox",
        ".ruff_cache", ".gradle", ".terragrunt-cache", "__pycache__", ".next", ".nuxt", ".output", "vendor", "bin", "obj",
        ".turbo", ".parcel-cache", ".dart_tool", ".zig-cache", "zig-out", ".angular", ".svelte-kit", ".astro", "coverage",
        "DerivedData", "Pods", ".cxx", ".expo", ".build"
    ]

    private static let projectIndicators = [
        "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "requirements.txt", "pom.xml", "build.gradle",
        "build.gradle.kts", "terragrunt.hcl", "Gemfile", "composer.json", "pubspec.yaml", "Package.swift", "Makefile",
        "build.zig", "build.zig.zon", "Podfile", "lerna.json", "pnpm-workspace.yaml", "nx.json", "rush.json", ".git"
    ]

    private static let defaultRoots = [
        "www", "dev", "Projects", "GitHub", "Code", "Workspace", "Repos", "Development", "Developer", "Projekte",
        ".codex/worktrees", ".claude/worktrees"
    ]

    private static let maxDepth = 6

    static func scan() -> [ProjectArtifact] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let custom = (UserDefaults.standard.string(forKey: "purgePaths") ?? "")
            .split(whereSeparator: \.isNewline)
            .map { ($0.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath }
            .filter { !$0.isEmpty }
        // Sind eigene Ordner eingetragen, werden nur diese durchsucht.
        let roots = custom.isEmpty
            ? defaultRoots.map { home.appendingPathComponent($0, isDirectory: true) }
            : custom.map { URL(fileURLWithPath: $0, isDirectory: true) }

        var found: [(URL, ArtifactKind)] = []
        var visited = Set<String>()
        for root in roots where Glob.isDirectory(root) && visited.insert(root.standardizedFileURL.path).inserted {
            walk(root, depth: 0, into: &found)
        }

        return found.compactMap { url, kind -> ProjectArtifact? in
            let size = FileProbe.sizeOfItem(at: url)
            guard size > 0 else { return nil }
            return ProjectArtifact(
                url: url,
                kind: kind,
                projectName: url.deletingLastPathComponent().lastPathComponent,
                sizeBytes: size,
                modifiedAt: lastActivity(of: url)
            )
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func walk(_ directory: URL, depth: Int, into found: inout [(URL, ArtifactKind)]) {
        guard depth <= maxDepth else { return }
        let contents = Glob.children(of: directory)
        let siblings = Set(contents.map(\.lastPathComponent))
        let isProject = projectIndicators.contains { siblings.contains($0) }

        for url in contents where Glob.isDirectory(url) && !Glob.isSymlink(url) {
            let name = url.lastPathComponent
            if targets.contains(name) {
                if isProject, isSafeArtifact(url, name: name, siblings: siblings) {
                    found.append((url, ArtifactKind(folder: name)))
                }
                continue
            }
            if name.hasPrefix(".") || name == "Library" || ["app", "xcodeproj", "xcworkspace", "photoslibrary"].contains(url.pathExtension) {
                continue
            }
            walk(url, depth: depth + 1, into: &found)
        }
    }

    static func isSafeArtifact(_ url: URL, name: String, siblings: Set<String>) -> Bool {
        switch name {
        case "bin", "obj":
            // Nur .NET-Build-Ausgaben, nie beliebige bin-Ordner.
            guard siblings.contains(where: { $0.hasSuffix(".csproj") || $0.hasSuffix(".fsproj") || $0.hasSuffix(".vbproj") || $0.hasSuffix(".sln") }) else { return false }
        case "vendor":
            // PHP Composer. Go-vendor-Ordner enthalten Quelltext und bleiben.
            guard siblings.contains("composer.json"), !siblings.contains("go.mod") else { return false }
        default:
            break
        }
        let inner = Set(Glob.children(of: url).map(\.lastPathComponent))
        // Verschachtelte Git-Repositories und Deployment-Schlüssel sind tabu.
        if inner.contains(".git") { return false }
        if inner.contains(where: { $0.hasSuffix(".pem") || $0.hasSuffix(".p12") || $0.hasSuffix(".key") || $0.hasPrefix("id_rsa") || $0.hasPrefix("id_ed25519") }) {
            return false
        }
        return !isGitTracked(url)
    }

    /// Ordner mit eingecheckten Dateien werden nicht angefasst. Läuft nur, wenn git ohne Installationsdialog verfügbar ist.
    private static func isGitTracked(_ url: URL) -> Bool {
        let candidates = ["/opt/homebrew/bin/git", "/usr/local/bin/git", "/Library/Developer/CommandLineTools/usr/bin/git",
                          "/Applications/Xcode.app/Contents/Developer/usr/bin/git"]
        guard let git = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return false }
        let parent = url.deletingLastPathComponent().path
        let result = Shell.run(git, ["-C", parent, "ls-files", "--", url.lastPathComponent], timeout: 5)
        return result.ok && !result.output.isEmpty
    }

    /// Letzte Änderung im Ordner selbst oder in seinen direkten Einträgen.
    private static func lastActivity(of url: URL) -> Date {
        let dates = ([url] + Glob.children(of: url).prefix(200)).compactMap { FileScan.modified($0) }
        return dates.max() ?? Date()
    }
}

// MARK: - Deinstallieren mit Rückständen

struct AppRemnant: Identifiable, Hashable {
    let url: URL
    let sizeBytes: Int64

    var id: URL { url }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}

struct UninstallResult {
    var movedItems = 0
    var bytes: Int64 = 0
    var failures: [String] = []
}

enum AppRemnantProbe {
    /// Apple-Apps, die sich deinstallieren lassen (Xcode, iWork, iMovie, GarageBand, Final Cut …).
    private static let uninstallableApple = [
        "com.apple.dt.*", "com.apple.finalcut*", "com.apple.motion*", "com.apple.compressor*", "com.apple.logic*",
        "com.apple.garageband*", "com.apple.imovie*", "com.apple.iwork.*", "com.apple.mainstage*", "com.apple.server.*",
        "com.apple.playgrounds*", "com.apple.configurator*", "com.apple.transporter*"
    ]

    /// Sicherheits- und Verwaltungssoftware braucht das offizielle Deinstallationsprogramm des Herstellers.
    private static let officialUninstallerPrefixes = [
        "com.eset.", "com.jamf.", "com.jamfsoftware.", "com.crowdstrike.", "com.sentinelone.", "com.sentinel-labs.",
        "com.paloaltonetworks.", "com.cisco.anyconnect", "com.cisco.secureclient"
    ]

    /// Wörter, die zu allgemein sind, um daraus Rückstände abzuleiten.
    private static let genericNames: Set<String> = [
        "app", "apps", "google", "microsoft", "adobe", "apple", "mozilla", "jetbrains", "setapp", "utilities", "helper",
        "update", "updater", "installer", "support", "data", "cache", "caches", "logs", "tools", "system", "library",
        "shared", "common", "desktop", "preferences", "default", "user", "users", "service", "services", "application",
        "applications", "plugins", "settings", "config", "local", "share"
    ]

    static func protectionReason(_ app: InstalledApplication) -> String? {
        if app.url.path.hasPrefix("/System/") { return String(localized: "Gehört zu macOS") }
        let identifier = app.bundleIdentifier.lowercased()
        if officialUninstallerPrefixes.contains(where: { identifier.hasPrefix($0) }) {
            return String(localized: "Bitte mit dem Deinstallationsprogramm des Herstellers entfernen")
        }
        if identifier.hasPrefix("com.apple."), !uninstallableApple.contains(where: { fnmatch($0, identifier, 0) == 0 }) {
            return String(localized: "Gehört zu macOS")
        }
        return nil
    }

    static func isProtected(_ app: InstalledApplication) -> Bool {
        protectionReason(app) != nil
    }

    static func isRunning(_ app: InstalledApplication) -> Bool {
        guard !app.bundleIdentifier.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    static func remnants(for app: InstalledApplication) -> [AppRemnant] {
        guard !isProtected(app) else { return [] }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let identifier = app.bundleIdentifier

        // Gibt es eine zweite Kopie derselben App, bleiben die gemeinsamen Daten erhalten.
        // Kopien im Papierkorb oder längst gelöschte Einträge der Launch Services zählen nicht.
        if !identifier.isEmpty {
            let ownPath = app.url.standardizedFileURL.path
            let others = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: identifier).filter { url in
                let path = url.standardizedFileURL.path
                return path != ownPath && !path.contains("/.Trash/") && fm.fileExists(atPath: path)
            }
            if !others.isEmpty { return [] }
        }

        var candidates: [URL] = []
        func add(_ relative: String) { candidates.append(library.appendingPathComponent(relative)) }

        if BundleID.isReverseDNS(identifier) || identifier.contains(".") {
            for relative in [
                "Application Support/\(identifier)", "Caches/\(identifier)", "Logs/\(identifier)",
                "Preferences/\(identifier).plist", "Preferences/\(identifier)", "Saved Application State/\(identifier).savedState",
                "Containers/\(identifier)", "WebKit/\(identifier)", "WebKit/com.apple.WebKit.WebContent/\(identifier)",
                "HTTPStorages/\(identifier)", "HTTPStorages/\(identifier).binarycookies", "Cookies/\(identifier).binarycookies",
                "Application Scripts/\(identifier)", "Input Methods/\(identifier).app", "Autosave Information/\(identifier)",
                "SyncedPreferences/\(identifier).plist", "Caches/com.apple.nsurlsessiond/Downloads/\(identifier)"
            ] { add(relative) }

            let lower = identifier.lowercased()
            for entry in Glob.children(of: library.appendingPathComponent("Preferences/ByHost")) {
                if entry.lastPathComponent.lowercased().hasPrefix(lower + ".") { candidates.append(entry) }
            }
            for entry in Glob.children(of: library.appendingPathComponent("LaunchAgents")) {
                let name = entry.lastPathComponent.lowercased()
                if name == lower + ".plist" || (name.hasPrefix(lower + ".") && name.hasSuffix(".plist")) { candidates.append(entry) }
            }
            for entry in Glob.children(of: library.appendingPathComponent("Group Containers")) {
                let name = entry.lastPathComponent.lowercased()
                if name == lower || name.hasSuffix("." + lower) || name.hasPrefix(lower + ".") { candidates.append(entry) }
            }
            // Erweiterungen der App (com.foo.app.ShareExtension …).
            for folder in ["Containers", "Application Scripts"] {
                for entry in Glob.children(of: library.appendingPathComponent(folder))
                where entry.lastPathComponent.lowercased().hasPrefix(lower + ".") {
                    candidates.append(entry)
                }
            }
        }

        let rawNames = [app.name, app.url.deletingPathExtension().lastPathComponent]
        var names: [String] = []
        for name in rawNames {
            for variant in [name, name.replacingOccurrences(of: " ", with: ""),
                            name.replacingOccurrences(of: " ", with: "_"), name.replacingOccurrences(of: " ", with: "-")]
            where variant.count >= 3 && !genericNames.contains(variant.lowercased()) && !names.contains(variant) {
                names.append(variant)
            }
        }
        for name in names {
            for relative in [
                "Application Support/\(name)", "Caches/\(name)", "Logs/\(name)", "Preferences/\(name)",
                "Preferences/\(name).plist", "Saved Application State/\(name).savedState", "Services/\(name).workflow",
                "QuickLook/\(name).qlgenerator", "Internet Plug-Ins/\(name).plugin", "Audio/Plug-Ins/Components/\(name).component",
                "Audio/Plug-Ins/VST/\(name).vst", "Audio/Plug-Ins/VST3/\(name).vst3", "PreferencePanes/\(name).prefPane",
                "Screen Savers/\(name).saver", "Frameworks/\(name).framework", "Spotlight/\(name).mdimporter",
                "ColorPickers/\(name).colorPicker", "Workflows/\(name).workflow"
            ] { add(relative) }
            let lower = name.lowercased()
            for dotFolder in [".config", ".cache", ".local/share"] {
                candidates.append(home.appendingPathComponent("\(dotFolder)/\(lower)"))
            }
        }

        var seen = Set<String>()
        var results: [AppRemnant] = []
        for url in candidates {
            let key = url.standardizedFileURL.path.lowercased()
            guard fm.fileExists(atPath: url.path), !Glob.isSymlink(url), seen.insert(key).inserted else { continue }
            results.append(AppRemnant(url: url, sizeBytes: FileProbe.sizeOfItem(at: url)))
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Legt nur die Rückstände in den Papierkorb, etwa wenn die App selbst schon gelöscht wurde.
    static func trash(_ remnants: [AppRemnant]) -> UninstallResult {
        var result = UninstallResult()
        for remnant in remnants {
            do {
                try FileManager.default.trashItem(at: remnant.url, resultingItemURL: nil)
                ClyroLog.append("Reste entfernt: \(remnant.url.path)")
                result.movedItems += 1
                result.bytes += max(0, remnant.sizeBytes)
            } catch {
                result.failures.append(remnant.url.lastPathComponent)
            }
        }
        return result
    }

    static func uninstall(_ app: InstalledApplication, remnants: [AppRemnant]) -> UninstallResult {
        var result = UninstallResult()
        guard !isProtected(app), !isRunning(app) else {
            result.failures.append(app.name)
            return result
        }

        let targets: [(URL, Int64)] = [(app.url, app.sizeBytes)] + remnants.map { ($0.url, $0.sizeBytes) }
        for (url, size) in targets {
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                ClyroLog.append("Deinstallieren: \(url.path)")
                result.movedItems += 1
                result.bytes += max(0, size)
            } catch {
                result.failures.append(url.lastPathComponent)
            }
        }
        return result
    }
}
