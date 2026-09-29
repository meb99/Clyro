import AppKit
import SwiftUI

struct StartupItemsView: View {
    @State private var items: [StartupItem] = []
    @State private var isScanning = false
    @State private var hasScanned = false
    @State private var query = ""

    private let accent = ClyroTheme.palette(for: .startup).accent
    private let secondary = ClyroTheme.palette(for: .startup).secondary

    private var filtered: [StartupItem] {
        guard !query.isEmpty else { return items }
        return items.filter {
            $0.label.localizedCaseInsensitiveContains(query)
                || $0.program.localizedCaseInsensitiveContains(query)
                || $0.scope.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ClyroPageHeader(
                    title: String(localized: "Autostart"),
                    subtitle: String(localized: "Hintergrunddienste, getrennt nach Benutzer- und Systembereich."),
                    icon: "bolt.fill",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: String(localized: "Gefunden"), value: String(localized: "\(items.count) Dienste"), icon: "bolt.horizontal.fill", color: accent)
                TextField("Dienst suchen", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 210)
            }

            if !hasScanned || isScanning {
                ClyroStartStage(
                    title: String(localized: "Autostart prüfen"),
                    message: String(localized: "Clyro zeigt, welche Dienste im Hintergrund mit deinem Mac starten. Es wird nichts verändert."),
                    buttonTitle: String(localized: "Autostart scannen"),
                    busyTitle: String(localized: "Hintergrunddienste werden gesucht"),
                    busyMessage: String(localized: "Launch Agents und Launch Daemons werden gelesen …"),
                    accent: accent,
                    isBusy: isScanning,
                    action: { scanStartup() }
                )
            } else if items.isEmpty {
                VStack(spacing: 10) {
                    ClyroArtifact(symbol: "bolt.slash.fill", satellite: "checkmark", accent: accent, secondary: secondary)
                    Text("Keine Autostart-Dienste gefunden")
                        .font(.system(size: 21, weight: .semibold))
                    Text("Die bekannten Launch-Agent- und Launch-Daemon-Ordner sind leer.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clyroPanel(padding: 20, cornerRadius: 20)
            } else {
                HStack(spacing: 14) {
                    VStack(spacing: 12) {
                        ClyroArtifact(symbol: "bolt.fill", satellite: "gearshape.fill", accent: accent, secondary: secondary)
                            .scaleEffect(0.76)
                            .frame(height: 142)
                        StartupScopeStat(title: String(localized: "Benutzer"), count: items.filter { $0.scope == "Benutzer" }.count, color: accent)
                        StartupScopeStat(title: String(localized: "Alle Benutzer"), count: items.filter { $0.scope == "Alle Benutzer" }.count, color: secondary)
                        StartupScopeStat(title: String(localized: "System"), count: items.filter { $0.scope == "System" }.count, color: ClyroTheme.blue)
                        Spacer()
                        Text("Clyro zeigt die Einträge aktuell nur an und verändert keine Systemdienste.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: 220)
                    .clyroPanel(padding: 16, cornerRadius: 18)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filtered) { item in
                                StartupRow(item: item, accent: accent)
                                if item.id != filtered.last?.id {
                                    Divider().overlay(.white.opacity(0.05)).padding(.leading, 48)
                                }
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clyroPanel(padding: 14, cornerRadius: 18)
                }
            }
        }
        .padding(22)
    }

    private func scanStartup() {
        guard !isScanning else { return }
        isScanning = true
        let started = Date()
        Task {
            let found = await Task.detached(priority: .utility) { StartupProbe.scan() }.value
            await ScanTiming.hold(since: started)
            items = found
            hasScanned = true
            isScanning = false
        }
    }
}

private struct StartupScopeStat: View {
    let title: String
    let count: Int
    let color: Color

    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.system(size: 11, weight: .medium))
            Spacer()
            Text("\(count)").font(.system(size: 12, weight: .bold))
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9).fill(.white.opacity(0.045)))
    }
}

private struct StartupRow: View {
    let item: StartupItem
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.black.opacity(0.72))
                .frame(width: 34, height: 34)
                .background(Circle().fill(accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(item.program)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(L10n.dynamic(item.scope))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(Capsule().fill(.white.opacity(0.065)))
        }
        .frame(height: 54)
    }
}

private enum StartupProbe {
    static func scan() -> [StartupItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let locations: [(URL, String)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), "Benutzer"),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), "Alle Benutzer"),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), "System")
        ]
        var items: [StartupItem] = []

        for (directory, scope) in locations {
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension == "plist" {
                var plist: [String: Any]?
                if let data = try? Data(contentsOf: url),
                   let object = try? PropertyListSerialization.propertyList(from: data, format: nil) {
                    plist = object as? [String: Any]
                }
                let label = plist?["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let program = plist?["Program"] as? String
                    ?? (plist?["ProgramArguments"] as? [String])?.first
                    ?? String(localized: "Kein Programmpfad angegeben")
                items.append(StartupItem(url: url, label: label, program: program, scope: scope))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}
