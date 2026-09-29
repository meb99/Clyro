import Foundation
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var monitor: SystemMonitor

    private var snapshot: SystemSnapshot { monitor.snapshot }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    healthHeader
                    metricGrid
                    batteryAndNetwork
                    processCard
                }
                .padding(26)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
            .opacity(monitor.hasLoaded ? 1 : 0.25)

            if !monitor.hasLoaded {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(ClyroTheme.mint)
                    Text("Systemdaten werden geladen …")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                .clyroCard()
            }
        }
        .animation(.easeOut(duration: 0.25), value: monitor.hasLoaded)
    }

    private var healthHeader: some View {
        HStack(alignment: .top, spacing: 18) {
            ZStack {
                Circle()
                    .fill(ClyroTheme.mint.opacity(0.13))
                Image(systemName: snapshot.healthScore > 80 ? "sun.max.fill" : "gauge.with.dots.needle.50percent")
                    .font(.system(size: 29))
                    .foregroundStyle(ClyroTheme.mint)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text("\(snapshot.healthScore)")
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                    Text(snapshot.healthText)
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.62))
                }

                HStack(spacing: 7) {
                    TagView(text: snapshot.chipName)
                    TagView(text: ClyroFormat.byteCount(snapshot.memoryTotalBytes))
                    TagView(text: "macOS \(shortOSVersion)")
                    TagView(text: "Laufzeit \(ClyroFormat.uptime(snapshot.uptime))")
                }
            }

            Spacer()

            Button {
                monitor.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(.white.opacity(0.06)))
            .foregroundStyle(ClyroTheme.mint)
            .disabled(monitor.isRefreshing)
        }
        .clyroCard(padding: 22)
    }

    private var shortOSVersion: String {
        let numbers = snapshot.osVersion.split(separator: " ").first(where: { $0.first?.isNumber == true })
        return numbers.map(String.init) ?? snapshot.osVersion
    }

    private var metricGrid: some View {
        HStack(spacing: 16) {
            MetricCard(
                title: "CPU",
                icon: "cpu",
                value: String(format: "%.0f", snapshot.cpuPercent),
                unit: "%",
                badge: cpuBadge,
                detail: cpuDetail,
                color: ClyroTheme.mint,
                history: monitor.cpuHistory
            )
            MetricCard(
                title: "Arbeitsspeicher",
                icon: "memorychip",
                value: String(format: "%.0f", snapshot.memoryPercent),
                unit: "%",
                badge: memoryBadge,
                detail: "\(ClyroFormat.byteCount(snapshot.memoryUsedBytes)) von \(ClyroFormat.byteCount(snapshot.memoryTotalBytes))",
                color: ClyroTheme.gold,
                history: monitor.memoryHistory
            )
            diskCard
        }
    }

    private var diskCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Festplatte", systemImage: "internaldrive.fill")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                Spacer()
                Text(ClyroFormat.byteCount(snapshot.diskTotalBytes))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.67))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.065)))
            }

            Text(ClyroFormat.byteCount(snapshot.diskUsedBytes))
                .font(.system(size: 29, weight: .bold, design: .rounded))

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule()
                        .fill(ClyroTheme.blue)
                        .frame(width: geometry.size.width * min(1, snapshot.diskPercent / 100))
                }
            }
            .frame(height: 13)
            .padding(.vertical, 14)

            Text("\(ClyroFormat.byteCount(snapshot.diskTotalBytes - snapshot.diskUsedBytes)) frei · \(Int(snapshot.diskPercent)) % belegt")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ClyroTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clyroCard()
    }

    private var batteryAndNetwork: some View {
        HStack(spacing: 16) {
            MetricCard(
                title: "Netzwerk",
                icon: "network",
                value: ClyroFormat.speed(snapshot.downloadBytesPerSecond),
                unit: "↓",
                badge: "Live",
                detail: "↑ \(ClyroFormat.speed(snapshot.uploadBytesPerSecond))",
                color: ClyroTheme.blue,
                history: normalizedNetworkHistory
            )

            batteryCard
        }
    }

    @ViewBuilder
    private var batteryCard: some View {
        if snapshot.battery.isPresent {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 11) {
                    Label("Batterie", systemImage: snapshot.battery.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.64))
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(snapshot.battery.percentage)%")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(snapshot.battery.timeRemaining)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(ClyroTheme.secondaryText)
                    }
                    Text(snapshot.battery.isCharging ? "Mit Strom verbunden" : batteryAdvice)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.07), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: Double(snapshot.battery.percentage) / 100)
                        .stroke(ClyroTheme.mint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: "bolt.fill")
                        .foregroundStyle(ClyroTheme.mint)
                }
                .frame(width: 72, height: 72)
            }
            .frame(maxWidth: .infinity, minHeight: 122)
            .clyroCard()
        } else {
            HStack(spacing: 18) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 31))
                    .foregroundStyle(ClyroTheme.mint)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Mac ohne Batterie")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Auf diesem Mac wurde keine interne Batterie erkannt.")
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 122)
            .clyroCard()
        }
    }

    private var processCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("🧰")
                            .font(.system(size: 20))
                        Text("Die Clyro Crew")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    Text("Was gerade auf deinem Mac arbeitet – verständlich erklärt.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                Spacer()
                HStack(spacing: 18) {
                    Label("RAM", systemImage: "memorychip")
                        .frame(width: 86, alignment: .trailing)
                    Label("CPU", systemImage: "cpu")
                        .frame(width: 72, alignment: .trailing)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(ClyroTheme.secondaryText)
            }

            Divider().overlay(.white.opacity(0.055))

            if snapshot.processes.isEmpty {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(ClyroTheme.mint)
                    Text("Die Crew wird gerade zusammengestellt …")
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            } else {
                let visibleProcesses = Array(snapshot.processes.prefix(7))
                ForEach(visibleProcesses) { process in
                    ProcessCrewRow(process: process, showsTechnicalDetails: false)
                    if process.id != visibleProcesses.last?.id {
                        Divider()
                            .overlay(.white.opacity(0.045))
                            .padding(.leading, 64)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clyroCard()
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
        return "Größter Verbraucher: \(top.name)"
    }

    private var memoryBadge: String {
        snapshot.memoryPercent < 70 ? "Entspannt" : snapshot.memoryPercent < 86 ? "Normal" : "Hoch"
    }

    private var batteryAdvice: String {
        snapshot.battery.percentage < 20 ? "Bald mit Strom verbinden" : "Batteriestand ist in Ordnung"
    }
}
