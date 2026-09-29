import SwiftUI

enum GardenPhase {
    /// Ruhig im Wind, ein paar Pollen schweben.
    case idle
    /// Die Sonne scheint, Lichtpartikel steigen auf (Photosynthese).
    case scanning
    /// Eine Gießkanne gießt den Keimling, während Clyro aufräumt.
    case watering
    /// Die Pflanze ist gewachsen, Blütenblätter fliegen auf.
    case bloom
}

/// Animierte Szene für Scan, Bereinigung und Ergebnis. Alles wird live gezeichnet, es gibt keine Bilddateien.
struct ClyroGardenScene: View {
    let phase: GardenPhase
    let growth: Double
    var accent: Color = ClyroTheme.mint
    /// Startwert, von dem aus die Pflanze sichtbar auf `growth` wächst.
    var startGrowth: Double?

    @State private var fromGrowth = 0.1
    @State private var toGrowth = 0.1
    @State private var changeTime = Date().timeIntervalSinceReferenceDate
    @State private var phaseStart = Date().timeIntervalSinceReferenceDate

    private static let gold = Color(red: 1.0, green: 0.83, blue: 0.38)
    private static let water = Color(red: 0.45, green: 0.72, blue: 1.0)
    private static let can = Color(red: 0.55, green: 0.66, blue: 0.78)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                draw(in: context, size: size, now: timeline.date.timeIntervalSinceReferenceDate)
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

    // MARK: - Zeichnen

    private func draw(in context: GraphicsContext, size: CGSize, now: Double) {
        var ctx = context
        let w = size.width
        let h = size.height
        let groundY = h * 0.86
        let since = max(0, now - phaseStart)
        let g = displayedGrowth(at: now)

        drawSun(in: ctx, size: size, now: now)
        drawMotes(in: &ctx, size: size, now: now)

        if phase == .watering {
            let wet = min(0.3, since * 0.12)
            let patch = CGRect(x: w * 0.5 - 34, y: groundY - h * 0.045, width: 68, height: 10)
            ctx.fill(Path(ellipseIn: patch), with: .color(Self.water.opacity(wet)))
        }

        GardenPainter.paint(in: &ctx, size: size, growth: g, accent: accent, time: now)

        if phase == .watering { drawWateringCan(in: &ctx, size: size, now: now, since: since) }
        if phase == .bloom { drawPetals(in: &ctx, size: size, growth: g, since: since) }
    }

    private func drawSun(in context: GraphicsContext, size: CGSize, now: Double) {
        let opacity: Double
        switch phase {
        case .scanning: opacity = 1
        case .bloom: opacity = 0.7
        default: opacity = 0.35
        }
        var sun = context
        sun.opacity = opacity
        sun.translateBy(x: size.width * 0.82, y: size.height * 0.2)
        sun.rotate(by: .radians(now * 0.35))
        for index in 0..<12 {
            let angle = Double(index) / 12 * 2 * Double.pi
            var ray = Path()
            ray.move(to: CGPoint(x: cos(angle) * 20, y: sin(angle) * 20))
            ray.addLine(to: CGPoint(x: cos(angle) * 30, y: sin(angle) * 30))
            sun.stroke(ray, with: .color(Self.gold), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        sun.fill(Path(ellipseIn: CGRect(x: -14, y: -14, width: 28, height: 28)), with: .color(Self.gold))
    }

    private func drawMotes(in context: inout GraphicsContext, size: CGSize, now: Double) {
        guard phase == .idle || phase == .scanning else { return }
        let groundY = size.height * 0.86
        let speed = phase == .scanning ? 0.16 : 0.05
        for index in 0..<8 {
            let seed = Double(index) * 0.37
            let drift = 0.12 + 0.76 * fract(seed * 2.3 + now * 0.015 * Double(1 + index % 3))
            let x = size.width * CGFloat(drift)
            let rise = fract(seed + now * speed)
            let y = groundY - size.height * CGFloat(0.08 + 0.6 * rise)
            let alpha = sin(rise * Double.pi) * 0.7
            let rect = CGRect(x: x - 2, y: y - 2, width: 4, height: 4)
            context.fill(Path(ellipseIn: rect), with: .color(Self.gold.opacity(alpha)))
        }
    }

    private func drawWateringCan(in context: inout GraphicsContext, size: CGSize, now: Double, since: Double) {
        let w = size.width
        let h = size.height
        let groundY = h * 0.86
        let tilt = 32 * ease(min(1, since / 0.9))
        let center = CGPoint(x: w * 0.24, y: h * 0.30 + CGFloat(sin(now * 2.2)) * 2)

        var can = context
        can.translateBy(x: center.x, y: center.y)
        can.rotate(by: .degrees(tilt))

        var handle = Path()
        handle.addArc(center: CGPoint(x: -22, y: 1), radius: 11, startAngle: .degrees(90), endAngle: .degrees(270), clockwise: false)
        can.stroke(handle, with: .color(Self.can), style: StrokeStyle(lineWidth: 4, lineCap: .round))

        let body = CGRect(x: -22, y: -14, width: 44, height: 30)
        can.fill(Path(roundedRect: body, cornerRadius: 7), with: .color(Self.can))
        let shine = CGRect(x: -17, y: -10, width: 8, height: 20)
        can.fill(Path(roundedRect: shine, cornerRadius: 4), with: .color(.white.opacity(0.25)))

        var spout = Path()
        spout.move(to: CGPoint(x: 20, y: 6))
        spout.addLine(to: CGPoint(x: 40, y: -10))
        can.stroke(spout, with: .color(Self.can), style: StrokeStyle(lineWidth: 5, lineCap: .round))
        can.fill(Path(ellipseIn: CGRect(x: 36, y: -18, width: 9, height: 12)), with: .color(Self.can))

        guard since > 0.5 else { return }

        let radians = tilt * Double.pi / 180
        let localX = 42.0
        let localY = -9.0
        let tip = CGPoint(
            x: center.x + CGFloat(localX * cos(radians) - localY * sin(radians)),
            y: center.y + CGFloat(localX * sin(radians) + localY * cos(radians))
        )
        let target = CGPoint(x: w * 0.5 - 4, y: groundY - h * 0.03)

        for index in 0..<16 {
            let progress = fract(now * 1.1 + Double(index) / 16)
            let x = tip.x + (target.x - tip.x) * CGFloat(progress)
            let y = tip.y + (target.y - tip.y) * CGFloat(progress * progress)
            let drop = CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4)
            context.fill(Path(ellipseIn: drop), with: .color(Self.water.opacity(0.95 - progress * 0.3)))

            if progress > 0.93 {
                let ring = (progress - 0.93) / 0.07
                let splash = CGRect(x: target.x - 4 - ring * 8, y: target.y - 1, width: 8 + ring * 16, height: 3)
                context.stroke(Path(ellipseIn: splash), with: .color(Self.water.opacity(0.7 - ring * 0.6)), lineWidth: 1)
            }
        }
    }

    private func drawPetals(in context: inout GraphicsContext, size: CGSize, growth: Double, since: Double) {
        guard since < 3.2 else { return }
        let groundY = size.height * 0.86
        let top = CGPoint(x: size.width * 0.5, y: groundY - size.height * (0.17 + 0.5 * CGFloat(growth)))
        let fade = max(0, 1 - since / 3.2)

        for index in 0..<22 {
            let angle = Double(index) * 2.399963
            let speed = 26 + 46 * fract(Double(index) * 0.618)
            let distance = speed * min(since, 2.2)
            let x = top.x + CGFloat(cos(angle) * distance)
            let y = top.y + CGFloat(sin(angle) * distance + since * since * 7)
            let radius = 2.5 + 2 * fract(Double(index) * 0.3)
            let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
            let color = GardenPainter.flowerColors[index % GardenPainter.flowerColors.count]
            context.fill(Path(ellipseIn: rect), with: .color(color.opacity(fade)))
        }
    }

    // MARK: - Hilfen

    private func displayedGrowth(at now: Double) -> Double {
        let progress = min(1, max(0, (now - changeTime) / 2.2))
        return fromGrowth + (toGrowth - fromGrowth) * ease(progress)
    }

    private func ease(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    private func fract(_ value: Double) -> Double {
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

/// Einheitlicher Startbildschirm: erst Button, dann Scan-Animation, erst danach Ergebnisse.
struct ClyroStartStage: View {
    let title: String
    let message: String
    let buttonTitle: String
    let busyTitle: String
    let busyMessage: String
    let accent: Color
    var isBusy = false
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            ClyroGardenScene(
                phase: isBusy ? .scanning : .idle,
                growth: isBusy ? 0.2 : 0.12,
                accent: accent
            )
            .frame(width: 260, height: 220)

            Text(isBusy ? busyTitle : title)
                .font(.system(size: 24, weight: .semibold))
            Text(isBusy ? busyMessage : message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            if isBusy {
                ProgressView().tint(accent).frame(width: 240).padding(.top, 4)
            } else {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clyroPanel(padding: 20, cornerRadius: 20)
    }
}
