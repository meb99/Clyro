import AppKit
import SwiftUI

/// Sprache der Oberfläche. Deutsch ist die Quellsprache, Englisch liegt in `en.lproj/Localizable.strings`.
///
/// macOS wählt die Sprache einer App beim Start über `AppleLanguages`. Ein Wechsel wird deshalb gespeichert
/// und Clyro startet einmal neu, damit alle Texte – auch Mitteilungen und Menüs – einheitlich umgestellt sind.
enum AppLanguage: String, CaseIterable, Identifiable {
    case german = "de"
    case english = "en"

    var id: String { rawValue }

    /// Kurzform für den Umschalter.
    var code: String { rawValue.uppercased() }

    var name: String {
        switch self {
        case .german: "Deutsch"
        case .english: "English"
        }
    }

    /// Die Sprache, in der Clyro gerade läuft.
    static var current: AppLanguage {
        let preferred = Bundle.main.preferredLocalizations.first ?? "de"
        return preferred.hasPrefix("en") ? .english : .german
    }

    /// Speichert die Sprache für Clyro und startet die App neu.
    static func switchTo(_ language: AppLanguage) {
        guard language != current else { return }
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        UserDefaults.standard.synchronize()
        relaunch()
    }

    private static func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Kurz warten, bis diese Instanz beendet ist, dann dieselbe App erneut öffnen.
        task.arguments = ["-c", "sleep 0.6; /usr/bin/open -n \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }
}

enum L10n {
    /// Übersetzt Texte, die erst zur Laufzeit feststehen (z. B. Namen aus Regeltabellen).
    static func dynamic(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }
}

/// Kompakter DE/EN-Umschalter für die obere Leiste und die Einstellungen.
struct LanguageSwitch: View {
    var compact = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(AppLanguage.allCases) { language in
                let isCurrent = language == AppLanguage.current
                Button {
                    AppLanguage.switchTo(language)
                } label: {
                    Text(compact ? language.code : language.name)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isCurrent ? Color.black.opacity(0.84) : Color.white.opacity(0.6))
                        .padding(.horizontal, compact ? 9 : 12)
                        .frame(height: compact ? 24 : 26)
                        .background {
                            if isCurrent { Capsule().fill(.white) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(language == .german ? "Deutsch" : "English")
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }
}
