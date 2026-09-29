import AppKit
import SwiftUI

enum ClyroTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let card = Color.black.opacity(0.18)
    static let cardStrong = Color.white.opacity(0.085)
    static let border = Color.white.opacity(0.085)
    static let mint = Color(red: 0.28, green: 0.76, blue: 0.62)
    static let mintSoft = Color(red: 0.22, green: 0.62, blue: 0.51)
    static let gold = Color(red: 0.88, green: 0.72, blue: 0.38)
    static let orange = Color(red: 0.91, green: 0.52, blue: 0.27)
    static let blue = Color(red: 0.35, green: 0.58, blue: 0.91)
    static let secondaryText = Color.white.opacity(0.58)

    static func palette(for section: AppSection) -> ClyroPalette {
        switch section {
        case .overview:
            ClyroPalette(
                top: Color(red: 0.12, green: 0.105, blue: 0.045),
                bottom: Color(red: 0.27, green: 0.19, blue: 0.055),
                accent: mint,
                secondary: gold
            )
        case .cleanup:
            ClyroPalette(
                top: Color(red: 0.055, green: 0.075, blue: 0.16),
                bottom: Color(red: 0.105, green: 0.16, blue: 0.31),
                accent: Color(red: 0.43, green: 0.69, blue: 1.0),
                secondary: mint
            )
        case .optimize:
            ClyroPalette(
                top: Color(red: 0.03, green: 0.10, blue: 0.11),
                bottom: Color(red: 0.05, green: 0.25, blue: 0.27),
                accent: Color(red: 0.30, green: 0.85, blue: 0.85),
                secondary: mint
            )
        case .projects:
            ClyroPalette(
                top: Color(red: 0.10, green: 0.05, blue: 0.13),
                bottom: Color(red: 0.26, green: 0.10, blue: 0.30),
                accent: Color(red: 0.90, green: 0.50, blue: 0.85),
                secondary: Color(red: 0.68, green: 0.49, blue: 0.98)
            )
        case .explorer:
            ClyroPalette(
                top: Color(red: 0.03, green: 0.09, blue: 0.14),
                bottom: Color(red: 0.06, green: 0.20, blue: 0.32),
                accent: Color(red: 0.36, green: 0.72, blue: 0.98),
                secondary: Color(red: 0.30, green: 0.85, blue: 0.85)
            )
        case .storage:
            ClyroPalette(
                top: Color(red: 0.15, green: 0.065, blue: 0.03),
                bottom: Color(red: 0.34, green: 0.15, blue: 0.055),
                accent: Color(red: 0.95, green: 0.60, blue: 0.31),
                secondary: Color(red: 0.91, green: 0.42, blue: 0.25)
            )
        case .processes:
            ClyroPalette(
                top: Color(red: 0.065, green: 0.055, blue: 0.145),
                bottom: Color(red: 0.20, green: 0.105, blue: 0.30),
                accent: Color(red: 0.68, green: 0.49, blue: 0.98),
                secondary: blue
            )
        case .applications:
            ClyroPalette(
                top: Color(red: 0.15, green: 0.035, blue: 0.045),
                bottom: Color(red: 0.32, green: 0.075, blue: 0.095),
                accent: Color(red: 1.0, green: 0.44, blue: 0.44),
                secondary: orange
            )
        case .startup:
            ClyroPalette(
                top: Color(red: 0.085, green: 0.08, blue: 0.055),
                bottom: Color(red: 0.25, green: 0.19, blue: 0.065),
                accent: gold,
                secondary: orange
            )
        case .history:
            ClyroPalette(
                top: Color(red: 0.035, green: 0.105, blue: 0.09),
                bottom: Color(red: 0.045, green: 0.24, blue: 0.18),
                accent: mint,
                secondary: blue
            )
        }
    }
}

struct ClyroPalette {
    let top: Color
    let bottom: Color
    let accent: Color
    let secondary: Color

    var background: LinearGradient {
        LinearGradient(colors: [top, bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    func clyroCard(padding: CGFloat = 18) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ClyroTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(ClyroTheme.border, lineWidth: 0.75)
                    )
            )
    }

    func clyroPanel(padding: CGFloat = 16, cornerRadius: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(ClyroTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(ClyroTheme.border, lineWidth: 0.8)
                    )
            )
    }
}

enum ClyroFormat {
    static let bytes: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.isAdaptive = true
        formatter.includesUnit = true
        return formatter
    }()

    static func byteCount(_ value: Int64) -> String {
        bytes.string(fromByteCount: max(0, value))
    }

    static func speed(_ value: Double) -> String {
        "\(byteCount(Int64(max(0, value))))/s"
    }

    /// Wie im Vorbild: sehr kleine Raten erscheinen als „<1 KB/s“.
    static func compactSpeed(_ value: Double) -> String {
        value < 1024 ? "<1 KB/s" : speed(value)
    }

    static func memory(_ value: Int64) -> String {
        let gigabytes = Double(value) / 1_073_741_824
        if gigabytes >= 1 { return String(format: "%.1f GB", gigabytes) }
        return String(format: "%.0f MB", Double(value) / 1_048_576)
    }

    static func uptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        if days > 0 { return "\(days) T \(hours) Std" }
        let minutes = (Int(seconds) % 3_600) / 60
        return "\(hours) Std \(minutes) Min"
    }
}
