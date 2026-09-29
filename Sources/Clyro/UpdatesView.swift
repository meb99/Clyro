import AppKit
import SwiftUI

// MARK: - Modell

struct AppUpdate: Identifiable, Hashable {
    enum Source: Hashable {
        case appStore(URL)
        case sparkle
    }

    let appURL: URL
    let name: String
    let installed: String
    let available: String
    let source: Source

    var id: URL { appURL }
}

enum UpdateChecker {
    private struct Candidate: Sendable {
        let url: URL
        let name: String
        let bundleID: String
        let shortVersion: String
        let buildVersion: String
        let feedURL: URL?
        let isAppStore: Bool
    }

    /// Prüft App-Store-Apps über die iTunes-Suche und Apps mit Sparkle-Updater über ihren Update-Feed.
    static func check(progress: @escaping @Sendable (Int, Int) -> Void) async -> [AppUpdate] {
        let candidates = installedCandidates()
        let total = candidates.count
        var updates: [AppUpdate] = []
        var done = 0

        await withTaskGroup(of: AppUpdate?.self) { group in
            var iterator = candidates.makeIterator()
            for _ in 0..<min(8, total) {
                if let next = iterator.next() { group.addTask { await check(next) } }
            }
            while let result = await group.next() {
                done += 1
                progress(done, total)
                if let result { updates.append(result) }
                if let next = iterator.next() { group.addTask { await check(next) } }
            }
        }
        return updates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func installedCandidates() -> [Candidate] {
        let roots = [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
        ]
        var seen = Set<String>()
        var results: [Candidate] = []
        for root in roots {
            for url in Glob.children(of: root) where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let identifier = bundle.bundleIdentifier,
                      seen.insert(identifier).inserted else { continue }
                let info = bundle.infoDictionary ?? [:]
                let isAppStore = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
                let feed = (info["SUFeedURL"] as? String).flatMap(URL.init(string:))
                guard isAppStore || feed != nil else { continue }
                results.append(Candidate(
                    url: url,
                    name: (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent,
                    bundleID: identifier,
                    shortVersion: (info["CFBundleShortVersionString"] as? String) ?? "0",
                    buildVersion: (info["CFBundleVersion"] as? String) ?? "0",
                    feedURL: feed,
                    isAppStore: isAppStore
                ))
            }
        }
        return results
    }

    private static func check(_ candidate: Candidate) async -> AppUpdate? {
        if candidate.isAppStore {
            return await checkAppStore(candidate)
        }
        if let feed = candidate.feedURL {
            return await checkSparkle(candidate, feed: feed)
        }
        return nil
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return URLSession(configuration: configuration)
    }()

    private static func checkAppStore(_ candidate: Candidate) async -> AppUpdate? {
        let country = Locale.current.region?.identifier.lowercased() ?? "de"
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(candidate.bundleID)&country=\(country)"),
              let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let first = (json["results"] as? [[String: Any]])?.first,
              let version = first["version"] as? String,
              Version.isNewer(version, than: candidate.shortVersion) else { return nil }
        let storeURL = (first["trackViewUrl"] as? String).flatMap { string in
            URL(string: string.replacingOccurrences(of: "https://", with: "macappstore://"))
        } ?? URL(string: "macappstore://apps.apple.com")!
        return AppUpdate(appURL: candidate.url, name: candidate.name, installed: candidate.shortVersion,
                         available: version, source: .appStore(storeURL))
    }

    private static func checkSparkle(_ candidate: Candidate, feed: URL) async -> AppUpdate? {
        guard feed.scheme == "https" || feed.scheme == "http",
              let (data, _) = try? await session.data(from: feed) else { return nil }
        let parser = AppcastParser(data: data)
        guard let latest = parser.latest() else { return nil }

        if let short = latest.short, Version.isNewer(short, than: candidate.shortVersion) {
            return AppUpdate(appURL: candidate.url, name: candidate.name, installed: candidate.shortVersion,
                             available: short, source: .sparkle)
        }
        if latest.short == nil, let build = latest.build, Version.isNewer(build, than: candidate.buildVersion) {
            return AppUpdate(appURL: candidate.url, name: candidate.name, installed: candidate.shortVersion,
                             available: build, source: .sparkle)
        }
        return nil
    }
}

enum Version {
    /// Vergleicht Versionsnummern Zahl für Zahl (1.10 ist neuer als 1.9).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = numbers(candidate)
        let rhs = numbers(current)
        guard !lhs.isEmpty else { return false }
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func numbers(_ version: String) -> [Int] {
        version.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }
}

/// Liest aus einem Sparkle-Appcast die höchste Version, Beta-Kanäle ausgenommen.
private final class AppcastParser: NSObject, XMLParserDelegate {
    struct Entry {
        var short: String?
        var build: String?
        var isBeta = false
    }

    private let parser: XMLParser
    private var entries: [Entry] = []
    private var current: Entry?
    private var text = ""

    init(data: Data) {
        parser = XMLParser(data: data)
        super.init()
        parser.delegate = self
        parser.parse()
    }

    func latest() -> (short: String?, build: String?)? {
        let stable = entries.filter { !$0.isBeta && ($0.short != nil || $0.build != nil) }
        guard let best = stable.max(by: { lhs, rhs in
            Version.isNewer(rhs.short ?? rhs.build ?? "0", than: lhs.short ?? lhs.build ?? "0")
        }) else { return nil }
        return (best.short, best.build)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        text = ""
        if elementName == "item" { current = Entry() }
        if elementName == "enclosure", var entry = current {
            if entry.short == nil { entry.short = attributeDict["sparkle:shortVersionString"] }
            if entry.build == nil { entry.build = attributeDict["sparkle:version"] }
            current = entry
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "sparkle:shortVersionString": if !value.isEmpty { current?.short = value }
        case "sparkle:version": if !value.isEmpty { current?.build = value }
        case "sparkle:channel": if !value.isEmpty { current?.isBeta = true }
        case "item":
            if let current { entries.append(current) }
            current = nil
        default: break
        }
        text = ""
    }
}

// MARK: - Ansicht

struct UpdatesView: View {
    let accent: Color

    @State private var updates: [AppUpdate] = []
    @State private var isChecking = false
    @State private var hasChecked = false
    @State private var progressDone = 0
    @State private var progressTotal = 0

    var body: some View {
        Group {
            if !hasChecked || isChecking {
                ClyroStartStage(
                    title: "Nach Updates suchen",
                    message: "Clyro fragt den App Store und die Update-Server deiner Apps nach neuen Versionen. Es wird nichts installiert.",
                    buttonTitle: "Nach Updates suchen",
                    busyTitle: "Suche nach Updates",
                    busyMessage: progressTotal > 0 ? "\(progressDone) / \(progressTotal) Apps geprüft …" : "Apps werden gesammelt …",
                    accent: accent,
                    isBusy: isChecking,
                    action: { check() }
                )
                .padding(22)
            } else if updates.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(accent)
                    Text("Alles aktuell")
                        .font(.system(size: 24, weight: .semibold))
                    Text("Für deine App-Store- und Sparkle-Apps gibt es keine neuen Versionen.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    Button("Erneut prüfen") { check() }
                        .buttonStyle(ClyroPillButtonStyle())
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Verfügbare Updates")
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(updates.count) Apps")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 26)
                    .padding(.vertical, 12)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(updates) { update in
                                UpdateRow(update: update, accent: accent)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .scrollIndicators(.hidden)
                }
            }
        }
    }

    private func check() {
        guard !isChecking else { return }
        isChecking = true
        progressDone = 0
        progressTotal = 0
        let started = Date()
        Task {
            let found = await UpdateChecker.check { done, total in
                Task { @MainActor in
                    progressDone = done
                    progressTotal = total
                }
            }
            await ScanTiming.hold(since: started, minimum: 1.5)
            updates = found
            hasChecked = true
            isChecking = false
        }
    }
}

private struct UpdateRow: View {
    let update: AppUpdate
    let accent: Color

    var body: some View {
        HStack(spacing: 16) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: update.appURL.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 54, height: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(update.name)
                    .font(.system(size: 18, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(update.installed)
                    Text("→").foregroundStyle(.secondary.opacity(0.6))
                    Text(update.available).foregroundStyle(ClyroTheme.mint)
                    Text("·").foregroundStyle(.secondary.opacity(0.6))
                    Text(sourceLabel)
                }
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle) { open() }
                .buttonStyle(.bordered)
                .tint(accent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var sourceLabel: String {
        switch update.source {
        case .appStore: "App Store"
        case .sparkle: "Hersteller"
        }
    }

    private var buttonTitle: String {
        switch update.source {
        case .appStore: "Im App Store"
        case .sparkle: "App öffnen"
        }
    }

    private func open() {
        switch update.source {
        case .appStore(let url):
            NSWorkspace.shared.open(url)
        case .sparkle:
            NSWorkspace.shared.open(update.appURL)
        }
    }
}
