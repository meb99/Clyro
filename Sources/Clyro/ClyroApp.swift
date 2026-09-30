import SwiftUI

@main
struct ClyroApp: App {
    @StateObject private var monitor = SystemMonitor()
    @StateObject private var cleaner = CleanupScanner()

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environmentObject(monitor)
                .environmentObject(cleaner)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 680)
                .task { ReminderService.shared.start(monitor: monitor, cleaner: cleaner) }
        }
        .defaultSize(width: 1180, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Nach Updates suchen …") {
                    Task { await UpdateService.shared.checkFromMenu() }
                }
            }
        }

        MenuBarExtra("Clyro", systemImage: "leaf.fill") {
            MenuBarStatusView()
                .environmentObject(monitor)
                .environmentObject(cleaner)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .frame(width: 520, height: 760)
                .preferredColorScheme(.dark)
        }
    }
}
