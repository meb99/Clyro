import SwiftUI

struct RootView: View {
    @State private var selection: AppSection = .cleanup

    private var palette: ClyroPalette {
        ClyroTheme.palette(for: selection)
    }

    var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            RadialGradient(
                colors: [palette.accent.opacity(0.14), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )
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
                    case .optimize: OptimizeView()
                    case .storage: StorageView()
                    case .explorer: ExplorerView()
                    case .applications: ApplicationsView()
                    case .startup: StartupItemsView()
                    case .history: HistoryView()
                    }
                }
                .id(selection)
                .environment(\.clyroSeason, ClyroSeason.of(selection))
                .transition(.opacity.combined(with: .scale(scale: 0.992)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: selection)
    }

    private var group: NavGroup {
        NavGroup.group(of: selection)
    }

    private var topNavigation: some View {
        HStack(spacing: 3) {
            ZStack {
                Circle().fill(.white)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.bottom)
            }
            .frame(width: 34, height: 34)
            .padding(.trailing, 4)

            ForEach(NavGroup.allCases) { entry in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        selection = entry.section
                    }
                } label: {
                    Text(entry.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(group == entry ? .black.opacity(0.84) : .white.opacity(0.56))
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background {
                            if group == entry {
                                Capsule().fill(.white)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.title)
                .accessibilityAddTraits(group == entry ? .isSelected : [])
            }
        }
        .padding(5)
        .background(palette.top.opacity(0.74), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }
}
