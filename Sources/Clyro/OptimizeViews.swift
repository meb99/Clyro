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
    @State private var failed = 0
    @State private var previewRun = false
    @State private var showConfirmation = false

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
        .alert("Dienste neu starten?", isPresented: $showConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Optimieren", role: .destructive) { run() }
        } message: {
            Text("Dock, Finder, Menüleiste und weitere Dienste starten kurz neu und erscheinen sofort wieder. Ungespeicherte Arbeit ist nicht betroffen.")
        }
    }

    // MARK: - Start

    private var startStage: some View {
        VStack(spacing: 14) {
            ClyroGardenScene(phase: .idle, growth: 0.2, accent: accent)
                .frame(width: 340, height: 290)
            Text("Ein paar sanfte Handgriffe,\ndamit alles wieder rund läuft.")
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
            Button("Optimieren") {
                if dryRun { run() } else { showConfirmation = true }
            }
            .buttonStyle(ClyroPillButtonStyle())
            .padding(.top, 10)
            if dryRun {
                Text("Vorschau ist aktiv – es wird nichts verändert (Einstellungen)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        failed = 0
        let started = Date()

        Task {
            var lastGroup = ""
            for task in chosen {
                runCurrent = task.title
                if task.group != lastGroup {
                    log.append(CleanLogEntry(text: task.group, bytes: nil, isHeader: true))
                    lastGroup = task.group
                }
                let outcome = await Task.detached(priority: .utility) {
                    OptimizeRunner.run(task, dryRun: preview)
                }.value
                runDone += 1
                if !outcome.succeeded { failed += 1 }
                log.append(CleanLogEntry(
                    text: task.title,
                    bytes: nil,
                    isHeader: false,
                    trailing: outcome.succeeded ? nil : "✗ \(outcome.message)",
                    checked: outcome.succeeded
                ))
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            await ScanTiming.hold(since: started)
            stage = .done
        }
    }

    // MARK: - Ergebnis

    private var doneStage: some View {
        VStack(spacing: 10) {
            ClyroGardenScene(phase: .bloom, growth: 0.66, accent: accent, startGrowth: 0.34)
                .frame(width: 340, height: 290)
            Text(previewRun ? "Vorschau abgeschlossen" : "\(tasks.count - failed) Aufgaben erledigt")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(failed > 0 ? "\(failed) Aufgabe(n) sind fehlgeschlagen." : "Alles läuft wieder rund.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Weiter") { stage = .start }
                .buttonStyle(ClyroPillButtonStyle())
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
