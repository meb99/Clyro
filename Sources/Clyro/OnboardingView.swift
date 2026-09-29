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
            title: String(localized: "Willkommen bei Clyro"),
            points: [
                ("sparkles", String(localized: "Bereinigen findet Caches, Protokolle, Reste deinstallierter Apps und Installationsdateien.")),
                ("app.dashed", String(localized: "Apps entfernt Programme vollständig, zeigt verfügbare Updates und alle Startobjekte.")),
                ("dial.medium.fill", String(localized: "Optimieren führt 21 Wartungsaufgaben in einem Durchgang aus.")),
                ("chart.pie.fill", String(localized: "Analyse zeigt, welche Ordner und Dateien den meisten Platz belegen.")),
                ("square.grid.2x2.fill", String(localized: "Status zeigt Auslastung, Temperatur, Akku und Prozesse in Echtzeit."))
            ]
        ),
        Page(
            season: .winter,
            accent: Color(red: 0.43, green: 0.69, blue: 1.0),
            title: String(localized: "So arbeitet Clyro"),
            points: [
                ("eye", String(localized: "Jeder Vorgang beginnt mit einem Scan. Gelöscht wird nur, was du auswählst.")),
                ("trash.slash", String(localized: "Caches und Protokolle werden endgültig gelöscht. In den Einstellungen lässt sich der Papierkorb aktivieren.")),
                ("lock.shield", String(localized: "Passwortmanager, Schlüssel, VPN-Clients, Sicherheitssoftware und persönliche Ordner sind ausgenommen.")),
                ("key.fill", String(localized: "Systembereiche erfordern das Administratorpasswort und werden nur nach Auswahl bereinigt.")),
                ("doc.text.magnifyingglass", String(localized: "Jeder Löschvorgang wird unter ~/Library/Logs/Clyro protokolliert."))
            ]
        ),
        Page(
            season: .summer,
            accent: Color(red: 1.0, green: 0.62, blue: 0.44),
            title: String(localized: "Im Alltag"),
            points: [
                ("leaf.fill", String(localized: "Das Symbol in der Menüleiste zeigt die wichtigsten Werte und kann den Ruhezustand verhindern.")),
                ("bell.badge", String(localized: "In den Einstellungen (⌘,) findest du Erinnerungen, wöchentliche Bereinigung, Autostart, Touch ID für sudo und die Sprache.")),
                ("tree.fill", String(localized: "Jede Bereinigung wird im Verlauf festgehalten."))
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
                Button(page == pages.count - 1 ? String(localized: "Los geht's") : String(localized: "Weiter")) {
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
