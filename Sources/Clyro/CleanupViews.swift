import AppKit
import SwiftUI

/// Großer weißer Kapsel-Button, wie bei den Hauptaktionen der Vorbilder.
struct ClyroPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.black.opacity(0.88))
            .padding(.horizontal, 32)
            .frame(height: 52)
            .background(Capsule().fill(.white))
            .shadow(color: .white.opacity(0.14), radius: 18)
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

struct CleanupView: View {
    @EnvironmentObject private var cleaner: CleanupScanner
    @State private var showConfirmation = false

    private let accent = ClyroTheme.palette(for: .cleanup).accent

    var body: some View {
        Group {
            if let celebration = cleaner.celebration {
                bloomStage(celebration)
            } else if cleaner.state == .cleaning {
                wateringStage
            } else if cleaner.state == .scanning {
                scanningStage
            } else if cleaner.categories.isEmpty {
                startStage
            } else {
                resultsScreen
            }
        }
        .padding(22)
        .alert("Ausgewählte Dateien bereinigen?", isPresented: $showConfirmation) {
            Button("Abbrechen", role: .cancel) {}
            Button(cleaner.selectedPermanentBytes > 0 ? "Bereinigen" : "In den Papierkorb", role: .destructive) {
                cleaner.cleanSelected()
            }
        } message: {
            Text(confirmationText)
        }
    }

    private var confirmationText: String {
        var text = "\(cleaner.selectedItems) Elemente mit ungefähr \(ClyroFormat.byteCount(cleaner.selectedBytes)) werden in den Papierkorb verschoben."
        if cleaner.selectedPermanentBytes > 0 {
            text += " Der Inhalt des Papierkorbs (\(ClyroFormat.byteCount(cleaner.selectedPermanentBytes))) wird dagegen endgültig gelöscht und lässt sich nicht zurückholen."
        }
        return text
    }

    // MARK: - Start und Scan

    private var startStage: some View {
        VStack(spacing: 14) {
            ClyroGardenScene(phase: .idle, growth: 0.14, accent: accent)
                .frame(width: 340, height: 290)
            Text("Ein wenig Wasser, ein wenig Licht –\nund dein Mac wächst wieder frei.")
                .font(.system(size: 20, weight: .medium, design: .serif))
                .foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
            Button("Mac scannen") { cleaner.scan() }
                .buttonStyle(ClyroPillButtonStyle())
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningStage: some View {
        VStack(spacing: 18) {
            ClyroGardenScene(phase: .scanning, growth: 0.2, accent: accent)
                .frame(width: 340, height: 290)
            Text("Wird durchsucht · \(ClyroFormat.byteCount(cleaner.progressBytes))")
                .font(.system(size: 34, weight: .bold))
                .monospacedDigit()
            HStack(spacing: 10) {
                Circle().fill(accent).frame(width: 9, height: 9)
                Text(displayPath(cleaner.progressPath))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: 560)
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: home, with: "~")
    }

    // MARK: - Ergebnisse

    private var resultsScreen: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bereit zum Aufräumen")
                        .font(.system(size: 30, weight: .bold))
                    summaryLine
                }
                Spacer()
                circleButton("arrow.clockwise", help: "Neu scannen") { cleaner.scan() }
                circleButton("xmark", help: "Schließen") { cleaner.close() }
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach($cleaner.categories) { $category in
                        CleanupCategoryCard(category: $category, accent: accent)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.hidden)

            footer
        }
    }

    private var summaryLine: some View {
        HStack(spacing: 6) {
            Text("\(ClyroFormat.byteCount(cleaner.totalBytes)) bereinigbar · \(cleaner.totalItems) Objekte · \(cleaner.categories.count) Kategorien")
                .foregroundStyle(.secondary)
            if !cleaner.blockedApps.isEmpty {
                Text("· \(cleaner.blockedApps.map(\.name).joined(separator: ", ")) belegen Cache ·")
                    .foregroundStyle(.secondary)
                Button("Beenden") { cleaner.quitBlockedApps() }
                    .buttonStyle(.plain)
                    .foregroundStyle(accent)
                    .help("Schließt die Apps und scannt danach neu")
            }
        }
        .font(.system(size: 14, weight: .medium))
    }

    private func circleButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.10)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Text("\(cleaner.selectedItems) ausgewählt")
                .font(.system(size: 15, weight: .semibold))
            HStack(spacing: 6) {
                linkButton("Alle") { cleaner.selectAll() }
                Text("·").foregroundStyle(.secondary)
                linkButton("Keine") { cleaner.selectNone() }
                Text("·").foregroundStyle(.secondary)
                linkButton("Empfohlene") { cleaner.selectRecommended() }
            }
            .font(.system(size: 14, weight: .medium))
            Spacer()
            Button {
                showConfirmation = true
            } label: {
                Text("\(cleaner.selectedPermanentBytes > 0 ? "Bereinigen" : "In den Papierkorb") · \(ClyroFormat.byteCount(cleaner.selectedBytes))")
            }
            .buttonStyle(ClyroPillButtonStyle())
            .disabled(cleaner.selectedItems == 0)
            .opacity(cleaner.selectedItems == 0 ? 0.4 : 1)
        }
        .padding(.top, 4)
    }

    private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .foregroundStyle(accent)
    }

    // MARK: - Bereinigen und Ergebnis

    private var wateringStage: some View {
        VStack(spacing: 10) {
            ClyroGardenScene(phase: .watering, growth: 0.32, accent: accent, startGrowth: 0.12)
                .frame(width: 340, height: 290)
            Text("Clyro gießt deinen Mac frisch")
                .font(.system(size: 26, weight: .semibold))
            Text("Die ausgewählten Dateien werden aufgeräumt …")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            ProgressView().tint(accent).frame(width: 240).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func bloomStage(_ celebration: CleanupCelebration) -> some View {
        VStack(spacing: 10) {
            ClyroGardenScene(phase: .bloom, growth: 0.66, accent: accent, startGrowth: 0.32)
                .frame(width: 340, height: 290)
            Text("\(ClyroFormat.byteCount(celebration.bytes)) freigegeben")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Dein Mac ist frisch gegossen – der Keimling wächst.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Button("Weiter") { cleaner.dismissCelebration() }
                .buttonStyle(ClyroPillButtonStyle())
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: celebration.id) {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            cleaner.dismissCelebration()
        }
    }
}

// MARK: - Kategorie-Karte

private struct CleanupCategoryCard: View {
    @Binding var category: CleanupCategory
    let accent: Color

    private var sizeLabel: String {
        if category.selectedBytes == category.totalBytes || category.isFullyLocked {
            return ClyroFormat.byteCount(category.totalBytes)
        }
        return "\(ClyroFormat.byteCount(category.selectedBytes)) / \(ClyroFormat.byteCount(category.totalBytes))"
    }

    private var checkboxSymbol: String {
        switch category.selectionState {
        case .all: "checkmark.square.fill"
        case .partial: "minus.square.fill"
        case .none: "square"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                selector

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { category.isExpanded.toggle() }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 10) {
                                Text(category.kind.title)
                                    .font(.system(size: 16, weight: .semibold))
                                Text("\(category.selectedCount)/\(category.itemCount) ausgewählt")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Text(category.kind.detail)
                                .font(.system(size: 13))
                                .foregroundStyle(ClyroTheme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(sizeLabel)
                            .font(.system(size: 15, weight: .semibold, design: .monospaced))
                            .foregroundStyle(accent)
                        Image(systemName: category.isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 74)

            if category.isExpanded {
                Divider().overlay(ClyroTheme.border)
                VStack(spacing: 0) {
                    ForEach($category.items) { $item in
                        CleanupItemRow(item: $item, accent: accent)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ClyroTheme.card)
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(ClyroTheme.border))
        )
    }

    @ViewBuilder
    private var selector: some View {
        if category.isFullyLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .help("Die App läuft noch. Beende sie, damit ihr Cache bereinigt werden kann.")
        } else {
            Button {
                category.setSelected(category.selectionState != .all)
            } label: {
                Image(systemName: checkboxSymbol)
                    .font(.system(size: 22))
                    .foregroundStyle(category.selectionState == .none ? Color.white.opacity(0.35) : accent)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CleanupItemRow: View {
    @Binding var item: CleanupItem
    let accent: Color

    var body: some View {
        HStack(spacing: 12) {
            if item.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
            } else {
                Button {
                    item.isSelected.toggle()
                } label: {
                    Image(systemName: item.isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 17))
                        .foregroundStyle(item.isSelected ? accent : Color.white.opacity(0.35))
                }
                .buttonStyle(.plain)
                .frame(width: 20)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(item.locationName)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(ClyroFormat.byteCount(item.bytes))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "folder")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.5))
            .help("Im Finder zeigen")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
}
