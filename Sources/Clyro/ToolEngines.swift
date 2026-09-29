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

// MARK: - Optimieren

struct OptimizeTask: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let executable: String
    let arguments: [String]
    /// Startet sichtbare Systemteile neu (Dock, Finder) und ist deshalb standardmäßig abgewählt.
    let isDisruptive: Bool

    var commandLine: String {
        ([URL(fileURLWithPath: executable).lastPathComponent] + arguments).joined(separator: " ")
    }
}

enum OptimizeCatalog {
    static let tasks: [OptimizeTask] = [
        OptimizeTask(
            id: "quicklook",
            title: "Quick-Look-Vorschauen erneuern",
            detail: "Leert den Vorschau-Cache, damit veraltete oder kaputte Miniaturen neu entstehen.",
            icon: "eye.fill",
            executable: "/usr/bin/qlmanage",
            arguments: ["-r", "cache"],
            isDisruptive: false
        ),
        OptimizeTask(
            id: "dns",
            title: "DNS-Cache leeren",
            detail: "Hilft, wenn Webseiten oder Server nach einem Umzug noch alte Adressen nutzen.",
            icon: "network",
            executable: "/usr/bin/dscacheutil",
            arguments: ["-flushcache"],
            isDisruptive: false
        ),
        OptimizeTask(
            id: "spotlight",
            title: "Spotlight-Index prüfen",
            detail: "Liest nur den Status der Suche aus und ändert nichts.",
            icon: "magnifyingglass",
            executable: "/usr/bin/mdutil",
            arguments: ["-s", "/"],
            isDisruptive: false
        ),
        OptimizeTask(
            id: "dock",
            title: "Dock neu starten",
            detail: "Behebt hängende Dock-Symbole, Mission Control und Animationsfehler.",
            icon: "dock.rectangle",
            executable: "/usr/bin/killall",
            arguments: ["Dock"],
            isDisruptive: true
        ),
        OptimizeTask(
            id: "finder",
            title: "Finder neu starten",
            detail: "Lädt Fenster und Schreibtisch neu. Offene Finder-Fenster schließen kurz.",
            icon: "folder.fill",
            executable: "/usr/bin/killall",
            arguments: ["Finder"],
            isDisruptive: true
        )
    ]
}

struct OptimizeOutcome: Hashable {
    let succeeded: Bool
    let message: String
}

enum OptimizeRunner {
    static func run(_ task: OptimizeTask, dryRun: Bool) -> OptimizeOutcome {
        if dryRun {
            return OptimizeOutcome(succeeded: true, message: "Vorschau: \(task.commandLine)")
        }
        guard FileManager.default.isExecutableFile(atPath: task.executable) else {
            return OptimizeOutcome(succeeded: false, message: "Werkzeug nicht gefunden")
        }

        ClyroLog.append("Optimieren: \(task.commandLine)")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: task.executable)
        process.arguments = task.arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
        } catch {
            return OptimizeOutcome(succeeded: false, message: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        if process.terminationStatus == 0 {
            return OptimizeOutcome(succeeded: true, message: firstLine.isEmpty ? "Erledigt" : firstLine)
        }
        return OptimizeOutcome(succeeded: false, message: firstLine.isEmpty ? "Fehlgeschlagen" : firstLine)
    }
}

// MARK: - Projekte (Purge)

enum ArtifactKind: String, CaseIterable, Identifiable, Hashable {
    case nodeModules
    case rustTarget
    case swiftBuild
    case pods
    case buildOutput

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nodeModules: "node_modules"
        case .rustTarget: "Rust target"
        case .swiftBuild: "Swift .build"
        case .pods: "CocoaPods"
        case .buildOutput: "dist / build"
        }
    }

    var icon: String {
        switch self {
        case .nodeModules: "shippingbox.fill"
        case .rustTarget: "gearshape.fill"
        case .swiftBuild: "swift"
        case .pods: "cube.fill"
        case .buildOutput: "hammer.fill"
        }
    }

    /// Ordnername und Projektdatei, die daneben liegen muss, damit der Ordner sicher als Artefakt gilt.
    static func match(folder: String, siblings: Set<String>) -> ArtifactKind? {
        switch folder {
        case "node_modules": siblings.contains("package.json") ? .nodeModules : nil
        case "target": siblings.contains("Cargo.toml") ? .rustTarget : nil
        case ".build": siblings.contains("Package.swift") ? .swiftBuild : nil
        case "Pods": siblings.contains("Podfile") ? .pods : nil
        case "dist", "build": siblings.contains("package.json") ? .buildOutput : nil
        default: nil
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

enum ProjectPurgeProbe {
    private static let rootNames = [
        "Developer", "Projects", "Projekte", "Code", "dev", "src", "repos",
        "GitHub", "Sites", "Work", "Documents", "Desktop"
    ]
    private static let maxDepth = 6

    static func scan() -> [ProjectArtifact] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var found: [(URL, ArtifactKind)] = []
        var visited = Set<String>()

        let custom = (UserDefaults.standard.string(forKey: "purgePaths") ?? "")
            .split(whereSeparator: \.isNewline)
            .map { ($0.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath }
            .filter { !$0.isEmpty }
        let roots = rootNames.map { home.appendingPathComponent($0, isDirectory: true) }
            + custom.map { URL(fileURLWithPath: $0, isDirectory: true) }

        for root in roots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  visited.insert(root.path).inserted else { continue }
            walk(root, depth: 0, into: &found)
        }

        let artifacts = found.map { url, kind -> ProjectArtifact in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            return ProjectArtifact(
                url: url,
                kind: kind,
                projectName: url.deletingLastPathComponent().lastPathComponent,
                sizeBytes: FileProbe.sizeOfItem(at: url),
                modifiedAt: values?.contentModificationDate ?? Date()
            )
        }
        return artifacts
            .filter { $0.sizeBytes > 0 }
            .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func walk(_ directory: URL, depth: Int, into found: inout [(URL, ArtifactKind)]) {
        guard depth <= maxDepth,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: []
              ) else { return }

        let siblings = Set(contents.map(\.lastPathComponent))

        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            let name = url.lastPathComponent

            if let kind = ArtifactKind.match(folder: name, siblings: siblings) {
                found.append((url, kind))
                continue
            }
            if name.hasPrefix(".") || name == "Library" || ["app", "xcodeproj", "xcworkspace"].contains(url.pathExtension) {
                continue
            }
            walk(url, depth: depth + 1, into: &found)
        }
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
    static func isProtected(_ app: InstalledApplication) -> Bool {
        app.bundleIdentifier.hasPrefix("com.apple.") || app.url.path.hasPrefix("/System/")
    }

    static func isRunning(_ app: InstalledApplication) -> Bool {
        guard !app.bundleIdentifier.isEmpty else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleIdentifier).isEmpty
    }

    static func remnants(for app: InstalledApplication) -> [AppRemnant] {
        guard !isProtected(app) else { return [] }
        let fm = FileManager.default
        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library", isDirectory: true)
        let identifier = app.bundleIdentifier
        let names = Set([app.name, app.url.deletingPathExtension().lastPathComponent]).filter { $0.count >= 3 }

        var candidates: [String] = []
        if !identifier.isEmpty {
            candidates += [
                "Application Support/\(identifier)",
                "Caches/\(identifier)",
                "Preferences/\(identifier).plist",
                "Containers/\(identifier)",
                "Saved Application State/\(identifier).savedState",
                "HTTPStorages/\(identifier)",
                "HTTPStorages/\(identifier).binarycookies",
                "WebKit/\(identifier)",
                "LaunchAgents/\(identifier).plist",
                "Application Scripts/\(identifier)",
                "Cookies/\(identifier).binarycookies"
            ]
            let groups = library.appendingPathComponent("Group Containers", isDirectory: true)
            for entry in (try? fm.contentsOfDirectory(atPath: groups.path)) ?? [] where entry.hasSuffix(identifier) {
                candidates.append("Group Containers/\(entry)")
            }
        }
        for name in names {
            candidates += ["Application Support/\(name)", "Caches/\(name)", "Logs/\(name)"]
        }

        var seen = Set<String>()
        var results: [AppRemnant] = []
        for relative in candidates {
            let url = library.appendingPathComponent(relative)
            guard fm.fileExists(atPath: url.path), seen.insert(url.path).inserted else { continue }
            results.append(AppRemnant(url: url, sizeBytes: FileProbe.sizeOfItem(at: url)))
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
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
