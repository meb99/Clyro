import AppKit
import SwiftUI

struct RootView: View {
    @State private var selection: AppSection = .cleanup
    @AppStorage(OnboardingView.doneKey) private var onboardingDone = false
    @ObservedObject private var updater = UpdateService.shared
    @EnvironmentObject private var cleaner: CleanupScanner

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
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .trailing) {
                        HStack(spacing: 8) {
                            VersionBadge()
                            LanguageSwitch(compact: true)
                        }
                        .padding(.trailing, 20)
                    }
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
        // Wer Bereinigen verlässt, beginnt beim Zurückkehren wieder mit dem Startbild und scannt neu.
        // Ein laufender Scan oder eine laufende Bereinigung wird dabei nicht abgebrochen.
        .onChange(of: selection) { previous, _ in
            switch previous {
            case .cleanup:
                cleaner.dismissCelebration()
                cleaner.close()
            case .optimize:
                // Ein laufender Durchgang läuft weiter; nur ein bereits angesehenes Ergebnis wird zurückgesetzt.
                OptimizeRunner.shared.reset()
            default:
                break
            }
        }
        .sheet(isPresented: Binding(get: { !onboardingDone }, set: { _ in })) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        // Der Update-Hinweis erscheint erst nach der Einführung.
        .sheet(item: Binding(
            get: { onboardingDone ? updater.presentedRelease : nil },
            set: { updater.presentedRelease = $0 }
        )) { release in
            UpdateSheet(release: release)
        }
        .task { updater.checkOnLaunch() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            updater.checkWhenActivated()
        }
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
            .accessibilityHidden(true)

            ForEach(Array(NavGroup.allCases.enumerated()), id: \.element) { index, entry in
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
                // ⌘1 bis ⌘5 wechseln zwischen den Bereichen.
                .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                .help(entry.title)
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
