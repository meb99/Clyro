import AppKit
import SwiftUI

// MARK: - Modell

struct ExplorerEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var sizeBytes: Int64?
    var isPartial = false
    var label: String?

    var id: URL { url }
    var name: String { label ?? url.lastPathComponent }
}

/// Verhindert, dass ein abgebrochener Scan weiter Rechenzeit verbraucht.
final class ExplorerScanToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

enum ExplorerProbe {
    /// Die wichtigsten Orte der Festplatte als Startansicht (statt „/“ mit geschützten Systemordnern).
    static func curatedRoots() -> [ExplorerEntry] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates: [(URL, String?)] = [
            (home, "Users/\(NSUserName())"),
            (URL(fileURLWithPath: "/Applications"), nil),
            (URL(fileURLWithPath: "/Library"), nil),
            (URL(fileURLWithPath: "/opt/homebrew"), "opt/homebrew"),
            (URL(fileURLWithPath: "/usr/local"), "usr/local")
        ]
        return candidates.compactMap { url, label in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
            return ExplorerEntry(url: url, isDirectory: true, sizeBytes: nil, label: label)
        }
    }

    static func list(_ directory: URL) -> [ExplorerEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: []
        )) ?? []

        return urls.compactMap { url -> ExplorerEntry? in
            let values = try? url.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true { return nil }
            let isDirectory = values?.isDirectory == true
            let size: Int64? = isDirectory ? nil : Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
            return ExplorerEntry(url: url, isDirectory: isDirectory, sizeBytes: size)
        }
    }

    /// Größe eines Ordners inklusive versteckter Dateien. `partial` heißt: macOS hat Teile nicht freigegeben.
    static func size(of url: URL, isCancelled: () -> Bool) -> (bytes: Int64, partial: Bool) {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        var partial = false
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in
                partial = true
                return true
            }
        ) else { return (0, true) }

        var total: Int64 = 0
        for case let item as URL in enumerator {
            if isCancelled() { break }
            guard let values = try? item.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return (total, partial)
    }

    /// Persönliche Standardordner und alles außerhalb des Home-Ordners bleiben unantastbar.
    static func canTrash(_ url: URL) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let protected = ["Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public", "Applications"]
            .map { "\(home)/\($0)" }
        return url.path.hasPrefix(home + "/") && !protected.contains(url.path)
    }
}

@MainActor
final class ExplorerScanner: ObservableObject {
    @Published private(set) var location: URL
    @Published private(set) var entries: [ExplorerEntry] = []
    @Published private(set) var isScanning = false
    @Published private(set) var isRoot = true
    @Published var errorMessage: String?

    private var token = ExplorerScanToken()

    init() {
        location = URL(fileURLWithPath: "/")
    }

    var canGoUp: Bool { !isRoot }

    private var curatedURLs: Set<URL> {
        Set(ExplorerProbe.curatedRoots().map(\.url))
    }

    func openRoot() {
        isRoot = true
        location = URL(fileURLWithPath: "/")
        scan()
    }

    var knownBytes: Int64 {
        entries.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    func open(_ url: URL) {
        isRoot = false
        location = url
        scan()
    }

    func goUp() {
        guard canGoUp else { return }
        if curatedURLs.contains(location) {
            openRoot()
        } else {
            open(location.deletingLastPathComponent())
        }
    }

    func scan() {
        token.cancel()
        let currentToken = ExplorerScanToken()
        token = currentToken
        let directory = location
        let root = isRoot
        isScanning = true
        entries = []

        Task {
            let listed = await Task.detached(priority: .userInitiated) {
                root ? ExplorerProbe.curatedRoots() : ExplorerProbe.list(directory)
            }.value
            guard !currentToken.isCancelled else { return }
            entries = Self.sorted(listed)

            let folders = listed.filter(\.isDirectory).map(\.url)
            await withTaskGroup(of: (URL, Int64, Bool).self) { group in
                for folder in folders {
                    group.addTask(priority: .utility) {
                        let result = ExplorerProbe.size(of: folder) { currentToken.isCancelled }
                        return (folder, result.bytes, result.partial)
                    }
                }
                for await (url, bytes, partial) in group {
                    if currentToken.isCancelled {
                        group.cancelAll()
                        break
                    }
                    if let index = entries.firstIndex(where: { $0.url == url }) {
                        entries[index].sizeBytes = bytes
                        entries[index].isPartial = partial
                        entries = Self.sorted(entries)
                    }
                }
            }
            if !currentToken.isCancelled { isScanning = false }
        }
    }

    func trash(_ entry: ExplorerEntry) {
        guard ExplorerProbe.canTrash(entry.url) else { return }
        do {
            try FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)
            ClyroLog.append("Ordner: \(entry.url.path)")
            entries.removeAll { $0.url == entry.url }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func sorted(_ values: [ExplorerEntry]) -> [ExplorerEntry] {
        values.sorted {
            let left = $0.sizeBytes ?? -1
            let right = $1.sizeBytes ?? -1
            if left != right { return left > right }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Treemap

enum Treemap {
    /// Quadratische Kacheln nach dem "Squarified"-Verfahren: Fläche proportional zur Größe.
    static func layout(_ entries: [ExplorerEntry], in rect: CGRect) -> [(entry: ExplorerEntry, rect: CGRect)] {
        let items = entries
            .filter { ($0.sizeBytes ?? 0) > 0 }
            .sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
            .prefix(40)
        let total = items.reduce(0.0) { $0 + Double($1.sizeBytes ?? 0) }
        guard total > 0, rect.width > 1, rect.height > 1 else { return [] }

        let scale = Double(rect.width * rect.height) / total
        var remaining = items.map { (entry: $0, area: Double($0.sizeBytes ?? 0) * scale) }
        var free = rect
        var result: [(entry: ExplorerEntry, rect: CGRect)] = []

        while !remaining.isEmpty {
            let side = Double(min(free.width, free.height))
            var row = [remaining.removeFirst()]
            while let next = remaining.first,
                  worstRatio(row.map(\.area) + [next.area], side: side) <= worstRatio(row.map(\.area), side: side) {
                row.append(remaining.removeFirst())
            }

            let rowArea = row.reduce(0.0) { $0 + $1.area }
            if free.width >= free.height {
                let columnWidth = CGFloat(rowArea) / free.height
                var y = free.minY
                for item in row {
                    let height = CGFloat(item.area) / columnWidth
                    result.append((item.entry, CGRect(x: free.minX, y: y, width: columnWidth, height: height)))
                    y += height
                }
                free = CGRect(x: free.minX + columnWidth, y: free.minY, width: free.width - columnWidth, height: free.height)
            } else {
                let rowHeight = CGFloat(rowArea) / free.width
                var x = free.minX
                for item in row {
                    let width = CGFloat(item.area) / rowHeight
                    result.append((item.entry, CGRect(x: x, y: free.minY, width: width, height: rowHeight)))
                    x += width
                }
                free = CGRect(x: free.minX, y: free.minY + rowHeight, width: free.width, height: free.height - rowHeight)
            }
        }
        return result
    }

    private static func worstRatio(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard sum > 0, let maxArea = areas.max(), let minArea = areas.min(), minArea > 0, side > 0 else { return .infinity }
        return max(side * side * maxArea / (sum * sum), (sum * sum) / (side * side * minArea))
    }
}

// MARK: - Ansicht

struct ExplorerView: View {
    @StateObject private var scanner = ExplorerScanner()
    @State private var pendingTrash: ExplorerEntry?
    @State private var started = false
    @State private var isStarting = false

    private let palette = ClyroTheme.palette(for: .explorer)
    private var accent: Color { palette.accent }

    private var title: String {
        if scanner.isRoot { return "Gesamte Festplatte" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return scanner.location.path.replacingOccurrences(of: home, with: "~")
    }

    private var sortedEntries: [ExplorerEntry] {
        scanner.entries.sorted { ($0.sizeBytes ?? -1) > ($1.sizeBytes ?? -1) }
    }

    var body: some View {
        Group {
            if !started {
                ClyroStartStage(
                    title: "Speicher erkunden",
                    message: "Sieh auf einen Blick, welche Ordner den meisten Platz belegen, und klick dich hinein.",
                    buttonTitle: "Analysieren",
                    busyTitle: "Clyro misst deine Ordner",
                    busyMessage: "Die größten Einträge werden zuerst berechnet …",
                    accent: accent,
                    isBusy: isStarting,
                    action: { begin() }
                )
                .padding(22)
            } else {
                HStack(alignment: .top, spacing: 18) {
                    sidebar
                        .frame(width: 270)
                    VStack(alignment: .leading, spacing: 12) {
                        header
                        treemap
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
            }
        }
        .alert(
            "In den Papierkorb verschieben?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })
        ) {
            Button("Abbrechen", role: .cancel) { pendingTrash = nil }
            Button("In den Papierkorb", role: .destructive) {
                if let entry = pendingTrash { scanner.trash(entry) }
                pendingTrash = nil
            }
        } message: {
            if let entry = pendingTrash {
                Text("„\(entry.name)“ (\(ClyroFormat.byteCount(entry.sizeBytes ?? 0))) wird in den Papierkorb verschoben und lässt sich von dort zurückholen.")
            }
        }
        .alert(
            "Das hat nicht geklappt",
            isPresented: Binding(get: { scanner.errorMessage != nil }, set: { if !$0 { scanner.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) { scanner.errorMessage = nil }
        } message: {
            Text(scanner.errorMessage ?? "")
        }
    }

    private func begin() {
        guard !isStarting else { return }
        isStarting = true
        scanner.openRoot()
        Task {
            await ScanTiming.hold(since: Date(), minimum: 2.0)
            started = true
            isStarting = false
        }
    }

    // MARK: Kopf

    private var volumeText: String {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity,
              let free = values.volumeAvailableCapacityForImportantUsage else { return "" }
        let used = Int64(total) - free
        return "Belegt \(ClyroFormat.byteCount(used)) / \(ClyroFormat.byteCount(Int64(total)))"
    }

    private var usedFraction: Double {
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity, total > 0,
              let free = values.volumeAvailableCapacityForImportantUsage else { return 0 }
        return min(1, max(0, Double(Int64(total) - free) / Double(total)))
    }

    private var header: some View {
        HStack(spacing: 12) {
            if scanner.canGoUp {
                Button {
                    scanner.goUp()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .help("Eine Ebene höher")
            }
            Text(title)
                .font(.system(size: 18, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(accent).frame(width: geometry.size.width * usedFraction)
                }
            }
            .frame(width: 120, height: 6)

            Text("Dateien \(ClyroFormat.byteCount(scanner.knownBytes))")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            if !volumeText.isEmpty {
                Text("· \(volumeText)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if scanner.isScanning {
                ProgressView().controlSize(.small).tint(accent)
            }
            Button {
                scanner.scan()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.65))
            .help("Neu berechnen")
        }
        .frame(height: 32)
    }

    // MARK: Seitenleiste

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            ClyroGardenScene(phase: scanner.isScanning ? .scanning : .idle, growth: 0.3, accent: accent)
                .frame(width: 230, height: 190)
                .frame(maxWidth: .infinity)

            Text("\(scanner.entries.count) Objekte, \(ClyroFormat.byteCount(scanner.knownBytes))")
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity)

            Text("Aktueller Ordner")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.top, 6)

            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(sortedEntries) { entry in
                        SidebarRow(entry: entry, accent: accent) {
                            if entry.isDirectory { scanner.open(entry.url) }
                        }
                        .contextMenu { menu(for: entry) }
                    }
                }
            }
            .scrollIndicators(.hidden)

            Text("Rechtsklick: öffnen oder in den Papierkorb")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func menu(for entry: ExplorerEntry) -> some View {
        if entry.isDirectory {
            Button("Öffnen") { scanner.open(entry.url) }
        }
        Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
        if ExplorerProbe.canTrash(entry.url) && entry.sizeBytes != nil {
            Divider()
            Button("In den Papierkorb …", role: .destructive) { pendingTrash = entry }
        }
    }

    // MARK: Treemap

    private var treemap: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            let tiles = Treemap.layout(scanner.entries, in: bounds)

            ZStack(alignment: .topLeading) {
                if tiles.isEmpty {
                    VStack(spacing: 10) {
                        if scanner.isScanning {
                            ProgressView().controlSize(.large).tint(accent)
                            Text("Größen werden berechnet …")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Nichts zu sehen")
                                .font(.system(size: 20, weight: .semibold))
                            Text("Dieser Ordner ist leer oder macOS erlaubt Clyro keinen Einblick.")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                ForEach(Array(tiles.enumerated()), id: \.element.entry.id) { index, tile in
                    TreemapTileView(entry: tile.entry, index: index, rect: tile.rect.insetBy(dx: 3, dy: 3)) {
                        if tile.entry.isDirectory { scanner.open(tile.entry.url) }
                    }
                    .contextMenu { menu(for: tile.entry) }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: tiles.count)
        }
    }
}

private struct SidebarRow: View {
    let entry: ExplorerEntry
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: entry.isDirectory ? "folder" : "doc")
                    .font(.system(size: 17))
                    .foregroundStyle(accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if entry.sizeBytes == nil {
                        Text("wird berechnet …")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 5) {
                            if entry.isPartial {
                                Image(systemName: "lock.fill").font(.system(size: 9))
                            }
                            Text(ClyroFormat.byteCount(entry.sizeBytes ?? 0))
                        }
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if entry.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct TreemapTileView: View {
    let entry: ExplorerEntry
    let index: Int
    let rect: CGRect
    let action: () -> Void

    private static let hues: [Double] = [0.56, 0.52, 0.60, 0.48, 0.64, 0.54]

    private var fill: Color {
        let hue = Self.hues[index % Self.hues.count]
        return Color(hue: hue, saturation: 0.42, brightness: 0.62 - min(0.22, Double(index) * 0.012))
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill)
                if rect.width > 70 && rect.height > 46 {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                            Text(entry.name).lineLimit(1).truncationMode(.middle)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        Text(ClyroFormat.byteCount(entry.sizeBytes ?? 0))
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .padding(6)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: max(0, rect.width), height: max(0, rect.height))
        .position(x: rect.midX, y: rect.midY)
        .help("\(entry.name) · \(ClyroFormat.byteCount(entry.sizeBytes ?? 0))")
    }
}
