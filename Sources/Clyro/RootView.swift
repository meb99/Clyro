import SwiftUI

struct RootView: View {
    @State private var selection: AppSection = .overview

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 240)
        } detail: {
            Group {
                switch selection {
                case .overview: DashboardView()
                case .cleanup: CleanupView()
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(ClyroTheme.mint.opacity(0.16))
                    Image(systemName: "sparkles")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(ClyroTheme.mint)
                }
                .frame(width: 39, height: 39)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Clyro")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                    Text("Mac care, made clear")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(ClyroTheme.secondaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 23)
            .padding(.bottom, 26)

            VStack(spacing: 6) {
                ForEach(AppSection.allCases) { item in
                    Button {
                        selection = item
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .frame(width: 19)
                            Text(item.title)
                            Spacer()
                        }
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == item ? .white : .white.opacity(0.58))
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(selection == item ? ClyroTheme.mint.opacity(0.14) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            VStack(alignment: .leading, spacing: 7) {
                Label("Alles bleibt lokal", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(ClyroTheme.mint)
                Text("Keine Konten. Keine Cloud. Keine versteckten Löschungen.")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(ClyroTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 13).fill(.white.opacity(0.035)))
            .padding(14)
        }
        .background(ClyroTheme.sidebar)
    }
}
