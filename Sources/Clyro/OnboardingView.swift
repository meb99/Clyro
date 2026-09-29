import SwiftUI

/// Kurze Einführung beim ersten Start: die fünf Seiten, wie Clyro löscht, Menüleiste und Einstellungen.
struct OnboardingView: View {
    static let doneKey = "onboardingDone"

    @AppStorage(OnboardingView.doneKey) private var done = false
    @State private var page = 0

    private struct Page {
        let season: ClyroSeason
        let accent: Color
        let title: String
        let points: [(icon: String, text: String)]
    }

    private let pages: [Page] = [
        Page(
            season: .spring,
            accent: ClyroTheme.mint,
            title: "Willkommen bei Clyro",
            points: [
                ("sparkles", "Bereinigen findet Caches, Protokolle, Reste und Installationsdateien – im Winter wird aufgeräumt."),
                ("app.dashed", "Apps entfernt Programme samt Rückständen, zeigt Updates und Autostart – mitten im Sommer."),
                ("dial.medium.fill", "Optimieren erledigt 21 Wartungsaufgaben mit einem Klick – der Frühling für deinen Mac."),
                ("chart.pie.fill", "Analyse zeigt, was Platz belegt, und findet große Dateien – der Herbst zeigt, was abfällt."),
                ("square.grid.2x2.fill", "Status zeigt live, wie es deinem Mac geht.")
            ]
        ),
        Page(
            season: .winter,
            accent: Color(red: 0.43, green: 0.69, blue: 1.0),
            title: "So löscht Clyro",
            points: [
                ("eye", "Erst wird gescannt, dann entscheidest du. Gelöscht wird nur, was ausgewählt ist."),
                ("trash.slash", "Wie Mole löscht Clyro endgültig. In den Einstellungen kannst du stattdessen den Papierkorb wählen."),
                ("lock.shield", "Passwortmanager, Schlüssel, VPNs, Sicherheitssoftware und persönliche Ordner sind immer geschützt."),
                ("key.fill", "Für Systembereiche fragt macOS einmal nach deinem Passwort – nur wenn du sie auswählst."),
                ("doc.text.magnifyingglass", "Jede Löschung steht im Protokoll unter ~/Library/Logs/Clyro.")
            ]
        ),
        Page(
            season: .summer,
            accent: Color(red: 1.0, green: 0.62, blue: 0.44),
            title: "Immer griffbereit",
            points: [
                ("leaf.fill", "Das Blatt in der Menüleiste zeigt alle Werte auf einen Blick und hält den Mac auf Wunsch wach."),
                ("tree.fill", "Jede Bereinigung pflanzt einen Baum in deinem Wald."),
                ("bell.badge", "In den Einstellungen (⌘,) gibt es Erinnerungen, wöchentliches Bereinigen, Start bei Anmeldung und Touch ID für sudo.")
            ]
        )
    ]

    var body: some View {
        let current = pages[page]
        VStack(spacing: 0) {
            ClyroGardenScene(phase: .idle, growth: 0.25 + 0.2 * Double(page), accent: current.accent)
                .environment(\.clyroSeason, current.season)
                .frame(width: 240, height: 190)
                .id(page)
                .transition(.opacity)

            Text(current.title)
                .font(.system(size: 26, weight: .bold))
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(current.points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: point.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(current.accent)
                            .frame(width: 22)
                        Text(point.text)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 480, alignment: .leading)
            .padding(.top, 18)

            Spacer(minLength: 16)

            HStack {
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? current.accent : Color.white.opacity(0.2))
                            .frame(width: index == page ? 18 : 7, height: 7)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Zurück") { withAnimation { page -= 1 } }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.trailing, 12)
                }
                Button(page == pages.count - 1 ? "Los geht's" : "Weiter") {
                    if page == pages.count - 1 {
                        done = true
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(ClyroPillButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 620, height: 600)
        .background(
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.13, blue: 0.15), Color(red: 0.04, green: 0.07, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .environment(\.colorScheme, .dark)
    }
}
