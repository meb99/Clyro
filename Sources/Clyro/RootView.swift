import SwiftUI

struct RootView: View {
    @State private var selection: AppSection = .overview

    var body: some View {
        ZStack {
            ClyroTheme.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topNavigation
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                Divider()
                    .overlay(ClyroTheme.border)

                Group {
                    switch selection {
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
            }
        }
    }

    private var topNavigation: some View {
        HStack(spacing: 3) {
            Button {
                selection = .overview
            } label: {
                ZStack {
                    Circle()
                        .fill(ClyroTheme.mint)
                    Image(systemName: "circle.hexagonpath.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.78))
                }
                .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .help("Clyro Übersicht")

            ForEach(AppSection.allCases) { section in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = section
                    }
                } label: {
                    Text(section.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selection == section ? .black.opacity(0.82) : .secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background {
                            if selection == section {
                                Capsule()
                                    .fill(ClyroTheme.mint)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(section.title)
                .accessibilityAddTraits(selection == section ? .isSelected : [])
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(ClyroTheme.border, lineWidth: 0.75))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }
}
