import AppKit
import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var cleaner: CleanupScanner
    @State private var showConfirmation = false

    private let accent = ClyroTheme.palette(for: .cleanup).accent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ClyroPageHeader(
                    title: "Bereinigen",
                    subtitle: "Sicher prüfen, bewusst auswählen, erst dann in den Papierkorb verschieben.",
                    icon: "sparkles",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: "Ausgewählt", value: ClyroFormat.byteCount(cleaner.selectedBytes), icon: "externaldrive", color: accent)
                Button {
                    cleaner.scan()
                } label: {
                    Label(cleaner.state == .scanning ? "Scanne …" : "Neu prüfen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .disabled(cleaner.state == .scanning || cleaner.state == .cleaning)
            }

            if cleaner.categories.isEmpty || cleaner.state == .scanning {
                scanStage
            } else {
                HStack(spacing: 16) {
                    cleanupHero
                        .frame(width: 300)

                    VStack(spacing: 9) {
                        ForEach($cleaner.categories) { $category in
                            CleanupCategoryRow(category: $category, accent: accent) {
                                cleaner.reveal(category)
                            }
                        }

                        HStack(spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(ClyroFormat.byteCount(cleaner.selectedBytes)) bereit")
                                    .font(.system(size: 17, weight: .bold))
                                Text("\(cleaner.selectedItems) Elemente · zunächst nur Papierkorb")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                showConfirmation = true
                            } label: {
                                Label("Auswahl bereinigen", systemImage: "trash")
                                    .frame(minWidth: 150)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(accent)
                            .disabled(cleaner.selectedItems == 0 || cleaner.state == .cleaning)
                        }
                        .clyroPanel(padding: 13)
                    }
                }
            }
        }
        .padding(22)
        .onAppear {
            if cleaner.categories.isEmpty { cleaner.scan() }
        }
        .alert("Ausgewählte Dateien verschieben?", isPresented: $showConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("In den Papierkorb", role: .destructive) { cleaner.cleanSelected() }
        } message: {
            Text("\(cleaner.selectedItems) Elemente mit ungefähr \(ClyroFormat.byteCount(cleaner.selectedBytes)) werden in den Papierkorb verschoben. Geöffnete Apps solltest du vorher schließen.")
        }
    }

    private var scanStage: some View {
        VStack(spacing: 8) {
            ClyroArtifact(symbol: "wind", satellite: "sparkles", accent: accent, secondary: ClyroTheme.mint)
            Text(cleaner.state == .scanning ? "Clyro prüft deinen Mac" : "Bereit für den ersten Scan")
                .font(.system(size: 24, weight: .semibold))
            Text(cleaner.state == .scanning
                 ? "Caches, Protokolle, Installer und Entwicklerdaten werden lokal analysiert."
                 : "Du siehst jedes Ergebnis, bevor Clyro etwas bewegt.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            if cleaner.state == .scanning {
                ProgressView().tint(accent).frame(width: 240)
            } else {
                Button("Mac prüfen") { cleaner.scan() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clyroPanel(padding: 20, cornerRadius: 20)
    }

    private var cleanupHero: some View {
        VStack(spacing: 7) {
            ClyroArtifact(symbol: "wind", satellite: "checkmark", accent: accent, secondary: ClyroTheme.mint)
            Text(ClyroFormat.byteCount(cleaner.categories.reduce(0) { $0 + $1.bytes }))
                .font(.system(size: 29, weight: .bold, design: .rounded))
            Text("in \(cleaner.categories.reduce(0) { $0 + $1.itemCount }) gefundenen Elementen")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Alles bleibt auf deinem Mac")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 4)
        }
        .frame(maxHeight: .infinity)
        .clyroPanel(padding: 18, cornerRadius: 20)
    }
}

private struct CleanupCategoryRow: View {
    @Binding var category: CleanupCategory
    let accent: Color
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Toggle("", isOn: $category.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(category.itemCount == 0)

            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.13))
                Image(systemName: category.kind.icon).foregroundStyle(accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.kind.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(category.kind.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(ClyroTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(ClyroFormat.byteCount(category.bytes))
                    .font(.system(size: 13, weight: .bold))
                Text("\(category.itemCount) Elemente")
                    .font(.system(size: 10))
                    .foregroundStyle(ClyroTheme.secondaryText)
            }
            Button(action: reveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.52))
            .disabled(category.paths.isEmpty)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 64)
        .background(
            RoundedRectangle(cornerRadius: 13)
                .fill(ClyroTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(ClyroTheme.border))
        )
    }
}

struct StorageView: View {
    @State private var files: [LargeFileItem] = []
    @State private var isScanning = false
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
        .padding(22)
        .task {
            if files.isEmpty { scan() }
        }
        .onChange(of: threshold) {
            scan()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ClyroPageHeader(
                title: "Speicher",
                subtitle: "Große Dateien als klare Speicherlandschaft – ohne automatisches Löschen.",
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
                Label(isScanning ? "Scanne …" : "Neu scannen", systemImage: "arrow.clockwise")
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

            StorageSideStat(title: "Größte Datei", value: files.first?.displayName ?? "–", icon: "arrow.up.left.and.arrow.down.right", color: accent)
            StorageSideStat(title: "Geprüfte Ordner", value: "Downloads · Desktop · Dokumente · Filme", icon: "folder", color: secondary)

            Spacer(minLength: 0)

            Text("Clyro zeigt nur an. Öffne eine Datei gezielt im Finder, bevor du sie entfernst.")
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
                title: "Gefunden",
                value: "\(files.count)",
                detail: "ab \(threshold.title)",
                color: ClyroTheme.mint
            )
            StorageSummaryTile(
                icon: "internaldrive",
                title: "Zusammen",
                value: ClyroFormat.byteCount(totalBytes),
                detail: "nur eine Übersicht",
                color: ClyroTheme.blue
            )
            StorageSummaryTile(
                icon: "arrow.up.left.and.arrow.down.right",
                title: "Größte Datei",
                value: files.first?.displayName ?? "–",
                detail: files.first.map { ClyroFormat.byteCount($0.sizeBytes) } ?? "Noch keine Werte",
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
                    Text(query.isEmpty ? "Keine großen Dateien gefunden" : "Keine passende Datei")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text(query.isEmpty
                         ? "In den geprüften Ordnern liegt nichts über \(threshold.title)."
                         : "Ändere den Suchbegriff oder die Mindestgröße.")
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
        Task {
            files = await Task.detached(priority: .utility) {
                LargeFileProbe.scan(minimumSize: minimumSize)
            }.value
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
                    Text("Nach dem Scan entsteht hier deine Speicherlandschaft.")
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

struct ProcessesView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @AppStorage("showTechnicalDetails") private var showTechnicalDetails = false
    @State private var query = ""
    @State private var selectedRole: ProcessCrewRole?
    @State private var sort: ProcessSort = .cpu

    private let accent = ClyroTheme.palette(for: .processes).accent
    private let secondary = ClyroTheme.palette(for: .processes).secondary

    private var filteredProcesses: [SystemProcess] {
        var values = monitor.snapshot.processes.filter { process in
            let matchesSearch = query.isEmpty
                || process.name.localizedCaseInsensitiveContains(query)
                || process.crewRole.title.localizedCaseInsensitiveContains(query)
                || process.explanation.localizedCaseInsensitiveContains(query)
            let matchesRole = selectedRole == nil || process.crewRole == selectedRole
            return matchesSearch && matchesRole
        }

        switch sort {
        case .cpu:
            values.sort {
                if abs($0.cpuPercent - $1.cpuPercent) > 0.05 { return $0.cpuPercent > $1.cpuPercent }
                return $0.memoryBytes > $1.memoryBytes
            }
        case .memory:
            values.sort { $0.memoryBytes > $1.memoryBytes }
        case .name:
            values.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return values
    }

    private var memoryLeader: SystemProcess? {
        monitor.snapshot.processes.max { $0.memoryBytes < $1.memoryBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            summary
            roleFilters
            processList
        }
        .padding(22)
    }

    private var header: some View {
        HStack(spacing: 14) {
            ClyroPageHeader(
                title: "Prozesse",
                subtitle: "Die Clyro Crew erklärt laufende Prozesse ohne Technik-Kauderwelsch.",
                icon: "waveform.path.ecg",
                accent: accent
            )
            Spacer()
            TextField("Prozess oder Rolle suchen", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 230)
            Picker("Sortierung", selection: $sort) {
                ForEach(ProcessSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 210)
            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .disabled(monitor.isRefreshing)
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            ClyroArtifact(symbol: "gearshape.2.fill", satellite: "bolt.fill", accent: accent, secondary: secondary)
                .scaleEffect(0.50)
                .frame(width: 95, height: 78)
                .clyroPanel(padding: 0, cornerRadius: 15)
            ProcessSummaryTile(
                icon: "person.3",
                title: "Crew an Bord",
                value: "\(monitor.snapshot.processes.count)",
                detail: "sichtbare Prozesse",
                color: accent
            )
            ProcessSummaryTile(
                icon: "flame.fill",
                title: "Meiste CPU",
                value: monitor.snapshot.processes.first?.name ?? "–",
                detail: monitor.snapshot.processes.first.map { String(format: "%.1f %% CPU", $0.cpuPercent) } ?? "Noch keine Werte",
                color: ClyroTheme.orange
            )
            ProcessSummaryTile(
                icon: "memorychip",
                title: "Meister RAM",
                value: memoryLeader?.name ?? "–",
                detail: memoryLeader.map { ClyroFormat.byteCount($0.memoryBytes) } ?? "Noch keine Werte",
                color: secondary
            )
        }
    }

    private var roleFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                CrewRoleFilter(
                    title: "Alle",
                    icon: "square.grid.2x2",
                    color: accent,
                    isSelected: selectedRole == nil
                ) {
                    selectedRole = nil
                }

                ForEach(ProcessCrewRole.allCases) { role in
                    CrewRoleFilter(
                        title: role.title,
                        icon: role.systemImage,
                        color: role.color,
                        isSelected: selectedRole == role
                    ) {
                        selectedRole = role
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private var processList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Name und Aufgabe")
                Spacer()
                Text("RAM").frame(width: 86, alignment: .trailing)
                Text("CPU").frame(width: 72, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(ClyroTheme.secondaryText)
            .padding(.bottom, 12)

            Divider().overlay(.white.opacity(0.055))

            if filteredProcesses.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 30, weight: .light))
                        .foregroundStyle(ClyroTheme.mint)
                    Text("Keine Crew-Mitglieder gefunden")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Ändere den Suchbegriff oder wähle eine andere Rolle.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredProcesses) { process in
                            ProcessCrewRow(
                                process: process,
                                showsTechnicalDetails: showTechnicalDetails
                            )
                            .padding(.vertical, 7)

                            if process.id != filteredProcesses.last?.id {
                                Divider()
                                    .overlay(.white.opacity(0.045))
                                    .padding(.leading, 64)
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
}

private enum ProcessSort: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "RAM"
        case .name: "A–Z"
        }
    }
}

private struct ProcessSummaryTile: View {
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

private struct CrewRoleFilter: View {
    let title: String
    let icon: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                Capsule()
                    .fill(isSelected ? color.opacity(0.20) : .white.opacity(0.045))
                    .overlay(Capsule().stroke(isSelected ? color.opacity(0.45) : ClyroTheme.border))
            )
        }
        .buttonStyle(.plain)
    }
}

struct ApplicationsView: View {
    @State private var applications: [InstalledApplication] = []
    @State private var isLoading = false
    @State private var query = ""
    @State private var sort: ApplicationSort = .size
    @State private var uninstallTarget: InstalledApplication?

    private let accent = ClyroTheme.palette(for: .applications).accent
    private let secondary = ClyroTheme.palette(for: .applications).secondary

    private var filtered: [InstalledApplication] {
        var values = query.isEmpty ? applications : applications.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
        switch sort {
        case .size: values.sort { $0.sizeBytes > $1.sizeBytes }
        case .name: values.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return values
    }

    private var totalBytes: Int64 {
        applications.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ClyroPageHeader(
                    title: "Apps",
                    subtitle: "Installierte Programme, echte Größen – gründlich deinstallieren mit Rückständen.",
                    icon: "square.grid.2x2.fill",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: "Installiert", value: "\(applications.count) Apps", icon: "app.fill", color: accent)
                Picker("Sortierung", selection: $sort) {
                    ForEach(ApplicationSort.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 130)
                TextField("Apps suchen", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
            }

            if isLoading {
                VStack(spacing: 12) {
                    ClyroArtifact(symbol: "app.gift.fill", satellite: "magnifyingglass", accent: accent, secondary: secondary)
                    ProgressView("Apps werden analysiert …").tint(accent)
                }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 14) {
                    VStack(spacing: 10) {
                        ClyroArtifact(symbol: "square.grid.2x2.fill", satellite: "app.badge.checkmark", accent: accent, secondary: secondary)
                            .scaleEffect(0.76)
                            .frame(height: 142)
                        Text(ClyroFormat.byteCount(totalBytes))
                            .font(.system(size: 27, weight: .bold, design: .rounded))
                        Text("belegen deine installierten Apps")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Divider().overlay(ClyroTheme.border)
                        if let largest = applications.first {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("GRÖSSTE APP")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(accent)
                                Text(largest.name)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                Text(ClyroFormat.byteCount(largest.sizeBytes))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer()
                    }
                    .frame(width: 220)
                    .clyroPanel(padding: 16, cornerRadius: 18)

                    List(filtered) { app in
                        ApplicationRow(app: app, accent: accent) {
                            uninstallTarget = app
                        }
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(.white.opacity(0.055))
                    }
                    .scrollContentBackground(.hidden)
                    .clyroPanel(padding: 6, cornerRadius: 18)
                }
            }
        }
        .padding(22)
        .task { await loadApps() }
        .sheet(item: $uninstallTarget) { target in
            UninstallSheet(app: target, accent: accent) {
                applications.removeAll { $0.id == target.id }
            }
        }
    }

    private func loadApps() async {
        guard applications.isEmpty else { return }
        isLoading = true
        applications = await Task.detached(priority: .utility) {
            ApplicationProbe.scan()
        }.value
        isLoading = false
    }
}

private enum ApplicationSort: String, CaseIterable, Identifiable {
    case size
    case name

    var id: String { rawValue }
    var title: String { self == .size ? "Größe" : "A–Z" }
}

private struct ApplicationRow: View {
    let app: InstalledApplication
    let accent: Color
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(size: 13, weight: .semibold))
                Text(app.bundleIdentifier.isEmpty ? app.url.path : app.bundleIdentifier)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("v\(app.version)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Text(ClyroFormat.byteCount(app.sizeBytes))
                .font(.system(size: 11, weight: .bold))
                .frame(width: 76, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([app.url])
            } label: {
                Image(systemName: "folder")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .help("Im Finder zeigen")
            Button(action: onUninstall) {
                Image(systemName: "trash")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.52))
            .disabled(AppRemnantProbe.isProtected(app))
            .help("Deinstallieren und Rückstände finden")
        }
        .padding(.vertical, 3)
    }
}

private enum ApplicationProbe {
    static func scan() -> [InstalledApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var seen = Set<String>()
        var results: [InstalledApplication] = []

        for root in roots {
            let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url) else { continue }
                let identifier = bundle.bundleIdentifier ?? ""
                guard seen.insert(identifier.isEmpty ? url.path : identifier).inserted else { continue }
                let info = bundle.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (info?["CFBundleShortVersionString"] as? String) ?? "–"
                results.append(InstalledApplication(
                    url: url,
                    name: name,
                    version: version,
                    bundleIdentifier: identifier,
                    sizeBytes: FileProbe.sizeOfItem(at: url)
                ))
            }
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
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
                    title: "Autostart",
                    subtitle: "Hintergrunddienste nach Benutzer- und Systembereich verständlich aufgeschlüsselt.",
                    icon: "bolt.fill",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: "Gefunden", value: "\(items.count) Dienste", icon: "bolt.horizontal.fill", color: accent)
                TextField("Dienst suchen", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
            }

            if items.isEmpty {
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
                        StartupScopeStat(title: "Benutzer", count: items.filter { $0.scope == "Benutzer" }.count, color: accent)
                        StartupScopeStat(title: "Alle Benutzer", count: items.filter { $0.scope == "Alle Benutzer" }.count, color: secondary)
                        StartupScopeStat(title: "System", count: items.filter { $0.scope == "System" }.count, color: ClyroTheme.blue)
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
        .task {
            items = await Task.detached(priority: .utility) { StartupProbe.scan() }.value
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
            Text(item.scope)
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
                    ?? "Kein Programmpfad angegeben"
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
                    title: "Verlauf",
                    subtitle: "Jede Bereinigung bleibt nachvollziehbar – lokal gespeichert und klar datiert.",
                    icon: "clock.arrow.circlepath",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: "Freigegeben", value: ClyroFormat.byteCount(totalBytes), icon: "externaldrive.fill", color: accent)
                ClyroStatPill(title: "Elemente", value: "\(totalItems)", icon: "doc.on.doc.fill", color: secondary)
            }

            if cleaner.history.isEmpty {
                VStack(spacing: 10) {
                    ClyroArtifact(symbol: "clock.arrow.circlepath", satellite: "checkmark", accent: accent, secondary: secondary)
                    Text("Noch kein Verlauf")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Nach der ersten Bereinigung erscheint hier eine lokale, transparente Chronik.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clyroPanel(padding: 20, cornerRadius: 20)
            } else {
                HStack(spacing: 14) {
                    VStack(spacing: 10) {
                        ClyroArtifact(symbol: "clock.fill", satellite: "checkmark", accent: accent, secondary: secondary)
                            .scaleEffect(0.76)
                            .frame(height: 145)
                        Text("\(cleaner.history.count)")
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                        Text("Bereinigungen dokumentiert")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(width: 220)
                    .clyroPanel(padding: 16, cornerRadius: 18)

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
    @AppStorage("showTechnicalDetails") private var showTechnicalDetails = false
    @AppStorage("includeDeveloperData") private var includeDeveloperData = true

    var body: some View {
        Form {
            Section("Darstellung") {
                Toggle("Technische Details anzeigen", isOn: $showTechnicalDetails)
            }
            Section("Scan") {
                Toggle("Xcode-Daten berücksichtigen", isOn: $includeDeveloperData)
                Text("Clyro verschiebt ausgewählte Dateien in den Papierkorb. Systemdateien werden nicht automatisch verändert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Über Clyro") {
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Datenschutz", value: "100 % lokal")
            }
        }
        .padding(20)
    }
}
