import AppKit
import Combine
import Foundation

@MainActor
final class CleanupScanner: ObservableObject {
    enum State: Equatable {
        case idle
        case scanning
        case ready
        case cleaning
        case failed(String)
    }

    @Published var categories: [CleanupCategory] = []
    @Published private(set) var state: State = .idle
    @Published private(set) var history: [CleanupRecord] = []

    private let historyKey = "clyro.cleanup.history"

    init() {
        loadHistory()
    }

    var selectedBytes: Int64 {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.bytes }
    }

    var selectedItems: Int {
        categories.filter(\.isSelected).reduce(0) { $0 + $1.itemCount }
    }

    func scan() {
        guard state != .scanning && state != .cleaning else { return }
        state = .scanning
        let includeDeveloperData = UserDefaults.standard.object(forKey: "includeDeveloperData") as? Bool ?? true

        Task {
            let results = await Task.detached(priority: .utility) {
                CleanupProbe.scan(includeDeveloperData: includeDeveloperData)
            }.value
            categories = results
            state = .ready
        }
    }

    func cleanSelected() {
        let selected = categories.filter(\.isSelected)
        let paths = selected.flatMap(\.paths)
        guard !paths.isEmpty else { return }
        state = .cleaning

        Task {
            let result = await Task.detached(priority: .utility) {
                var moved = 0
                var bytes: Int64 = 0
                for category in selected {
                    for url in category.paths {
                        let estimatedSize = FileProbe.sizeOfItem(at: url)
                        do {
                            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                            moved += 1
                            bytes += max(0, estimatedSize)
                        } catch {
                            continue
                        }
                    }
                }
                return (moved, bytes)
            }.value

            if result.0 > 0 {
                let estimatedBytes = result.1 > 0 ? result.1 : selected.reduce(0) { $0 + $1.bytes }
                let record = CleanupRecord(
                    id: UUID(),
                    date: Date(),
                    bytes: estimatedBytes,
                    itemCount: result.0,
                    categories: selected.map(\.kind)
                )
                history.insert(record, at: 0)
                history = Array(history.prefix(50))
                saveHistory()
            }
            state = .idle
            scan()
        }
    }

    func reveal(_ category: CleanupCategory) {
        guard let first = category.paths.first else { return }
        NSWorkspace.shared.activateFileViewerSelecting([first])
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([CleanupRecord].self, from: data) else { return }
        history = decoded
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }
}

private enum CleanupProbe {
    static func scan(includeDeveloperData: Bool) -> [CleanupCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var categories = [
            category(.caches, root: home.appendingPathComponent("Library/Caches"), olderThanDays: 14),
            category(.logs, root: home.appendingPathComponent("Library/Logs"), olderThanDays: 14),
            filteredCategory(
                .installers,
                root: home.appendingPathComponent("Downloads"),
                olderThanDays: 30,
                extensions: ["dmg", "pkg", "zip"]
            )
        ]
        if includeDeveloperData {
            categories.append(category(
                .developerData,
                root: home.appendingPathComponent("Library/Developer/Xcode/DerivedData"),
                olderThanDays: 14
            ))
        }
        return categories
    }

    private static func category(_ kind: CleanupKind, root: URL, olderThanDays days: Int) -> CleanupCategory {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let urls = topLevelItems(at: root).filter { url in
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isSymbolicLinkKey])
            return values?.isSymbolicLink != true && (values?.contentModificationDate ?? .distantFuture) < threshold
        }
        let bytes = urls.reduce(Int64(0)) { $0 + FileProbe.sizeOfItem(at: $1) }
        return CleanupCategory(kind: kind, bytes: bytes, itemCount: urls.count, paths: urls, isSelected: bytes > 0)
    }

    private static func filteredCategory(
        _ kind: CleanupKind,
        root: URL,
        olderThanDays days: Int,
        extensions: Set<String>
    ) -> CleanupCategory {
        let threshold = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let urls = topLevelItems(at: root).filter { url in
            guard extensions.contains(url.pathExtension.lowercased()) else { return false }
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
            return values?.isRegularFile == true && (values?.contentModificationDate ?? .distantFuture) < threshold
        }
        let bytes = urls.reduce(Int64(0)) { $0 + FileProbe.sizeOfItem(at: $1) }
        return CleanupCategory(kind: kind, bytes: bytes, itemCount: urls.count, paths: urls, isSelected: bytes > 0)
    }

    private static func topLevelItems(at root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }
}

enum FileProbe {
    static func sizeOfItem(at url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .isSymbolicLinkKey]
        guard let rootValues = try? url.resourceValues(forKeys: keys), rootValues.isSymbolicLink != true else { return 0 }
        if rootValues.isRegularFile == true {
            return Int64(rootValues.totalFileAllocatedSize ?? rootValues.fileAllocatedSize ?? 0)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        var total: Int64 = 0
        for case let itemURL as URL in enumerator {
            guard let values = try? itemURL.resourceValues(forKeys: keys),
                  values.isSymbolicLink != true,
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }
}
