import AppKit
import SwiftUI

enum ClyroTheme {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let appBackground = LinearGradient(
        colors: [
            Color(nsColor: .windowBackgroundColor),
            Color(red: 0.045, green: 0.065, blue: 0.060)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let sidebar = Color(nsColor: .underPageBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor).opacity(0.72)
    static let cardStrong = Color(nsColor: .selectedContentBackgroundColor).opacity(0.14)
    static let border = Color(nsColor: .separatorColor).opacity(0.55)
    static let mint = Color(red: 0.28, green: 0.76, blue: 0.62)
    static let mintSoft = Color(red: 0.22, green: 0.62, blue: 0.51)
    static let gold = Color(red: 0.88, green: 0.72, blue: 0.38)
    static let orange = Color(red: 0.91, green: 0.52, blue: 0.27)
    static let blue = Color(red: 0.35, green: 0.58, blue: 0.91)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
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
