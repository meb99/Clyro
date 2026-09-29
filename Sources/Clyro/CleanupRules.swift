import AppKit
import Darwin
import Foundation

// MARK: - Whitelist

enum CleanupWhitelist {
    static let defaultsKey = "cleanupWhitelist"

    /// Ein Eintrag pro Zeile: ein Name (z. B. com.spotify.client) oder ein Pfad mit Platzhaltern (z. B. ~/Library/Caches/Foo*).
    static func entries() -> [String] {
        let raw = UserDefaults.standard.string(forKey: defaultsKey) ?? ""
        return raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    static func matches(_ url: URL) -> Bool {
        matches(url, entries: entries())
    }

    static func matches(_ url: URL, entries: [String]) -> Bool {
        guard !entries.isEmpty else { return false }
        let path = url.standardizedFileURL.path
        let components = path.split(separator: "/").map { $0.lowercased() }
        for entry in entries {
            if entry.contains("/") {
                let pattern = (entry as NSString).expandingTildeInPath
                if path == pattern || path.hasPrefix(pattern.hasSuffix("/") ? pattern : pattern + "/") { return true }
                if fnmatch(pattern, path, 0) == 0 { return true }
            } else {
                let name = entry.lowercased()
                if components.contains(where: { $0 == name || fnmatch(name, $0, 0) == 0 }) { return true }
            }
        }
        return false
    }
}

// MARK: - Regeln

/// Eine Gruppe von Pfaden, die als ein Eintrag in einer Kategorie erscheint.
/// Pfade sind relativ zum Home-Ordner (oder absolut) und dürfen `*` enthalten. Endet ein Pfad auf `/*`,
/// wird der Inhalt des Ordners gelöscht, der Ordner selbst bleibt.
struct CleanupRule {
    let kind: CleanupKind
    let label: String
    let paths: [String]
    var owners: [String] = []
    var recommended = true
}

enum CleanupRules {
    static let browsers: [CleanupRule] = [
        CleanupRule(kind: .browserCaches, label: "Safari-Cache", paths: ["Library/Caches/com.apple.Safari/*"],
                    owners: ["com.apple.Safari"]),
        CleanupRule(kind: .browserCaches, label: "Chrome-Cache", paths: CleanupRules.chromium("Library/Application Support/Google/Chrome")
                        + ["Library/Caches/Google/Chrome/*",
                           "Library/Application Support/Google/Chrome/*/Application Cache/*",
                           "Library/Application Support/Google/Chrome/OptGuideOnDeviceModel/*",
                           "Library/Application Support/Google/GoogleUpdater/crx_cache/*"],
                    owners: ["com.google.Chrome"]),
        CleanupRule(kind: .browserCaches, label: "Chromium-Cache", paths: ["Library/Caches/Chromium/*"],
                    owners: ["org.chromium.Chromium"]),
        CleanupRule(kind: .browserCaches, label: "Edge-Cache", paths: CleanupRules.chromium("Library/Application Support/Microsoft Edge")
                        + ["Library/Caches/com.microsoft.edgemac/*", "Library/Caches/Microsoft Edge/*"],
                    owners: ["com.microsoft.edgemac"]),
        CleanupRule(kind: .browserCaches, label: "Arc-Cache", paths: CleanupRules.chromium("Library/Application Support/Arc/User Data")
                        + ["Library/Caches/company.thebrowser.Browser/*"],
                    owners: ["company.thebrowser.Browser"]),
        CleanupRule(kind: .browserCaches, label: "Dia-Cache", paths: CleanupRules.chromium("Library/Application Support/Dia/User Data")
                        + ["Library/Caches/company.thebrowser.dia/*", "Library/Caches/Dia/User Data/*/Cache/*",
                           "Library/Caches/Dia/User Data/*/Code Cache/*"],
                    owners: ["company.thebrowser.dia"]),
        CleanupRule(kind: .browserCaches, label: "Brave-Cache", paths: CleanupRules.chromium("Library/Application Support/BraveSoftware/Brave-Browser")
                        + ["Library/Caches/BraveSoftware/Brave-Browser/*"],
                    owners: ["com.brave.Browser"]),
        CleanupRule(kind: .browserCaches, label: "Firefox-Cache", paths: ["Library/Caches/Firefox/*",
                                                                          "Library/Application Support/Firefox/Profiles/*/cache2/*"],
                    owners: ["org.mozilla.firefox"]),
        CleanupRule(kind: .browserCaches, label: "Opera-Cache", paths: ["Library/Caches/com.operasoftware.Opera/*"],
                    owners: ["com.operasoftware.Opera"]),
        CleanupRule(kind: .browserCaches, label: "Vivaldi-Cache", paths: CleanupRules.chromium("Library/Application Support/Vivaldi")
                        + ["Library/Caches/com.vivaldi.Vivaldi/*"],
                    owners: ["com.vivaldi.Vivaldi"]),
        CleanupRule(kind: .browserCaches, label: "Zen-Cache", paths: ["Library/Caches/zen/*"], owners: ["app.zen-browser.zen"]),
        CleanupRule(kind: .browserCaches, label: "Orion-Cache", paths: ["Library/Caches/com.kagi.kagimacOS/*"],
                    owners: ["com.kagi.kagimacOS"]),
        CleanupRule(kind: .browserCaches, label: "Helium-Cache", paths: CleanupRules.chromium("Library/Application Support/net.imput.helium")
                        + ["Library/Caches/net.imput.helium/*"],
                    owners: ["net.imput.helium"]),
        CleanupRule(kind: .browserCaches, label: "Comet-Cache", paths: ["Library/Caches/Comet/*"], owners: ["ai.perplexity.comet"]),
        CleanupRule(kind: .browserCaches, label: "Yandex-Cache", paths: ["Library/Caches/Yandex/YandexBrowser/*"],
                    owners: ["ru.yandex.desktop.yandex-browser"])
    ]

    /// Wiederherstellbare Chromium-Caches innerhalb eines Profilordners.
    static func chromium(_ root: String) -> [String] {
        ["Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "GraphiteDawnCache"]
            .map { "\(root)/*/\($0)/*" }
            + ["ShaderCache", "GrShaderCache", "GraphiteDawnCache", "component_crx_cache", "extensions_crx_cache", "Crashpad/completed"]
            .map { "\(root)/\($0)/*" }
    }

    static let ai: [CleanupRule] = [
        CleanupRule(kind: .aiTools, label: "ChatGPT-Cache", paths: ["Library/Caches/com.openai.chat/*"], owners: ["com.openai.chat"]),
        CleanupRule(kind: .aiTools, label: "Claude-Cache", paths: [
            "Library/Caches/com.anthropic.claudefordesktop/*",
            "Library/Application Support/Claude/Cache/*",
            "Library/Application Support/Claude/Code Cache/*",
            "Library/Application Support/Claude/GPUCache/*",
            "Library/Application Support/Claude/DawnGraphiteCache/*",
            "Library/Application Support/Claude/DawnWebGPUCache/*",
            "Library/Application Support/Claude/sentry/*"
        ], owners: ["com.anthropic.claudefordesktop"]),
        CleanupRule(kind: .aiTools, label: "Claude-Protokolle", paths: ["Library/Logs/Claude/*"]),
        CleanupRule(kind: .aiTools, label: "Codex-Browsercache", paths: [
            "Library/Caches/Codex/Default/Cache/*",
            "Library/Caches/Codex/Default/Code Cache/*",
            "Library/Caches/Codex/codex-browser-app/Cache/*",
            "Library/Caches/Codex/codex-browser-app/Code Cache/*"
        ], owners: ["com.openai.codex"]),
        CleanupRule(kind: .aiTools, label: "LM-Studio-Cache", paths: ["Library/Caches/com.lmstudio.lmstudio/*"],
                    owners: ["com.lmstudio.lmstudio"]),
        CleanupRule(kind: .aiTools, label: "Antigravity-Cache", paths: [
            "Library/Application Support/Antigravity/Cache/*",
            "Library/Application Support/Antigravity/Code Cache/*",
            "Library/Application Support/Antigravity/GPUCache/*"
        ]),
        CleanupRule(kind: .aiTools, label: "Qoder-Cache", paths: [
            "Library/Application Support/Qoder/Cache/*",
            "Library/Application Support/Qoder/CachedData/*",
            "Library/Application Support/Qoder/Code Cache/*",
            "Library/Application Support/Qoder/GPUCache/*",
            "Library/Application Support/Qoder/logs/*"
        ]),
        CleanupRule(kind: .aiTools, label: "OpenCode-Cache", paths: [".cache/opencode/*"]),
        CleanupRule(kind: .aiTools, label: "Prisma-Cache", paths: [".cache/prisma/*"])
    ]

    static let developer: [CleanupRule] = [
        CleanupRule(kind: .developerData, label: "Xcode DerivedData", paths: ["Library/Developer/Xcode/DerivedData/*"],
                    owners: ["com.apple.dt.Xcode"]),
        CleanupRule(kind: .developerData, label: "Simulator-Caches", paths: ["Library/Developer/CoreSimulator/Caches/*"],
                    owners: ["com.apple.iphonesimulator"]),
        CleanupRule(kind: .developerData, label: "Swift Package Manager", paths: ["Library/Caches/org.swift.swiftpm/*",
                                                                                  ".cache/swift-package-manager/*"]),
        CleanupRule(kind: .developerData, label: "CocoaPods", paths: ["Library/Caches/CocoaPods/*"]),
        CleanupRule(kind: .developerData, label: "npm", paths: [".npm/_cacache/*", ".npm/_logs/*", ".tnpm/_cacache/*"]),
        CleanupRule(kind: .developerData, label: "Yarn", paths: [".yarn/cache/*", "Library/Caches/Yarn/*"]),
        CleanupRule(kind: .developerData, label: "pnpm", paths: ["Library/pnpm/store/*", ".local/share/pnpm/store/*"]),
        CleanupRule(kind: .developerData, label: "Bun", paths: [".bun/install/cache/*"]),
        CleanupRule(kind: .developerData, label: "Node-Werkzeuge", paths: [
            ".cache/typescript/*", ".cache/electron/*", ".cache/node-gyp/*", ".node-gyp/*",
            ".turbo/cache/*", ".vite/cache/*", ".cache/vite/*", ".cache/webpack/*", ".parcel-cache/*",
            ".cache/eslint/*", ".cache/prettier/*", ".cache/puppeteer/*"
        ]),
        CleanupRule(kind: .developerData, label: "Python (pip, Poetry, uv)", paths: [
            "Library/Caches/pip/*", ".cache/pip/*", ".cache/poetry/*", "Library/Caches/pypoetry/artifacts/*",
            "Library/Caches/pypoetry/cache/*", ".cache/uv/*", ".pyenv/cache/*", ".cache/ruff/*", ".cache/mypy/*",
            ".jupyter/runtime/*"
        ]),
        CleanupRule(kind: .developerData, label: "Go Build-Cache", paths: ["Library/Caches/go-build/*"]),
        CleanupRule(kind: .developerData, label: "Rust (Cargo)", paths: [".cargo/registry/cache/*"]),
        CleanupRule(kind: .developerData, label: "Ruby (Gems, Bundler)", paths: [".gem/specs/*", ".bundle/cache/*", ".rbenv/cache/*"]),
        CleanupRule(kind: .developerData, label: "Gradle", paths: [".gradle/caches/*"]),
        CleanupRule(kind: .developerData, label: "Android", paths: [".android/build-cache/*", ".android/cache/*",
                                                                    "Library/Caches/Google/AndroidStudio*/*", ".cache/flutter/*"]),
        CleanupRule(kind: .developerData, label: "PHP Composer", paths: ["Library/Caches/composer/*", ".composer/cache/*"]),
        CleanupRule(kind: .developerData, label: "Homebrew", paths: ["Library/Caches/Homebrew/downloads/*"]),
        CleanupRule(kind: .developerData, label: "Container & Cloud", paths: [
            ".docker/buildx/cache/*", ".kube/cache/*", ".local/share/containers/storage/tmp/*",
            ".aws/cli/cache/*", ".config/gcloud/logs/*", ".azure/logs/*", ".cache/terraform/*", ".cache/bazel/*", ".cache/zig/*"
        ]),
        CleanupRule(kind: .developerData, label: "VS Code", paths: [
            "Library/Application Support/Code/Cache/*", "Library/Application Support/Code/CachedData/*",
            "Library/Application Support/Code/CachedExtensions/*", "Library/Application Support/Code/CachedExtensionVSIXs/*",
            "Library/Application Support/Code/logs/*", "Library/Application Support/Code/WebStorage/*/CacheStorage/*"
        ], owners: ["com.microsoft.VSCode"]),
        CleanupRule(kind: .developerData, label: "Cursor", paths: [
            "Library/Application Support/Cursor/Cache/*", "Library/Application Support/Cursor/CachedData/*",
            "Library/Application Support/Cursor/CachedExtensionVSIXs/*", "Library/Application Support/Cursor/Code Cache/*",
            "Library/Application Support/Cursor/GPUCache/*", "Library/Application Support/Cursor/logs/*"
        ], owners: ["com.todesktop.230313mzl4w4u92"]),
        CleanupRule(kind: .developerData, label: "Zed", paths: ["Library/Caches/Zed/*", "Library/Logs/Zed/*",
                                                                "Library/Application Support/Zed/node/cache/*"],
                    owners: ["dev.zed.Zed"]),
        CleanupRule(kind: .developerData, label: "Sublime Text", paths: ["Library/Caches/com.sublimetext.*/*"]),
        CleanupRule(kind: .developerData, label: "JetBrains-Protokolle", paths: ["Library/Logs/JetBrains/*"]),
        CleanupRule(kind: .developerData, label: "Entwickler-Apps", paths: [
            "Library/Caches/com.postmanlabs.mac/*", "Library/Caches/com.konghq.insomnia/*",
            "Library/Caches/com.tinyapp.TablePlus/*", "Library/Caches/com.sequel-ace.sequel-ace/*",
            "Library/Caches/com.github.GitHubDesktop/*", "Library/Caches/com.mongodb.compass/*",
            "Library/Caches/com.charlesproxy.charles/*", "Library/Caches/com.proxyman.NSProxy/*",
            "Library/Caches/com.unity3d.*/*"
        ]),
        CleanupRule(kind: .developerData, label: "Shell & Git", paths: [
            ".oh-my-zsh/cache/*", ".cache/pre-commit/*", ".zcompdump*", ".gitconfig.bak*", ".cache/curl/*", ".cache/wget/*"
        ])
    ]

    static let system: [CleanupRule] = [
        CleanupRule(kind: .systemCaches, label: "Quick-Look-Miniaturen", paths: [
            "Library/Caches/com.apple.QuickLook.thumbnailcache", "Library/Caches/Quick Look/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "Symbol-Cache", paths: ["Library/Caches/com.apple.iconservices*"]),
        CleanupRule(kind: .systemCaches, label: "WebKit-Netzwerkcache", paths: ["Library/Caches/com.apple.WebKit.Networking/*"]),
        CleanupRule(kind: .systemCaches, label: "Foto-Analyse-Cache", paths: [
            "Library/Caches/com.apple.photoanalysisd",
            "Library/Containers/com.apple.mediaanalysisd/Data/Library/Caches/*",
            "Library/Containers/com.apple.mediaanalysisd/Data/tmp/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "App Store & Medien", paths: [
            "Library/Containers/com.apple.AppStore/Data/Library/Caches/*",
            "Library/Caches/com.apple.AppleMediaServices/*",
            "Library/Containers/com.apple.AppleMediaServicesUI.UtilityExtension/Data/tmp/*",
            "Library/Containers/com.apple.AMPArtworkAgent/Data/Library/Caches/*",
            "Library/Caches/com.apple.amp.mediasevicesd"
        ]),
        CleanupRule(kind: .systemCaches, label: "Karten & Orte", paths: [
            "Library/Caches/GeoServices/*", "Library/Containers/com.apple.geod/Data/tmp/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "Hilfe & Vorschläge", paths: [
            "Library/Caches/com.apple.helpd/*", "Library/Suggestions/*",
            "Library/Caches/com.apple.duetexpertd/*", "Library/Caches/com.apple.parsecd/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "Hintergrundbilder & Memoji", paths: [
            "Library/Containers/com.apple.wallpaper.agent/Data/Library/Caches/*",
            "Library/Containers/com.apple.wallpaper.extension.aerials/Data/tmp/*",
            "Library/Containers/com.apple.AvatarUI.AvatarPickerMemojiPicker/Data/Library/Caches/*"
        ]),
        CleanupRule(kind: .systemCaches, label: "Weitere Systemdienste", paths: [
            "Library/Caches/com.apple.akd",
            "Library/Caches/com.apple.python/*",
            "Library/Caches/com.apple.rosetta.update",
            "Library/Containers/com.apple.stocks/Data/Library/Caches/*",
            "Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/*",
            "Library/Containers/com.apple.NeptuneOneExtension/Data/Library/Caches/*",
            "Library/Containers/com.apple.configurator.xpc.InternetService/Data/tmp/*",
            "Library/Application Support/AddressBook/Sources/*/Photos.cache"
        ])
    ]

    static let other: [CleanupRule] = [
        CleanupRule(kind: .other, label: "Diagnoseberichte", paths: ["Library/Logs/DiagnosticReports/*", "Library/DiagnosticReports/*"]),
        CleanupRule(kind: .other, label: "Gespeicherte App-Zustände", paths: ["Library/Saved Application State/*"]),
        CleanupRule(kind: .other, label: "Absturzberichte", paths: [
            "Library/Caches/SentryCrash/*", "Library/Caches/KSCrash/*", "Library/Caches/com.crashlytics.data/*"
        ]),
        CleanupRule(kind: .other, label: "Nachrichten-Vorschauen", paths: [
            "Library/Messages/StickerCache/*",
            "Library/Messages/Caches/Previews/Attachments/*",
            "Library/Messages/Caches/Previews/StickerCache/*"
        ])
    ]

    /// App-Caches außerhalb von ~/Library/Caches, die gezielt geleert werden.
    static let appSupport: [CleanupRule] = [
        CleanupRule(kind: .caches, label: "Discord", paths: ["Library/Application Support/discord/Cache/*",
                                                             "Library/Application Support/discord/Code Cache/*"],
                    owners: ["com.hnc.Discord"]),
        CleanupRule(kind: .caches, label: "Slack", paths: ["Library/Application Support/Slack/Cache/*",
                                                           "Library/Application Support/Slack/Code Cache/*"],
                    owners: ["com.tinyspeck.slackmacgap"]),
        CleanupRule(kind: .caches, label: "Microsoft Teams (klassisch)", paths: [
            "Library/Application Support/Microsoft/Teams/Cache/*",
            "Library/Application Support/Microsoft/Teams/Code Cache/*",
            "Library/Application Support/Microsoft/Teams/GPUCache/*",
            "Library/Application Support/Microsoft/Teams/logs/*"
        ], owners: ["com.microsoft.teams"]),
        CleanupRule(kind: .caches, label: "Steam", paths: [
            "Library/Application Support/Steam/htmlcache/*", "Library/Application Support/Steam/appcache/*",
            "Library/Application Support/Steam/depotcache/*", "Library/Application Support/Steam/steamapps/shadercache/*",
            "Library/Application Support/Steam/logs/*"
        ], owners: ["com.valvesoftware.steam"]),
        CleanupRule(kind: .caches, label: "Battle.net", paths: ["Library/Application Support/Battle.net/Cache/*"],
                    owners: ["net.battle.app"]),
        CleanupRule(kind: .caches, label: "Minecraft", paths: [
            "Library/Application Support/minecraft/logs/*", "Library/Application Support/minecraft/webcache/*",
            "Library/Application Support/minecraft/webcache2/*", "Library/Application Support/minecraft/crash-reports/*"
        ]),
        CleanupRule(kind: .caches, label: "Adobe", paths: [
            "Library/Caches/Adobe/*", "Library/Caches/com.adobe.*/*",
            "Library/Application Support/Adobe/Common/Media Cache Files/*"
        ]),
        CleanupRule(kind: .caches, label: "DaVinci Resolve CacheClip", paths: ["Movies/CacheClip/*"],
                    owners: ["com.blackmagic-design.DaVinciResolve"]),
        CleanupRule(kind: .caches, label: "Spotify", paths: ["Library/Application Support/Spotify/PersistentCache/Storage/*"],
                    owners: ["com.spotify.client"])
    ]
}

// MARK: - Schutzlisten

enum CleanupProtection {
    /// Ordnernamen in ~/Library/Caches und ~/Library/Containers, die nie pauschal geleert werden
    /// (Eingabemethoden, Passwortmanager, Sicherheit, VPN, Lizenzen, virtuelle Maschinen …).
    static let protectedPatterns: [String] = [
        "com.apple.*", "*inputmethod*", "*ime", "com.sogou.*", "im.rime.*", "com.googlecode.rimeime.*",
        "com.nektony.*", "com.macpaw.*", "com.freemacsoft.appcleaner", "com.daisydiskapp.*",
        "com.1password.*", "com.agilebits.*", "com.lastpass.*", "com.dashlane.*", "com.bitwarden.*",
        "org.keepassxc.*", "com.keepassx.*", "com.authy.*", "com.yubico.*",
        "com.jetbrains.*", "jetbrains*", "com.microsoft.vscode*", "com.todesktop.*", "cursor",
        "com.anthropic.claude*", "claude", "com.openai.*", "chatgpt", "codex", "com.ollama.ollama", "ollama",
        "com.lmstudio.lmstudio",
        "*clash*", "*surge*", "*v2ray*", "*openvpn*", "*wireguard*", "*tailscale*", "*zerotier*", "*nordvpn*",
        "*expressvpn*", "*protonvpn*", "*mullvad*", "*surfshark*", "*windscribe*", "*cloudflare*warp*", "*1dot1dot1dot1*",
        "com.docker.*", "dev.orbstack.*", "com.getutm.utm", "com.utmapp.utm", "com.vmware.fusion", "com.parallels.*",
        "adobe", "adobe *", "* adobe*", "com.adobe.*",
        "com.crowdstrike.*", "com.sentinelone.*", "com.sentinel-labs.*", "com.eset.*", "com.jamf.*", "com.jamfsoftware.*",
        "com.paloaltonetworks.*", "com.cisco.anyconnect*", "com.cisco.secureclient*",
        "com.native-instruments*", "com.paceap.*", "com.avid.*", "com.izotope.*", "com.lasersoft-imaging.*",
        "com.displaylink.*", "ms-playwright", "app.cotypist.cotypist", "familycircle", "gippseudonymousid",
        "cctclearcutlogger", "homebrew", "mole", "clyro", "dev.meb99.clyro",
        // Cloud-Sync und Backup
        "com.dropbox.*", "com.getdropbox.*", "*dropbox*", "ws.agile.*", "com.backblaze.*", "*backblaze*", "com.box.desktop*",
        "com.microsoft.onedrive*", "com.microsoft.syncreporter", "*onedrive*", "com.google.googledrive", "com.google.keystone*",
        "*googledrive*", "com.amazon.drive", "com.synology.*", "com.shirtpocket.*", "com.digidna.imazing*",
        // Werkzeuge und Menüleisten-Apps
        "com.bjango.istatmenus*", "eu.exelban.stats", "com.monitorcontrol.*", "com.bresink.system-toolkit.*", "com.macitbetter.*",
        "com.hegenberg.*", "com.manytricks.*", "com.if.amphetamine", "com.lwouis.alt-tab-macos", "com.surteesstudios.bartender",
        "com.raycast.*", "com.raycast-x.*", "com.blacktree.quicksilver", "com.stairways.keyboardmaestro.*",
        "org.pqrs.karabiner-elements", "com.knollsoft.*", "com.amethyst.amethyst", "com.pointum.hazeover",
        "com.lightheadsw.caffeine", "com.contextual.contexts", "com.gaosun.eul", "net.matthewpalmer.vanilla",
        "com.pilotmoon.scroll-reverser", "com.happenapps.quitter",
        // Terminals und Git-Clients
        "com.googlecode.iterm2", "net.kovidgoyal.kitty", "io.alacritty", "com.github.wez.wezterm", "com.hyper.hyper",
        "com.termius-dmg", "com.sublimemerge", "com.torusknot.sourcetreenotmas", "com.git-tower.tower*", "com.fork.fork",
        "com.axosoft.gitkraken", "com.gitfox.gitfox",
        // Schreiben, Notizen, Aufgaben, Dateien
        "com.typora.*", "abnerworks.typora", "com.ulyssesapp.*", "com.literatureandlatte.*", "com.dayoneapp.*",
        "com.onenote.mac", "com.omnigroup.*", "com.goodnotes.goodnotes", "com.marginnote.*", "com.roamresearch.*",
        "com.reflect.reflectapp", "com.inkdrop.*", "com.coteditor.coteditor", "com.macromates.textmate", "com.panic.*",
        "com.uranusjr.macdown", "com.culturedcode.*", "com.ticktick.*", "com.microsoft.to-do", "com.trello.trello",
        "com.asana.nativeapp", "com.clickup.*", "com.monday.desktop", "com.airtable.airtable", "com.linear.linear",
        "com.binarynights.forklift*", "com.noodlesoft.hazel", "com.cyberduck.cyberduck", "io.filezilla.filezilla",
        "com.cisco.webexmeetings", "com.ringcentral.ringcentral", "com.postbox-inc.postbox",
        // Kreativ- und Audiosoftware
        "com.pixelmatorteam.*", "com.affinitydesigner.*", "com.affinityphoto.*", "com.affinitypublisher.*", "com.linearity.curve",
        "com.canva.canvadesktop", "com.autodesk.*", "com.fabfilter.*", "com.framerx.*", "com.zeplin.*", "com.invisionapp.*",
        "com.principle.*",
        // Bildschirm, Fernzugriff, Geräte
        "com.tunabellysoftware.*", "com.techsmith.*", "com.kap.kap", "com.getkap.*", "com.linebreak.cloudapp",
        "com.droplr.droplr-mac", "com.realvnc.*", "com.logmein.*", "org.chromium.chromoting*", "com.google.chrome_remote_desktop*",
        "com.citrix.*", "org.xquartz.*", "com.fujitsu.pfu.scansnap*",
        // Datenbanken und API-Werkzeuge ohne eigene Regel
        "com.valentina-db.*", "com.dbvis.dbvisualizer", "com.pgadmin.pgadmin4", "com.telerik.fiddler", "com.usebruno.app",
        // Wissenschaft, Finanzen, Lizenzen, Updater
        "com.mathworks.*", "com.ibm.spss.*", "com.wolfram.*", "com.stata.*", "org.rstudio.*", "com.tableausoftware.*",
        "com.quicken.*", "com.sas.*", "com.kolide.*", "com.setapp.desktopclient", "com.paddle.paddle*", "com.devmate.*",
        "org.sparkle-project.sparkle*", "homebrew.mxcl.*",
        // Weitere KI-Apps mit lokalen Daten
        "co.supertool.chatbox", "page.jan.jan", "com.huggingface.huggingchat", "gemini", "com.perplexity.perplexity",
        "com.drawthings.drawthings", "com.divamgupta.diffusionbee", "com.exafunction.windsurf", "com.quora.poe.electron",
        // Bildschirmschoner und virtuelle Maschinen
        "*aerial.saver", "com.johncoates.aerial*", "*fliqlo*", "com.orbstack.orbstack", "dev.kdrag0n.macvirt",
        "org.virtualbox.app.virtualbox", "com.vagrant.*"
    ]

    /// Zusätzlich nie als verwaist gewertet (Schlüssel, Signaturen, Microsoft-Dienste).
    private static let orphanNeverDelete: [String] = [
        "*1password*", "*keychain*", "*bitwarden*", "*lastpass*", "*keepass*", "*dashlane*", "*enpass*",
        "*ssh*", "*gpg*", "*gnupg*", "com.microsoft.*", "com.docker.*", "com.tencent.*"
    ]

    static func isProtected(_ name: String) -> Bool {
        let lower = name.lowercased()
        return protectedPatterns.contains { fnmatch($0, lower, 0) == 0 }
    }

    /// Namen, die nie als Rest einer deinstallierten App gelten.
    static func isProtectedBundle(_ identifier: String) -> Bool {
        let lower = identifier.lowercased()
        if lower.hasPrefix("com.apple.") || lower.hasPrefix("org.cups.") { return true }
        if orphanNeverDelete.contains(where: { fnmatch($0, lower, 0) == 0 }) { return true }
        return isProtected(lower)
    }
}
