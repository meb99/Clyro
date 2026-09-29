import SwiftUI

@main
struct ClyroApp: App {
    @StateObject private var monitor = SystemMonitor()
    @StateObject private var cleaner = CleanupScanner()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(monitor)
                .environmentObject(cleaner)
                .preferredColorScheme(.dark)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 790)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .frame(width: 480, height: 620)
                .preferredColorScheme(.dark)
        }
    }
}
