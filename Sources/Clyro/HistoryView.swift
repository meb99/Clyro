import AppKit
import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var cleaner: CleanupScanner

    private let accent = ClyroTheme.palette(for: .history).accent
    private let secondary = ClyroTheme.palette(for: .history).secondary

    private var totalBytes: Int64 {
        cleaner.history.reduce(0) { $0 + $1.bytes }
    }

    private var totalItems: Int {
        cleaner.history.reduce(0) { $0 + $1.itemCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ClyroPageHeader(
                    title: String(localized: "Verlauf"),
                    subtitle: String(localized: "Alle Bereinigungen mit Datum und Umfang, lokal gespeichert."),
                    icon: "clock.arrow.circlepath",
                    accent: accent
                )
                Spacer()
                ClyroStatPill(title: String(localized: "Freigegeben"), value: ClyroFormat.byteCount(totalBytes), icon: "externaldrive.fill", color: accent)
                ClyroStatPill(title: String(localized: "Elemente"), value: "\(totalItems)", icon: "doc.on.doc.fill", color: secondary)
            }

            if cleaner.history.isEmpty {
                VStack(spacing: 10) {
                    ClyroArtifact(symbol: "clock.arrow.circlepath", satellite: "checkmark", accent: accent, secondary: secondary, growth: 0.05)
                    Text("Noch kein Verlauf")
                        .font(.system(size: 22, weight: .semibold))
                    Text("Jede Bereinigung pflanzt einen Baum.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clyroPanel(padding: 20, cornerRadius: 20)
            } else {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dein Wald")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Jede Bereinigung pflanzt einen Baum.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        ClyroForest(records: cleaner.history)
                            .frame(height: 130)
                        Text("\(min(cleaner.history.count, 40)) Bäume")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                        Text("Die Größe entspricht dem freigegebenen Speicher, die Farbe der Jahreszeit.")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clyroPanel(padding: 16, cornerRadius: 18)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Freigegeben pro Woche")
                            .font(.system(size: 13, weight: .semibold))
                        SavingsChart(records: cleaner.history, accent: accent)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clyroPanel(padding: 16, cornerRadius: 18)
                }
                .frame(height: 250)

                HStack(spacing: 14) {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(cleaner.history.enumerated()), id: \.element.id) { index, record in
                                HistoryTimelineRow(record: record, isLast: index == cleaner.history.count - 1, accent: accent)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .clyroPanel(padding: 14, cornerRadius: 18)
                }
            }
        }
        .padding(22)
    }
}

private struct HistoryTimelineRow: View {
    let record: CleanupRecord
    let isLast: Bool
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.black.opacity(0.72))
                }
                .frame(width: 28, height: 28)
                if !isLast {
                    Rectangle().fill(accent.opacity(0.24)).frame(width: 2, height: 34)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.categories.map(\.title).joined(separator: ", "))
                    .font(.system(size: 12, weight: .semibold))
                Text(record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(record.itemCount) Elemente")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            Text(ClyroFormat.byteCount(record.bytes))
                .font(.system(size: 12, weight: .bold))
                .frame(width: 86, alignment: .trailing)
        }
        .frame(minHeight: 62, alignment: .top)
    }
}
