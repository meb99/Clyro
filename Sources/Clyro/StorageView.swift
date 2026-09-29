import AppKit
import SwiftUI

struct StorageView: View {
    @State private var files: [LargeFileItem] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var threshold: LargeFileThreshold = .hundredMB
    @State private var query = ""

    private let accent = ClyroTheme.palette(for: .storage).accent
    private let secondary = ClyroTheme.palette(for: .storage).secondary

    private var filteredFiles: [LargeFileItem] {
        guard !query.isEmpty else { return files }
        return files.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.locationName.localizedCaseInsensitiveContains(query)
                || $0.kind.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var totalBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !hasScanned || isScanning {
                ClyroStartStage(
                    title: String(localized: "Große Dateien finden"),
                    message: String(localized: "Clyro sucht in Downloads, Schreibtisch, Dokumenten und Filmen. Es wird nichts gelöscht."),
                    buttonTitle: String(localized: "Speicher scannen"),
                    busyTitle: String(localized: "Speicher wird durchsucht"),
                    busyMessage: String(localized: "Downloads, Schreibtisch, Dokumente und Filme werden geprüft …"),
                    accent: accent,
                    isBusy: isScanning,
                    action: { scan() }
                )
            } else {
                HStack(spacing: 14) {
                    storageSidebar
                        .frame(width: 238)

                    VStack(spacing: 12) {
                        StorageMosaicView(files: Array(filteredFiles.prefix(3)), accent: accent, secondary: secondary)
                            .frame(height: 172)
                        fileList
                    }
                }
            }
        }
        .padding(22)
        .onChange(of: threshold) {
            if hasScanned { scan() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ClyroPageHeader(
                title: String(localized: "Speicher"),
                subtitle: String(localized: "Große Dateien in Downloads, Schreibtisch, Dokumenten und Filmen."),
                icon: "square.3.layers.3d",
                accent: accent
            )
            Spacer()
            TextField("Dateien suchen", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
            Picker("Mindestgröße", selection: $threshold) {
                ForEach(LargeFileThreshold.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .frame(width: 150)
            Button {
                scan()
            } label: {
                Label(isScanning ? String(localized: "Scanne …") : String(localized: "Neu scannen"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(isScanning)
        }
    }

    private var storageSidebar: some View {
        VStack(alignment: .leading, spacing: 13) {
            ClyroArtifact(symbol: "archivebox.fill", satellite: "magnifyingglass", accent: accent, secondary: secondary)
                .scaleEffect(0.74)
                .frame(height: 126)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 2) {
                Text(ClyroFormat.byteCount(totalBytes))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                Text("\(files.count) Dateien ab \(threshold.title)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Divider().overlay(ClyroTheme.border)

            StorageSideStat(title: String(localized: "Größte Datei"), value: files.first?.displayName ?? "–", icon: "arrow.up.left.and.arrow.down.right", color: accent)
            StorageSideStat(title: String(localized: "Geprüfte Ordner"), value: String(localized: "Downloads · Desktop · Dokumente · Filme"), icon: "folder", color: secondary)

            Spacer(minLength: 0)

            Text("Clyro löscht hier nichts. Dateien lassen sich im Finder prüfen und entfernen.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .clyroPanel(padding: 16, cornerRadius: 18)
    }

    private var summary: some View {
        HStack(spacing: 14) {
            StorageSummaryTile(
                icon: "doc.text.magnifyingglass",
                title: String(localized: "Gefunden"),
                value: "\(files.count)",
                detail: String(localized: "ab \(threshold.title)"),
                color: ClyroTheme.mint
            )
            StorageSummaryTile(
                icon: "internaldrive",
                title: String(localized: "Zusammen"),
                value: ClyroFormat.byteCount(totalBytes),
                detail: String(localized: "nur eine Übersicht"),
                color: ClyroTheme.blue
            )
            StorageSummaryTile(
                icon: "arrow.up.left.and.arrow.down.right",
                title: String(localized: "Größte Datei"),
                value: files.first?.displayName ?? "–",
                detail: files.first.map { ClyroFormat.byteCount($0.sizeBytes) } ?? String(localized: "Noch keine Werte"),
                color: ClyroTheme.orange
            )
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Datei und Speicherort")
                Spacer()
                Text("Geändert").frame(width: 100, alignment: .trailing)
                Text("Größe").frame(width: 90, alignment: .trailing)
                Color.clear.frame(width: 34)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(ClyroTheme.secondaryText)
            .padding(.bottom, 12)

            Divider().overlay(.white.opacity(0.055))

            if isScanning && files.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(accent)
                    Text("Downloads, Schreibtisch, Dokumente und Filme werden geprüft …")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 210)
            } else if filteredFiles.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: query.isEmpty ? "checkmark.circle" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(accent)
                    Text(query.isEmpty ? String(localized: "Keine großen Dateien gefunden") : String(localized: "Keine passende Datei"))
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(query.isEmpty
                         ? String(localized: "In den geprüften Ordnern liegt nichts über \(threshold.title).")
                         : String(localized: "Ändere den Suchbegriff oder die Mindestgröße."))
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 210)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredFiles) { file in
                            LargeFileRow(file: file)
                                .padding(.vertical, 7)
                            if file.id != filteredFiles.last?.id {
                                Divider()
                                    .overlay(.white.opacity(0.045))
                                    .padding(.leading, 62)
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clyroPanel(padding: 14, cornerRadius: 16)
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        let minimumSize = threshold.bytes
        let started = Date()
        Task {
            let found = await Task.detached(priority: .utility) {
                LargeFileProbe.scan(minimumSize: minimumSize)
            }.value
            await ScanTiming.hold(since: started)
            files = found
            hasScanned = true
            isScanning = false
        }
    }
}

private struct StorageSideStat: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 17)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(2)
            }
        }
    }
}

private struct StorageMosaicView: View {
    let files: [LargeFileItem]
    let accent: Color
    let secondary: Color

    var body: some View {
        GeometryReader { geometry in
            if files.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(accent)
                    Text("Nach dem Scan erscheinen hier die größten Dateien.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 16).fill(ClyroTheme.card))
            } else {
                HStack(spacing: 7) {
                    StorageMosaicTile(file: files[0], color: accent.opacity(0.64))
                        .frame(width: geometry.size.width * 0.61)

                    VStack(spacing: 7) {
                        if files.indices.contains(1) {
                            StorageMosaicTile(file: files[1], color: secondary.opacity(0.66))
                        }
                        if files.indices.contains(2) {
                            StorageMosaicTile(file: files[2], color: ClyroTheme.gold.opacity(0.62))
                        } else {
                            RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.045))
                        }
                    }
                }
            }
        }
    }
}

private struct StorageMosaicTile: View {
    let file: LargeFileItem
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: file.kind.systemImage)
                .font(.system(size: 19, weight: .semibold))
            Text(file.displayName)
                .font(.system(size: 11, weight: .bold))
                .lineLimit(1)
            Text(ClyroFormat.byteCount(file.sizeBytes))
                .font(.system(size: 10, weight: .semibold))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 13).fill(color))
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)))
    }
}

private enum LargeFileThreshold: Int64, CaseIterable, Identifiable {
    case hundredMB = 100_000_000
    case fiveHundredMB = 500_000_000
    case oneGB = 1_000_000_000

    var id: Int64 { rawValue }
    var bytes: Int64 { rawValue }

    var title: String {
        switch self {
        case .hundredMB: "100 MB"
        case .fiveHundredMB: "500 MB"
        case .oneGB: "1 GB"
        }
    }
}

private struct StorageSummaryTile: View {
    let icon: String
    let title: String
    let value: String
    let detail: String
    let color: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .symbolRenderingMode(.hierarchical)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 10).fill(color.opacity(0.10)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(ClyroTheme.secondaryText)
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clyroCard(padding: 15)
    }
}

private struct LargeFileRow: View {
    let file: LargeFileItem

    var body: some View {
        HStack(spacing: 13) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 42, height: 42)
                Image(systemName: file.kind.systemImage)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ClyroTheme.mint)
                    .frame(width: 19, height: 19)
                    .background(Circle().fill(ClyroTheme.sidebar))
                    .offset(x: 3, y: 3)
            }
            .padding(.trailing, 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(file.displayName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(file.kind.title)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(ClyroTheme.mint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(ClyroTheme.mint.opacity(0.10)))
                }
                Text(file.locationName)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(ClyroTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(file.modifiedAt.formatted(date: .abbreviated, time: .omitted))
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(ClyroTheme.secondaryText)
                .frame(width: 100, alignment: .trailing)
            Text(ClyroFormat.byteCount(file.sizeBytes))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .frame(width: 90, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([file.url])
            } label: {
                Image(systemName: "folder")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(ClyroTheme.mint)
            .help("Im Finder zeigen")
            .accessibilityLabel("Im Finder zeigen")
        }
    }
}

private enum LargeFileProbe {
    static func scan(minimumSize: Int64) -> [LargeFileItem] {
        let fileManager = FileManager.default
        let home = fileManager.homeDirectoryForCurrentUser
        let roots = ["Downloads", "Desktop", "Documents", "Movies"].map {
            home.appendingPathComponent($0, isDirectory: true)
        }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey
        ]
        var results: [LargeFileItem] = []

        for root in roots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      values.isHidden != true else { continue }
                let size = Int64(values.fileSize ?? 0)
                guard size >= minimumSize else { continue }
                results.append(
                    LargeFileItem(
                        url: url,
                        sizeBytes: size,
                        modifiedAt: values.contentModificationDate ?? .distantPast
                    )
                )
            }
        }

        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
