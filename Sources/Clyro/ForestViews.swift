import Charts
import SwiftUI

/// Dein Wald: Jede Bereinigung pflanzt einen Baum. Größe nach freigegebenem Speicher, Farbe nach Jahreszeit.
struct ClyroForest: View {
    let records: [CleanupRecord]
    var maxTrees = 40

    private struct Tree {
        let x: CGFloat
        let depth: CGFloat
        let scale: CGFloat
        let season: ClyroSeason
        let seed: Double
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                draw(in: context, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .opacity(0.9)
        .accessibilityHidden(true)
    }

    private var trees: [Tree] {
        let planted = Array(records.prefix(maxTrees).reversed())
        guard !planted.isEmpty else { return [] }
        return planted.enumerated().map { index, record -> Tree in
            let seed = Double(index) * 1.618 + Double(record.bytes % 997)
            let slot = (CGFloat(index) + 0.5) / CGFloat(planted.count)
            let jitter = CGFloat(Self.hash(seed) - 0.5) * 0.6 / CGFloat(planted.count)
            let gigabytes = Double(max(0, record.bytes)) / 1_000_000_000
            let scale = CGFloat(min(1, 0.4 + 0.25 * log10(1 + gigabytes * 10)))
            return Tree(
                x: min(0.96, max(0.04, slot + jitter)),
                depth: CGFloat(Self.hash(seed * 3.3)),
                scale: scale,
                season: Self.season(of: record.date),
                seed: seed
            )
        }
        .sorted { $0.depth < $1.depth }
    }

    private func draw(in context: GraphicsContext, size: CGSize, time: Double) {
        var ctx = context
        let groundY = size.height * 0.84
        let ground = CGRect(x: 0, y: groundY - size.height * 0.04, width: size.width, height: size.height * 0.2)
        ctx.fill(Path(roundedRect: ground, cornerRadius: size.height * 0.1), with: .color(Color(red: 0.24, green: 0.34, blue: 0.22).opacity(0.55)))

        let list = trees
        if list.isEmpty {
            drawTree(in: &ctx, base: CGPoint(x: size.width * 0.5, y: groundY), height: size.height * 0.35, season: .spring, seed: 1, time: time)
            return
        }
        for tree in list {
            let base = CGPoint(x: size.width * tree.x, y: groundY - tree.depth * size.height * 0.1)
            let height = size.height * 0.72 * tree.scale * (0.85 + 0.15 * tree.depth)
            drawTree(in: &ctx, base: base, height: height, season: tree.season, seed: tree.seed, time: time)
        }
    }

    private func drawTree(in ctx: inout GraphicsContext, base: CGPoint, height: CGFloat, season: ClyroSeason, seed: Double, time: Double) {
        let sway = CGFloat(sin(time * 1.1 + seed)) * height * 0.03
        let top = CGPoint(x: base.x + sway, y: base.y - height)
        var trunk = Path()
        trunk.move(to: base)
        trunk.addQuadCurve(to: CGPoint(x: top.x, y: top.y + height * 0.35), control: CGPoint(x: base.x, y: base.y - height * 0.4))
        ctx.stroke(trunk, with: .color(Color(red: 0.38, green: 0.26, blue: 0.17)), style: StrokeStyle(lineWidth: max(1.5, height * 0.07), lineCap: .round))

        let r = height * 0.3
        let center = CGPoint(x: top.x, y: top.y + r * 0.9)
        switch season {
        case .winter:
            for side in [-1.0, 1.0] {
                var branch = Path()
                branch.move(to: CGPoint(x: center.x, y: center.y + r * 0.4))
                branch.addLine(to: CGPoint(x: center.x + CGFloat(side) * r * 0.8, y: center.y - r * 0.3))
                ctx.stroke(branch, with: .color(Color(red: 0.38, green: 0.30, blue: 0.28)), style: StrokeStyle(lineWidth: max(1, height * 0.035), lineCap: .round))
                let cap = CGRect(x: center.x + CGFloat(side) * r * 0.8 - r * 0.2, y: center.y - r * 0.45, width: r * 0.4, height: r * 0.22)
                ctx.fill(Path(ellipseIn: cap), with: .color(.white.opacity(0.9)))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: top.x - r * 0.25, y: top.y + r * 0.3, width: r * 0.5, height: r * 0.25)), with: .color(.white.opacity(0.9)))
        case .spring, .summer, .autumn:
            let colors = Self.canopy(season)
            let blobs: [(dx: CGFloat, dy: CGFloat, size: CGFloat)] = [(-0.45, 0.2, 0.75), (0.45, 0.2, 0.75), (0, -0.15, 1), (0, 0.35, 0.8)]
            for (index, blob) in blobs.enumerated() {
                let br = r * blob.size
                let rect = CGRect(x: center.x + blob.dx * r - br, y: center.y + blob.dy * r - br, width: br * 2, height: br * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(colors[index % colors.count]))
            }
            if season == .spring {
                for index in 0..<4 {
                    let angle = Double(index) * 1.7 + seed
                    let point = CGPoint(x: center.x + CGFloat(cos(angle)) * r * 0.6, y: center.y + CGFloat(sin(angle)) * r * 0.5)
                    ctx.fill(Path(ellipseIn: CGRect(x: point.x - r * 0.12, y: point.y - r * 0.12, width: r * 0.24, height: r * 0.24)), with: .color(Color(red: 1.0, green: 0.76, blue: 0.86)))
                }
            }
        }
    }

    static func season(of date: Date) -> ClyroSeason {
        switch Calendar.current.component(.month, from: date) {
        case 3, 4, 5: .spring
        case 6, 7, 8: .summer
        case 9, 10, 11: .autumn
        default: .winter
        }
    }

    private static func canopy(_ season: ClyroSeason) -> [Color] {
        switch season {
        case .spring: [Color(red: 0.55, green: 0.82, blue: 0.45), Color(red: 0.66, green: 0.88, blue: 0.50)]
        case .summer: [Color(red: 0.20, green: 0.52, blue: 0.27), Color(red: 0.28, green: 0.62, blue: 0.31)]
        case .autumn: [Color(red: 0.93, green: 0.55, blue: 0.20), Color(red: 0.84, green: 0.32, blue: 0.18), Color(red: 0.96, green: 0.76, blue: 0.28)]
        case .winter: [.white]
        }
    }

    private static func hash(_ value: Double) -> Double {
        let x = sin(value * 127.1 + 311.7) * 43758.5453
        return x - x.rounded(.down)
    }
}

/// Freigegebener Speicher pro Woche, die letzten 12 Wochen.
struct SavingsChart: View {
    let records: [CleanupRecord]
    let accent: Color

    private struct Week: Identifiable {
        let start: Date
        let gigabytes: Double
        var id: Date { start }
    }

    private var weeks: [Week] {
        let calendar = Calendar.current
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        var totals: [Date: Int64] = [:]
        for record in records {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: record.date)?.start else { continue }
            totals[start, default: 0] += max(0, record.bytes)
        }
        return (0..<12).reversed().compactMap { offset -> Week? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
            return Week(start: start, gigabytes: Double(totals[start] ?? 0) / 1_000_000_000)
        }
    }

    var body: some View {
        Chart(weeks) { week in
            BarMark(
                x: .value("Woche", week.start, unit: .weekOfYear),
                y: .value("GB", week.gigabytes)
            )
            .foregroundStyle(accent.gradient)
            .cornerRadius(4)
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let gb = value.as(Double.self) {
                        Text(gb < 1 && gb > 0 ? String(format: "%.1f GB", gb) : "\(Int(gb)) GB")
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
    }
}
