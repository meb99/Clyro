import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case cleanup
    case optimize
    case storage
    case explorer
    case applications
    case startup
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .cleanup: "Bereinigen"
        case .optimize: "Optimieren"
        case .storage: "Speicher"
        case .explorer: "Ordner"
        case .applications: "Apps"
        case .startup: "Autostart"
        case .history: "Verlauf"
        }
    }

    var tabTitle: String {
        switch self {
        case .overview: "Status"
        case .optimize: "Wartung"
        default: title
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .cleanup: "sparkles"
        case .optimize: "dial.medium.fill"
        case .storage: "internaldrive.fill"
        case .explorer: "chart.pie.fill"
        case .applications: "app.dashed"
        case .startup: "bolt.fill"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// Die fünf Hauptbereiche der oberen Leiste. Jeder Bereich ist genau eine Seite, es gibt keine Unterreiter.
enum NavGroup: String, CaseIterable, Identifiable {
    case clean
    case apps
    case optimize
    case analyze
    case status

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: "Bereinigen"
        case .apps: "Apps"
        case .optimize: "Optimieren"
        case .analyze: "Analyse"
        case .status: "Status"
        }
    }

    var section: AppSection {
        switch self {
        case .clean: .cleanup
        case .apps: .applications
        case .optimize: .optimize
        case .analyze: .explorer
        case .status: .overview
        }
    }

    static func group(of section: AppSection) -> NavGroup {
        allCases.first { $0.section == section } ?? .clean
    }
}

struct SystemProcess: Identifiable, Hashable {
    let id: Int32
    let name: String
    let cpuPercent: Double
    let memoryBytes: Int64
    let cpuTicks: UInt64
    let executablePath: String
    var power: Double?
}

struct CPUCounters: Hashable {
    var user: UInt64 = 0
    var system: UInt64 = 0
    var idle: UInt64 = 0
    var nice: UInt64 = 0

    var active: UInt64 { user + system + nice }
    var total: UInt64 { active + idle }
}

struct BatterySnapshot: Hashable {
    var cycleCount: Int?
    var healthPercent: Int?
    var percentage: Int = 0
    var isCharging = false
    var isPresent = false
    var timeRemaining = "–"
}

enum SmartStatus: Hashable {
    case unknown
    case verified
    case failing
    case unsupported
}

struct DiskCounters: Hashable {
    var readBytes: UInt64 = 0
    var writtenBytes: UInt64 = 0
}

struct NetworkCounters: Hashable {
    var receivedBytes: UInt64 = 0
    var sentBytes: UInt64 = 0
}

struct SystemSnapshot: Hashable {
    var cpuPercent = 0.0
    var cpuCounters = CPUCounters()
    var memoryUsedBytes: Int64 = 0
    var memoryTotalBytes: Int64 = 0
    var diskUsedBytes: Int64 = 0
    var diskTotalBytes: Int64 = 0
    var downloadBytesPerSecond = 0.0
    var uploadBytesPerSecond = 0.0
    var networkCounters = NetworkCounters()
    var diskCounters = DiskCounters()
    var smartStatus: SmartStatus = .unknown
    var diskReadBytesPerSecond = 0.0
    var diskWriteBytesPerSecond = 0.0
    var battery = BatterySnapshot()
    var temperatureCelsius: Double?
    var gpuTemperatureCelsius: Double?
    var gpuPercent: Double?
    var gpuCores: Int?
    var processCount = 0
    var loadAverage: Double?
    var coreCounters: [CPUCounters] = []
    var corePercents: [Double] = []
    var memoryPressurePercent: Int?
    var memoryPressureLevel = 1
    var swapUsedBytes: Int64 = 0
    var networkType: String?
    var temperaturePeak: Double?
    var thermalState: ProcessInfo.ThermalState = .nominal
    var processes: [SystemProcess] = []
    var chipName = "Mac"
    var osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    var uptime = ProcessInfo.processInfo.systemUptime

    var memoryPercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100
    }

    var diskPercent: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return Double(diskUsedBytes) / Double(diskTotalBytes) * 100
    }

    var thermalText: String {
        switch thermalState {
        case .nominal: "Kühl und ruhig"
        case .fair: "Leicht erwärmt"
        case .serious: "Heiß – Leistung gedrosselt"
        case .critical: "Kritisch heiß"
        @unknown default: "Unbekannt"
        }
    }

    /// Gesundheitswert nach denselben Schwellen wie Mole: CPU, Arbeitsspeicher, Festplatte, SMART, Temperatur, I/O, Akku, Laufzeit.
    var health: (score: Int, issues: [String]) {
        var score = 100.0
        var issues: [String] = []

        func penalty(_ value: Double, normal: Double, high: Double, weight: Double) -> Double {
            guard value > normal else { return 0 }
            if value > high { return weight * (value - normal) / (100 - normal) }
            return (weight / 2) * (value - normal) / (high - normal)
        }

        score -= penalty(cpuPercent, normal: 50, high: 85, weight: 30)
        if cpuPercent > 85 { issues.append("Hohe CPU-Last") }

        score -= penalty(memoryPercent, normal: 70, high: 88, weight: 25)
        if memoryPercent > 88 { issues.append("Wenig Arbeitsspeicher") }
        switch memoryPressureLevel {
        case 2:
            score -= 5
            issues.append("Speicherdruck")
        case 4:
            score -= 15
            issues.append("Kritischer Speicherdruck")
        default:
            break
        }

        if diskTotalBytes > 0 {
            score -= penalty(diskPercent, normal: 80, high: 93, weight: 20)
            if diskPercent > 93 { issues.append("Festplatte fast voll") }
        }
        if smartStatus == .failing {
            score = min(score, 44)
            issues.append("SMART meldet Fehler")
        }

        if let temperature = temperatureCelsius, temperature > 65 {
            if temperature > 85 {
                score -= 15
                issues.append("Überhitzung")
            } else {
                score -= 15 * (temperature - 65) / 20
            }
        }

        let ioMegabytes = (diskReadBytesPerSecond + diskWriteBytesPerSecond) / 1_048_576
        if ioMegabytes > 50 {
            if ioMegabytes > 150 {
                score -= 10
                issues.append("Hohe Festplattenlast")
            } else {
                score -= 10 * (ioMegabytes - 50) / 100
            }
        }

        if battery.isPresent {
            let cycles = battery.cycleCount ?? 0
            let capacity = battery.healthPercent ?? 100
            if cycles > 900 || capacity < 60 {
                score -= 5
                issues.append("Akku bald tauschen")
            } else if cycles > 800 || capacity < 80 {
                score -= 2
            }
        }

        if uptime > 14 * 86_400 {
            score -= 3
            issues.append("Neustart empfohlen")
        } else if uptime > 7 * 86_400 {
            score -= 1
        }

        return (Int(max(0, min(100, score))), issues)
    }

    var healthScore: Int { health.score }

    var healthText: String {
        switch healthScore {
        case 85...: "Ausgezeichnet"
        case 65...: "Gut"
        case 45...: "Mittel"
        default: "Aufmerksamkeit nötig"
        }
    }

}

enum CleanupKind: String, CaseIterable, Codable, Identifiable {
    case caches
    case systemCaches
    case other
    case developerData
    case aiTools
    case browserCaches
    case appRemnants
    case installers
    case projectArtifacts
    case trash
    /// Systembereiche außerhalb des Benutzerordners, die nur mit Admin-Passwort bereinigt werden können.
    case adminSystem
    // Ältere Einträge im Verlauf.
    case logs
    case packageCaches

    var id: String { rawValue }

    /// Reihenfolge der Kategorien in der Ergebnisliste.
    static let displayOrder: [CleanupKind] = [
        .caches, .systemCaches, .adminSystem, .other, .developerData, .aiTools,
        .browserCaches, .appRemnants, .installers, .projectArtifacts, .trash
    ]

    /// Der Papierkorb wird immer endgültig geleert.
    var isPermanent: Bool { self == .trash }

    var title: String {
        switch self {
        case .caches: "App-Caches"
        case .systemCaches: "System-Caches"
        case .other: "Sonstiges"
        case .developerData: "Entwicklerwerkzeuge"
        case .aiTools: "KI-Werkzeuge"
        case .browserCaches: "Browser"
        case .appRemnants: "Reste deinstallierter Apps"
        case .installers: "Installationsdateien"
        case .projectArtifacts: "Projekt-Artefakte"
        case .trash: "Papierkorb"
        case .adminSystem: "Systembereiche (Admin)"
        case .logs: "Protokolle"
        case .packageCaches: "Paket-Caches"
        }
    }

    var detail: String {
        switch self {
        case .caches: "Temporäre App-Dateien. Werden beim nächsten Start neu erstellt."
        case .systemCaches: "Von macOS verwaltete Caches. Werden automatisch neu erstellt."
        case .other: "Protokolle, Diagnoseberichte und verschiedene einmalige Caches."
        case .developerData: "Xcode / SwiftPM / node Caches. Der erste Build dauert etwas länger."
        case .aiTools: "Temporäre KI-App-Caches. Gespräche, Projekte und lokale Modelle bleiben erhalten."
        case .browserCaches: "Browser-Caches. Cookies und Sitzungen bleiben erhalten."
        case .appRemnants: "Daten von Apps, die nicht mehr auf diesem Mac installiert sind."
        case .installers: "DMG-, PKG-, ISO-, XIP- und Installer-ZIP-Dateien."
        case .projectArtifacts: "Wiederherstellbare Build-Ordner wie node_modules, target oder .build."
        case .trash: "Leert den Papierkorb endgültig."
        case .adminSystem: "Systemweite Caches, Protokolle und Diagnosedaten älter als 7 Tage. macOS fragt einmal nach deinem Passwort."
        case .logs: "Protokoll- und Absturzdateien"
        case .packageCaches: "Downloads von Paketmanagern"
        }
    }

    var icon: String {
        switch self {
        case .caches: "shippingbox.fill"
        case .systemCaches: "gearshape.fill"
        case .other: "tray.full.fill"
        case .developerData: "hammer.fill"
        case .aiTools: "sparkles"
        case .browserCaches: "globe"
        case .appRemnants: "trash.slash.fill"
        case .installers: "arrow.down.doc.fill"
        case .projectArtifacts: "shippingbox.and.arrow.backward.fill"
        case .trash: "trash.fill"
        case .adminSystem: "lock.shield.fill"
        case .logs: "doc.text.magnifyingglass"
        case .packageCaches: "archivebox.fill"
        }
    }
}

struct CleanupItem: Identifiable, Hashable {
    /// Stellvertretender Ort (für Finder und Anzeige).
    let url: URL
    /// Was tatsächlich gelöscht wird. Bei Cache-Ordnern ist das der Inhalt, nicht der Ordner selbst.
    var targets: [URL]
    let bytes: Int64
    var isSelected: Bool
    /// Gesperrt, solange die zugehörige App läuft.
    var isLocked = false
    var isRecommended = true
    var ownerName: String?
    var detail: String?
    /// Bundle-ID der laufenden App, die diesen Eintrag sperrt.
    var ownerBundle: String?

    var id: URL { url }
    var displayName: String { ownerName ?? url.lastPathComponent }

    var locationName: String {
        if let detail { return detail }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}

struct CleanupCategory: Identifiable {
    enum SelectionState {
        case none
        case partial
        case all
    }

    let kind: CleanupKind
    var items: [CleanupItem]
    var isExpanded = false

    var id: CleanupKind { kind }
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    var selectedBytes: Int64 { items.filter(\.isSelected).reduce(0) { $0 + $1.bytes } }
    var itemCount: Int { items.count }
    var selectedCount: Int { items.filter(\.isSelected).count }
    var selectableCount: Int { items.filter { !$0.isLocked }.count }
    var isFullyLocked: Bool { !items.isEmpty && selectableCount == 0 }

    var selectionState: SelectionState {
        if selectedCount == 0 { return .none }
        return selectedCount == selectableCount ? .all : .partial
    }

    mutating func setSelected(_ value: Bool) {
        for index in items.indices where !items[index].isLocked {
            items[index].isSelected = value
        }
    }

    mutating func selectRecommended() {
        for index in items.indices {
            items[index].isSelected = items[index].isRecommended && !items[index].isLocked
        }
    }
}

struct CleanupRecord: Codable, Identifiable {
    let id: UUID
    let date: Date
    let bytes: Int64
    let itemCount: Int
    let categories: [CleanupKind]
}

struct InstalledApplication: Identifiable, Hashable {
    let url: URL
    let name: String
    let version: String
    let bundleIdentifier: String
    let sizeBytes: Int64
    var lastUsed: Date?
    var addedDate: Date?
    var isIntelOnly = false
    var isRunning = false

    var id: URL { url }
}

struct LargeFileItem: Identifiable, Hashable {
    let url: URL
    let sizeBytes: Int64
    let modifiedAt: Date

    var id: URL { url }

    var displayName: String {
        url.lastPathComponent
    }

    var locationName: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.deletingLastPathComponent().path.replacingOccurrences(of: home, with: "~")
    }

    var kind: LargeFileKind {
        LargeFileKind.classify(url.pathExtension)
    }
}

enum LargeFileKind: String, CaseIterable, Hashable {
    case video
    case archive
    case installer
    case image
    case audio
    case document
    case other

    var title: String {
        switch self {
        case .video: "Video"
        case .archive: "Archiv"
        case .installer: "Installer"
        case .image: "Bild"
        case .audio: "Audio"
        case .document: "Dokument"
        case .other: "Sonstiges"
        }
    }

    var systemImage: String {
        switch self {
        case .video: "film"
        case .archive: "archivebox"
        case .installer: "opticaldiscdrive"
        case .image: "photo"
        case .audio: "waveform"
        case .document: "doc.text"
        case .other: "doc"
        }
    }

    static func classify(_ fileExtension: String) -> LargeFileKind {
        let value = fileExtension.lowercased()
        if ["mov", "mp4", "mkv", "avi", "m4v", "webm"].contains(value) { return .video }
        if ["zip", "rar", "7z", "tar", "gz", "xz"].contains(value) { return .archive }
        if ["dmg", "pkg", "iso"].contains(value) { return .installer }
        if ["jpg", "jpeg", "png", "heic", "tiff", "raw", "psd"].contains(value) { return .image }
        if ["mp3", "m4a", "wav", "flac", "aac"].contains(value) { return .audio }
        if ["pdf", "doc", "docx", "pages", "ppt", "pptx", "key"].contains(value) { return .document }
        return .other
    }
}

struct StartupItem: Identifiable, Hashable {
    let url: URL
    let label: String
    let program: String
    let scope: String

    var id: URL { url }
}
