import AppKit
import CoreServices
import SwiftUI

// MARK: - Apps

struct ApplicationsView: View {
    private enum Mode {
        case uninstall
        case updates
        case startup
    }

    private enum SortKey: CaseIterable {
        case name
        case size
        case lastUsed
        case added

        var title: String {
            switch self {
            case .name: "Name"
            case .size: "App-Größe"
            case .lastUsed: "Zuletzt verwendet"
            case .added: "Hinzugefügt"
            }
        }
    }

    @EnvironmentObject private var cleaner: CleanupScanner
    @State private var mode: Mode = .uninstall
    @State private var applications: [InstalledApplication] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var sortKey: SortKey = .lastUsed
    @State private var reversed = false
    @State private var query = ""
    @State private var showSearch = false
    @State private var selection: Set<URL> = []
    @State private var showUninstall = false

    private let accent = ClyroTheme.palette(for: .applications).accent

    private var visible: [InstalledApplication] {
        var values = query.isEmpty ? applications : applications.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
        switch sortKey {
        case .name:
            values.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .size:
            values.sort { $0.sizeBytes > $1.sizeBytes }
        case .lastUsed:
            values.sort { recency($0) > recency($1) }
        case .added:
            values.sort { ($0.addedDate ?? .distantPast) > ($1.addedDate ?? .distantPast) }
        }
        return reversed ? values.reversed() : values
    }

    private func recency(_ app: InstalledApplication) -> Date {
        if app.isRunning { return Date() }
        return app.lastUsed ?? Date.distantPast
    }

    private var selectedApps: [InstalledApplication] {
        applications.filter { selection.contains($0.url) }
    }

    private var totalBytes: Int64 {
        applications.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Die Unterseiten erscheinen erst, nachdem die Apps geladen wurden.
            if hasLoaded {
                toolbar
                    .padding(.horizontal, 22)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
            }

            switch mode {
            case .uninstall: uninstallContent
            case .updates: UpdatesView(accent: accent)
            case .startup: StartupItemsView()
            }
        }
        .sheet(isPresented: $showUninstall) {
            BulkUninstallSheet(apps: selectedApps, accent: accent) { removed in
                let urls = Set(removed.map(\.url))
                applications.removeAll { urls.contains($0.url) }
                selection.subtract(urls)
            }
            .environmentObject(cleaner)
            .environment(\.clyroSeason, .summer)
        }
    }

    // MARK: - Kopfleiste

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                modeButton("Deinstallieren", .uninstall)
                modeButton("Updates", .updates)
                modeButton("Start", .startup)
            }
            .padding(4)
            .background(Capsule().fill(.white.opacity(0.07)))

            if mode == .uninstall && hasLoaded {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .help("Neu laden")
            }

            Spacer()

            if mode == .uninstall && hasLoaded && !isLoading {
                ForEach(SortKey.allCases, id: \.self) { key in
                    Button {
                        if sortKey == key { reversed.toggle() } else { sortKey = key; reversed = false }
                    } label: {
                        Text(key.title + (sortKey == key ? (reversed ? " ↓" : " ↑") : ""))
                            .font(.system(size: 14, weight: sortKey == key ? .semibold : .medium))
                            .foregroundStyle(sortKey == key ? Color.white : Color.white.opacity(0.45))
                    }
                    .buttonStyle(.plain)
                }

                if showSearch {
                    TextField("Suchen", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                }
                Button {
                    showSearch.toggle()
                    if !showSearch { query = "" }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func modeButton(_ title: String, _ value: Mode) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { mode = value }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(mode == value ? Color.white : Color.white.opacity(0.55))
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background {
                    if mode == value { Capsule().fill(.white.opacity(0.14)) }
                }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Deinstallieren

    @ViewBuilder
    private var uninstallContent: some View {
        if !hasLoaded || isLoading {
            ClyroStartStage(
                title: "Mitten im Sommer –\nsieh nach, was bei dir alles wächst.",
                buttonTitle: "Apps laden",
                busyTitle: "Clyro misst deine Apps",
                busyMessage: "Größen, Versionen und letzte Nutzung werden ermittelt …",
                accent: accent,
                isBusy: isLoading,
                action: { Task { await load() } }
            )
            .padding(22)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Text("Installierte Apps")
                        .font(.system(size: 15, weight: .semibold))
                    Text("\(applications.count) Apps · \(ClyroFormat.byteCount(totalBytes))")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 12)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible) { app in
                            AppRow(
                                app: app,
                                accent: accent,
                                isSelected: selection.contains(app.url)
                            ) {
                                toggle(app)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                .scrollIndicators(.hidden)
            }
            .safeAreaInset(edge: .bottom) {
                if !selection.isEmpty { selectionBar }
            }
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 14) {
            Text("\(selection.count) ausgewählt · \(ClyroFormat.byteCount(selectedApps.reduce(0) { $0 + $1.sizeBytes }))")
                .font(.system(size: 15, weight: .semibold))
            Button("Keine") { selection = [] }
                .buttonStyle(.plain)
                .foregroundStyle(accent)
            Spacer()
            Button("Deinstallieren") { showUninstall = true }
                .buttonStyle(ClyroPillButtonStyle())
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func toggle(_ app: InstalledApplication) {
        guard !AppRemnantProbe.isProtected(app) else { return }
        if selection.contains(app.url) { selection.remove(app.url) } else { selection.insert(app.url) }
    }

    private func load() async {
        guard !isLoading else { return }
        isLoading = true
        let started = Date()
        let found = await Task.detached(priority: .utility) {
            ApplicationProbe.scan()
        }.value
        await ScanTiming.hold(since: started)
        applications = found
        selection = selection.filter { url in found.contains { $0.url == url } }
        hasLoaded = true
        isLoading = false
    }
}

// MARK: - Zeile

private struct AppRow: View {
    let app: InstalledApplication
    let accent: Color
    let isSelected: Bool
    let onToggle: () -> Void

    private var isProtected: Bool { AppRemnantProbe.isProtected(app) }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 5) {
                    Text(app.name)
                        .font(.system(size: 18, weight: .semibold))
                        .lineLimit(1)
                    metaLine
                }
                Spacer()
                if isProtected {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                        .help(AppRemnantProbe.protectionReason(app) ?? "")
                } else {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? accent : Color.white.opacity(0.35))
                        .frame(width: 30)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var metaLine: some View {
        let activity = ApplicationActivity.describe(app)
        return HStack(spacing: 6) {
            if app.version != "–" {
                Text(app.version)
                separator
            }
            Text(ClyroFormat.byteCount(app.sizeBytes))
            if app.isIntelOnly {
                separator
                Text("Intel").foregroundStyle(ClyroTheme.orange)
            }
            separator
            Text(activity.text).foregroundStyle(activity.color)
        }
        .font(.system(size: 14, weight: .medium, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var separator: some View {
        Text("·").foregroundStyle(.secondary.opacity(0.6))
    }
}

enum ApplicationActivity {
    static func describe(_ app: InstalledApplication) -> (text: String, color: Color) {
        if app.isRunning { return ("jetzt aktiv", ClyroTheme.mint) }
        guard let date = app.lastUsed else { return ("nie geöffnet", .secondary) }

        let days = max(0, Int(Date().timeIntervalSince(date) / 86_400))
        func unit(_ count: Int, _ singular: String, _ plural: String) -> String {
            "aktiv vor \(count) \(count == 1 ? singular : plural)"
        }
        switch days {
        case 0: return ("heute aktiv", ClyroTheme.mint)
        case 1..<7: return (unit(days, "Tag", "Tagen"), .secondary)
        case 7..<30: return (unit(days / 7, "Woche", "Wochen"), .secondary)
        case 30..<365:
            let months = max(1, days / 30)
            return (unit(months, "Monat", "Monaten"), months >= 3 ? ClyroTheme.gold : .secondary)
        default:
            return (unit(days / 365, "Jahr", "Jahren"), ClyroTheme.orange)
        }
    }
}

// MARK: - Auslesen

enum ApplicationProbe {
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

                var app = InstalledApplication(
                    url: url,
                    name: name,
                    version: version,
                    bundleIdentifier: identifier,
                    sizeBytes: FileProbe.sizeOfItem(at: url)
                )
                app.lastUsed = metadataDate("kMDItemLastUsedDate", for: url)
                app.addedDate = metadataDate("kMDItemDateAdded", for: url)
                app.isIntelOnly = intelOnly(bundle)
                app.isRunning = !identifier.isEmpty
                    && !NSRunningApplication.runningApplications(withBundleIdentifier: identifier).isEmpty
                results.append(app)
            }
        }
        return results
    }

    private static func metadataDate(_ attribute: String, for url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, attribute as CFString) as? Date
    }

    /// Nur auf Apple-Silicon-Macs sinnvoll: Apps ohne native Version laufen über Rosetta.
    private static func intelOnly(_ bundle: Bundle) -> Bool {
        #if arch(arm64)
        let architectures = bundle.executableArchitectures?.map(\.intValue) ?? []
        let x86 = 0x0100_0007
        let arm = 0x0100_000c
        return architectures.contains(x86) && !architectures.contains(arm)
        #else
        return false
        #endif
    }
}

// MARK: - Sammel-Deinstallation

private struct UninstallPlan: Identifiable {
    let app: InstalledApplication
    var remnants: [AppRemnant]

    var id: URL { app.url }
    var bytes: Int64 { app.sizeBytes + remnants.reduce(0) { $0 + $1.sizeBytes } }
    var isBlocked: Bool { AppRemnantProbe.isProtected(app) || AppRemnantProbe.isRunning(app) }
}

struct BulkUninstallSheet: View {
    private enum Phase {
        case review
        case running
        case done
    }

    @EnvironmentObject private var cleaner: CleanupScanner
    @Environment(\.dismiss) private var dismiss

    let apps: [InstalledApplication]
    let accent: Color
    let onFinished: ([InstalledApplication]) -> Void

    @State private var phase: Phase = .review
    @State private var plans: [UninstallPlan] = []
    @State private var isLoading = true
    @State private var freed: Int64 = 0
    @State private var done = 0
    @State private var total = 0
    @State private var current = ""
    @State private var log: [CleanLogEntry] = []
    @State private var removed: [InstalledApplication] = []

    private var runnable: [UninstallPlan] { plans.filter { !$0.isBlocked } }
    private var runnableBytes: Int64 { runnable.reduce(0) { $0 + $1.bytes } }

    var body: some View {
        VStack(spacing: 14) {
            switch phase {
            case .review: review
            case .running: running
            case .done: finished
            }
        }
        .padding(24)
        .frame(width: 680, height: 600)
        .task {
            let selected = apps
            let loaded = await Task.detached(priority: .utility) {
                selected.map { UninstallPlan(app: $0, remnants: AppRemnantProbe.remnants(for: $0)) }
            }.value
            plans = loaded
            isLoading = false
        }
    }

    // MARK: Prüfen

    private var review: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Apps deinstallieren")
                .font(.system(size: 26, weight: .bold))
            Text("Alles landet im Papierkorb und lässt sich zurückholen.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            if isLoading {
                ProgressView("Suche nach Rückständen …")
                    .tint(accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(plans) { plan in
                            HStack(spacing: 12) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: plan.app.url.path))
                                    .resizable()
                                    .frame(width: 36, height: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(plan.app.name)
                                        .font(.system(size: 14, weight: .semibold))
                                    Text(plan.isBlocked
                                         ? (AppRemnantProbe.protectionReason(plan.app) ?? "läuft noch – bitte erst beenden")
                                         : "\(plan.remnants.count) Rückstände gefunden")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(plan.isBlocked ? ClyroTheme.orange : Color.secondary)
                                }
                                Spacer()
                                Text(ClyroFormat.byteCount(plan.bytes))
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(ClyroTheme.card)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(ClyroTheme.border))
                            )
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            HStack {
                Button("Abbrechen") { dismiss() }
                Spacer()
                Button("Deinstallieren · \(ClyroFormat.byteCount(runnableBytes))") { start() }
                    .buttonStyle(ClyroPillButtonStyle())
                    .disabled(isLoading || runnable.isEmpty)
                    .opacity(isLoading || runnable.isEmpty ? 0.4 : 1)
            }
        }
    }

    // MARK: Ausführen

    private var running: some View {
        VStack(spacing: 12) {
            ClyroGardenScene(phase: .watering, growth: 0.3, accent: accent, startGrowth: 0.12)
                .frame(width: 260, height: 210)
            Text(ClyroFormat.byteCount(freed))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 10) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text("\(current.isEmpty ? "Wird vorbereitet" : current) · \(done) / \(total)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .monospacedDigit()
            }
            .frame(maxWidth: 560)
            CleanLogBox(entries: log, accent: accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func start() {
        let work = runnable
        total = work.reduce(0) { $0 + 1 + $1.remnants.count }
        phase = .running
        let started = Date()

        Task {
            var movedItems = 0
            for plan in work {
                log.append(CleanLogEntry(text: plan.app.name, bytes: nil, isHeader: true))
                var targets: [(URL, Int64)] = [(plan.app.url, plan.app.sizeBytes)]
                targets += plan.remnants.map { ($0.url, $0.sizeBytes) }
                var appMoved = false

                for (index, target) in targets.enumerated() {
                    current = target.0.lastPathComponent
                    let ok = await Task.detached(priority: .utility) { () -> Bool in
                        do {
                            try FileManager.default.trashItem(at: target.0, resultingItemURL: nil)
                            ClyroLog.append("Deinstallieren: \(target.0.path)")
                            return true
                        } catch {
                            return false
                        }
                    }.value
                    done += 1
                    if ok {
                        movedItems += 1
                        freed += max(0, target.1)
                        if index == 0 { appMoved = true }
                        log.append(CleanLogEntry(text: target.0.lastPathComponent, bytes: target.1, isHeader: false, checked: true))
                    }
                    try? await Task.sleep(nanoseconds: 60_000_000)
                }
                if appMoved { removed.append(plan.app) }
            }
            await ScanTiming.hold(since: started)
            cleaner.record(bytes: freed, itemCount: movedItems, kinds: [.appRemnants])
            ClyroStats.add(uninstalled: removed.count)
            phase = .done
        }
    }

    // MARK: Ergebnis

    private var finished: some View {
        VStack(spacing: 10) {
            ClyroGardenScene(phase: .bloom, growth: 0.62, accent: accent, startGrowth: 0.3)
                .frame(width: 300, height: 250)
            Text("\(ClyroFormat.byteCount(freed)) freigegeben")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("\(removed.count) App(s) im Papierkorb.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Fertig") {
                onFinished(removed)
                dismiss()
            }
            .buttonStyle(ClyroPillButtonStyle())
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
