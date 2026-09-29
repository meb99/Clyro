import SwiftUI

/// Clyros Erkennungsmotiv: ein Keimling, der mit deiner Pflege zum Wald heranwächst.
/// `growth` reicht von 0 (frisch gepflanzt) bis 1 (ausgewachsener Wald).
struct ClyroGrowth: View {
    let growth: Double
    var accent: Color = ClyroTheme.mint

    static func stageName(for growth: Double) -> String {
        switch growth {
        case ..<0.15: "Keimling"
        case ..<0.35: "Setzling"
        case ..<0.55: "junger Baum"
        case ..<0.8: "kleiner Hain"
        default: "Wald"
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
        Canvas { context, size in
            let g = min(1, max(0, growth))
            let w = size.width
            let h = size.height
            let groundY = h * 0.86

            let soil = Path(ellipseIn: CGRect(x: w * 0.04, y: groundY - h * 0.05, width: w * 0.92, height: h * 0.17))
            context.fill(soil, with: .color(Color(red: 0.31, green: 0.20, blue: 0.11)))
            let grass = Path(ellipseIn: CGRect(x: w * 0.04, y: groundY - h * 0.065, width: w * 0.92, height: h * 0.11))
            context.fill(grass, with: .color(accent.opacity(0.62)))

            let mainHeight = h * (0.17 + 0.5 * g)
            var trees: [(x: CGFloat, scale: CGFloat)] = [(0.5, 1.0)]
            if g >= 0.55 { trees += [(0.27, 0.72), (0.73, 0.78)] }
            if g >= 0.8 { trees += [(0.11, 0.5), (0.89, 0.55)] }

            for tree in trees.sorted(by: { $0.scale < $1.scale }) {
                Self.drawTree(
                    in: &context,
                    x: w * tree.x,
                    baseY: groundY - h * 0.02,
                    height: mainHeight * tree.scale,
                    accent: accent
                )
            }
        }
    }

    private static func drawTree(in context: inout GraphicsContext, x: CGFloat, baseY: CGFloat, height: CGFloat, accent: Color) {
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
            context.fill(
                Path(ellipseIn: CGRect(x: x - leafWidth - 1, y: baseY - height - leafHeight * 0.4, width: leafWidth, height: leafHeight)),
                with: .color(leaf)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: x + 1, y: baseY - height - leafHeight * 0.9, width: leafWidth, height: leafHeight)),
                with: .color(deep)
            )
            return
        }

        let trunkWidth = max(4, height * 0.09)
        let trunkHeight = height * 0.52
        context.fill(
            Path(roundedRect: CGRect(x: x - trunkWidth / 2, y: baseY - trunkHeight, width: trunkWidth, height: trunkHeight), cornerRadius: trunkWidth / 2),
            with: .color(Color(red: 0.45, green: 0.30, blue: 0.17))
        )

        let crown = height * 0.3
        let centers: [(CGFloat, CGFloat, CGFloat, Color)] = [
            (-0.55, 0.46, 0.78, deep),
            (0.55, 0.46, 0.78, deep),
            (0, 0.7, 1.0, leaf)
        ]
        for (dx, dy, radiusScale, color) in centers {
            let radius = crown * radiusScale
            let center = CGPoint(x: x + dx * crown, y: baseY - height * dy)
            context.fill(
                Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
                with: .color(color)
            )
        }
    }
}
