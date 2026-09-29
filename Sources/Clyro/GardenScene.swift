import SwiftUI

enum GardenPhase {
    /// Ruhig im Wind.
    case idle
    /// Scan läuft: mehr Bewegung im Bild.
    case scanning
    /// Aufräumen oder Wartung läuft.
    case watering
    /// Fertig: der Baum wächst ein Stück, Partikel fliegen auf.
    case bloom
}

/// Jede Seite hat ihre Jahreszeit: Bereinigen Winter, Optimieren Frühling, Apps Sommer, Analyse Herbst.
enum ClyroSeason {
    case winter
    case spring
    case summer
    case autumn

    static func of(_ section: AppSection) -> ClyroSeason {
        switch section {
        case .cleanup, .projects, .storage, .history: .winter
        case .optimize: .spring
        case .explorer: .autumn
        case .applications, .startup, .overview, .processes: .summer
        }
    }
}

private struct ClyroSeasonKey: EnvironmentKey {
    static let defaultValue: ClyroSeason = .spring
}

extension EnvironmentValues {
    var clyroSeason: ClyroSeason {
        get { self[ClyroSeasonKey.self] }
        set { self[ClyroSeasonKey.self] = newValue }
    }
}

/// Animierter Jahreszeiten-Baum für Start, Scan, Bereinigung und Ergebnis. Alles wird live gezeichnet.
struct ClyroGardenScene: View {
    let phase: GardenPhase
    let growth: Double
    var accent: Color = ClyroTheme.mint
    /// Startwert, von dem aus der Baum sichtbar auf `growth` wächst.
    var startGrowth: Double?

    @Environment(\.clyroSeason) private var season

    @State private var fromGrowth = 0.1
    @State private var toGrowth = 0.1
    @State private var changeTime = Date().timeIntervalSinceReferenceDate
    @State private var phaseStart = Date().timeIntervalSinceReferenceDate

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                var painter = SeasonPainter(
                    season: season,
                    phase: phase,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    since: max(0, timeline.date.timeIntervalSinceReferenceDate - phaseStart),
                    growth: displayedGrowth(at: timeline.date.timeIntervalSinceReferenceDate),
                    tint: accent
                )
                painter.paint(in: context)
            }
        }
        .onAppear {
            let now = Date().timeIntervalSinceReferenceDate
            fromGrowth = startGrowth ?? growth
            toGrowth = growth
            changeTime = now
            phaseStart = now
        }
        .onChange(of: growth) { _, newValue in
            let now = Date().timeIntervalSinceReferenceDate
            fromGrowth = displayedGrowth(at: now)
            toGrowth = newValue
            changeTime = now
        }
        .onChange(of: phase) { _, _ in
            phaseStart = Date().timeIntervalSinceReferenceDate
        }
    }

    private func displayedGrowth(at now: Double) -> Double {
        let progress = min(1, max(0, (now - changeTime) / 2.2))
        let eased = progress * progress * (3 - 2 * progress)
        return fromGrowth + (toGrowth - fromGrowth) * eased
    }
}

// MARK: - Zeichnen

private struct SeasonPainter {
    let season: ClyroSeason
    let phase: GardenPhase
    let size: CGSize
    let time: Double
    let since: Double
    let growth: Double

    private struct Branch {
        let from: CGPoint
        let to: CGPoint
        let width: CGFloat
        let depth: Int
    }

    private var branches: [Branch] = []
    private var tips: [CGPoint] = []

    /// Farbe des Seitenhintergrunds, die über die ganze Szene gelegt wird.
    let tint: Color

    init(season: ClyroSeason, phase: GardenPhase, size: CGSize, time: Double, since: Double, growth: Double, tint: Color) {
        self.tint = tint
        self.season = season
        self.phase = phase
        self.size = size
        self.time = time
        self.since = since
        self.growth = growth
    }

    // Maßstab: Die Szene ist für 290 pt Höhe entworfen.
    private var unit: CGFloat { max(0.5, size.height / 290) }
    private var groundY: CGFloat { size.height * 0.86 }
    private var isActive: Bool { phase == .scanning || phase == .watering }
    private var wind: Double { isActive ? 1.8 : 1.0 }

    // MARK: Farben

    private static let bark = Color(red: 0.36, green: 0.24, blue: 0.16)
    private static let winterBark = Color(red: 0.30, green: 0.25, blue: 0.24)
    private static let soil = Color(red: 0.29, green: 0.19, blue: 0.11)
    private static let snow = Color(red: 0.94, green: 0.97, blue: 1.0)
    private static let gold = Color(red: 1.0, green: 0.83, blue: 0.38)
    private static let rain = Color(red: 0.58, green: 0.78, blue: 1.0)

    private static let springLeaves: [Color] = [
        Color(red: 0.55, green: 0.84, blue: 0.42),
        Color(red: 0.68, green: 0.90, blue: 0.48),
        Color(red: 0.45, green: 0.76, blue: 0.36)
    ]
    private static let blossoms: [Color] = [
        Color(red: 1.0, green: 0.74, blue: 0.84),
        Color(red: 1.0, green: 0.90, blue: 0.94),
        Color(red: 0.98, green: 0.62, blue: 0.76)
    ]
    private static let summerLeaves: [Color] = [
        Color(red: 0.17, green: 0.47, blue: 0.24),
        Color(red: 0.24, green: 0.60, blue: 0.29),
        Color(red: 0.32, green: 0.69, blue: 0.33)
    ]
    private static let autumnLeaves: [Color] = [
        Color(red: 0.96, green: 0.56, blue: 0.18),
        Color(red: 0.86, green: 0.28, blue: 0.16),
        Color(red: 0.98, green: 0.78, blue: 0.26),
        Color(red: 0.70, green: 0.40, blue: 0.16)
    ]

    private var groundColor: Color {
        switch season {
        case .winter: Self.snow
        case .spring: Color(red: 0.52, green: 0.80, blue: 0.42)
        case .summer: Color(red: 0.27, green: 0.58, blue: 0.29)
        case .autumn: Color(red: 0.66, green: 0.46, blue: 0.22)
        }
    }

    // MARK: Ablauf

    mutating func paint(in context: GraphicsContext) {
        buildTree()
        let painter = self
        var scene = context
        // Die Szene wird als Ganzes leicht durchsichtig und nimmt die Farbe des Hintergrunds an,
        // damit sie nicht knallig wirkt.
        scene.opacity = 0.72
        scene.drawLayer { ctx in
            painter.drawSky(in: &ctx)
            painter.drawGround(in: &ctx)
            painter.drawBranches(in: &ctx)
            painter.drawCanopy(in: &ctx)
            painter.drawWeather(in: &ctx)
            if painter.phase == .bloom { painter.drawBurst(in: &ctx) }
            ctx.blendMode = .sourceAtop
            ctx.fill(Path(CGRect(origin: .zero, size: painter.size)), with: .color(painter.tint.opacity(0.42)))
        }
    }

    // MARK: Baum

    private mutating func buildTree() {
        let scale = CGFloat(0.84 + 0.16 * min(1, max(0, growth)))
        let base = CGPoint(x: size.width * 0.5, y: groundY - size.height * 0.02)
        let trunk = size.height * 0.2 * scale
        grow(from: base, angle: -Double.pi / 2, length: trunk, width: 9 * unit * scale, depth: 0, seed: 1)
    }

    private mutating func grow(from start: CGPoint, angle: Double, length: CGFloat, width: CGFloat, depth: Int, seed: Double) {
        let sway = wind * 0.022 * Double(depth + 1) * sin(time * 1.25 + Double(depth) * 0.8 + seed)
        let direction = angle + sway
        let end = CGPoint(
            x: start.x + CGFloat(cos(direction)) * length,
            y: start.y + CGFloat(sin(direction)) * length
        )
        branches.append(Branch(from: start, to: end, width: width, depth: depth))

        guard depth < 5 else {
            tips.append(end)
            return
        }

        let spread = 0.36 + 0.2 * Self.hash(seed * 3.1)
        let ratio = CGFloat(0.72 + 0.08 * Self.hash(seed * 5.7))
        grow(from: end, angle: direction - spread, length: length * ratio, width: width * 0.68, depth: depth + 1, seed: seed * 2 + 1)
        grow(from: end, angle: direction + spread * 0.9, length: length * ratio * 0.96, width: width * 0.68, depth: depth + 1, seed: seed * 2 + 2)
        if depth < 3, Self.hash(seed * 9.3) > 0.45 {
            let lean = (Self.hash(seed * 1.7) - 0.5) * 0.3
            grow(from: end, angle: direction + lean, length: length * ratio * 0.8, width: width * 0.6, depth: depth + 1, seed: seed * 2 + 3)
        }
    }

    private func drawBranches(in ctx: inout GraphicsContext) {
        let color = season == .winter ? Self.winterBark : Self.bark
        for branch in branches {
            var path = Path()
            path.move(to: branch.from)
            path.addLine(to: branch.to)
            ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: max(1, branch.width), lineCap: .round))
        }
        guard season == .winter else { return }
        // Schnee liegt oben auf den dickeren Ästen.
        for branch in branches where branch.depth >= 1 && branch.depth <= 4 {
            let lift = branch.width * 0.45
            var path = Path()
            path.move(to: CGPoint(x: branch.from.x, y: branch.from.y - lift))
            path.addLine(to: CGPoint(x: branch.to.x, y: branch.to.y - lift))
            ctx.stroke(path, with: .color(Self.snow.opacity(0.92)), style: StrokeStyle(lineWidth: max(1, branch.width * 0.5), lineCap: .round))
        }
    }

    private func drawCanopy(in ctx: inout GraphicsContext) {
        switch season {
        case .winter: drawSnowCaps(in: &ctx)
        case .spring: drawSpringCanopy(in: &ctx)
        case .summer: drawSummerCanopy(in: &ctx)
        case .autumn: drawAutumnCanopy(in: &ctx)
        }
    }

    private func drawSnowCaps(in ctx: inout GraphicsContext) {
        for (index, tip) in tips.enumerated() where index % 2 == 0 {
            let r = 2.4 * unit
            ctx.fill(Path(ellipseIn: CGRect(x: tip.x - r, y: tip.y - r * 1.2, width: r * 2, height: r * 1.4)), with: .color(Self.snow))
        }
    }

    private func drawSpringCanopy(in ctx: inout GraphicsContext) {
        // Junge Blätter wachsen während der Wartung sichtbar nach.
        let open = isActive ? 0.55 + 0.45 * min(1, since / 6) : 1.0
        for (index, tip) in tips.enumerated() {
            let seed = Double(index)
            let r = 7 * unit * CGFloat(0.7 + 0.5 * Self.hash(seed * 1.3)) * CGFloat(open)
            let offset = CGPoint(x: CGFloat(Self.hash(seed * 2.1) - 0.5) * 8 * unit, y: CGFloat(Self.hash(seed * 4.4) - 0.5) * 8 * unit)
            let color = Self.springLeaves[index % Self.springLeaves.count]
            let rect = CGRect(x: tip.x + offset.x - r, y: tip.y + offset.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.92)))
        }
        for (index, tip) in tips.enumerated() where index % 3 == 0 {
            let color = Self.blossoms[index % Self.blossoms.count]
            let pulse = 1 + 0.08 * CGFloat(sin(time * 2 + Double(index)))
            drawFlower(in: &ctx, center: tip, radius: 2.6 * unit * pulse * CGFloat(open), color: color)
        }
    }

    private func drawSummerCanopy(in ctx: inout GraphicsContext) {
        let layers: [(shade: Int, grow: CGFloat, shift: CGFloat)] = [(0, 1.25, 3), (1, 1.0, 0), (2, 0.7, -3)]
        for layer in layers {
            for (index, tip) in tips.enumerated() {
                let seed = Double(index) + Double(layer.shade) * 17
                let r = 10 * unit * layer.grow * CGFloat(0.8 + 0.4 * Self.hash(seed * 1.9))
                let dx = CGFloat(Self.hash(seed * 3.3) - 0.5) * 8 * unit
                let dy = layer.shift * unit + CGFloat(Self.hash(seed * 6.1) - 0.5) * 6 * unit
                let rect = CGRect(x: tip.x + dx - r, y: tip.y + dy - r, width: r * 2, height: r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(Self.summerLeaves[layer.shade]))
            }
        }
        // Äpfel
        let apple = Color(red: 0.90, green: 0.22, blue: 0.20)
        for (index, tip) in tips.enumerated() where index % 5 == 2 {
            let r = 3.2 * unit
            let center = CGPoint(x: tip.x, y: tip.y + 5 * unit)
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(apple))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r * 0.5, y: center.y - r * 0.6, width: r * 0.6, height: r * 0.6)), with: .color(.white.opacity(0.45)))
        }
    }

    private func drawAutumnCanopy(in ctx: inout GraphicsContext) {
        // Während des Scans lichtet sich die Krone langsam.
        let thinning = isActive ? min(0.45, since * 0.04) : 0
        for (index, tip) in tips.enumerated() {
            let seed = Double(index)
            guard Self.hash(seed * 7.7) > 0.12 + thinning else { continue }
            let r = 7.5 * unit * CGFloat(0.75 + 0.5 * Self.hash(seed * 2.6))
            let dx = CGFloat(Self.hash(seed * 3.9) - 0.5) * 9 * unit
            let dy = CGFloat(Self.hash(seed * 5.2) - 0.5) * 7 * unit
            let color = Self.autumnLeaves[index % Self.autumnLeaves.count]
            let rect = CGRect(x: tip.x + dx - r, y: tip.y + dy - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.95)))
        }
    }

    // MARK: Himmel

    private func drawSky(in ctx: inout GraphicsContext) {
        let center = CGPoint(x: size.width * 0.82, y: size.height * 0.17)
        switch season {
        case .winter:
            drawStars(in: &ctx)
            drawMoon(in: &ctx, center: center)
        case .spring:
            drawSun(in: &ctx, center: center, color: Self.gold, opacity: 0.55, rays: 10)
            if isActive { drawRainCloud(in: &ctx) }
        case .summer:
            drawSun(in: &ctx, center: center, color: Self.gold, opacity: isActive ? 1 : 0.8, rays: 14)
        case .autumn:
            let low = CGPoint(x: center.x, y: center.y + size.height * 0.05)
            drawSun(in: &ctx, center: low, color: Color(red: 1.0, green: 0.62, blue: 0.30), opacity: 0.6, rays: 10)
        }
    }

    private func drawSun(in ctx: inout GraphicsContext, center: CGPoint, color: Color, opacity: Double, rays: Int) {
        var sun = ctx
        sun.opacity = opacity
        sun.translateBy(x: center.x, y: center.y)
        let glow = 26 * unit * CGFloat(1 + 0.06 * sin(time * 1.6))
        sun.fill(Path(ellipseIn: CGRect(x: -glow, y: -glow, width: glow * 2, height: glow * 2)), with: .color(color.opacity(0.14)))
        sun.rotate(by: .radians(time * (isActive ? 0.6 : 0.3)))
        for index in 0..<rays {
            let angle = Double(index) / Double(rays) * 2 * Double.pi
            var ray = Path()
            ray.move(to: CGPoint(x: CGFloat(cos(angle)) * 18 * unit, y: CGFloat(sin(angle)) * 18 * unit))
            ray.addLine(to: CGPoint(x: CGFloat(cos(angle)) * 26 * unit, y: CGFloat(sin(angle)) * 26 * unit))
            sun.stroke(ray, with: .color(color), style: StrokeStyle(lineWidth: 2.6 * unit, lineCap: .round))
        }
        let r = 12.5 * unit
        sun.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2)), with: .color(color))
    }

    private func drawMoon(in ctx: inout GraphicsContext, center: CGPoint) {
        let r = 13 * unit
        let glow = r * 2.1
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - glow, y: center.y - glow, width: glow * 2, height: glow * 2)), with: .color(Self.snow.opacity(0.06)))
        var moon = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        moon = moon.subtracting(Path(ellipseIn: CGRect(x: center.x - r * 0.35, y: center.y - r * 1.15, width: r * 2, height: r * 2)))
        ctx.fill(moon, with: .color(Color(red: 0.95, green: 0.93, blue: 0.82)))
    }

    private func drawStars(in ctx: inout GraphicsContext) {
        for index in 0..<16 {
            let seed = Double(index)
            let x = size.width * CGFloat(0.06 + 0.88 * Self.hash(seed * 1.7))
            let y = size.height * CGFloat(0.04 + 0.36 * Self.hash(seed * 2.9))
            let twinkle = 0.25 + 0.55 * (0.5 + 0.5 * sin(time * (1.2 + Self.hash(seed) * 2) + seed))
            let r = (0.8 + 0.8 * CGFloat(Self.hash(seed * 4.1))) * unit
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(twinkle)))
        }
    }

    private func drawRainCloud(in ctx: inout GraphicsContext) {
        let fadeIn = min(1, since / 0.8)
        let center = CGPoint(x: size.width * 0.5 + CGFloat(sin(time * 0.5)) * 10 * unit, y: size.height * 0.09)
        let puffs: [(dx: CGFloat, dy: CGFloat, r: CGFloat)] = [(-22, 4, 13), (0, -2, 17), (22, 4, 13), (10, 8, 12), (-10, 8, 12)]
        for puff in puffs {
            let r = puff.r * unit
            let rect = CGRect(x: center.x + puff.dx * unit - r, y: center.y + puff.dy * unit - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect), with: .color(Color(red: 0.85, green: 0.90, blue: 0.96).opacity(0.85 * fadeIn)))
        }
        let top = center.y + 18 * unit
        let bottom = groundY - size.height * 0.04
        for index in 0..<22 {
            let seed = Double(index)
            let x = center.x + CGFloat(Self.hash(seed * 3.3) - 0.5) * 64 * unit
            let progress = Self.fract(time * 1.4 + Self.hash(seed * 1.1))
            let y = top + (bottom - top) * CGFloat(progress)
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - 1 * unit, y: y + 6 * unit))
            ctx.stroke(drop, with: .color(Self.rain.opacity(0.75 * fadeIn)), style: StrokeStyle(lineWidth: 1.3 * unit, lineCap: .round))
        }
    }

    // MARK: Boden

    private func drawGround(in ctx: inout GraphicsContext) {
        let w = size.width
        let h = size.height
        let soil = CGRect(x: w * 0.08, y: groundY - h * 0.04, width: w * 0.84, height: h * 0.14)
        ctx.fill(Path(ellipseIn: soil), with: .color(Self.soil))
        let top = CGRect(x: w * 0.08, y: groundY - h * 0.055, width: w * 0.84, height: h * 0.09)
        ctx.fill(Path(ellipseIn: top), with: .color(groundColor))

        switch season {
        case .winter:
            for index in 0..<5 {
                let seed = Double(index)
                let x = w * CGFloat(0.2 + 0.6 * Self.hash(seed * 2.3))
                let r = (8 + 6 * CGFloat(Self.hash(seed * 3.7))) * unit
                let rect = CGRect(x: x - r, y: groundY - h * 0.03 - r * 0.45, width: r * 2, height: r * 0.9)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white))
            }
        case .spring, .summer:
            for index in 0..<7 {
                let seed = Double(index)
                let x = w * CGFloat(0.18 + 0.64 * Self.hash(seed * 1.9))
                let center = CGPoint(x: x, y: groundY - h * 0.02 + CGFloat(Self.hash(seed * 5.1) - 0.5) * 6 * unit)
                let colors = season == .spring ? Self.blossoms : [Color.white, Self.gold, Color(red: 0.75, green: 0.62, blue: 0.98)]
                drawFlower(in: &ctx, center: center, radius: 2.2 * unit, color: colors[index % colors.count])
            }
        case .autumn:
            for index in 0..<16 {
                let seed = Double(index)
                let x = w * CGFloat(0.14 + 0.72 * Self.hash(seed * 2.7))
                let y = groundY - h * 0.03 + CGFloat(Self.hash(seed * 4.3) - 0.5) * 12 * unit
                drawLeaf(in: &ctx, center: CGPoint(x: x, y: y), size: 3.2 * unit, angle: seed, color: Self.autumnLeaves[index % Self.autumnLeaves.count])
            }
        }
    }

    // MARK: Wetter

    private func drawWeather(in ctx: inout GraphicsContext) {
        switch season {
        case .winter: drawSnowfall(in: &ctx)
        case .spring: drawDriftingPetals(in: &ctx)
        case .summer: drawButterflies(in: &ctx)
        case .autumn: drawFallingLeaves(in: &ctx)
        }
    }

    private func drawSnowfall(in ctx: inout GraphicsContext) {
        let count = isActive ? 70 : 34
        let speed = isActive ? 0.16 : 0.07
        for index in 0..<count {
            let seed = Double(index)
            let progress = Self.fract(time * speed * (0.7 + 0.6 * Self.hash(seed * 1.3)) + Self.hash(seed * 2.2))
            let drift = CGFloat(sin(time * 0.9 + seed)) * 8 * unit + CGFloat(progress) * (isActive ? 30 : 10) * unit
            let x = size.width * CGFloat(Self.hash(seed * 3.9)) + drift
            let y = size.height * CGFloat(progress) * 0.9
            let r = (0.9 + 1.4 * CGFloat(Self.hash(seed * 5.3))) * unit
            let alpha = min(1, (1 - progress) * 4) * 0.9
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(alpha)))
        }
    }

    private func drawDriftingPetals(in ctx: inout GraphicsContext) {
        let count = isActive ? 8 : 12
        for index in 0..<count {
            let seed = Double(index)
            let progress = Self.fract(time * 0.06 * (0.8 + 0.4 * Self.hash(seed)) + Self.hash(seed * 2.7))
            let x = size.width * CGFloat(0.1 + 0.9 * Self.fract(Self.hash(seed * 3.1) + progress * 0.5))
            let y = size.height * CGFloat(0.25 + 0.6 * progress) + CGFloat(sin(time * 1.5 + seed)) * 6 * unit
            let alpha = sin(progress * Double.pi) * 0.9
            var petal = ctx
            petal.translateBy(x: x, y: y)
            petal.rotate(by: .radians(time * 1.2 + seed))
            let rect = CGRect(x: -3 * unit, y: -1.6 * unit, width: 6 * unit, height: 3.2 * unit)
            petal.fill(Path(ellipseIn: rect), with: .color(Self.blossoms[index % Self.blossoms.count].opacity(alpha)))
        }
    }

    private func drawButterflies(in ctx: inout GraphicsContext) {
        let count = isActive ? 4 : 2
        let colors: [Color] = [Color(red: 1.0, green: 0.78, blue: 0.30), Color(red: 0.62, green: 0.80, blue: 1.0), Color(red: 1.0, green: 0.62, blue: 0.78), .white]
        let speed = isActive ? 1.6 : 1.0
        for index in 0..<count {
            let seed = Double(index)
            let t = time * 0.45 * speed + seed * 2.1
            let x = size.width * CGFloat(0.5 + 0.36 * sin(t * 0.9 + seed))
            let y = size.height * CGFloat(0.42 + 0.18 * sin(t * 1.7 + seed * 0.5))
            let flap = CGFloat(abs(sin(time * 11 + seed)))
            var fly = ctx
            fly.translateBy(x: x, y: y)
            let wing = 4.2 * unit
            let color = colors[index % colors.count]
            fly.fill(Path(ellipseIn: CGRect(x: -wing * (0.3 + flap), y: -wing, width: wing * (0.3 + flap), height: wing * 1.6)), with: .color(color))
            fly.fill(Path(ellipseIn: CGRect(x: 0, y: -wing, width: wing * (0.3 + flap), height: wing * 1.6)), with: .color(color))
            fly.fill(Path(roundedRect: CGRect(x: -0.7 * unit, y: -wing * 0.9, width: 1.4 * unit, height: wing * 1.6), cornerRadius: 0.7 * unit), with: .color(Color(red: 0.2, green: 0.15, blue: 0.1)))
        }
        // Pollen in der Sommerluft
        for index in 0..<8 {
            let seed = Double(index) + 30
            let rise = Self.fract(time * 0.05 + Self.hash(seed))
            let x = size.width * CGFloat(0.12 + 0.76 * Self.hash(seed * 1.9))
            let y = groundY - size.height * CGFloat(0.06 + 0.55 * rise)
            let alpha = sin(rise * Double.pi) * 0.7
            ctx.fill(Path(ellipseIn: CGRect(x: x - 1.6 * unit, y: y - 1.6 * unit, width: 3.2 * unit, height: 3.2 * unit)), with: .color(Self.gold.opacity(alpha)))
        }
    }

    private func drawFallingLeaves(in ctx: inout GraphicsContext) {
        guard !tips.isEmpty else { return }
        let count = isActive ? 26 : 12
        let speed = isActive ? 0.2 : 0.09
        for index in 0..<count {
            let seed = Double(index)
            let start = tips[Int(Self.hash(seed * 1.7) * Double(tips.count)) % tips.count]
            let progress = Self.fract(time * speed * (0.7 + 0.6 * Self.hash(seed * 2.3)) + Self.hash(seed * 3.1))
            let fall = (groundY - start.y) * CGFloat(progress)
            let sway = CGFloat(sin(time * 2 + seed * 1.3)) * 12 * unit * CGFloat(progress)
            let push = CGFloat(progress) * (isActive ? 40 : 14) * unit
            let center = CGPoint(x: start.x + sway + push, y: start.y + fall)
            let alpha = min(1, (1 - progress) * 5)
            let color = Self.autumnLeaves[index % Self.autumnLeaves.count].opacity(alpha)
            drawLeaf(in: &ctx, center: center, size: 3.6 * unit, angle: time * 2.4 + seed, color: color)
        }
    }

    // MARK: Ergebnis

    private func drawBurst(in ctx: inout GraphicsContext) {
        guard since < 3.4 else { return }
        let top = tips.min(by: { $0.y < $1.y }) ?? CGPoint(x: size.width * 0.5, y: size.height * 0.3)
        let origin = CGPoint(x: size.width * 0.5, y: top.y + size.height * 0.08)
        let fade = max(0, 1 - since / 3.4)
        for index in 0..<26 {
            let seed = Double(index)
            let angle = seed * 2.399963
            let distance = (26 + 50 * Self.fract(seed * 0.618)) * min(since, 2.2)
            let x = origin.x + CGFloat(cos(angle) * distance) * unit
            let y = origin.y + CGFloat(sin(angle) * distance + since * since * 7) * unit
            let center = CGPoint(x: x, y: y)
            switch season {
            case .winter:
                drawSparkle(in: &ctx, center: center, radius: 3.4 * unit, color: Self.snow.opacity(fade))
            case .spring:
                drawFlower(in: &ctx, center: center, radius: 2.4 * unit, color: Self.blossoms[index % Self.blossoms.count].opacity(fade))
            case .summer:
                drawSparkle(in: &ctx, center: center, radius: 3 * unit, color: Self.gold.opacity(fade))
            case .autumn:
                drawLeaf(in: &ctx, center: center, size: 3.6 * unit, angle: seed + since * 3, color: Self.autumnLeaves[index % Self.autumnLeaves.count].opacity(fade))
            }
        }
    }

    // MARK: Formen

    private func drawFlower(in ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        guard radius > 0.3 else { return }
        for petal in 0..<5 {
            let angle = Double(petal) / 5 * 2 * Double.pi
            let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
            ctx.fill(Path(ellipseIn: CGRect(x: point.x - radius * 0.7, y: point.y - radius * 0.7, width: radius * 1.4, height: radius * 1.4)), with: .color(color))
        }
        let core = radius * 0.6
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - core, y: center.y - core, width: core * 2, height: core * 2)), with: .color(Self.gold))
    }

    private func drawLeaf(in ctx: inout GraphicsContext, center: CGPoint, size: CGFloat, angle: Double, color: Color) {
        var leaf = ctx
        leaf.translateBy(x: center.x, y: center.y)
        leaf.rotate(by: .radians(angle))
        var path = Path()
        path.move(to: CGPoint(x: -size, y: 0))
        path.addQuadCurve(to: CGPoint(x: size, y: 0), control: CGPoint(x: 0, y: -size * 0.9))
        path.addQuadCurve(to: CGPoint(x: -size, y: 0), control: CGPoint(x: 0, y: size * 0.9))
        leaf.fill(path, with: .color(color))
    }

    private func drawSparkle(in ctx: inout GraphicsContext, center: CGPoint, radius: CGFloat, color: Color) {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: center)
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: center)
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: center)
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: center)
        ctx.fill(path, with: .color(color))
    }

    // MARK: Hilfen

    private static func hash(_ value: Double) -> Double {
        fract(sin(value * 127.1 + 311.7) * 43758.5453)
    }

    private static func fract(_ value: Double) -> Double {
        value - value.rounded(.down)
    }
}

/// Sorgt dafür, dass die Scan-Animation auch bei sehr schnellen Scans sichtbar bleibt.
enum ScanTiming {
    static func hold(since started: Date, minimum: Double = 2.6) async {
        let elapsed = Date().timeIntervalSince(started)
        guard elapsed < minimum else { return }
        try? await Task.sleep(nanoseconds: UInt64((minimum - elapsed) * 1_000_000_000))
    }
}

/// Einheitlicher Startbildschirm aller Seiten: Szene, Satz, weißer Knopf – immer an derselben Stelle.
/// Während des Scans bleibt die Szene stehen, darunter erscheinen Titel und Fortschritt.
struct ClyroStartStage<Extra: View>: View {
    let title: String
    let message: String?
    let buttonTitle: String
    let busyTitle: String
    let busyMessage: String
    let accent: Color
    let isBusy: Bool
    let action: () -> Void
    let extra: Extra

    init(
        title: String,
        message: String? = nil,
        buttonTitle: String,
        busyTitle: String = "",
        busyMessage: String = "",
        accent: Color,
        isBusy: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder extra: () -> Extra
    ) {
        self.title = title
        self.message = message
        self.buttonTitle = buttonTitle
        self.busyTitle = busyTitle
        self.busyMessage = busyMessage
        self.accent = accent
        self.isBusy = isBusy
        self.action = action
        self.extra = extra()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            ClyroGardenScene(phase: isBusy ? .scanning : .idle, growth: isBusy ? 0.3 : 0.2, accent: accent)
                .frame(width: 340, height: 290)
            VStack(spacing: 14) {
                if isBusy {
                    Text(busyTitle)
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .lineLimit(1)
                    HStack(spacing: 10) {
                        Circle().fill(accent).frame(width: 9, height: 9)
                        Text(busyMessage)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 560)
                    .frame(height: 22)
                } else {
                    Text(title)
                        .font(.system(size: 20, weight: .medium, design: .serif))
                        .foregroundStyle(.white.opacity(0.78))
                        .multilineTextAlignment(.center)
                    if let message {
                        Text(message)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 460)
                    }
                    Button(buttonTitle, action: action)
                        .buttonStyle(ClyroPillButtonStyle())
                        .padding(.top, 10)
                    extra
                }
            }
            .padding(.top, 14)
            .frame(height: 220, alignment: .top)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension ClyroStartStage where Extra == EmptyView {
    init(
        title: String,
        message: String? = nil,
        buttonTitle: String,
        busyTitle: String = "",
        busyMessage: String = "",
        accent: Color,
        isBusy: Bool = false,
        action: @escaping () -> Void
    ) {
        self.init(
            title: title,
            message: message,
            buttonTitle: buttonTitle,
            busyTitle: busyTitle,
            busyMessage: busyMessage,
            accent: accent,
            isBusy: isBusy,
            action: action,
            extra: { EmptyView() }
        )
    }
}
