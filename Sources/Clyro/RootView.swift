import SwiftUI

struct RootView: View {
    @State private var selection: AppSection? = .overview

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    navigationLink(for: .overview)
                }

                Section("Analysieren") {
                    navigationLink(for: .cleanup)
                    navigationLink(for: .storage)
                    navigationLink(for: .processes)
                }

                Section("Verwalten") {
                    navigationLink(for: .applications)
                    navigationLink(for: .startup)
                    navigationLink(for: .history)
                }

                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("Alles bleibt lokal", systemImage: "lock.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ClyroTheme.mint)
                        Text("Keine Cloud, kein Konto und keine versteckten Löschungen.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 6)
                    .listRowSeparator(.hidden)
                    .accessibilityElement(children: .combine)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Clyro")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 240)
        } detail: {
            Group {
                switch selection ?? .overview {
                case .overview: DashboardView()
                case .cleanup: CleanupView()
                case .storage: StorageView()
                case .processes: ProcessesView()
                case .applications: ApplicationsView()
                case .startup: StartupItemsView()
                case .history: HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ClyroTheme.background)
        }
        .navigationSplitViewStyle(.balanced)
        .background(ClyroTheme.background)
    }

    private func navigationLink(for section: AppSection) -> some View {
        NavigationLink(value: section) {
            Label(section.title, systemImage: section.icon)
        }
    }
}
