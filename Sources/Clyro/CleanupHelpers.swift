import AppKit
import Darwin
import Foundation

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
