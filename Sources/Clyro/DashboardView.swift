import AppKit
import Foundation
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let compact = geometry.size.height < 660

                VStack(spacing: 10) {
                    overviewRow
                        .frame(height: compact ? 132 : 144)

                    activityRow
                        .frame(height: compact ? 112 : 122)

                    processTable
                        .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: 1320, maxHeight: .infinity)
                .frame(maxWidth: .infinity)
            }
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

    private var overviewRow: some View {
        HStack(spacing: 10) {
            statusTile
            CompactMetricTile(
                title: "CPU",
                icon: "cpu",
                value: String(format: "%.0f", snapshot.cpuPercent),
                unit: "%",
                badge: snapshot.temperatureCelsius.map { "\(Int($0.rounded())) °C" } ?? cpuBadge,
                detail: cpuDetail,
                color: ClyroTheme.mint,
                history: monitor.cpuHistory
            )
            gpuTile
            CompactMetricTile(
                title: "Arbeitsspeicher",
                icon: "memorychip",
                value: String(format: "%.0f", snapshot.memoryPercent),
                unit: "%",
                badge: memoryBadge,
                detail: "\(ClyroFormat.byteCount(snapshot.memoryUsedBytes)) von \(ClyroFormat.byteCount(snapshot.memoryTotalBytes))",
                color: ClyroTheme.gold,
                history: monitor.memoryHistory
            )
        }
    }

    private var activityRow: some View {
        HStack(spacing: 10) {
            batteryTile
            diskTile
            CompactMetricTile(
                title: "Netzwerk",
                icon: "network",
                value: ClyroFormat.speed(snapshot.downloadBytesPerSecond),
                unit: "↓",
                badge: "Live",
                detail: "↑ \(ClyroFormat.speed(snapshot.uploadBytesPerSecond))",
                color: ClyroTheme.blue,
                history: normalizedNetworkHistory
            )
            thermalTile
        }
    }

    @ViewBuilder
    private var gpuTile: some View {
        if let gpu = snapshot.gpuPercent {
            CompactMetricTile(
                title: "GPU",
                icon: "display",
                value: String(format: "%.0f", gpu),
                unit: "%",
                badge: snapshot.gpuTemperatureCelsius.map { "\(Int($0.rounded())) °C" } ?? (gpu < 35 ? "Leerlauf" : "Aktiv"),
                detail: snapshot.gpuCores.map { "\($0) GPU-Kerne" } ?? "Grafikprozessor",
                color: ClyroTheme.blue,
                history: monitor.gpuHistory
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("GPU", systemImage: "display")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("–")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                Spacer(minLength: 0)
                Text("Keine GPU-Werte verfügbar")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clyroCard(padding: 14)
        }
    }

    private var statusTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("ZUSTAND", systemImage: "sun.max.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ClyroTheme.mint)
                Spacer()
                CompactBadge(text: snapshot.chipName)
                CompactBadge(text: "macOS \(shortOSVersion)")
            }

            HStack(spacing: 8) {
                Text("\(snapshot.healthScore)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text(snapshot.healthText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                ClyroOrb(score: snapshot.healthScore)
                    .frame(width: 46, height: 46)
            }

            Text(snapshot.healthScore >= 92 ? "Alle Prüfungen bestanden" : "Ein paar Werte sind auffällig")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Text("Laufzeit \(ClyroFormat.uptime(snapshot.uptime))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(ClyroTheme.mint)
                .disabled(monitor.isRefreshing)
                .help("Systemdaten aktualisieren")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clyroCard(padding: 14)
    }

    private var diskBadge: String {
        let size = ClyroFormat.byteCount(snapshot.diskTotalBytes)
        switch snapshot.smartStatus {
        case .verified: return "SMART ✓ · \(size)"
        case .failing: return "SMART ⚠ · \(size)"
        case .unsupported, .unknown: return size
        }
    }

    private var diskTile: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Festplatte", systemImage: "internaldrive.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                CompactBadge(text: diskBadge)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(ClyroFormat.byteCount(snapshot.diskUsedBytes))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text("belegt")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule()
                        .fill(ClyroTheme.blue)
                        .frame(width: geometry.size.width * min(1, snapshot.diskPercent / 100))
                }
            }
            .frame(height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(ClyroFormat.byteCount(snapshot.diskTotalBytes - snapshot.diskUsedBytes)) frei · \(Int(snapshot.diskPercent)) % belegt")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("Lesen \(ClyroFormat.speed(snapshot.diskReadBytesPerSecond)) · Schreiben \(ClyroFormat.speed(snapshot.diskWriteBytesPerSecond))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(ClyroTheme.blue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clyroCard(padding: 14)
    }

    private var thermalColor: Color {
        switch snapshot.thermalState {
        case .nominal: ClyroTheme.mint
        case .fair: ClyroTheme.gold
        default: ClyroTheme.orange
        }
    }

    private var thermalTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Temperatur", systemImage: "thermometer.medium")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                CompactBadge(text: snapshot.thermalState == .nominal ? "Normal" : "Warm")
            }

            if let cpu = snapshot.temperatureCelsius {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    temperatureValue("CPU", cpu, color: ClyroTheme.mint)
                    if let gpu = snapshot.gpuTemperatureCelsius {
                        temperatureValue("GPU", gpu, color: ClyroTheme.blue)
                    }
                }
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.07))
                        Capsule()
                            .fill(thermalColor)
                            .frame(width: geometry.size.width * min(1, cpu / 100))
                    }
                }
                .frame(height: 8)
                Text(peakText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text(snapshot.thermalText)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(thermalColor)
                    .lineLimit(2)
                Spacer(minLength: 0)
                Text("Wärmezustand laut macOS")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clyroCard(padding: 14)
    }

    private func temperatureValue(_ label: String, _ value: Double, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(color)
            Text(String(format: "%.0f°", value))
                .font(.system(size: 26, weight: .bold, design: .rounded))
        }
    }

    private var peakText: String {
        let peak = monitor.temperatureHistory.max() ?? 0
        let chip = snapshot.chipName
        return peak > 0 ? "\(chip) · Spitze \(Int(peak.rounded())) °C" : chip
    }

    @ViewBuilder
    private var batteryTile: some View {
        if snapshot.battery.isPresent {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Batterie", systemImage: snapshot.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(snapshot.battery.percentage)%")
                            .font(.system(size: 29, weight: .bold, design: .rounded))
                        Text(snapshot.battery.timeRemaining)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text(batteryDetail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle().stroke(.white.opacity(0.07), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: Double(snapshot.battery.percentage) / 100)
                        .stroke(ClyroTheme.mint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: snapshot.battery.isCharging ? "bolt.fill" : "battery.75percent")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ClyroTheme.mint)
                }
                .frame(width: 48, height: 48)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clyroCard(padding: 14)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 27))
                    .foregroundStyle(ClyroTheme.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Desktop-Mac")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Keine interne Batterie erkannt")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clyroCard(padding: 14)
        }
    }

    private var processTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("NAME (\(snapshot.processCount))")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("SPEICHER")
                    .frame(width: 90, alignment: .trailing)
                Text("% CPU")
                    .frame(width: 130, alignment: .trailing)
                Text("PID")
                    .frame(width: 64, alignment: .trailing)
                Color.clear.frame(width: 26)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            Divider().overlay(ClyroTheme.border)

            if snapshot.processes.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Prozesse werden eingelesen …")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshot.processes) { process in
                            CompactProcessRow(process: process)
                            Divider()
                                .overlay(.white.opacity(0.035))
                                .padding(.leading, 30)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clyroCard(padding: 12)
    }

    private var shortOSVersion: String {
        let numbers = snapshot.osVersion.split(separator: " ").first(where: { $0.first?.isNumber == true })
        return numbers.map(String.init) ?? snapshot.osVersion
    }

    private var normalizedNetworkHistory: [Double] {
        let maxValue = max(1, monitor.downloadHistory.max() ?? 1)
        return monitor.downloadHistory.map { $0 / maxValue * 100 }
    }

    private var cpuBadge: String {
        snapshot.cpuPercent < 35 ? "Leerlauf" : snapshot.cpuPercent < 70 ? "Aktiv" : "Hoch"
    }

    private var cpuDetail: String {
        guard let top = snapshot.processes.first else { return "Keine Prozessdaten" }
        if let load = snapshot.loadAverage {
            return "Last \(String(format: "%.1f", load)) · Top: \(top.name)"
        }
        return "Top: \(top.name)"
    }

    private var memoryBadge: String {
        snapshot.memoryPercent < 70 ? "Entspannt" : snapshot.memoryPercent < 86 ? "Normal" : "Hoch"
    }

    private var batteryDetail: String {
        var parts = [snapshot.battery.isCharging ? "Mit Strom verbunden" : batteryAdvice]
        if let health = snapshot.battery.healthPercent { parts.append("Kapazität \(health) %") }
        if let cycles = snapshot.battery.cycleCount { parts.append("\(cycles) Zyklen") }
        return parts.joined(separator: " · ")
    }

    private var batteryAdvice: String {
        snapshot.battery.percentage < 20 ? "Bald mit Strom verbinden" : "Batteriestand in Ordnung"
    }
}

private struct CompactMetricTile: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let badge: String
    let detail: String
    let color: Color
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                CompactBadge(text: badge)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                Text(unit)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
            }

            Sparkline(values: history, color: color)
                .frame(height: 28)

            Text(detail)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clyroCard(padding: 14)
    }
}

private struct CompactBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.055)))
            .lineLimit(1)
    }
}

private struct CompactProcessRow: View {
    let process: SystemProcess

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                } else {
                    Image(systemName: process.crewRole.systemImage)
                        .resizable()
                        .scaledToFit()
                        .padding(3)
                        .foregroundStyle(process.crewRole.color)
                }
            }
            .frame(width: 20, height: 20)

            Text(process.name)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(ClyroFormat.byteCount(process.memoryBytes))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .trailing)

            HStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.07))
                        Capsule()
                            .fill(process.cpuPercent > 40 ? ClyroTheme.orange : Color.white.opacity(0.45))
                            .frame(width: geometry.size.width * min(1, process.cpuPercent / 100))
                    }
                }
                .frame(width: 70, height: 5)
                Text(String(format: "%.1f", process.cpuPercent))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(process.cpuPercent > 40 ? ClyroTheme.orange : Color.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
            .frame(width: 130, alignment: .trailing)

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
                    .frame(width: 26, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 26)
        }
        .frame(height: 30)
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
