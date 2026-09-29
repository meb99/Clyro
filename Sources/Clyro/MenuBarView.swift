import AppKit
import SwiftUI

/// Zähler für die Verlaufsübersicht im Menüleisten-Fenster.
enum ClyroStats {
    static let uninstalledKey = "clyro.stats.uninstalled"
    static let optimizedKey = "clyro.stats.optimized"

    static func add(uninstalled count: Int) {
        guard count > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: uninstalledKey) + count, forKey: uninstalledKey)
    }

    static func add(optimized count: Int) {
        guard count > 0 else { return }
        let defaults = UserDefaults.standard
        defaults.set(defaults.integer(forKey: optimizedKey) + count, forKey: optimizedKey)
    }
}

/// Hält den Mac wach, solange Clyro läuft (über `caffeinate`, das mit Clyro endet).
@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var isOn = false
    private var process: Process?

    func toggle() {
        if isOn { stop() } else { start() }
    }

    private func start() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-di", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try process.run()
            self.process = process
            isOn = true
        } catch {
            isOn = false
        }
    }

    private func stop() {
        process?.terminate()
        process = nil
        isOn = false
    }
}

/// Kompakte Statusübersicht im Menüleisten-Fenster.
struct MenuBarStatusView: View {
    @EnvironmentObject private var monitor: SystemMonitor
    @EnvironmentObject private var cleaner: CleanupScanner
    @StateObject private var keepAwake = KeepAwake()
    @AppStorage(ClyroStats.uninstalledKey) private var uninstalled = 0
    @AppStorage(ClyroStats.optimizedKey) private var optimized = 0
    @Environment(\.openWindow) private var openWindow

    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            badges

            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    cpuCard
                    gpuCard
                }
                GridRow {
                    memoryCard
                    diskCard
                }
                GridRow {
                    networkCard
                    thermalCard
                }
            }

            batteryCard
            processCard
            footer
        }
        .padding(14)
        .frame(width: 380)
        .foregroundStyle(.white)
        // Das Menüleisten-Fenster folgt sonst dem hellen Systemmodus: dunkle Schrift auf dunklem Grund.
        .environment(\.colorScheme, .dark)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.11, blue: 0.13), Color(red: 0.05, green: 0.07, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    // MARK: Kopf

    private var header: some View {
        let health = snapshot.health
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(ClyroTheme.mint)
            Text("\(health.score)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(snapshot.healthText)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var badges: some View {
        HStack(spacing: 6) {
            MenuBadge(text: snapshot.chipName)
            MenuBadge(text: ClyroFormat.memory(snapshot.memoryTotalBytes).replacingOccurrences(of: ".0", with: ""))
            MenuBadge(text: "macOS \(shortOSVersion)")
            MenuBadge(text: String(localized: "Laufzeit \(ClyroFormat.uptime(snapshot.uptime))"))
            Spacer(minLength: 0)
        }
        .lineLimit(1)
    }

    // MARK: Karten

    private var cpuCard: some View {
        MenuCard(icon: "cpu", title: "CPU", accent: ClyroTheme.mint,
                 badge: snapshot.temperatureCelsius.map { "\(Int($0.rounded())) °C" }) {
            MenuValue(value: String(format: "%.0f", snapshot.cpuPercent), unit: "%")
            MenuCoreBars(values: snapshot.corePercents, color: ClyroTheme.mint)
                .frame(height: 14)
            MenuDetail(text: cpuDetail)
        }
    }

    private var gpuCard: some View {
        MenuCard(icon: "display", title: "GPU", accent: ClyroTheme.blue,
                 badge: snapshot.gpuTemperatureCelsius.map { "\(Int($0.rounded())) °C" }) {
            MenuValue(value: snapshot.gpuPercent.map { String(format: "%.0f", $0) } ?? "–",
                      unit: snapshot.gpuPercent == nil ? "" : "%")
            Sparkline(values: monitor.gpuHistory, color: ClyroTheme.blue)
                .frame(height: 14)
            MenuDetail(text: gpuDetail)
        }
    }

    private var memoryCard: some View {
        MenuCard(icon: "memorychip", title: "RAM", accent: ClyroTheme.gold,
                 badge: snapshot.memoryPressurePercent.map { String(localized: "Druck \($0) %") }) {
            MenuValue(value: String(format: "%.0f", snapshot.memoryPercent), unit: "%")
            Sparkline(values: monitor.memoryHistory, color: ClyroTheme.gold)
                .frame(height: 14)
            MenuDetail(text: "\(ClyroFormat.memory(snapshot.memoryUsedBytes)) / \(ClyroFormat.memory(snapshot.memoryTotalBytes))")
        }
    }

    private var diskCard: some View {
        let free = max(0, snapshot.diskTotalBytes - snapshot.diskUsedBytes)
        return MenuCard(icon: "internaldrive", title: "SSD", accent: ClyroTheme.blue,
                        badge: ClyroFormat.byteCount(snapshot.diskTotalBytes)) {
            MenuValue(value: ClyroFormat.byteCount(free), unit: String(localized: "frei"))
            MenuFillBar(fraction: snapshot.diskPercent / 100, color: ClyroTheme.blue)
                .frame(height: 14)
            MenuDetail(text: "\(ClyroFormat.byteCount(snapshot.diskUsedBytes)) belegt · \(Int(snapshot.diskPercent)) %")
        }
    }

    private var networkCard: some View {
        MenuCard(icon: "globe", title: String(localized: "Netzwerk"), accent: ClyroTheme.blue, badge: snapshot.networkType) {
            MenuValue(value: ClyroFormat.compactSpeed(snapshot.downloadBytesPerSecond), unit: "")
            Sparkline(values: normalizedNetworkHistory, color: ClyroTheme.blue)
                .frame(height: 14)
            MenuDetail(text: "↑ \(ClyroFormat.compactSpeed(snapshot.uploadBytesPerSecond)) · ↓ \(ClyroFormat.compactSpeed(snapshot.downloadBytesPerSecond))")
        }
    }

    private var thermalCard: some View {
        MenuCard(icon: "thermometer.medium", title: "Temp", accent: thermalColor,
                 badge: snapshot.thermalState == .nominal ? String(localized: "Normal") : String(localized: "Warm")) {
            if let cpu = snapshot.temperatureCelsius {
                MenuValue(value: String(format: "%.0f", cpu), unit: "°C")
                MenuFillBar(fraction: cpu / 100, color: thermalColor)
                    .frame(height: 14)
                MenuDetail(text: snapshot.gpuTemperatureCelsius.map { "GPU \(Int($0.rounded())) °C · \(snapshot.chipName)" } ?? snapshot.chipName)
            } else {
                MenuValue(value: snapshot.thermalText, unit: "")
                Spacer(minLength: 14)
                MenuDetail(text: String(localized: "Wärmezustand laut macOS"))
            }
        }
    }

    @ViewBuilder
    private var batteryCard: some View {
        if snapshot.battery.isPresent {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .foregroundStyle(ClyroTheme.mint)
                    Text("Batterie")
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    if let health = snapshot.battery.healthPercent {
                        MenuBadge(text: String(localized: "\(health) % Gesundheit"))
                    }
                }
                .font(.system(size: 12, weight: .semibold))

                HStack(alignment: .center) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(snapshot.battery.percentage) %")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                        Text(batteryTime)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ZStack {
                        Circle().stroke(.white.opacity(0.08), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: Double(snapshot.battery.percentage) / 100)
                            .stroke(ClyroTheme.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: snapshot.battery.isCharging ? "bolt.fill" : "laptopcomputer")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 38, height: 38)
                }

                if let top = topConsumer {
                    Label("Hauptverbraucher \(top.name) · \(String(format: "%.1f", top.power ?? 0))", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .menuCardStyle()
        }
    }

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Top-Prozesse", systemImage: "chart.bar.fill")
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text("Speicher").frame(width: 80, alignment: .trailing)
                Text("% CPU").frame(width: 56, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)

            ForEach(topProcesses) { process in
                HStack {
                    Text(process.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Text(ClyroFormat.memory(process.memoryBytes))
                        .frame(width: 80, alignment: .trailing)
                    Text(String(format: "%.1f", process.cpuPercent))
                        .frame(width: 56, alignment: .trailing)
                }
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .frame(height: 20)
            }
            if topProcesses.isEmpty {
                Text("Prozesse werden eingelesen …")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .menuCardStyle()
    }

    // MARK: Aktionen und Verlauf

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                MenuAction(title: keepAwake.isOn ? String(localized: "Wach") : String(localized: "Wachhalten"),
                           icon: keepAwake.isOn ? "cup.and.saucer.fill" : "cup.and.saucer",
                           isOn: keepAwake.isOn) {
                    keepAwake.toggle()
                }
                MenuAction(title: String(localized: "Clyro öffnen"), icon: "leaf.fill", isOn: false) {
                    openMainWindow()
                }
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("Einstellungen")
                .accessibilityLabel("Einstellungen")
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.7))
                .help("Clyro beenden")
                .accessibilityLabel("Clyro beenden")
            }

            Divider().overlay(ClyroTheme.border)

            VStack(alignment: .leading, spacing: 8) {
                Label("Bereinigungsverlauf", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                HStack {
                    MenuStat(value: ClyroFormat.byteCount(cleaner.history.reduce(0) { $0 + $1.bytes }), label: String(localized: "Bereinigt"))
                    MenuStat(value: "\(uninstalled)", label: String(localized: "Deinstalliert"))
                    MenuStat(value: "\(optimized)", label: String(localized: "Optimiert"))
                }
                ClyroForest(records: cleaner.history)
                    .frame(height: 54)
                    .help("Jede Bereinigung pflanzt einen Baum")
            }
        }
        .menuCardStyle()
    }

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
    }

    // MARK: Texte

    private var topProcesses: [SystemProcess] {
        Array(snapshot.processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(5))
    }

    private var shortOSVersion: String {
        let numbers = snapshot.osVersion.split(separator: " ").first(where: { $0.first?.isNumber == true })
        return numbers.map(String.init) ?? snapshot.osVersion
    }

    private var cpuDetail: String {
        let cores = snapshot.corePercents.isEmpty ? ProcessInfo.processInfo.processorCount : snapshot.corePercents.count
        let state = snapshot.cpuPercent < 35 ? String(localized: "Leerlauf") : snapshot.cpuPercent < 70 ? String(localized: "Aktiv") : String(localized: "Hohe Last")
        let load = snapshot.loadAverage.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–"
        return String(localized: "\(state) · Last \(load)/\(cores)")
    }

    private var gpuDetail: String {
        let state = (snapshot.gpuPercent ?? 0) < 35 ? String(localized: "Leerlauf") : String(localized: "Aktiv")
        return snapshot.gpuCores.map { String(localized: "\(state) · \($0) Kerne") } ?? state
    }

    private var batteryTime: String {
        let remaining = snapshot.battery.timeRemaining
        if remaining.contains(":") { return String(localized: "\(remaining) übrig") }
        return remaining
    }

    private var topConsumer: SystemProcess? {
        snapshot.processes.filter { ($0.power ?? 0) > 0 }.max { ($0.power ?? 0) < ($1.power ?? 0) }
    }

    private var thermalColor: Color {
        switch snapshot.thermalState {
        case .nominal: ClyroTheme.mint
        case .fair: ClyroTheme.gold
        default: ClyroTheme.orange
        }
    }

    private var normalizedNetworkHistory: [Double] {
        let maxValue = max(1, monitor.downloadHistory.max() ?? 1)
        return monitor.downloadHistory.map { $0 / maxValue * 100 }
    }
}

// MARK: - Bausteine

private extension View {
    func menuCardStyle() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white.opacity(0.07)))
            )
    }
}

private struct MenuCard<Content: View>: View {
    let icon: String
    let title: String
    let accent: Color
    let badge: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    MenuBadge(text: badge)
                }
            }
            content
        }
        .menuCardStyle()
    }
}

private struct MenuBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
    }
}

private struct MenuValue: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MenuDetail: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

private struct MenuFillBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * CGFloat(min(1, max(0, fraction))))
            }
            .frame(height: 7)
            .frame(maxHeight: .infinity)
        }
    }
}

private struct MenuCoreBars: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let count = max(1, values.count)
            let spacing: CGFloat = 3
            let width = max(2, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(color.opacity(0.35 + 0.65 * min(1, value / 100)))
                        .frame(width: width, height: max(2, geometry.size.height * CGFloat(min(1, value / 100))))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

private struct MenuAction: View {
    let title: String
    let icon: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isOn ? Color.black.opacity(0.85) : Color.white.opacity(0.8))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(Capsule().fill(isOn ? ClyroTheme.mint : Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

private struct MenuStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
