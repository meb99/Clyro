import AppKit
import Foundation
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    statusTile
                    cpuTile
                    gpuTile
                    memoryTile
                }
                .frame(height: 150)

                HStack(spacing: 12) {
                    batteryTile
                    diskTile
                    networkTile
                    thermalTile
                }
                .frame(height: 150)

                processTable
                    .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: 1400, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
            .opacity(monitor.hasLoaded ? 1 : 0.22)

            if !monitor.hasLoaded {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(ClyroTheme.mint)
                    Text("Systemdaten werden geladen …")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .clyroCard(padding: 18)
            }
        }
        .animation(.easeOut(duration: 0.2), value: monitor.hasLoaded)
    }

    // MARK: - Reihe 1

    private var statusTile: some View {
        let health = snapshot.health
        return StatusCard(title: String(localized: "ZUSTAND"), icon: "sun.max.fill", accent: ClyroTheme.mint, badges: [
            snapshot.chipName,
            ClyroFormat.memory(snapshot.memoryTotalBytes).replacingOccurrences(of: ".0", with: ""),
            shortOSVersion.split(separator: ".").first.map { "macOS \($0)" } ?? "macOS"
        ]) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(health.score)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(snapshot.healthText)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    Text(health.issues.isEmpty ? String(localized: "Alle Prüfungen bestanden") : health.issues.joined(separator: " · "))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(health.issues.isEmpty ? Color.secondary : ClyroTheme.gold)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Text(uptimeText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                ClyroOrb(score: health.score)
                    .frame(width: 52, height: 52)
            }
        }
    }

    private var cpuTile: some View {
        StatusCard(title: "CPU", icon: "cpu", accent: ClyroTheme.mint,
                   badges: snapshot.temperatureCelsius.map { ["\(Int($0.rounded())) °C"] } ?? []) {
            BigValue(value: String(format: "%.0f", snapshot.cpuPercent), unit: "%")
            CoreBars(values: snapshot.corePercents, color: ClyroTheme.mint)
                .frame(height: 22)
            Text(cpuDetail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var gpuTile: some View {
        StatusCard(title: "GPU", icon: "display", accent: ClyroTheme.blue,
                   badges: snapshot.gpuTemperatureCelsius.map { ["\(Int($0.rounded())) °C"] } ?? []) {
            BigValue(value: snapshot.gpuPercent.map { String(format: "%.0f", $0) } ?? "–", unit: snapshot.gpuPercent == nil ? "" : "%")
            Sparkline(values: monitor.gpuHistory, color: ClyroTheme.blue)
                .frame(height: 22)
            Text(gpuDetail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var memoryTile: some View {
        StatusCard(title: String(localized: "ARBEITSSPEICHER"), icon: "memorychip", accent: ClyroTheme.gold,
                   badges: snapshot.memoryPressurePercent.map { [String(localized: "Druck \($0) %")] } ?? []) {
            BigValue(value: String(format: "%.0f", snapshot.memoryPercent), unit: "%")
            Sparkline(values: monitor.memoryHistory, color: ClyroTheme.gold)
                .frame(height: 22)
            Text("\(ClyroFormat.memory(snapshot.memoryUsedBytes)) · \(snapshot.swapUsedBytes > 0 ? ClyroFormat.memory(snapshot.swapUsedBytes) : "0") Swap")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Reihe 2

    @ViewBuilder
    private var batteryTile: some View {
        if snapshot.battery.isPresent {
            StatusCard(title: String(localized: "BATTERIE"), icon: "battery.75percent", accent: ClyroTheme.mint,
                       badges: snapshot.battery.healthPercent.map { [String(localized: "\($0) % Gesundheit")] } ?? []) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            BigValue(value: "\(snapshot.battery.percentage)", unit: "%")
                            Text(batteryTime)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        Text(snapshot.battery.cycleCount.map { String(localized: "\($0) Zyklen") } ?? (snapshot.battery.isCharging ? String(localized: "Mit Strom verbunden") : String(localized: "Akkubetrieb")))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().stroke(.white.opacity(0.08), lineWidth: 4)
                        Circle()
                            .trim(from: 0, to: Double(snapshot.battery.percentage) / 100)
                            .stroke(ClyroTheme.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Image(systemName: snapshot.battery.isCharging ? "bolt.fill" : "laptopcomputer")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 46, height: 46)
                }
                Spacer(minLength: 0)
                if let top = topConsumer {
                    Label("Hauptverbraucher \(top.name) · \(String(format: "%.1f", top.power ?? 0))", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        } else {
            StatusCard(title: String(localized: "STROM"), icon: "powerplug.fill", accent: ClyroTheme.mint, badges: [String(localized: "Netzbetrieb")]) {
                BigValue(value: String(localized: "Desktop"), unit: "")
                Spacer(minLength: 0)
                if let top = topConsumer {
                    Label("Hauptverbraucher \(top.name) · \(String(format: "%.1f", top.power ?? 0))", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("Keine interne Batterie")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var diskTile: some View {
        var badges = [ClyroFormat.byteCount(snapshot.diskTotalBytes)]
        if snapshot.smartStatus == .failing { badges.insert("SMART ⚠", at: 0) }
        return StatusCard(title: String(localized: "FESTPLATTE"), icon: "internaldrive", accent: ClyroTheme.blue, badges: badges) {
            BigValue(value: ClyroFormat.byteCount(max(0, snapshot.diskTotalBytes - snapshot.diskUsedBytes)), unit: String(localized: "frei"))
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(ClyroTheme.blue)
                        .frame(width: geometry.size.width * min(1, snapshot.diskPercent / 100))
                }
            }
            .frame(height: 8)
            Text("\(ClyroFormat.byteCount(snapshot.diskUsedBytes)) belegt · \(Int(snapshot.diskPercent)) % · ↓\(ClyroFormat.compactSpeed(snapshot.diskReadBytesPerSecond)) ↑\(ClyroFormat.compactSpeed(snapshot.diskWriteBytesPerSecond))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var networkTile: some View {
        StatusCard(title: String(localized: "NETZWERK"), icon: "globe", accent: ClyroTheme.blue,
                   badges: snapshot.networkType.map { [$0] } ?? []) {
            BigValue(value: ClyroFormat.compactSpeed(snapshot.downloadBytesPerSecond), unit: "")
            Sparkline(values: normalizedNetworkHistory, color: ClyroTheme.blue)
                .frame(height: 22)
            Text("↑ \(ClyroFormat.compactSpeed(snapshot.uploadBytesPerSecond))\(snapshot.networkType.map { " · \($0)" } ?? "")")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var thermalTile: some View {
        StatusCard(title: String(localized: "TEMPERATUR"), icon: "thermometer.medium", accent: thermalColor,
                   badges: [snapshot.thermalState == .nominal ? String(localized: "Normal") : String(localized: "Warm")]) {
            if let cpu = snapshot.temperatureCelsius {
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    temperatureValue("CPU", cpu, color: ClyroTheme.mint)
                    if let gpu = snapshot.gpuTemperatureCelsius {
                        temperatureValue("GPU", gpu, color: ClyroTheme.blue)
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule()
                            .fill(thermalColor)
                            .frame(width: geometry.size.width * min(1, cpu / 100))
                    }
                }
                .frame(height: 8)
                Text(peakText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(snapshot.thermalText)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(thermalColor)
                Spacer(minLength: 0)
                Text("Wärmezustand laut macOS")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func temperatureValue(_ label: String, _ value: Double, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
            Text(String(format: "%.0f°", value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
        }
    }

    // MARK: - Prozesse

    private var processTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("NAME (\(snapshot.processCount))")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("MEM").frame(width: 80, alignment: .trailing)
                Text("% CPU").frame(width: 130, alignment: .trailing)
                Text("PWR").frame(width: 60, alignment: .trailing)
                Text("PID").frame(width: 64, alignment: .trailing)
                Spacer().frame(width: 26, height: 1)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(height: 22)
            .padding(.horizontal, 6)

            Divider().overlay(ClyroTheme.border)

            if snapshot.processes.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Prozesse werden eingelesen …")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.processes) { process in
                            ProcessRow(process: process)
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clyroCard(padding: 10)
    }

    // MARK: - Texte

    private var shortOSVersion: String {
        let numbers = snapshot.osVersion.split(separator: " ").first(where: { $0.first?.isNumber == true })
        return numbers.map(String.init) ?? snapshot.osVersion
    }

    private var uptimeText: String {
        String(localized: "Laufzeit \(ClyroFormat.uptime(snapshot.uptime))")
    }

    private var cpuDetail: String {
        let cores = snapshot.corePercents.isEmpty ? ProcessInfo.processInfo.processorCount : snapshot.corePercents.count
        let state = snapshot.cpuPercent < 35 ? String(localized: "Leerlauf") : snapshot.cpuPercent < 70 ? String(localized: "Aktiv") : String(localized: "Hohe Last")
        let load = snapshot.loadAverage.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "–"
        return String(localized: "\(state) · Last \(load) / \(cores) Kerne")
    }

    private var gpuDetail: String {
        let state = (snapshot.gpuPercent ?? 0) < 35 ? String(localized: "Leerlauf") : String(localized: "Aktiv")
        return snapshot.gpuCores.map { String(localized: "\(state) · \($0) GPU-Kerne") } ?? state
    }

    private var batteryTime: String {
        let remaining = snapshot.battery.timeRemaining
        if remaining.contains(":") { return String(localized: "\(remaining) übrig") }
        return remaining
    }

    private var topConsumer: SystemProcess? {
        snapshot.processes.filter { ($0.power ?? 0) > 0 }.max { ($0.power ?? 0) < ($1.power ?? 0) }
    }

    private var peakText: String {
        guard let peak = snapshot.temperaturePeak else { return snapshot.chipName }
        return String(localized: "\(snapshot.chipName) · Spitze 5 Min \(Int(peak.rounded())) °C")
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

private struct StatusCard<Content: View>: View {
    let title: String
    let icon: String
    let accent: Color
    let badges: [String]
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(title == String(localized: "ZUSTAND") ? accent : Color.white.opacity(0.75))
                    .lineLimit(1)
                Spacer(minLength: 4)
                ForEach(badges, id: \.self) { badge in
                    CompactBadge(text: badge)
                }
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clyroCard(padding: 14)
    }
}

private struct BigValue: View {
    let value: String
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !unit.isEmpty {
                Text(unit)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Ein kleiner Balken pro CPU-Kern.
private struct CoreBars: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let count = max(1, values.count)
            let spacing: CGFloat = 4
            let width = max(2, (geometry.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(0.35 + 0.65 * min(1, value / 100)))
                        .frame(width: width, height: max(2, geometry.size.height * min(1, value / 100)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct CompactBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.07)))
            .lineLimit(1)
    }
}

private struct ProcessRow: View {
    let process: SystemProcess

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: "terminal.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)

            Text(process.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(ClyroFormat.memory(process.memoryBytes))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)

            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.07))
                        Capsule()
                            .fill(process.cpuPercent > 40 ? ClyroTheme.gold : Color.white.opacity(0.45))
                            .frame(width: geometry.size.width * min(1, process.cpuPercent / 100))
                    }
                }
                .frame(width: 70, height: 5)
                Text(String(format: "%.1f", process.cpuPercent))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(process.cpuPercent > 40 ? ClyroTheme.gold : Color.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            .frame(width: 130, alignment: .trailing)

            Text(process.power.map { String(format: "%.1f", $0) } ?? "–")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle((process.power ?? 0) > 20 ? ClyroTheme.gold : Color.secondary)
                .frame(width: 60, alignment: .trailing)

            Text("\(process.id)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)

            Menu {
                if let appURL {
                    Button("Im Finder zeigen") { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }
                }
                Button("App beenden") {
                    NSRunningApplication(processIdentifier: process.id)?.terminate()
                }
                .disabled(NSRunningApplication(processIdentifier: process.id) == nil)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 26, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .frame(height: 28)
        .padding(.horizontal, 6)
    }

    private var appURL: URL? {
        guard !process.executablePath.isEmpty else { return nil }
        let pieces = process.executablePath.components(separatedBy: ".app/")
        guard pieces.count > 1 else { return nil }
        let appPath = pieces[0] + ".app"
        guard FileManager.default.fileExists(atPath: appPath) else { return nil }
        return URL(fileURLWithPath: appPath)
    }

    private var appIcon: NSImage? {
        guard let appURL else { return nil }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
}

private struct ClyroOrb: View {
    let score: Int

    var body: some View {
        ClyroGrowth(growth: ClyroGrowth.growth(forHealth: score))
            .help("Dein Mac als \(ClyroGrowth.stageName(for: ClyroGrowth.growth(forHealth: score)))")
    }
}
