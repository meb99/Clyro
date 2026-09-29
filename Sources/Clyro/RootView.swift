import SwiftUI

struct RootView: View {
    @State private var selection: AppSection = .overview

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
                    case .projects: ProjectsView()
                    case .storage: StorageView()
                    case .processes: ProcessesView()
                    case .applications: ApplicationsView()
                    case .startup: StartupItemsView()
                    case .history: HistoryView()
                    }
                }
                .id(selection)
                .transition(.opacity.combined(with: .scale(scale: 0.992)))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.32), value: selection)
    }

    private var topNavigation: some View {
        HStack(spacing: 3) {
            Button {
                selection = .overview
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                    Image(systemName: "circle.hexagonpath.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.bottom)
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
                        .foregroundStyle(selection == section ? .black.opacity(0.84) : .white.opacity(0.56))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background {
                            if selection == section {
                                Capsule()
                                    .fill(.white)
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
        .background(palette.top.opacity(0.74), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }
}
