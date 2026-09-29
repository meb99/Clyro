import SwiftUI

/// Optimieren: Startseite, dann läuft die Wartung direkt mit Zähler und Protokoll, am Ende das Ergebnis.
struct OptimizeView: View {
    private enum Stage {
        case start
        case running
        case done
    }

    @AppStorage("optimizeDryRun") private var dryRun = false
    @State private var stage: Stage = .start
    @State private var log: [CleanLogEntry] = []
    @State private var runDone = 0
    @State private var runCurrent = ""
    @State private var counts: [OptimizeResult: Int] = [:]
    @State private var previewRun = false

    private let palette = ClyroTheme.palette(for: .optimize)
    private var accent: Color { palette.accent }
    private var tasks: [OptimizeTask] { OptimizeCatalog.tasks }

    var body: some View {
        Group {
            switch stage {
            case .start: startStage
            case .running: runningStage
            case .done: doneStage
            }
        }
        .padding(22)
    }

    // MARK: - Start

    private var startStage: some View {
        ClyroStartStage(
            title: "Frühling für deinen Mac –\nein paar Handgriffe, und alles blüht auf.",
            buttonTitle: "Optimieren",
            accent: accent,
            action: { run() }
        ) {
            if dryRun {
                Text("Vorschau ist aktiv – es wird nichts verändert (Einstellungen)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Wartung

    private var runningStage: some View {
        VStack(spacing: 14) {
            ClyroGardenScene(phase: .watering, growth: 0.34, accent: accent, startGrowth: 0.2)
                .frame(width: 320, height: 260)
            Text("Wartung läuft")
                .font(.system(size: 34, weight: .bold))
            HStack(spacing: 10) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text("\(runCurrent.isEmpty ? "Wird vorbereitet" : runCurrent) · \(runDone) / \(tasks.count)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .monospacedDigit()
            }
            .frame(maxWidth: 560)
            .frame(height: 22)

            CleanLogBox(entries: log, accent: accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func run() {
        let chosen = tasks
        let preview = dryRun
        previewRun = preview
        stage = .running
        log = []
        runDone = 0
        runCurrent = ""
        counts = [:]
        let started = Date()

        Task {
            var lastGroup = ""
            for task in chosen {
                runCurrent = task.title
                if task.group != lastGroup {
                    log.append(CleanLogEntry(text: task.group, bytes: nil, isHeader: true))
                    lastGroup = task.group
                }
                let report = await Task.detached(priority: .utility) {
                    OptimizeCatalog.run(task, dryRun: preview)
                }.value
                runDone += 1
                counts[report.result, default: 0] += 1
                log.append(CleanLogEntry(
                    text: task.title,
                    bytes: nil,
                    isHeader: false,
                    trailing: report.result == .applied ? nil : report.message,
                    checked: report.result == .applied || report.result == .unchanged
                ))
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
            await ScanTiming.hold(since: started)
            stage = .done
        }
    }

    // MARK: - Ergebnis

    private var summaryLine: String {
        var parts: [String] = []
        if let value = counts[.unchanged], value > 0 { parts.append("\(value) unverändert") }
        if let value = counts[.skipped], value > 0 { parts.append("\(value) übersprungen") }
        if let value = counts[.unavailable], value > 0 { parts.append("\(value) nicht verfügbar") }
        if let value = counts[.failed], value > 0 { parts.append("\(value) fehlgeschlagen") }
        return parts.isEmpty ? "Alles läuft wieder rund." : parts.joined(separator: " · ")
    }

    private var doneStage: some View {
        let applied = counts[.applied] ?? 0
        return VStack(spacing: 10) {
            ClyroGardenScene(phase: .bloom, growth: 0.66, accent: accent, startGrowth: 0.34)
                .frame(width: 340, height: 290)
            Text(previewRun ? "Vorschau abgeschlossen" : "\(applied) Optimierungen angewendet")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(summaryLine)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Fertig") { stage = .start }
                .buttonStyle(ClyroPillButtonStyle())
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
