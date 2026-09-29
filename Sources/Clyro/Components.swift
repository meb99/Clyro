import Charts
import SwiftUI

struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.68))
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
                .font(.system(size: 27, weight: .bold, design: .rounded))
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(ClyroTheme.secondaryText)
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
