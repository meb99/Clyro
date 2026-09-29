import SwiftUI

/// Optimieren im selben Ablauf wie Bereinigen: Start, Vorbereitung, Auswahl, Ausführung mit Protokoll, Ergebnis.
struct OptimizeView: View {
    private enum Stage {
        case start
        case preparing
        case ready
        case running
        case done
    }

    @AppStorage("optimizeDryRun") private var dryRun = false
    @State private var stage: Stage = .start
    @State private var selected: Set<String> = []
    @State private var prepIndex = 0
    @State private var prepName = ""
    @State private var log: [CleanLogEntry] = []
    @State private var runDone = 0
    @State private var runTotal = 0
    @State private var runCurrent = ""
    @State private var failed = 0
    @State private var previewRun = false
    @State private var showConfirmation = false

    private let palette = ClyroTheme.palette(for: .optimize)
    private var accent: Color { palette.accent }
    private var tasks: [OptimizeTask] { OptimizeCatalog.tasks }

    private var chosenTasks: [OptimizeTask] {
        tasks.filter { selected.contains($0.id) }
    }

    var body: some View {
        Group {
            switch stage {
            case .start: startStage
            case .preparing: preparingStage
            case .ready: resultsScreen
            case .running: runningStage
            case .done: doneStage
            }
        }
        .padding(22)
        .alert("Dock oder Finder neu starten?", isPresented: $showConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("Optimieren", role: .destructive) { run() }
        } message: {
            Text("Fenster und Dock verschwinden kurz und erscheinen sofort wieder. Ungespeicherte Arbeit ist nicht betroffen.")
        }
    }

    // MARK: - Start und Vorbereitung

    private var startStage: some View {
        VStack(spacing: 14) {
            ClyroGardenScene(phase: .idle, growth: 0.2, accent: accent)
                .frame(width: 340, height: 290)
            Text("Ein paar sanfte Handgriffe,\ndamit alles wieder rund läuft.")
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
            Button("Aufgaben prüfen") { prepare() }
                .buttonStyle(ClyroPillButtonStyle())
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var preparingStage: some View {
        VStack(spacing: 18) {
            ClyroGardenScene(phase: .scanning, growth: 0.2, accent: accent)
                .frame(width: 340, height: 290)
            Text("Wird geprüft · \(prepIndex) / \(tasks.count)")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
            HStack(spacing: 10) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text(prepName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(maxWidth: 560)
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func prepare() {
        stage = .preparing
        prepIndex = 0
        prepName = ""
        let started = Date()
        let items = tasks
        Task {
            for (index, task) in items.enumerated() {
                prepIndex = index + 1
                prepName = task.title
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
            await ScanTiming.hold(since: started)
            selected = Set(items.filter { !$0.isDisruptive }.map(\.id))
            stage = .ready
        }
    }

    // MARK: - Auswahl

    private var resultsScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bereit zum Optimieren")
                        .font(.system(size: 30, weight: .bold))
                    Text("\(tasks.count) Aufgaben · \(tasks.filter { !$0.isDisruptive }.count) empfohlen")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                circleButton("arrow.clockwise", help: "Neu prüfen") { prepare() }
                circleButton("xmark", help: "Schließen") { stage = .start }
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(tasks) { task in
                        OptimizeTaskCard(
                            task: task,
                            accent: accent,
                            isSelected: Binding(
                                get: { selected.contains(task.id) },
                                set: { isOn in
                                    if isOn { selected.insert(task.id) } else { selected.remove(task.id) }
                                }
                            )
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)

            footer
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("\(selected.count) ausgewählt")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 6) {
                linkButton("Alle") { selected = Set(tasks.map(\.id)) }
                Text("·").foregroundStyle(.secondary)
                linkButton("Keine") { selected = [] }
                Text("·").foregroundStyle(.secondary)
                linkButton("Empfohlene") { selected = Set(tasks.filter { !$0.isDisruptive }.map(\.id)) }
            }
            .font(.system(size: 14, weight: .medium))

            Toggle("Vorschau", isOn: $dryRun)
                .toggleStyle(.switch)
                .tint(accent)
                .help("Zeigt nur, was passieren würde, ohne etwas auszuführen.")
                .padding(.leading, 12)

            Spacer()
            Button {
                if chosenTasks.contains(where: \.isDisruptive) && !dryRun {
                    showConfirmation = true
                } else {
                    run()
                }
            } label: {
                Text(dryRun ? "Vorschau starten" : "Optimieren")
            }
            .buttonStyle(ClyroPillButtonStyle())
            .disabled(selected.isEmpty)
            .opacity(selected.isEmpty ? 0.4 : 1)
        }
        .padding(.top, 4)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(accent)
    }

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Ausführen

    private var runningStage: some View {
        VStack(spacing: 14) {
            ClyroGardenScene(phase: .watering, growth: 0.34, accent: accent, startGrowth: 0.2)
                .frame(width: 320, height: 260)
            Text("\(runDone) / \(runTotal) Aufgaben")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
            HStack(spacing: 10) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text(runCurrent.isEmpty ? "Wird vorbereitet" : runCurrent)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
            }
            .frame(maxWidth: 560)
            .frame(height: 22)

            CleanLogBox(entries: log, accent: accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func run() {
        let chosen = chosenTasks
        guard !chosen.isEmpty else { return }
        let preview = dryRun
        previewRun = preview
        stage = .running
        log = []
        runDone = 0
        runTotal = chosen.count
        runCurrent = ""
        failed = 0
        let started = Date()

        Task {
            for task in chosen {
                runCurrent = task.title
                let outcome = await Task.detached(priority: .utility) {
                    OptimizeRunner.run(task, dryRun: preview)
                }.value
                runDone += 1
                if !outcome.succeeded { failed += 1 }
                log.append(CleanLogEntry(
                    text: task.title,
                    bytes: nil,
                    isHeader: false,
                    trailing: outcome.succeeded ? "✓" : "✗ \(outcome.message)"
                ))
                try? await Task.sleep(nanoseconds: 650_000_000)
            }
            await ScanTiming.hold(since: started)
            stage = .done
        }
    }

    private var doneStage: some View {
        VStack(spacing: 10) {
            ClyroGardenScene(phase: .bloom, growth: 0.66, accent: accent, startGrowth: 0.34)
                .frame(width: 340, height: 290)
            Text(previewRun ? "Vorschau abgeschlossen" : "\(runTotal - failed) Aufgaben erledigt")
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

private struct OptimizeTaskCard: View {
    let task: OptimizeTask
    let accent: Color
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 14) {
            Button {
                isSelected.toggle()
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? accent : Color.white.opacity(0.35))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(task.title)
                        .font(.system(size: 16, weight: .semibold))
                    if task.isDisruptive {
                        Text("STARTET NEU")
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(ClyroTheme.orange.opacity(0.22)))
                            .foregroundStyle(ClyroTheme.orange)
                    }
                }
                Text(task.detail)
                    .font(.system(size: 13))
                    .foregroundStyle(ClyroTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(task.commandLine)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 74)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ClyroTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ClyroTheme.border))
        )
    }
}
