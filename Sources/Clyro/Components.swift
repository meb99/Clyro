import AppKit
import Charts
import SwiftUI

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
