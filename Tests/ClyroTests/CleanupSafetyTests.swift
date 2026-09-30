import XCTest
@testable import Clyro

/// Clyro löscht endgültig. Diese Tests sichern die Schutzregeln ab, damit nie etwas Wichtiges vorgeschlagen wird.
final class CleanupProtectionTests: XCTestCase {
    func testPasswordManagersAreProtected() {
        for identifier in [
            "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
            "org.keepassxc.keepassxc", "com.lastpass.LastPass", "com.dashlane.Dashlane", "com.yubico.yubioath"
        ] {
            XCTAssertTrue(CleanupProtection.isProtected(identifier), identifier)
            XCTAssertTrue(CleanupProtection.isProtectedBundle(identifier), identifier)
        }
    }

    func testSystemInputAndSecurityAreProtected() {
        for identifier in [
            "com.apple.Safari", "com.apple.inputmethod.Kotoeri", "com.sogou.inputmethod.pinyin",
            "com.crowdstrike.falcon.App", "com.jamf.management.service", "com.docker.docker",
            "com.parallels.desktop.console", "com.vmware.fusion", "com.adobe.acc.AdobeCreativeCloud",
            "com.dropbox.client", "dev.meb99.Clyro"
        ] {
            XCTAssertTrue(CleanupProtection.isProtected(identifier), identifier)
        }
    }

    func testVPNClientsAreProtected() {
        for name in ["com.wireguard.macos", "io.tailscale.ipn.macos", "com.nordvpn.macos", "ch.protonvpn.mac", "net.mullvad.vpn"] {
            XCTAssertTrue(CleanupProtection.isProtected(name), name)
        }
    }

    func testKeysAndMicrosoftServicesNeverCountAsOrphans() {
        for identifier in ["org.gnupg.gpg-agent", "com.openssh.ssh-agent", "com.microsoft.autoupdate2", "com.apple.Music", "org.cups.printers"] {
            XCTAssertTrue(CleanupProtection.isProtectedBundle(identifier), identifier)
        }
    }

    func testOrdinaryAppsAreNotProtected() {
        for identifier in ["com.spotify.client", "com.tinyspeck.slackmacgap", "org.mozilla.firefox", "com.hnc.Discord"] {
            XCTAssertFalse(CleanupProtection.isProtected(identifier), identifier)
            XCTAssertFalse(CleanupProtection.isProtectedBundle(identifier), identifier)
        }
    }

    func testMatchingIgnoresCase() {
        XCTAssertTrue(CleanupProtection.isProtected("COM.APPLE.SAFARI"))
        XCTAssertTrue(CleanupProtection.isProtectedBundle("Com.1Password.1Password"))
    }
}

final class CleanupRuleSafetyTests: XCTestCase {
    /// Orte mit persönlichen Daten, die keine Regel je berühren darf.
    private let forbidden = [
        "Documents", "Desktop", "Pictures", "Movies", "Music", ".ssh", ".gnupg",
        "Library/Keychains", "Library/Mail", "Library/Messages", "Library/Photos", "Library/Mobile Documents",
        "Library/Application Support/MobileSync", "Library/Accounts", "Library/Cookies", "Library/Calendars",
        "Library/Safari/Bookmarks.plist", "Library/Containers/com.apple.mail"
    ]

    private var allRules: [CleanupRule] {
        CleanupRules.browsers + CleanupRules.ai + CleanupRules.developer
            + CleanupRules.system + CleanupRules.other + CleanupRules.appSupport
    }

    func testRulesExist() {
        XCTAssertGreaterThan(allRules.count, 20)
    }

    func testNoRuleTouchesPersonalData() {
        for rule in allRules {
            for raw in rule.paths {
                let path = raw.hasSuffix("/*") ? String(raw.dropLast(2)) : raw
                let relative = path.hasPrefix("~/") ? String(path.dropFirst(2)) : path
                // Ausnahme: reine Cache-Unterordner, z. B. Nachrichten-Vorschauen oder Movies/CacheClip.
                let isCacheFolder = relative.split(separator: "/").contains { $0.lowercased().contains("cache") }
                for place in forbidden {
                    let hitsPlace = relative == place || relative.hasPrefix(place + "/")
                    XCTAssertFalse(hitsPlace && !isCacheFolder, "\(rule.label): \(raw) liegt in \(place)")
                }
            }
        }
    }

    func testNoRuleDeletesWholeTopLevelFolders() {
        let tooBroad: Set<String> = ["", "/", "Library", "Library/Caches", "Library/Application Support", "Library/Containers",
                                     "Library/Group Containers", "Library/Preferences", ".config", ".local", ".cache"]
        for rule in allRules {
            for raw in rule.paths {
                XCTAssertFalse(tooBroad.contains(raw), "\(rule.label): \(raw) würde einen ganzen Stammordner löschen")
            }
        }
    }

    func testNoRuleUsesAbsoluteSystemPaths() {
        for rule in allRules {
            for raw in rule.paths where raw.hasPrefix("/") {
                XCTAssertFalse(raw.hasPrefix("/System") || raw.hasPrefix("/usr") || raw.hasPrefix("/bin") || raw.hasPrefix("/Applications"),
                               "\(rule.label): \(raw)")
            }
        }
    }
}

final class WhitelistTests: XCTestCase {
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func testNameMatchesAnyPathComponentIgnoringCase() {
        let url = home.appendingPathComponent("Library/Caches/com.spotify.client/Data")
        XCTAssertTrue(CleanupWhitelist.matches(url, entries: ["COM.SPOTIFY.CLIENT"]))
        XCTAssertTrue(CleanupWhitelist.matches(url, entries: ["com.spotify.*"]))
        XCTAssertFalse(CleanupWhitelist.matches(url, entries: ["com.slack"]))
    }

    func testPathEntriesExpandTildeAndCoverChildren() {
        let url = home.appendingPathComponent("Library/Caches/Foo Bar/cache.db")
        XCTAssertTrue(CleanupWhitelist.matches(url, entries: ["~/Library/Caches/Foo Bar"]))
        XCTAssertTrue(CleanupWhitelist.matches(url, entries: ["~/Library/Caches/Foo*"]))
        XCTAssertFalse(CleanupWhitelist.matches(url, entries: ["~/Library/Caches/Other"]))
    }

    func testEmptyWhitelistMatchesNothing() {
        XCTAssertFalse(CleanupWhitelist.matches(home.appendingPathComponent("Library/Caches/x"), entries: []))
    }
}

final class BundleIDTests: XCTestCase {
    func testReverseDNS() {
        XCTAssertTrue(BundleID.isReverseDNS("com.example.app"))
        XCTAssertTrue(BundleID.isReverseDNS("dev.meb99.Clyro"))
        XCTAssertFalse(BundleID.isReverseDNS("Google"))
        XCTAssertFalse(BundleID.isReverseDNS("com.example"))
        XCTAssertFalse(BundleID.isReverseDNS("xyz.example.app"))
        XCTAssertFalse(BundleID.isReverseDNS("com.exa mple.app"))
    }
}

final class UninstallProtectionTests: XCTestCase {
    private func app(_ identifier: String, path: String = "/Applications/Test.app") -> InstalledApplication {
        InstalledApplication(url: URL(fileURLWithPath: path), name: "Test", version: "1.0", bundleIdentifier: identifier, sizeBytes: 1)
    }

    func testSystemAppsCannotBeUninstalled() {
        XCTAssertNotNil(AppRemnantProbe.protectionReason(app("com.apple.Safari")))
        XCTAssertNotNil(AppRemnantProbe.protectionReason(app("com.apple.mail")))
        XCTAssertNotNil(AppRemnantProbe.protectionReason(app("com.example.tool", path: "/System/Applications/Tool.app")))
    }

    func testSecuritySoftwareNeedsVendorUninstaller() {
        XCTAssertNotNil(AppRemnantProbe.protectionReason(app("com.crowdstrike.falcon.App")))
        XCTAssertNotNil(AppRemnantProbe.protectionReason(app("com.jamf.management.Jamf")))
    }

    func testRemovableAppleAndThirdPartyApps() {
        XCTAssertNil(AppRemnantProbe.protectionReason(app("com.apple.dt.Xcode")))
        XCTAssertNil(AppRemnantProbe.protectionReason(app("com.apple.iWork.Keynote")))
        XCTAssertNil(AppRemnantProbe.protectionReason(app("com.spotify.client")))
    }
}

final class ProjectArtifactSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClyroTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func folder(_ path: String, containing files: [String] = []) throws -> URL {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        for file in files {
            let fileURL = url.appendingPathComponent(file)
            if file.hasSuffix("/") {
                try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: true)
            } else {
                FileManager.default.createFile(atPath: fileURL.path, contents: Data("x".utf8))
            }
        }
        return url
    }

    func testPlainNodeModulesIsSafe() throws {
        let url = try folder("web/node_modules", containing: ["left-pad/"])
        XCTAssertTrue(ProjectPurgeProbe.isSafeArtifact(url, name: "node_modules", siblings: ["package.json"]))
    }

    func testNestedGitRepositoryIsNeverPurged() throws {
        let url = try folder("web/node_modules", containing: [".git/"])
        XCTAssertFalse(ProjectPurgeProbe.isSafeArtifact(url, name: "node_modules", siblings: ["package.json"]))
    }

    func testDeploymentKeysBlockPurge() throws {
        for key in ["id_rsa", "id_ed25519", "server.pem", "cert.p12", "private.key"] {
            let url = try folder("app-\(key)/build", containing: [key])
            XCTAssertFalse(ProjectPurgeProbe.isSafeArtifact(url, name: "build", siblings: ["package.json"]), key)
        }
    }

    func testBinOnlyForDotNetProjects() throws {
        let url = try folder("tool/bin", containing: ["run"])
        XCTAssertFalse(ProjectPurgeProbe.isSafeArtifact(url, name: "bin", siblings: ["Makefile"]))
        XCTAssertTrue(ProjectPurgeProbe.isSafeArtifact(url, name: "bin", siblings: ["Tool.csproj"]))
    }

    func testVendorOnlyForComposerNotGo() throws {
        let url = try folder("php/vendor", containing: ["autoload.php"])
        XCTAssertTrue(ProjectPurgeProbe.isSafeArtifact(url, name: "vendor", siblings: ["composer.json"]))
        XCTAssertFalse(ProjectPurgeProbe.isSafeArtifact(url, name: "vendor", siblings: ["composer.json", "go.mod"]))
        XCTAssertFalse(ProjectPurgeProbe.isSafeArtifact(url, name: "vendor", siblings: ["go.mod"]))
    }
}

final class AdminCleanupTests: XCTestCase {
    func testFamiliesStayInSystemCacheAndLogLocations() {
        for family in AdminCleanup.families {
            XCTAssertTrue(family.root.hasPrefix("/Library/") || family.root.hasPrefix("/private/var/"), family.root)
            XCTAssertFalse(family.root.hasPrefix("/private/var/folders"), family.root)
            XCTAssertGreaterThanOrEqual(family.days, 7, family.id)
            XCTAssertFalse(family.patterns.isEmpty, family.id)
        }
    }

    func testShellQuotingHandlesQuotes() {
        XCTAssertEqual(AdminShell.quote("/Library/Caches"), "'/Library/Caches'")
        XCTAssertEqual(AdminShell.quote("a'b"), "'a'\\''b'")
    }
}

final class HealthScoreTests: XCTestCase {
    func testIdleMacIsExcellent() {
        var snapshot = SystemSnapshot()
        snapshot.uptime = 3600
        snapshot.memoryTotalBytes = 16_000_000_000
        snapshot.memoryUsedBytes = 6_000_000_000
        snapshot.diskTotalBytes = 500_000_000_000
        snapshot.diskUsedBytes = 200_000_000_000
        XCTAssertEqual(snapshot.health.score, 100)
        XCTAssertTrue(snapshot.health.issues.isEmpty)
        XCTAssertEqual(snapshot.healthText, String(localized: "Ausgezeichnet"))
    }

    func testFailingSmartCapsScore() {
        var snapshot = SystemSnapshot()
        snapshot.uptime = 3600
        snapshot.smartStatus = .failing
        XCTAssertLessThanOrEqual(snapshot.health.score, 44)
        XCTAssertTrue(snapshot.health.issues.contains(String(localized: "SMART meldet Fehler")))
    }

    func testFullDiskAndHotCPUAreReported() {
        var snapshot = SystemSnapshot()
        snapshot.uptime = 3600
        snapshot.cpuPercent = 95
        snapshot.diskTotalBytes = 100
        snapshot.diskUsedBytes = 97
        let health = snapshot.health
        XCTAssertTrue(health.issues.contains(String(localized: "Hohe CPU-Last")))
        XCTAssertTrue(health.issues.contains(String(localized: "Festplatte fast voll")))
        XCTAssertLessThan(health.score, 85)
    }
}

final class VersionTests: XCTestCase {
    func testNumericComparison() {
        XCTAssertTrue(Version.isNewer("1.10", than: "1.9"))
        XCTAssertTrue(Version.isNewer("2.0", than: "1.99.9"))
        XCTAssertFalse(Version.isNewer("1.0", than: "1.0.0"))
        XCTAssertFalse(Version.isNewer("1.2", than: "1.3"))
        XCTAssertFalse(Version.isNewer("", than: "1.0"))
    }
}

final class MaintenanceScheduleTests: XCTestCase {
    func testAutomaticTasksExistAndNeverRestartTheInterface() {
        let ids = Set(OptimizeCatalog.tasks.map(\.id))
        XCTAssertTrue(OptimizeCatalog.automaticIDs.isSubset(of: ids))
        for restart in ["dock", "menubar", "control-center", "notification-center", "spotlight", "pasteboard", "input", "font-cache"] {
            XCTAssertFalse(OptimizeCatalog.automaticIDs.contains(restart), restart)
        }
    }

    func testTaskIDsAreUnique() {
        let ids = OptimizeCatalog.tasks.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }
}
