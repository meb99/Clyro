import AppKit
import SwiftUI

// MARK: - Modell

struct ExplorerEntry: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var sizeBytes: Int64?
    var isPartial = false

    var id: URL { url }
    var name: String { url.lastPathComponent }
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
    @Published var errorMessage: String?

    private var token = ExplorerScanToken()

    init() {
        location = FileManager.default.homeDirectoryForCurrentUser
    }

    var canGoUp: Bool { location.path != "/" }

    var knownBytes: Int64 {
        entries.reduce(0) { $0 + ($1.sizeBytes ?? 0) }
    }

    func open(_ url: URL) {
        location = url
        scan()
    }

    func goUp() {
        guard canGoUp else { return }
        open(location.deletingLastPathComponent())
    }

    func scan() {
        token.cancel()
        let currentToken = ExplorerScanToken()
        token = currentToken
        let directory = location
        isScanning = true
        entries = []

        Task {
            let listed = await Task.detached(priority: .userInitiated) {
                ExplorerProbe.list(directory)
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

// MARK: - Ansicht

struct ExplorerView: View {
    @StateObject private var scanner = ExplorerScanner()
    @State private var pendingTrash: ExplorerEntry?

    private let palette = ClyroTheme.palette(for: .explorer)
    private var accent: Color { palette.accent }

    private var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return scanner.location.path.replacingOccurrences(of: home, with: "~")
    }

    private var largestBytes: Int64 {
        max(1, scanner.entries.compactMap(\.sizeBytes).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ClyroPageHeader(
                    title: "Ordner",
                    subtitle: "Klick dich durch deinen Speicher – die größten Einträge stehen oben.",
                    icon: "chart.pie.fill",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: "Sichtbar", value: ClyroFormat.byteCount(scanner.knownBytes), icon: "externaldrive", color: accent)
                Menu {
                    Button("Home") { scanner.open(FileManager.default.homeDirectoryForCurrentUser) }
                    Button("Programme") { scanner.open(URL(fileURLWithPath: "/Applications")) }
                    Button("Macintosh HD") { scanner.open(URL(fileURLWithPath: "/")) }
                    Button("Externe Laufwerke") { scanner.open(URL(fileURLWithPath: "/Volumes")) }
                } label: {
                    Label("Springen", systemImage: "location.fill")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            HStack(spacing: 10) {
                Button {
                    scanner.goUp()
                } label: {
                    Image(systemName: "arrow.up")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .disabled(!scanner.canGoUp)
                .help("Eine Ebene höher")

                Text(displayPath)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
                if scanner.isScanning {
                    ProgressView().controlSize(.small).tint(accent)
                    Text("Größen werden berechnet …")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)

            if scanner.entries.isEmpty && !scanner.isScanning {
                VStack(spacing: 10) {
                    ClyroArtifact(symbol: "folder.fill", satellite: "questionmark", accent: accent, secondary: palette.secondary, growth: 0.1)
                    Text("Nichts zu sehen")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Dieser Ordner ist leer oder macOS erlaubt Clyro keinen Einblick.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clyroPanel(padding: 20, cornerRadius: 20)
            } else {
                List(scanner.entries) { entry in
                    ExplorerRow(
                        entry: entry,
                        largestBytes: largestBytes,
                        accent: accent,
                        onOpen: { if entry.isDirectory { scanner.open(entry.url) } },
                        onTrash: { pendingTrash = entry }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparatorTint(.white.opacity(0.055))
                }
                .scrollContentBackground(.hidden)
                .clyroPanel(padding: 6, cornerRadius: 18)
            }
        }
        .padding(22)
        .onAppear {
            if scanner.entries.isEmpty && !scanner.isScanning { scanner.scan() }
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
}

private struct ExplorerRow: View {
    let entry: ExplorerEntry
    let largestBytes: Int64
    let accent: Color
    let onOpen: () -> Void
    let onTrash: () -> Void

    private var fraction: Double {
        guard let size = entry.sizeBytes else { return 0 }
        return min(1, Double(size) / Double(largestBytes))
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 30, height: 30)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(entry.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1)
                            if entry.isDirectory {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.07))
                                Capsule()
                                    .fill(accent)
                                    .frame(width: max(3, geometry.size.width * fraction))
                            }
                        }
                        .frame(height: 5)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!entry.isDirectory)

            if entry.sizeBytes == nil {
                ProgressView().controlSize(.small).frame(width: 90, alignment: .trailing)
            } else {
                HStack(spacing: 4) {
                    if entry.isPartial {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .help("macOS hat nicht alle Inhalte freigegeben – die Größe ist unvollständig.")
                    }
                    Text(ClyroFormat.byteCount(entry.sizeBytes ?? 0))
                        .font(.system(size: 12, weight: .bold))
                }
                .frame(width: 90, alignment: .trailing)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([entry.url])
            } label: {
                Image(systemName: "folder")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .help("Im Finder zeigen")

            Button(action: onTrash) {
                Image(systemName: "trash")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.52))
            .disabled(!ExplorerProbe.canTrash(entry.url) || entry.sizeBytes == nil)
            .help(ExplorerProbe.canTrash(entry.url) ? "In den Papierkorb" : "Dieser Eintrag ist geschützt")
        }
        .padding(.vertical, 4)
    }
}
