import AppKit
import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var cleaner: CleanupScanner
    @State private var showConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    SectionHeader("Bereinigen", subtitle: "Nur transparente, ausgewählte Bereiche – nichts wird heimlich entfernt.")
                    Spacer()
                    Button {
                        cleaner.scan()
                    } label: {
                        Label(cleaner.state == .scanning ? "Scanne …" : "Mac prüfen", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ClyroTheme.mintSoft)
                    .disabled(cleaner.state == .scanning || cleaner.state == .cleaning)
                }

                if cleaner.categories.isEmpty && cleaner.state != .scanning {
                    EmptyStateView(
                        icon: "sparkle.magnifyingglass",
                        title: "Bereit für den ersten Scan",
                        message: "Clyro sucht nach alten Caches, Protokollen und Installationsdateien. Vor dem Löschen siehst du immer eine Zusammenfassung."
                    )
                } else if cleaner.state == .scanning {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(ClyroTheme.mint)
                        Text("Dateien werden sicher analysiert …")
                            .foregroundStyle(ClyroTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                    .clyroCard()
                } else {
                    VStack(spacing: 11) {
                        ForEach($cleaner.categories) { $category in
                            CleanupCategoryRow(category: $category) {
                                cleaner.reveal(category)
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(ClyroFormat.byteCount(cleaner.selectedBytes)) können freigegeben werden")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text("\(cleaner.selectedItems) Elemente werden zunächst in den Papierkorb verschoben.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(ClyroTheme.secondaryText)
                        }
                        Spacer()
                        Button {
                            showConfirmation = true
                        } label: {
                            Label("Auswahl bereinigen", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ClyroTheme.mintSoft)
                        .disabled(cleaner.selectedItems == 0 || cleaner.state == .cleaning)
                    }
                    .clyroCard()
                }
            }
            .padding(28)
        }
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
}

private struct CleanupCategoryRow: View {
    @Binding var category: CleanupCategory
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Toggle("", isOn: $category.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(category.itemCount == 0)

            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(ClyroTheme.mint.opacity(0.12))
                Image(systemName: category.kind.icon).foregroundStyle(ClyroTheme.mint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.kind.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(category.kind.detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(ClyroTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(ClyroFormat.byteCount(category.bytes))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("\(category.itemCount) Elemente")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(ClyroTheme.secondaryText)
            }
            Button(action: reveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.52))
            .disabled(category.paths.isEmpty)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(ClyroTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(ClyroTheme.border))
        )
    }
}

struct StorageView: View {
    @State private var files: [LargeFileItem] = []
    @State private var isScanning = false
    @State private var threshold: LargeFileThreshold = .hundredMB
    @State private var query = ""

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
        VStack(alignment: .leading, spacing: 18) {
            header
            summary
            fileList
        }
        .padding(28)
        .task {
            if files.isEmpty { scan() }
        }
        .onChange(of: threshold) {
            scan()
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            SectionHeader(
                "Speicherfinder",
                subtitle: "Findet große Dateien in deinen persönlichen Ordnern, ohne etwas zu löschen."
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
            .tint(ClyroTheme.mintSoft)
            .disabled(isScanning)
        }
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
                        .tint(ClyroTheme.mint)
                    Text("Downloads, Schreibtisch, Dokumente und Filme werden geprüft …")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 210)
            } else if filteredFiles.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: query.isEmpty ? "checkmark.circle" : "magnifyingglass")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(ClyroTheme.mint)
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
        .clyroCard()
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
        .padding(28)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            SectionHeader(
                "Prozesse",
                subtitle: "Die Clyro Crew zeigt, was auf deinem Mac arbeitet – ohne Technik-Kauderwelsch."
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
            ProcessSummaryTile(
                icon: "person.3",
                title: "Crew an Bord",
                value: "\(monitor.snapshot.processes.count)",
                detail: "sichtbare Prozesse",
                color: ClyroTheme.mint
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
                color: ClyroTheme.blue
            )
        }
    }

    private var roleFilters: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                CrewRoleFilter(
                    title: "Alle",
                    icon: "square.grid.2x2",
                    color: ClyroTheme.mint,
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
        .clyroCard()
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

    private var filtered: [InstalledApplication] {
        query.isEmpty ? applications : applications.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeader("Apps", subtitle: "Installierte Apps und ihr tatsächlicher Platzbedarf.")
                Spacer()
                TextField("Apps suchen", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
            }

            if isLoading {
                ProgressView("Apps werden analysiert …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { app in
                    HStack(spacing: 13) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(app.bundleIdentifier.isEmpty ? app.url.path : app.bundleIdentifier)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(ClyroTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(app.version)
                            .foregroundStyle(ClyroTheme.secondaryText)
                            .frame(width: 90, alignment: .trailing)
                        Text(ClyroFormat.byteCount(app.sizeBytes))
                            .fontWeight(.semibold)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(ClyroTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(28)
        .task { await loadApps() }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader("Autostart", subtitle: "Hintergrunddienste sichtbar machen, bevor wir sie später sicher verwalten.")

            if items.isEmpty {
                EmptyStateView(icon: "bolt.slash.fill", title: "Keine Einträge gefunden", message: "In den bekannten Launch-Agent-Ordnern wurden keine Einträge erkannt.")
            } else {
                List(items) { item in
                    HStack(spacing: 13) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 25))
                            .foregroundStyle(ClyroTheme.gold)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.label)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(item.program)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(ClyroTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        TagView(text: item.scope)
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(ClyroTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(28)
        .task {
            items = await Task.detached(priority: .utility) { StartupProbe.scan() }.value
        }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader("Verlauf", subtitle: "Eine transparente Übersicht aller Bereinigungen.")
            if cleaner.history.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", title: "Noch kein Verlauf", message: "Nach deiner ersten Bereinigung erscheint hier, was wann in den Papierkorb verschoben wurde.")
            } else {
                List(cleaner.history) { record in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(ClyroTheme.mint.opacity(0.12))
                            Image(systemName: "checkmark").foregroundStyle(ClyroTheme.mint)
                        }
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.categories.map(\.title).joined(separator: ", "))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(ClyroTheme.secondaryText)
                        }
                        Spacer()
                        Text("\(record.itemCount) Elemente")
                            .foregroundStyle(ClyroTheme.secondaryText)
                        Text(ClyroFormat.byteCount(record.bytes))
                            .fontWeight(.bold)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(ClyroTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            Spacer()
        }
        .padding(28)
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
                LabeledContent("Version", value: "0.5.0")
                LabeledContent("Datenschutz", value: "100 % lokal")
            }
        }
        .padding(20)
    }
}
