import SwiftUI

enum ClyroTheme {
    static let background = Color(red: 0.055, green: 0.052, blue: 0.049)
    static let sidebar = Color(red: 0.075, green: 0.071, blue: 0.066)
    static let card = Color.white.opacity(0.045)
    static let cardStrong = Color.white.opacity(0.075)
    static let border = Color.white.opacity(0.075)
    static let mint = Color(red: 0.31, green: 0.82, blue: 0.67)
    static let mintSoft = Color(red: 0.22, green: 0.62, blue: 0.51)
    static let gold = Color(red: 0.92, green: 0.78, blue: 0.46)
    static let orange = Color(red: 0.95, green: 0.60, blue: 0.34)
    static let blue = Color(red: 0.38, green: 0.63, blue: 0.94)
    static let secondaryText = Color.white.opacity(0.57)
}

extension View {
    func clyroCard(padding: CGFloat = 20) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(ClyroTheme.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .stroke(ClyroTheme.border, lineWidth: 1)
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

    static func uptime(_ seconds: TimeInterval) -> String {
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        if days > 0 { return "\(days) T \(hours) Std" }
        let minutes = (Int(seconds) % 3_600) / 60
        return "\(hours) Std \(minutes) Min"
    }
}
