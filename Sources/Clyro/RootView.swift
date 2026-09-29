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
            ForEach(AppSection.primary) { entry in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = entry }
                } label: {
                    barLabel(entry.title, active: selection == entry)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(entry.title)
                .accessibilityAddTraits(selection == entry ? .isSelected : [])
            }

            Menu {
                ForEach(AppSection.secondary) { entry in
                    Button(entry.title) {
                        withAnimation(.easeOut(duration: 0.16)) { selection = entry }
                    }
                }
            } label: {
                barLabel(
                    AppSection.secondary.contains(selection) ? selection.title : "Mehr",
                    active: AppSection.secondary.contains(selection)
                )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(5)
        .background(palette.top.opacity(0.74), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
    }

    private func barLabel(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? .black.opacity(0.84) : .white.opacity(0.56))
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background {
                if active { Capsule().fill(.white) }
            }
            .contentShape(Capsule())
    }
}
