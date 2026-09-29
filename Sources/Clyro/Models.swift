import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case overview
    case cleanup
    case optimize
    case projects
    case storage
    case explorer
    case processes
    case applications
    case startup
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .cleanup: "Bereinigen"
        case .optimize: "Optimieren"
        case .projects: "Projekte"
        case .storage: "Speicher"
        case .explorer: "Ordner"
        case .processes: "Prozesse"
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
        case .projects: "shippingbox.and.arrow.backward.fill"
        case .storage: "internaldrive.fill"
        case .explorer: "chart.pie.fill"
        case .processes: "list.bullet.rectangle.portrait.fill"
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

    var crewRole: ProcessCrewRole {
        ProcessCrewRole.classify(name)
    }

    var explanation: String {
        ProcessCrewRole.explanation(for: name)
    }
}

enum ProcessCrewRole: String, CaseIterable, Identifiable, Hashable {
    case navigator
    case messenger
    case studio
    case workshop
    case atelier
    case courier
    case guardian
    case engineRoom
    case helper

    var id: String { rawValue }

    var title: String {
        switch self {
        case .navigator: "Navigator"
        case .messenger: "Messenger"
        case .studio: "Studio"
        case .workshop: "Werkstatt"
        case .atelier: "Atelier"
        case .courier: "Kurier"
        case .guardian: "Wächter"
        case .engineRoom: "Maschinenraum"
        case .helper: "Helferlein"
        }
    }

    var emoji: String {
        switch self {
        case .navigator: "🧭"
        case .messenger: "💬"
        case .studio: "🎞️"
        case .workshop: "🛠️"
        case .atelier: "🎨"
        case .courier: "☁️"
        case .guardian: "🛡️"
        case .engineRoom: "⚙️"
        case .helper: "✨"
        }
    }

    var systemImage: String {
        switch self {
        case .navigator: "safari.fill"
        case .messenger: "bubble.left.and.bubble.right.fill"
        case .studio: "play.rectangle.fill"
        case .workshop: "hammer.fill"
        case .atelier: "paintpalette.fill"
        case .courier: "externaldrive.badge.icloud"
        case .guardian: "shield.lefthalf.filled"
        case .engineRoom: "gearshape.2.fill"
        case .helper: "sparkles"
        }
    }

    static func classify(_ processName: String) -> ProcessCrewRole {
        let name = processName.lowercased()

        if contains(name, any: ["safari", "chrome", "chromium", "firefox", "opera", "brave", "vivaldi", "edge", "arc helper"]) {
            return .navigator
        }
        if contains(name, any: ["mail", "messages", "whatsapp", "telegram", "discord", "slack", "teams", "signal", "facetime"]) {
            return .messenger
        }
        if contains(name, any: ["music", "spotify", "vlc", "quicktime", "tv", "podcast", "photo", "final cut", "premiere"]) {
            return .studio
        }
        if contains(name, any: ["xcode", "terminal", "iterm", "visual studio", "code helper", "swift", "python", "node", "git", "docker"]) {
            return .workshop
        }
        if contains(name, any: ["figma", "photoshop", "illustrator", "affinity", "sketch", "canva", "blender"]) {
            return .atelier
        }
        if contains(name, any: ["icloud", "cloudd", "bird", "dropbox", "onedrive", "google drive", "sync"] ) {
            return .courier
        }
        if contains(name, any: ["vpn", "security", "firewall", "trustd", "keychain", "antivirus", "malware"] ) {
            return .guardian
        }
        if contains(name, any: ["windowserver", "kernel_task", "launchd", "finder", "dock", "systemuiserver", "controlcenter", "spotlight", "mds", "coreaudiod", "bluetoothd", "loginwindow"] ) {
            return .engineRoom
        }
        return .helper
    }

    static func explanation(for processName: String) -> String {
        let name = processName.lowercased()
        if name.contains("windowserver") { return "Zeichnet Fenster, Animationen und externe Bildschirme." }
        if name.contains("kernel_task") { return "Verwaltet die Hardware und schützt den Mac vor Überhitzung." }
        if name == "finder" { return "Organisiert Dateien, Ordner und deinen Schreibtisch." }
        if name == "dock" { return "Steuert Dock, App-Wechsel und Mission Control." }
        if name.contains("coreaudiod") { return "Kümmert sich um Lautsprecher, Mikrofone und Audio." }
        if name.contains("mds") || name.contains("spotlight") { return "Indiziert Dateien, damit Spotlight sie schnell findet." }

        switch classify(processName) {
        case .navigator: return "Lädt Webseiten, Tabs, Erweiterungen und Webvideos."
        case .messenger: return "Hält Nachrichten, Anrufe und Benachrichtigungen bereit."
        case .studio: return "Verarbeitet Musik, Bilder oder Videos für dich."
        case .workshop: return "Baut, prüft oder startet Entwicklungsprojekte."
        case .atelier: return "Rendert kreative Inhalte und hält Arbeitsflächen bereit."
        case .courier: return "Gleicht Dateien sicher mit einem Cloud-Dienst ab."
        case .guardian: return "Überwacht Verbindungen, Zugriffe und Sicherheit."
        case .engineRoom: return "Hält eine wichtige macOS-Funktion am Laufen."
        case .helper: return "Unterstützt eine App oder arbeitet unauffällig im Hintergrund."
        }
    }

    private static func contains(_ value: String, any candidates: [String]) -> Bool {
        candidates.contains { value.contains($0) }
    }
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

    var healthScore: Int {
        var score = 100.0
        score -= max(0, cpuPercent - 65) * 0.25
        score -= max(0, memoryPercent - 75) * 0.35
        score -= max(0, diskPercent - 80) * 0.55
        if let temperature = temperatureCelsius { score -= max(0, temperature - 85) * 0.8 }
        if thermalState == .serious || thermalState == .critical { score -= 12 }
        if smartStatus == .failing { score -= 30 }
        return Int(max(1, min(100, score)).rounded())
    }

    var healthText: String {
        switch healthScore {
        case 92...: "Ausgezeichnet"
        case 80...: "Sehr gut"
        case 65...: "In Ordnung"
        default: "Aufmerksamkeit nötig"
        }
    }
}

enum CleanupKind: String, CaseIterable, Codable, Identifiable {
    case caches
    case systemCaches
    case trash
    case logs
    case installers
    case developerData
    case browserCaches
    case packageCaches
    case projectArtifacts
    case appRemnants

    var id: String { rawValue }

    /// Nur der Papierkorb wird endgültig geleert; alles andere geht in den Papierkorb.
    var isPermanent: Bool { self == .trash }

    var title: String {
        switch self {
        case .caches: "App-Caches"
        case .systemCaches: "System-Caches"
        case .trash: "Papierkorb"
        case .logs: "Protokolle"
        case .installers: "Alte Downloads"
        case .developerData: "Xcode-Daten"
        case .browserCaches: "Browser-Caches"
        case .packageCaches: "Paket-Caches"
        case .projectArtifacts: "Projekt-Artefakte"
        case .appRemnants: "App-Rückstände"
        }
    }

    var detail: String {
        switch self {
        case .caches: "Temporäre App-Dateien, älter als 14 Tage. Werden beim nächsten Start neu erstellt."
        case .systemCaches: "Von macOS verwaltete Caches. Werden automatisch neu erstellt."
        case .trash: "Leert den Papierkorb endgültig."
        case .logs: "Protokoll- und Absturzdateien, älter als 14 Tage"
        case .installers: "DMG-, PKG-, ISO-, XIP- und ZIP-Dateien in Downloads und auf dem Schreibtisch, älter als 30 Tage"
        case .developerData: "Alte Derived-Data-Ordner von Xcode"
        case .browserCaches: "Safari, Chrome, Edge, Brave, Firefox – nur wenn der Browser geschlossen ist"
        case .packageCaches: "Downloads von npm, pnpm, pip, Gradle und Homebrew, älter als 14 Tage"
        case .projectArtifacts: "Wiederherstellbare Build-Ordner wie node_modules oder .build"
        case .appRemnants: "Einstellungen, Caches und Daten deinstallierter Apps"
        }
    }

    var icon: String {
        switch self {
        case .caches: "shippingbox.fill"
        case .systemCaches: "gearshape.fill"
        case .trash: "trash.fill"
        case .logs: "doc.text.magnifyingglass"
        case .installers: "arrow.down.doc.fill"
        case .developerData: "hammer.fill"
        case .browserCaches: "globe"
        case .packageCaches: "archivebox.fill"
        case .projectArtifacts: "shippingbox.and.arrow.backward.fill"
        case .appRemnants: "trash.slash.fill"
        }
    }
}

struct CleanupItem: Identifiable, Hashable {
    let url: URL
    let bytes: Int64
    var isSelected: Bool
    /// Gesperrt, solange die zugehörige App läuft (z. B. ein geöffneter Browser).
    var isLocked = false
    var isRecommended = true
    var ownerName: String?

    var id: URL { url }
    var displayName: String { ownerName ?? url.lastPathComponent }

    var locationName: String {
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
