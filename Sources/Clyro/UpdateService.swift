import AppKit
import SwiftUI

/// Eine veröffentlichte Version aus den GitHub-Releases.
struct ClyroRelease: Identifiable, Equatable {
    let version: String
    let notes: String
    let dmgURL: URL
    let pageURL: URL

    var id: String { version }
}

/// Prüft GitHub-Releases auf neue Versionen und installiert sie.
///
/// Die DMG wird heruntergeladen, eingebunden und `Clyro.app` an Ort und Stelle ersetzt. Danach startet Clyro neu.
/// Liegt die App nicht in einem Programme-Ordner (etwa beim Start aus Xcode), wird nur die Release-Seite geöffnet.
@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    static let autoCheckKey = "updatesAutoCheck"
    private static let lastCheckKey = "updatesLastCheck"
    private static let skippedKey = "updatesSkippedVersion"
    private nonisolated static let latestReleaseURL = URL(string: "https://api.github.com/repos/meb99/Clyro/releases/latest")!

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ClyroRelease)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var presentedRelease: ClyroRelease?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Nur eine App im Programme-Ordner ersetzt sich selbst.
    var canInstallInPlace: Bool {
        let path = Bundle.main.bundlePath
        let userApplications = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApplications + "/")
    }

    /// Automatische Prüfung höchstens einmal am Tag.
    func checkOnLaunch() {
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true
        guard enabled else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard state != .checking, state != .installing else { return }
        state = .checking
        do {
            let release = try await Self.fetchLatest()
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            guard Version.isNewer(release.version, than: currentVersion) else {
                state = .upToDate
                return
            }
            state = .available(release)
            let skipped = UserDefaults.standard.string(forKey: Self.skippedKey)
            if userInitiated || skipped != release.version {
                presentedRelease = release
            }
        } catch {
            state = .failed(String(localized: "Die Update-Prüfung ist fehlgeschlagen."))
        }
    }

    func skip(_ release: ClyroRelease) {
        UserDefaults.standard.set(release.version, forKey: Self.skippedKey)
        presentedRelease = nil
    }

    func install(_ release: ClyroRelease) {
        guard canInstallInPlace else {
            NSWorkspace.shared.open(release.pageURL)
            presentedRelease = nil
            return
        }
        state = .installing
        Task {
            do {
                let (download, _) = try await URLSession.shared.download(from: release.dmgURL)
                let dmg = FileManager.default.temporaryDirectory.appendingPathComponent("Clyro-\(release.version).dmg")
                try? FileManager.default.removeItem(at: dmg)
                try FileManager.default.moveItem(at: download, to: dmg)
                let target = URL(fileURLWithPath: Bundle.main.bundlePath)
                try await Task.detached(priority: .userInitiated) {
                    try Self.replaceApp(at: target, withContentsOf: dmg)
                }.value
                ClyroLog.append("Update: \(currentVersion) → \(release.version)")
                AppRelauncher.relaunch()
            } catch {
                state = .failed(String(localized: "Das Update konnte nicht installiert werden. Die Release-Seite wird geöffnet."))
                NSWorkspace.shared.open(release.pageURL)
            }
        }
    }

    // MARK: - Netzwerk und Installation

    private enum UpdateError: Error {
        case badResponse
        case mountFailed
        case appMissing
    }

    private nonisolated static func fetchLatest() async throws -> ClyroRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              let assets = json["assets"] as? [[String: Any]] else {
            throw UpdateError.badResponse
        }
        let urls = assets.compactMap { ($0["browser_download_url"] as? String).flatMap(URL.init(string:)) }
        guard let dmg = urls.first(where: { $0.pathExtension.lowercased() == "dmg" }) else {
            throw UpdateError.badResponse
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return ClyroRelease(version: version, notes: json["body"] as? String ?? "", dmgURL: dmg, pageURL: page)
    }

    /// Bindet die DMG ein, kopiert die neue App neben die alte und tauscht beide aus.
    private nonisolated static func replaceApp(at target: URL, withContentsOf dmg: URL) throws {
        let fm = FileManager.default
        let mountPoint = fm.temporaryDirectory.appendingPathComponent("ClyroUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        let attach = Shell.run("/usr/bin/hdiutil",
                               ["attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mountPoint.path],
                               timeout: 120)
        guard attach.ok else { throw UpdateError.mountFailed }
        defer {
            _ = Shell.run("/usr/bin/hdiutil", ["detach", mountPoint.path, "-force"], timeout: 60)
            try? fm.removeItem(at: dmg)
        }

        let newApp = mountPoint.appendingPathComponent("Clyro.app")
        guard fm.fileExists(atPath: newApp.path) else { throw UpdateError.appMissing }

        let staging = target.deletingLastPathComponent().appendingPathComponent(".Clyro-update.app")
        try? fm.removeItem(at: staging)
        try fm.copyItem(at: newApp, to: staging)
        _ = try fm.replaceItemAt(target, withItemAt: staging)
        _ = Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path], timeout: 30)
    }
}

/// Startet Clyro neu: kurz warten, bis diese Instanz beendet ist, dann dieselbe App erneut öffnen.
enum AppRelauncher {
    static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; /usr/bin/open -n \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}

/// Hinweis auf eine neue Version mit Versionshinweisen.
struct UpdateSheet: View {
    let release: ClyroRelease
    @ObservedObject private var updater = UpdateService.shared

    private var isInstalling: Bool { updater.state == .installing }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Clyro \(release.version) ist verfügbar")
                        .font(.system(size: 18, weight: .bold))
                    Text("Installiert ist Version \(updater.currentVersion).")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !release.notes.isEmpty {
                ScrollView {
                    Text(release.notes)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 180)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.05)))
            }

            if case .failed(let message) = updater.state {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClyroTheme.orange)
            }

            HStack {
                Button("Diese Version überspringen") { updater.skip(release) }
                    .disabled(isInstalling)
                Spacer()
                Button("Später") { updater.presentedRelease = nil }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isInstalling)
                Button {
                    updater.install(release)
                } label: {
                    if isInstalling {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Wird installiert …")
                        }
                    } else {
                        Text(updater.canInstallInPlace ? "Installieren und neu starten" : "Zum Download")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isInstalling)
            }
        }
        .padding(22)
        .frame(width: 520)
    }
}

// MARK: - Versionsanzeige

extension UpdateService {
    /// Suche über das App-Menü. Ist Clyro aktuell oder schlägt die Prüfung fehl, gibt ein Hinweisfenster Auskunft;
    /// ein neues Update öffnet wie gewohnt den Update-Dialog.
    func checkFromMenu() async {
        await check(userInitiated: true)
        let alert = NSAlert()
        switch state {
        case .upToDate:
            alert.messageText = String(localized: "Clyro ist aktuell.")
            alert.informativeText = String(localized: "Version \(currentVersion) ist die neueste Version.")
        case .failed(let message):
            alert.alertStyle = .warning
            alert.messageText = message
        default:
            return
        }
        alert.runModal()
    }
}

/// Kleine Versionsanzeige in der Kopfleiste. Ein Klick sucht nach Updates; liegt eines bereit, öffnet er den Update-Dialog.
struct VersionBadge: View {
    @ObservedObject private var updater = UpdateService.shared

    private var isBusy: Bool {
        updater.state == .checking || updater.state == .installing
    }

    private var available: ClyroRelease? {
        if case .available(let release) = updater.state { return release }
        return nil
    }

    private var label: String {
        switch updater.state {
        case .checking: String(localized: "Suche läuft …")
        case .installing: String(localized: "Wird installiert …")
        case .upToDate: String(localized: "v\(updater.currentVersion) · aktuell")
        case .available(let release): String(localized: "Update \(release.version)")
        case .idle, .failed: "v\(updater.currentVersion)"
        }
    }

    private var hint: String {
        switch updater.state {
        case .available(let release): String(localized: "Klicken, um Version \(release.version) zu installieren")
        case .failed(let message): message
        default: String(localized: "Version \(updater.currentVersion) · Klicken, um nach Updates zu suchen")
        }
    }

    var body: some View {
        Button {
            if let available {
                updater.presentedRelease = available
            } else {
                Task { await updater.check(userInitiated: true) }
            }
        } label: {
            HStack(spacing: 5) {
                if available != nil {
                    Circle()
                        .fill(ClyroTheme.palette(for: .applications).accent)
                        .frame(width: 6, height: 6)
                } else if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(label)
            }
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(available != nil ? Color.white.opacity(0.92) : Color.white.opacity(0.5))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(.white.opacity(available != nil ? 0.16 : 0.08)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(hint)
        .accessibilityLabel(hint)
    }
}
