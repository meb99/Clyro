import AppKit
import SwiftUI

// MARK: - Projekte

struct ProjectsView: View {
    @EnvironmentObject private var cleaner: CleanupScanner
    @State private var artifacts: [ProjectArtifact] = []
    @State private var selected: Set<URL> = []
    @State private var isScanning = false
    @State private var isPurging = false
    @State private var hasScanned = false
    @State private var showConfirmation = false
    @State private var lastFreed: Int64?

    private let palette = ClyroTheme.palette(for: .projects)
    private var accent: Color { palette.accent }
    private static let autoSelectAfterDays = 7

    private var selectedArtifacts: [ProjectArtifact] {
        artifacts.filter { selected.contains($0.url) }
    }

    private var selectedBytes: Int64 {
        selectedArtifacts.reduce(0) { $0 + $1.sizeBytes }
    }

    private var totalBytes: Int64 {
        artifacts.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ClyroPageHeader(
                    title: "Projekte",
                    subtitle: "Build-Ordner alter Projekte finden – alles lässt sich später neu erzeugen.",
                    icon: "shippingbox.and.arrow.backward.fill",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: "Ausgewählt", value: ClyroFormat.byteCount(selectedBytes), icon: "externaldrive", color: accent)
                Button {
                    scan()
                } label: {
                    Label(isScanning ? "Suche …" : "Neu suchen", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .tint(accent)
                .disabled(isScanning)
            }

            if isScanning || !hasScanned || artifacts.isEmpty {
                stage
            } else {
                HStack(spacing: 16) {
                    VStack(spacing: 8) {
                        ClyroGardenScene(
                            phase: isPurging ? .watering : .idle,
                            growth: isPurging ? 0.4 : 0.28,
                            accent: accent
                        )
                        .frame(width: 220, height: 190)
                        Text(ClyroFormat.byteCount(totalBytes))
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                        Text("in \(artifacts.count) Build-Ordnern")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("Ordner unter \(Self.autoSelectAfterDays) Tagen Alter sind nicht vorausgewählt.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(accent)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                        Spacer()
                        Button {
                            showConfirmation = true
                        } label: {
                            Label("In den Papierkorb", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                        .controlSize(.large)
                        .disabled(selected.isEmpty)
                    }
                    .frame(width: 250)
                    .clyroPanel(padding: 18, cornerRadius: 20)

                    List(artifacts) { artifact in
                        ProjectArtifactRow(
                            artifact: artifact,
                            isSelected: Binding(
                                get: { selected.contains(artifact.url) },
                                set: { isOn in
                                    if isOn { selected.insert(artifact.url) } else { selected.remove(artifact.url) }
                                }
                            ),
                            accent: accent
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparatorTint(.white.opacity(0.055))
                    }
                    .scrollContentBackground(.hidden)
                    .clyroPanel(padding: 6, cornerRadius: 18)
                }
            }
        }
        .padding(22)
        .alert("Build-Ordner verschieben?", isPresented: $showConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("In den Papierkorb", role: .destructive) { purge() }
        } message: {
            Text("\(selected.count) Ordner mit ungefähr \(ClyroFormat.byteCount(selectedBytes)) landen im Papierkorb. Ein neuer Build oder `npm install` stellt sie wieder her.")
        }
    }

    private var stage: some View {
        VStack(spacing: 8) {
            ClyroGardenScene(phase: isScanning ? .scanning : .idle, growth: 0.2, accent: accent)
                .frame(width: 260, height: 220)
            if isScanning {
                Text("Clyro durchsucht deine Projektordner")
                    .font(.system(size: 24, weight: .semibold))
                ProgressView().tint(accent).frame(width: 240)
            } else if let lastFreed, artifacts.isEmpty, hasScanned {
                Text("\(ClyroFormat.byteCount(lastFreed)) verschoben")
                    .font(.system(size: 24, weight: .semibold))
                Text("Keine weiteren Build-Ordner gefunden.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            } else if hasScanned {
                Text("Nichts zu tun")
                    .font(.system(size: 24, weight: .semibold))
                Text("Keine Build-Ordner in ~/Developer, ~/Projects, ~/Code, ~/Documents und weiteren Projektordnern gefunden.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            } else {
                Text("Bereit für die Projektsuche")
                    .font(.system(size: 24, weight: .semibold))
                Button("Projekte prüfen") { scan() }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clyroPanel(padding: 20, cornerRadius: 20)
    }

    private func scan() {
        guard !isScanning else { return }
        isScanning = true
        let started = Date()
        Task {
            let results = await Task.detached(priority: .utility) {
                ProjectPurgeProbe.scan()
            }.value
            await ScanTiming.hold(since: started)
            artifacts = results
            selected = Set(results.filter { $0.ageDays >= Self.autoSelectAfterDays }.map(\.url))
            hasScanned = true
            isScanning = false
        }
    }

    private func purge() {
        let targets = selectedArtifacts
        isPurging = true
        let started = Date()
        Task {
            let result = await Task.detached(priority: .utility) { () -> (Int, Int64) in
                var moved = 0
                var bytes: Int64 = 0
                for artifact in targets {
                    do {
                        try FileManager.default.trashItem(at: artifact.url, resultingItemURL: nil)
                        ClyroLog.append("Projekte: \(artifact.url.path)")
                        moved += 1
                        bytes += artifact.sizeBytes
                    } catch {
                        continue
                    }
                }
                return (moved, bytes)
            }.value

            let elapsed = Date().timeIntervalSince(started)
            if elapsed < 2.2 {
                try? await Task.sleep(nanoseconds: UInt64((2.2 - elapsed) * 1_000_000_000))
            }
            isPurging = false

            cleaner.record(bytes: result.1, itemCount: result.0, kinds: [.projectArtifacts])
            lastFreed = result.1
            let removed = Set(targets.map(\.url))
            artifacts.removeAll { removed.contains($0.url) }
            selected.subtract(removed)
        }
    }
}

private struct ProjectArtifactRow: View {
    let artifact: ProjectArtifact
    @Binding var isSelected: Bool
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)

            ZStack {
                RoundedRectangle(cornerRadius: 9).fill(accent.opacity(0.13))
                Image(systemName: artifact.kind.icon).foregroundStyle(accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(artifact.projectName)
                        .font(.system(size: 13, weight: .semibold))
                    TagView(text: artifact.kind.title)
                }
                Text(artifact.locationName)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("\(artifact.ageDays) Tage")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)
            Text(ClyroFormat.byteCount(artifact.sizeBytes))
                .font(.system(size: 11, weight: .bold))
                .frame(width: 76, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([artifact.url])
            } label: {
                Image(systemName: "folder")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .help("Im Finder zeigen")
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Deinstallieren

struct UninstallSheet: View {
    @EnvironmentObject private var cleaner: CleanupScanner
    @Environment(\.dismiss) private var dismiss

    let app: InstalledApplication
    let accent: Color
    let onFinished: () -> Void

    @State private var remnants: [AppRemnant] = []
    @State private var deselected: Set<URL> = []
    @State private var isLoading = true
    @State private var failures: [String] = []

    private var isProtected: Bool { AppRemnantProbe.isProtected(app) }
    private var isRunning: Bool { AppRemnantProbe.isRunning(app) }

    private var chosenRemnants: [AppRemnant] {
        remnants.filter { !deselected.contains($0.url) }
    }

    private var totalBytes: Int64 {
        app.sizeBytes + chosenRemnants.reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(app.name) deinstallieren")
                        .font(.system(size: 18, weight: .semibold))
                    Text("Alles landet im Papierkorb und lässt sich zurückholen.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if isProtected {
                notice("Diese App gehört zu macOS und wird von Clyro nicht angerührt.", icon: "lock.fill")
            } else if isRunning {
                notice("\(app.name) läuft noch. Beende die App, öffne dieses Fenster dann erneut.", icon: "exclamationmark.triangle.fill")
            } else if isLoading {
                ProgressView("Suche nach Rückständen …")
                    .tint(accent)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                List {
                    HStack {
                        Image(systemName: "app.fill").foregroundStyle(accent)
                        Text(app.url.path)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                        Spacer()
                        Text(ClyroFormat.byteCount(app.sizeBytes))
                            .font(.system(size: 11, weight: .bold))
                    }
                    ForEach(remnants) { remnant in
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { !deselected.contains(remnant.url) },
                                set: { isOn in
                                    if isOn { deselected.remove(remnant.url) } else { deselected.insert(remnant.url) }
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                            Text(remnant.displayPath)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Text(ClyroFormat.byteCount(remnant.sizeBytes))
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .frame(minHeight: 180)
                .clyroPanel(padding: 4, cornerRadius: 12)

                if remnants.isEmpty {
                    Text("Keine Rückstände gefunden – nur die App selbst wird verschoben.")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if !failures.isEmpty {
                notice("Nicht verschoben: \(failures.joined(separator: ", "))", icon: "exclamationmark.triangle.fill")
            }

            HStack {
                Text("\(ClyroFormat.byteCount(totalBytes)) insgesamt")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Abbrechen") { dismiss() }
                Button {
                    uninstall()
                } label: {
                    Label("In den Papierkorb", systemImage: "trash")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(isProtected || isRunning || isLoading)
            }
        }
        .padding(22)
        .frame(width: 560, height: 470)
        .task {
            guard !isProtected else { return }
            let found = await Task.detached(priority: .utility) {
                AppRemnantProbe.remnants(for: app)
            }.value
            remnants = found
            isLoading = false
        }
    }

    private func notice(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 12, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .leading)
            .clyroPanel(padding: 12, cornerRadius: 12)
    }

    private func uninstall() {
        let chosen = chosenRemnants
        Task {
            let result = await Task.detached(priority: .utility) {
                AppRemnantProbe.uninstall(app, remnants: chosen)
            }.value

            cleaner.record(bytes: result.bytes, itemCount: result.movedItems, kinds: [.appRemnants])
            if result.failures.isEmpty {
                onFinished()
                dismiss()
            } else {
                failures = result.failures
                if !result.failures.contains(app.url.lastPathComponent) { onFinished() }
            }
        }
    }
}
