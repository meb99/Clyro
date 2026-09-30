import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage("includeDeveloperData") private var includeDeveloperData = true
    @AppStorage(CleanupScanner.useTrashKey) private var useTrash = false
    @AppStorage(CleanupWhitelist.defaultsKey) private var whitelist = ""
    @AppStorage("purgePaths") private var purgePaths = ""
    @AppStorage("optimizeDryRun") private var optimizeDryRun = false
    @AppStorage(OptimizeCatalog.excludedKey) private var excludedTasks = ""
    @AppStorage(ReminderService.lowDiskKey) private var remindLowDisk = false
    @AppStorage(ReminderService.lowDiskGBKey) private var lowDiskGB = 20
    @AppStorage(ReminderService.staleKey) private var remindStale = false
    @AppStorage(ReminderService.staleDaysKey) private var staleDays = 14
    @AppStorage(ReminderService.autoCleanKey) private var autoClean = false
    @AppStorage(AppRemovalWatcher.enabledKey) private var removeLeftovers = true
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var touchID = TouchIDSudo.isEnabled
    @State private var touchIDBusy = false
    @AppStorage(UpdateService.autoCheckKey) private var autoCheckUpdates = true
    @ObservedObject private var updater = UpdateService.shared

    private var updateStatus: String {
        switch updater.state {
        case .idle: ""
        case .checking: String(localized: "Suche läuft …")
        case .upToDate: String(localized: "Clyro ist aktuell.")
        case .available(let release): String(localized: "Version \(release.version) verfügbar")
        case .installing: String(localized: "Wird installiert …")
        case .failed(let message): message
        }
    }

    var body: some View {
        Form {
            Section("Allgemein") {
                LabeledContent("Sprache") {
                    LanguageSwitch()
                }
                Text("Clyro startet nach dem Wechsel einmal neu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Clyro bei der Anmeldung starten", isOn: Binding(
                    get: { launchAtLogin },
                    set: { value in
                        LaunchAtLogin.setEnabled(value)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                ))
                Text("Das Symbol in der Menüleiste ist dann nach jedem Neustart verfügbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Touch ID für sudo im Terminal", isOn: Binding(
                    get: { touchID },
                    set: { value in
                        touchIDBusy = true
                        Task.detached {
                            _ = TouchIDSudo.setEnabled(value)
                            let now = TouchIDSudo.isEnabled
                            await MainActor.run {
                                touchID = now
                                touchIDBusy = false
                            }
                        }
                    }
                ))
                .disabled(touchIDBusy)
                Text("Trägt pam_tid in /etc/pam.d/sudo_local ein. macOS fragt dafür einmal nach dem Administratorpasswort; die Einstellung bleibt bei Systemupdates erhalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Erinnerungen") {
                Toggle("Melden, wenn wenig Speicher frei ist", isOn: $remindLowDisk)
                if remindLowDisk {
                    Stepper("Unter \(lowDiskGB) GB frei", value: $lowDiskGB, in: 5...500, step: 5)
                }
                Toggle("Erinnern, wenn lange nicht bereinigt wurde", isOn: $remindStale)
                if remindStale {
                    Stepper("Nach \(staleDays) Tagen", value: $staleDays, in: 3...90)
                }
                Toggle("Jede Woche automatisch bereinigen", isOn: $autoClean)
                Text("Automatisch werden nur empfohlene Einträge bereinigt – ohne Systembereiche (Admin) und ohne Papierkorb. Clyro meldet danach, wie viel frei wurde.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: remindLowDisk) { _, on in if on { ClyroNotifier.requestAuthorization() } }
            .onChange(of: remindStale) { _, on in if on { ClyroNotifier.requestAuthorization() } }
            .onChange(of: autoClean) { _, on in if on { ClyroNotifier.requestAuthorization() } }
            Section("Bereinigen") {
                Toggle("Entwicklerwerkzeuge prüfen", isOn: $includeDeveloperData)
                Toggle("In den Papierkorb statt endgültig löschen", isOn: $useTrash)
                Text("Caches und Protokolle werden standardmäßig endgültig gelöscht, damit der Speicher sofort frei wird. Deinstallieren und Analyse verschieben immer in den Papierkorb.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Reste gelöschter Apps automatisch entfernen", isOn: $removeLeftovers)
                    .onChange(of: removeLeftovers) { _, on in if on { ClyroNotifier.requestAuthorization() } }
                Text("Landet eine App im Papierkorb, legt Clyro auch ihre Einstellungen, Caches und Container dorthin. Geschützte Apps von Apple und Sicherheitssoftware bleiben unberührt.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Whitelist") {
                TextEditor(text: $whitelist)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 80)
                Text("Ein Eintrag pro Zeile: ein Name wie com.spotify.client oder ein Pfad wie ~/Library/Caches/Foo*. Geschützte Einträge schlägt Clyro nie vor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Projektordner") {
                TextEditor(text: $purgePaths)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(height: 60)
                Text("Ein Pfad pro Zeile, z. B. ~/Arbeit. Sind Ordner eingetragen, sucht Clyro nur dort nach Build-Ordnern.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Optimieren") {
                Toggle("Nur als Vorschau ausführen", isOn: $optimizeDryRun)
                ForEach(OptimizeCatalog.tasks) { task in
                    Toggle(task.title, isOn: Binding(
                        get: { !excludedTasks.split(separator: ",").map(String.init).contains(task.id) },
                        set: { isOn in
                            var values = Set(excludedTasks.split(separator: ",").map(String.init))
                            if isOn { values.remove(task.id) } else { values.insert(task.id) }
                            excludedTasks = values.sorted().joined(separator: ",")
                        }
                    ))
                }
                Text("Abgewählte Aufgaben werden beim Optimieren übersprungen.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Aktivitätsprotokoll") {
                Button("Protokoll im Finder zeigen") {
                    if FileManager.default.fileExists(atPath: ClyroLog.url.path) {
                        NSWorkspace.shared.activateFileViewerSelecting([ClyroLog.url])
                    } else {
                        NSWorkspace.shared.open(ClyroLog.url.deletingLastPathComponent().deletingLastPathComponent())
                    }
                }
                Text("Jede gelöschte oder verschobene Datei wird lokal in ~/Library/Logs/Clyro festgehalten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Automatisch nach Updates suchen", isOn: $autoCheckUpdates)
                HStack {
                    Button("Jetzt suchen") {
                        Task { await updater.check(userInitiated: true) }
                    }
                    .disabled(updater.state == .checking || updater.state == .installing)
                    Spacer()
                    Text(updateStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Clyro fragt bei jedem Start und danach höchstens alle sechs Stunden bei GitHub nach einer neuen Version. Updates werden nur nach Bestätigung installiert.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Über Clyro") {
                LabeledContent("Version", value: updater.currentVersion)
                LabeledContent(String(localized: "Datenschutz"), value: String(localized: "Lokal · Updates nur auf Anfrage"))
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }
}
