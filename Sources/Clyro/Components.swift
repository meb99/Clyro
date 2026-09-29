import AppKit
import Charts
import SwiftUI

struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.white.opacity(0.07)))
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    private struct Point: Identifiable {
        let id: Int
        let value: Double
    }

    private var points: [Point] {
        values.enumerated().map { Point(id: $0.offset, value: $0.element) }
    }

    var body: some View {
        Chart(points) { point in
            AreaMark(
                x: .value("Zeit", point.id),
                y: .value("Wert", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [color.opacity(0.34), color.opacity(0.01)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            LineMark(
                x: .value("Zeit", point.id),
                y: .value("Wert", point.value)
            )
            .foregroundStyle(color)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...max(100, (values.max() ?? 0) * 1.12))
        .allowsHitTesting(false)
    }
}

struct MetricCard: View {
    let title: String
    let icon: String
    let value: String
    let unit: String
    let badge: String
    let detail: String
    let color: Color
    let history: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
                    .symbolRenderingMode(.hierarchical)
                Spacer()
                Text(badge)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.67))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.065)))
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                Text(unit)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            }

            Sparkline(values: history, color: color)
                .frame(height: 48)

            Text(detail)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(ClyroTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clyroCard()
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String?

    init(_ title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 25, weight: .semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(ClyroTheme.secondaryText)
            }
        }
    }
}

struct ClyroPageHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent.opacity(0.15))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ClyroTheme.secondaryText)
                    .lineLimit(1)
            }
        }
    }
}

struct ClyroStatPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 12, weight: .bold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 38)
        .background(Capsule().fill(.white.opacity(0.065)))
        .overlay(Capsule().stroke(.white.opacity(0.07)))
    }
}

struct ClyroArtifact: View {
    let symbol: String
    let satellite: String
    let accent: Color
    let secondary: Color
    var growth: Double = 0.55

    @State private var floating = false

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [accent.opacity(0.26), .clear], center: .center, startRadius: 4, endRadius: 92))
                .frame(width: 184, height: 184)

            ClyroGrowth(growth: growth, accent: accent)
                .frame(width: 170, height: 150)
                .rotationEffect(.degrees(floating ? 1.2 : -1.2), anchor: .bottom)

            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.9)))
                .offset(x: 64, y: floating ? -54 : -47)

            Image(systemName: satellite)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 24)
                .background(Circle().fill(secondary))
                .offset(x: -66, y: floating ? -22 : -29)
        }
        .frame(width: 190, height: 180)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.2).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 35))
                .foregroundStyle(ClyroTheme.mint)
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
            Text(message)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(ClyroTheme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .clyroCard()
    }
}

extension ProcessCrewRole {
    var color: Color {
        switch self {
        case .navigator: ClyroTheme.blue
        case .messenger: ClyroTheme.mint
        case .studio: ClyroTheme.orange
        case .workshop: ClyroTheme.gold
        case .atelier: Color(red: 0.78, green: 0.49, blue: 0.95)
        case .courier: Color(red: 0.42, green: 0.76, blue: 0.96)
        case .guardian: Color(red: 0.45, green: 0.84, blue: 0.60)
        case .engineRoom: Color(red: 0.65, green: 0.68, blue: 0.76)
        case .helper: ClyroTheme.mint
        }
    }
}

struct ProcessCrewRow: View {
    let process: SystemProcess
    var showsTechnicalDetails = false

    var body: some View {
        HStack(spacing: 14) {
            ProcessCrewAvatar(process: process)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(process.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)

                    Text("\(process.crewRole.emoji) \(process.crewRole.title)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(process.crewRole.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(process.crewRole.color.opacity(0.11)))
                }

                Text(process.explanation)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(ClyroTheme.secondaryText)
                    .lineLimit(1)

                if showsTechnicalDetails && !process.executablePath.isEmpty {
                    Text(process.executablePath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.34))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ClyroFormat.byteCount(process.memoryBytes))
                .frame(width: 86, alignment: .trailing)
                .foregroundStyle(ClyroTheme.secondaryText)

            VStack(alignment: .trailing, spacing: 4) {
                Text(String(format: "%.1f%%", process.cpuPercent))
                    .foregroundStyle(process.cpuPercent > 40 ? ClyroTheme.orange : .white.opacity(0.78))
                Capsule()
                    .fill(.white.opacity(0.07))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(process.cpuPercent > 40 ? ClyroTheme.orange : process.crewRole.color)
                            .frame(width: 64 * min(1, process.cpuPercent / 100))
                    }
                    .frame(width: 64, height: 4)
            }
            .frame(width: 72, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .semibold, design: .rounded))
        .padding(.vertical, 3)
    }
}

struct ProcessCrewAvatar: View {
    let process: SystemProcess

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.white.opacity(0.035)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 38, height: 38)
                } else {
                    Image(systemName: process.crewRole.systemImage)
                        .font(.system(size: 24, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .frame(width: 50, height: 50)

            Text(process.crewRole.emoji)
                .font(.system(size: 13))
                .frame(width: 22, height: 22)
                .background(Circle().fill(ClyroTheme.sidebar))
                .overlay(Circle().stroke(.white.opacity(0.10)))
                .offset(x: 4, y: 4)
        }
        .padding(.trailing, 4)
        .padding(.bottom, 4)
    }

    private var appIcon: NSImage? {
        guard !process.executablePath.isEmpty else { return nil }
        let pieces = process.executablePath.components(separatedBy: ".app/")
        guard pieces.count > 1 else { return nil }
        let appPath = pieces[0] + ".app"
        guard FileManager.default.fileExists(atPath: appPath) else { return nil }
        return NSWorkspace.shared.icon(forFile: appPath)
    }
}
