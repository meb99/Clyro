import SwiftUI

/// Clyros Erkennungsmotiv: ein Keimling, der mit deiner Pflege zum blühenden Wald heranwächst.
/// `growth` reicht von 0 (frisch gepflanzt) bis 1 (ausgewachsener Wald).
struct ClyroGrowth: View {
    let growth: Double
    var accent: Color = ClyroTheme.mint
    var animated = true

    static func stageName(for growth: Double) -> String {
        switch growth {
        case ..<0.15: String(localized: "Keimling")
        case ..<0.35: String(localized: "Setzling")
        case ..<0.55: String(localized: "junger Baum")
        case ..<0.8: String(localized: "kleiner Hain")
        default: String(localized: "Wald")
        }
    }

    /// Wachstum aus der insgesamt bereinigten Datenmenge: etwa 20 GB ergeben einen vollen Wald.
    static func growth(forFreedBytes bytes: Int64) -> Double {
        let gigabytes = Double(max(0, bytes)) / 1_000_000_000
        return min(1, 0.06 + (gigabytes / 20).squareRoot() * 0.94)
    }

    /// Wachstum aus dem Gesundheitswert (0–100).
    static func growth(forHealth score: Int) -> Double {
        min(1, max(0.08, Double(score - 40) / 60))
    }

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1.0 / 24.0)) { timeline in
                plant(time: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            plant(time: 0)
        }
    }

    private func plant(time: Double) -> some View {
        Canvas { context, size in
            var painter = context
            GardenPainter.paint(in: &painter, size: size, growth: growth, accent: accent, time: time)
        }
    }
}

/// Zeichnet Boden, Pflanzen und Blüten. Wird von `ClyroGrowth` und der Garten-Szene gemeinsam genutzt.
enum GardenPainter {
    static let flowerColors: [Color] = [
        Color(red: 0.98, green: 0.62, blue: 0.75),
        Color(red: 1.00, green: 0.85, blue: 0.40),
        Color(red: 0.97, green: 0.97, blue: 0.95),
        Color(red: 0.75, green: 0.62, blue: 0.98)
    ]

    static func paint(in context: inout GraphicsContext, size: CGSize, growth: Double, accent: Color, time: Double) {
        let g = CGFloat(min(1, max(0, growth)))
        let w = size.width
        let h = size.height
        let groundY = h * 0.86

        let soil = Path(ellipseIn: CGRect(x: w * 0.04, y: groundY - h * 0.05, width: w * 0.92, height: h * 0.17))
        context.fill(soil, with: .color(Color(red: 0.31, green: 0.20, blue: 0.11)))
        let grass = Path(ellipseIn: CGRect(x: w * 0.04, y: groundY - h * 0.065, width: w * 0.92, height: h * 0.11))
        context.fill(grass, with: .color(accent.opacity(0.62)))

        if g >= 0.5 {
            let factor = min(1, (g - 0.5) / 0.2)
            let spots: [(x: CGFloat, color: Int)] = [(0.16, 0), (0.30, 1), (0.70, 2), (0.85, 3), (0.5, 1)]
            for spot in spots {
                let center = CGPoint(x: w * spot.x, y: groundY - h * 0.03)
                drawFlower(in: &context, center: center, radius: 2.6 * factor, color: flowerColors[spot.color])
            }
        }

        let mainHeight = h * (0.17 + 0.5 * g)
        var trees: [(x: CGFloat, scale: CGFloat)] = [(0.5, 1.0)]
        if g >= 0.55 { trees += [(0.27, 0.72), (0.73, 0.78)] }
        if g >= 0.8 { trees += [(0.11, 0.5), (0.89, 0.55)] }
        let flowerScale = min(1, max(0, (g - 0.35) / 0.2))

        for tree in trees.sorted(by: { $0.scale < $1.scale }) {
            let x = w * tree.x
            let baseY = groundY - h * 0.02
            let sway = sin(time * 1.3 + Double(tree.x) * 6) * 0.025

            var treeContext = context
            treeContext.translateBy(x: x, y: baseY)
            treeContext.rotate(by: .radians(sway))
            treeContext.translateBy(x: -x, y: -baseY)
            drawTree(
                in: &treeContext,
                x: x,
                baseY: baseY,
                height: mainHeight * tree.scale,
                accent: accent,
                flowerScale: flowerScale
            )
        }
    }

    static func drawTree(
        in context: inout GraphicsContext,
        x: CGFloat,
        baseY: CGFloat,
        height: CGFloat,
        accent: Color,
        flowerScale: CGFloat
    ) {
        let leaf = accent
        let deep = accent.opacity(0.78)

        if height < 34 {
            // Frischer Keimling: dünner Stiel mit zwei Blättchen.
            var stem = Path()
            stem.move(to: CGPoint(x: x, y: baseY))
            stem.addLine(to: CGPoint(x: x, y: baseY - height))
            context.stroke(stem, with: .color(deep), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            let leafWidth = max(10, height * 0.62)
            let leafHeight = leafWidth * 0.56
            let left = CGRect(x: x - leafWidth - 1, y: baseY - height - leafHeight * 0.4, width: leafWidth, height: leafHeight)
            let right = CGRect(x: x + 1, y: baseY - height - leafHeight * 0.9, width: leafWidth, height: leafHeight)
            context.fill(Path(ellipseIn: left), with: .color(leaf))
            context.fill(Path(ellipseIn: right), with: .color(deep))
            return
        }

        let trunkWidth = max(4, height * 0.09)
        let trunkHeight = height * 0.52
        let trunk = CGRect(x: x - trunkWidth / 2, y: baseY - trunkHeight, width: trunkWidth, height: trunkHeight)
        context.fill(
            Path(roundedRect: trunk, cornerRadius: trunkWidth / 2),
            with: .color(Color(red: 0.45, green: 0.30, blue: 0.17))
        )

        let crown = height * 0.3
        let parts: [(dx: CGFloat, dy: CGFloat, scale: CGFloat, deep: Bool)] = [
            (-0.55, 0.46, 0.78, true),
            (0.55, 0.46, 0.78, true),
            (0, 0.7, 1.0, false)
        ]
        for part in parts {
            let radius = crown * part.scale
            let center = CGPoint(x: x + part.dx * crown, y: baseY - height * part.dy)
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .color(part.deep ? deep : leaf))
        }

        guard flowerScale > 0 else { return }
        let blossoms: [(dx: CGFloat, dy: CGFloat, color: Int)] = [
            (-0.55, 0.5, 0), (0.5, 0.55, 1), (0.05, 0.9, 2), (-0.2, 0.72, 3), (0.38, 0.78, 0)
        ]
        for blossom in blossoms {
            let center = CGPoint(x: x + blossom.dx * crown, y: baseY - height * blossom.dy)
            drawFlower(
                in: &context,
                center: center,
                radius: max(2, crown * 0.12) * flowerScale,
                color: flowerColors[blossom.color]
            )
        }
    }

    static func drawFlower(in context: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        guard radius > 0.3 else { return }
        for index in 0..<5 {
            let angle = Double(index) / 5 * 2 * Double.pi
            let petalX = center.x + CGFloat(cos(angle)) * radius
            let petalY = center.y + CGFloat(sin(angle)) * radius
            let rect = CGRect(x: petalX - radius * 0.7, y: petalY - radius * 0.7, width: radius * 1.4, height: radius * 1.4)
            context.fill(Path(ellipseIn: rect), with: .color(color))
        }
        let core = CGRect(x: center.x - radius * 0.5, y: center.y - radius * 0.5, width: radius, height: radius)
        context.fill(Path(ellipseIn: core), with: .color(Color(red: 1.0, green: 0.80, blue: 0.20)))
    }
}
