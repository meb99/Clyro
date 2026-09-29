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

struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var query = ""

    private let accent = ClyroTheme.palette(for: .startup).accent
    private let secondary = ClyroTheme.palette(for: .startup).secondary

    private var filtered: [StartupItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.label.localizedCaseInsensitiveContains(query)
                || $0.program.localizedCaseInsensitiveContains(query)
                || $0.scope.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ClyroPageHeader(
                    title: String(localized: "Autostart"),
                    subtitle: String(localized: "Hintergrunddienste, getrennt nach Benutzer- und Systembereich."),
                    icon: "bolt.fill",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: String(localized: "Gefunden"), value: String(localized: "\(items.count) Dienste"), icon: "bolt.horizontal.fill", color: accent)
                TextField("Dienst suchen", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
            }

            if !hasScanned || isScanning {
                ClyroStartStage(
                    title: String(localized: "Autostart prüfen"),
                    message: String(localized: "Clyro zeigt, welche Dienste im Hintergrund mit deinem Mac starten. Es wird nichts verändert."),
                    buttonTitle: String(localized: "Autostart scannen"),
                    busyTitle: String(localized: "Hintergrunddienste werden gesucht"),
                    busyMessage: String(localized: "Launch Agents und Launch Daemons werden gelesen …"),
                    accent: accent,
                    isBusy: isScanning,
                    action: { scanStartup() }
                )
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    ClyroArtifact(symbol: "bolt.slash.fill", satellite: "checkmark", accent: accent, secondary: secondary)
                    Text("Keine Autostart-Dienste gefunden")
                        .font(.system(size: 21, weight: .semibold))
                    Text("Die bekannten Launch-Agent- und Launch-Daemon-Ordner sind leer.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clyroPanel(padding: 20, cornerRadius: 20)
            } else {
                HStack(spacing: 14) {
                    VStack(spacing: 12) {
                        ClyroArtifact(symbol: "bolt.fill", satellite: "gearshape.fill", accent: accent, secondary: secondary)
                            .scaleEffect(0.76)
                            .frame(height: 142)
                        StartupScopeStat(title: String(localized: "Benutzer"), count: items.filter { $0.scope == "Benutzer" }.count, color: accent)
                        StartupScopeStat(title: String(localized: "Alle Benutzer"), count: items.filter { $0.scope == "Alle Benutzer" }.count, color: secondary)
                        StartupScopeStat(title: String(localized: "System"), count: items.filter { $0.scope == "System" }.count, color: ClyroTheme.blue)
                        Spacer()
                        Text("Clyro zeigt die Einträge aktuell nur an und verändert keine Systemdienste.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 220)
                    .clyroPanel(padding: 16, cornerRadius: 18)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { item in
                                StartupRow(item: item, accent: accent)
                                if item.id != filtered.last?.id {
                                    Divider().overlay(.white.opacity(0.05)).padding(.leading, 48)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clyroPanel(padding: 14, cornerRadius: 18)
                }
            }
        }
        .padding(22)
    }

    private func scanStartup() {
        guard !isScanning else { return }
        isScanning = true
        let started = Date()
        Task {
            let found = await Task.detached(priority: .utility) { StartupProbe.scan() }.value
            await ScanTiming.hold(since: started)
            items = found
            hasScanned = true
            isScanning = false
        }
    }
}

private struct StartupScopeStat: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Text("\(count)").font(.system(size: 12, weight: .bold))
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.045)))
    }
}

private struct StartupRow: View {
    let item: StartupItem
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black.opacity(0.72))
                .frame(width: 34, height: 34)
                .background(Circle().fill(accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(item.program)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(L10n.dynamic(item.scope))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(.white.opacity(0.065)))
        }
        .frame(height: 54)
    }
}

private enum StartupProbe {
    static func scan() -> [StartupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locations: [(URL, String)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), "Benutzer"),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "Alle Benutzer"),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "System")
        ]
        var items: [StartupItem] = []

        for (directory, scope) in locations {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "plist" {
                var plist: [String: Any]?
                if let data = try? Data(contentsOf: url),
                   let object = try? PropertyListSerialization.propertyList(from: data, format: nil) {
                    plist = object as? [String: Any]
                }
                let label = plist?["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = plist?["Program"] as? String
                    ?? (plist?["ProgramArguments"] as? [String])?.first
                    ?? String(localized: "Kein Programmpfad angegeben")
                items.append(StartupItem(url: url, label: label, program: program, scope: scope))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var cleaner: CleanupScanner

    private let accent = ClyroTheme.palette(for: .history).accent
    private let secondary = ClyroTheme.palette(for: .history).secondary

    private var totalBytes: Int64 {
        cleaner.history.reduce(0) { $0 + $1.bytes }
    }

    private var totalItems: Int {
        cleaner.history.reduce(0) { $0 + $1.itemCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ClyroPageHeader(
                    title: String(localized: "Verlauf"),
                    subtitle: String(localized: "Alle Bereinigungen mit Datum und Umfang, lokal gespeichert."),
                    icon: "clock.arrow.circlepath",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: String(localized: "Freigegeben"), value: ClyroFormat.byteCount(totalBytes), icon: "externaldrive.fill", color: accent)
                ClyroStatPill(title: String(localized: "Elemente"), value: "\(totalItems)", icon: "doc.on.doc.fill", color: secondary)
            }

            if cleaner.history.isEmpty {
                VStack(spacing: 10) {
                    ClyroArtifact(symbol: "clock.arrow.circlepath", satellite: "checkmark", accent: accent, secondary: secondary, growth: 0.05)
                    Text("Noch kein Verlauf")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Jede Bereinigung pflanzt einen Baum.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clyroPanel(padding: 20, cornerRadius: 20)
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dein Wald")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Jede Bereinigung pflanzt einen Baum.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        ClyroForest(records: cleaner.history)
                            .frame(height: 130)
                        Text("\(min(cleaner.history.count, 40)) Bäume")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Die Größe entspricht dem freigegebenen Speicher, die Farbe der Jahreszeit.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clyroPanel(padding: 16, cornerRadius: 18)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Freigegeben pro Woche")
                            .font(.system(size: 13, weight: .semibold))
                        SavingsChart(records: cleaner.history, accent: accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clyroPanel(padding: 16, cornerRadius: 18)
                }
                .frame(height: 250)

                HStack(spacing: 14) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(cleaner.history.enumerated()), id: \.element.id) { index, record in
                                HistoryTimelineRow(record: record, isLast: index == cleaner.history.count - 1, accent: accent)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .clyroPanel(padding: 14, cornerRadius: 18)
                }
            }
        }
        .padding(22)
    }
}

private struct HistoryTimelineRow: View {
    let record: CleanupRecord
    let isLast: Bool
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.72))
                }
                .frame(width: 28, height: 28)
                if !isLast {
                    Rectangle().fill(accent.opacity(0.24)).frame(width: 2, height: 34)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.categories.map(\.title).joined(separator: ", "))
                    .font(.system(size: 12, weight: .semibold))
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(record.itemCount) Elemente")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ClyroFormat.byteCount(record.bytes))
                .font(.system(size: 12, weight: .bold))
                .frame(width: 86, alignment: .trailing)
        }
        .frame(minHeight: 62, alignment: .top)
    }
}

struct SettingsView: View {
    @AppStorage("includeDeveloperData") private var includeDeveloperData = true
    @AppStorage(CleanupScanner.useTrashKey) private var useTrash = false
    @AppStorage(CleanupWhitelist.defaultsKey) private var whitelist = ""
    @AppStorage("purgePaths") private var purgePaths = ""
    @AppStorage("optimizeDryRun") private var optimizeDryRun = false
    @AppStorage(OptimizeCatalog.excludedKey) private var excludedTasks = ""
    @AppStorage(ReminderService.lowDiskKey) private var remindLowDisk = false
    @AppStorage(ReminderService.lowDiskGBKey) private var lowDiskGB = 20
    @AppStorage(ReminderService.staleKey) private var remindStale = false
    @AppStorage(ReminderService.staleDaysKey) private var staleDays = 14
    @AppStorage(ReminderService.autoCleanKey) private var autoClean = false
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var touchID = TouchIDSudo.isEnabled
    @State private var touchIDBusy = false

    var body: some View {
        Form {
            Section("Allgemein") {
                LabeledContent("Sprache") {
                    LanguageSwitch()
                }
                Text("Clyro startet nach dem Wechsel einmal neu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Clyro bei der Anmeldung starten", isOn: Binding(
                    get: { launchAtLogin },
                    set: { value in
                        LaunchAtLogin.setEnabled(value)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                Text("Das Symbol in der Menüleiste ist dann nach jedem Neustart verfügbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Touch ID für sudo im Terminal", isOn: Binding(
                    get: { touchID },
                    set: { value in
                        touchIDBusy = true
                        Task.detached {
                            _ = TouchIDSudo.setEnabled(value)
                            let now = TouchIDSudo.isEnabled
                            await MainActor.run {
                                touchID = now
                                touchIDBusy = false
                            }
                        }
                    }
                ))
                .disabled(touchIDBusy)
                Text("Trägt pam_tid in /etc/pam.d/sudo_local ein. macOS fragt dafür einmal nach dem Administratorpasswort; die Einstellung bleibt bei Systemupdates erhalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Erinnerungen") {
                Toggle("Melden, wenn wenig Speicher frei ist", isOn: $remindLowDisk)
                if remindLowDisk {
                    Stepper("Unter \(lowDiskGB) GB frei", value: $lowDiskGB, in: 5...500, step: 5)
                }
                Toggle("Erinnern, wenn lange nicht bereinigt wurde", isOn: $remindStale)
                if remindStale {
                    Stepper("Nach \(staleDays) Tagen", value: $staleDays, in: 3...90)
                }
                Toggle("Jede Woche automatisch bereinigen", isOn: $autoClean)
                Text("Automatisch werden nur empfohlene Einträge bereinigt – ohne Systembereiche (Admin) und ohne Papierkorb. Clyro meldet danach, wie viel frei wurde.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: remindLowDisk) { _, on in if on { ClyroNotifier.requestAuthorization() } }
            .onChange(of: remindStale) { _, on in if on { ClyroNotifier.requestAuthorization() } }
            .onChange(of: autoClean) { _, on in if on { ClyroNotifier.requestAuthorization() } }
            Section("Bereinigen") {
                Toggle("Entwicklerwerkzeuge prüfen", isOn: $includeDeveloperData)
                Toggle("In den Papierkorb statt endgültig löschen", isOn: $useTrash)
                Text("Caches und Protokolle werden standardmäßig endgültig gelöscht, damit der Speicher sofort frei wird. Deinstallieren und Analyse verschieben immer in den Papierkorb.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Whitelist") {
                TextEditor(text: $whitelist)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                Text("Ein Eintrag pro Zeile: ein Name wie com.spotify.client oder ein Pfad wie ~/Library/Caches/Foo*. Geschützte Einträge schlägt Clyro nie vor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Projektordner") {
                TextEditor(text: $purgePaths)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 60)
                Text("Ein Pfad pro Zeile, z. B. ~/Arbeit. Sind Ordner eingetragen, sucht Clyro nur dort nach Build-Ordnern.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Optimieren") {
                Toggle("Nur als Vorschau ausführen", isOn: $optimizeDryRun)
                ForEach(OptimizeCatalog.tasks) { task in
                    Toggle(task.title, isOn: Binding(
                        get: { !excludedTasks.split(separator: ",").map(String.init).contains(task.id) },
                        set: { isOn in
                            var values = Set(excludedTasks.split(separator: ",").map(String.init))
                            if isOn { values.remove(task.id) } else { values.insert(task.id) }
                            excludedTasks = values.sorted().joined(separator: ",")
                        }
                    ))
                }
                Text("Abgewählte Aufgaben werden beim Optimieren übersprungen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Aktivitätsprotokoll") {
                Button("Protokoll im Finder zeigen") {
                    if FileManager.default.fileExists(atPath: ClyroLog.url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([ClyroLog.url])
                    } else {
                        NSWorkspace.shared.open(ClyroLog.url.deletingLastPathComponent().deletingLastPathComponent())
                    }
                }
                Text("Jede gelöschte oder verschobene Datei wird lokal in ~/Library/Logs/Clyro festgehalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Über Clyro") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent(String(localized: "Datenschutz"), value: String(localized: "Lokal · Updates nur auf Anfrage"))
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}
