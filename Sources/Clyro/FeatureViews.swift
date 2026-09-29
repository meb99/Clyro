import AppKit
import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var cleaner: CleanupScanner
    @State private var showConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    SectionHeader("Bereinigen", subtitle: "Nur transparente, ausgewählte Bereiche – nichts wird heimlich entfernt.")
                    Spacer()
                    Button {
                        cleaner.scan()
                    } label: {
                        Label(cleaner.state == .scanning ? "Scanne …" : "Mac prüfen", systemImage: "sparkle.magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ClyroTheme.mintSoft)
                    .disabled(cleaner.state == .scanning || cleaner.state == .cleaning)
                }

                if cleaner.categories.isEmpty && cleaner.state != .scanning {
                    EmptyStateView(
                        icon: "sparkle.magnifyingglass",
                        title: "Bereit für den ersten Scan",
                        message: "Clyro sucht nach alten Caches, Protokollen und Installationsdateien. Vor dem Löschen siehst du immer eine Zusammenfassung."
                    )
                } else if cleaner.state == .scanning {
                    VStack(spacing: 14) {
                        ProgressView()
                            .controlSize(.large)
                            .tint(ClyroTheme.mint)
                        Text("Dateien werden sicher analysiert …")
                            .foregroundStyle(ClyroTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                    .clyroCard()
                } else {
                    VStack(spacing: 11) {
                        ForEach($cleaner.categories) { $category in
                            CleanupCategoryRow(category: $category) {
                                cleaner.reveal(category)
                            }
                        }
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(ClyroFormat.byteCount(cleaner.selectedBytes)) können freigegeben werden")
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text("\(cleaner.selectedItems) Elemente werden zunächst in den Papierkorb verschoben.")
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(ClyroTheme.secondaryText)
                        }
                        Spacer()
                        Button {
                            showConfirmation = true
                        } label: {
                            Label("Auswahl bereinigen", systemImage: "trash")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(ClyroTheme.mintSoft)
                        .disabled(cleaner.selectedItems == 0 || cleaner.state == .cleaning)
                    }
                    .clyroCard()
                }
            }
            .padding(28)
        }
        .onAppear {
            if cleaner.categories.isEmpty { cleaner.scan() }
        }
        .alert("Ausgewählte Dateien verschieben?", isPresented: $showConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button("In den Papierkorb", role: .destructive) { cleaner.cleanSelected() }
        } message: {
            Text("\(cleaner.selectedItems) Elemente mit ungefähr \(ClyroFormat.byteCount(cleaner.selectedBytes)) werden in den Papierkorb verschoben. Geöffnete Apps solltest du vorher schließen.")
        }
    }
}

private struct CleanupCategoryRow: View {
    @Binding var category: CleanupCategory
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 15) {
            Toggle("", isOn: $category.isSelected)
                .labelsHidden()
                .toggleStyle(.checkbox)
                .disabled(category.itemCount == 0)

            ZStack {
                RoundedRectangle(cornerRadius: 11).fill(ClyroTheme.mint.opacity(0.12))
                Image(systemName: category.kind.icon).foregroundStyle(ClyroTheme.mint)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.kind.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text(category.kind.detail)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(ClyroTheme.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(ClyroFormat.byteCount(category.bytes))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("\(category.itemCount) Elemente")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(ClyroTheme.secondaryText)
            }
            Button(action: reveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.52))
            .disabled(category.paths.isEmpty)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(ClyroTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(ClyroTheme.border))
        )
    }
}

struct ApplicationsView: View {
    @State private var applications: [InstalledApplication] = []
    @State private var isLoading = false
    @State private var query = ""

    private var filtered: [InstalledApplication] {
        query.isEmpty ? applications : applications.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeader("Apps", subtitle: "Installierte Apps und ihr tatsächlicher Platzbedarf.")
                Spacer()
                TextField("Apps suchen", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 230)
            }

            if isLoading {
                ProgressView("Apps werden analysiert …")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filtered) { app in
                    HStack(spacing: 13) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                            .resizable()
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(app.bundleIdentifier.isEmpty ? app.url.path : app.bundleIdentifier)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(ClyroTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(app.version)
                            .foregroundStyle(ClyroTheme.secondaryText)
                            .frame(width: 90, alignment: .trailing)
                        Text(ClyroFormat.byteCount(app.sizeBytes))
                            .fontWeight(.semibold)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(ClyroTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(28)
        .task { await loadApps() }
    }

    private func loadApps() async {
        guard applications.isEmpty else { return }
        isLoading = true
        applications = await Task.detached(priority: .utility) {
            ApplicationProbe.scan()
        }.value
        isLoading = false
    }
}

private enum ApplicationProbe {
    static func scan() -> [InstalledApplication] {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var seen = Set<String>()
        var results: [InstalledApplication] = []

        for root in roots {
            let urls = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for url in urls where url.pathExtension.lowercased() == "app" {
                guard let bundle = Bundle(url: url) else { continue }
                let identifier = bundle.bundleIdentifier ?? ""
                guard seen.insert(identifier.isEmpty ? url.path : identifier).inserted else { continue }
                let info = bundle.infoDictionary
                let name = (info?["CFBundleDisplayName"] as? String)
                    ?? (info?["CFBundleName"] as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let version = (info?["CFBundleShortVersionString"] as? String) ?? "–"
                results.append(InstalledApplication(
                    url: url,
                    name: name,
                    version: version,
                    bundleIdentifier: identifier,
                    sizeBytes: FileProbe.sizeOfItem(at: url)
                ))
            }
        }
        return results.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}

struct StartupItemsView: View {
    @State private var items: [StartupItem] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader("Autostart", subtitle: "Hintergrunddienste sichtbar machen, bevor wir sie später sicher verwalten.")

            if items.isEmpty {
                EmptyStateView(icon: "bolt.slash.fill", title: "Keine Einträge gefunden", message: "In den bekannten Launch-Agent-Ordnern wurden keine Einträge erkannt.")
            } else {
                List(items) { item in
                    HStack(spacing: 13) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 25))
                            .foregroundStyle(ClyroTheme.gold)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.label)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(item.program)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(ClyroTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        TagView(text: item.scope)
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(ClyroTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(28)
        .task {
            items = await Task.detached(priority: .utility) { StartupProbe.scan() }.value
        }
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
                    ?? "Kein Programmpfad angegeben"
                items.append(StartupItem(url: url, label: label, program: program, scope: scope))
            }
        }
        return items.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var cleaner: CleanupScanner

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader("Verlauf", subtitle: "Eine transparente Übersicht aller Bereinigungen.")
            if cleaner.history.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", title: "Noch kein Verlauf", message: "Nach deiner ersten Bereinigung erscheint hier, was wann in den Papierkorb verschoben wurde.")
            } else {
                List(cleaner.history) { record in
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(ClyroTheme.mint.opacity(0.12))
                            Image(systemName: "checkmark").foregroundStyle(ClyroTheme.mint)
                        }
                        .frame(width: 36, height: 36)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.categories.map(\.title).joined(separator: ", "))
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(record.date.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(ClyroTheme.secondaryText)
                        }
                        Spacer()
                        Text("\(record.itemCount) Elemente")
                            .foregroundStyle(ClyroTheme.secondaryText)
                        Text(ClyroFormat.byteCount(record.bytes))
                            .fontWeight(.bold)
                            .frame(width: 90, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.clear)
                }
                .scrollContentBackground(.hidden)
                .background(ClyroTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            Spacer()
        }
        .padding(28)
    }
}

struct SettingsView: View {
    @AppStorage("showTechnicalDetails") private var showTechnicalDetails = false
    @AppStorage("includeDeveloperData") private var includeDeveloperData = true

    var body: some View {
        Form {
            Section("Darstellung") {
                Toggle("Technische Details anzeigen", isOn: $showTechnicalDetails)
            }
            Section("Scan") {
                Toggle("Xcode-Daten berücksichtigen", isOn: $includeDeveloperData)
                Text("Clyro verschiebt ausgewählte Dateien in den Papierkorb. Systemdateien werden nicht automatisch verändert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Über Clyro") {
                LabeledContent("Version", value: "0.2.0")
                LabeledContent("Datenschutz", value: "100 % lokal")
            }
        }
        .padding(20)
    }
}
