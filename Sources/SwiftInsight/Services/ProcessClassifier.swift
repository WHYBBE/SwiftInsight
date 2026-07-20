import Foundation
import AppKit

/// 根据路径、Bundle ID、代码签名等区分 Apple 第一方与第三方进程
enum ProcessClassifier {

    // MARK: - 系统路径前缀（支持系统运行的核心组件）

    private static let systemPathPrefixes: [String] = [
        "/System/",
        "/usr/",
        "/bin/",
        "/sbin/",
        "/private/var/db/",
        "/Library/Apple/",
        "/Library/SystemExtensions/",
        "/Library/DriverExtensions/",
    ]

    private static let appleAppPathPrefixes: [String] = [
        "/System/Applications/",
        "/System/Library/CoreServices/",
        "/Applications/Utilities/",
        "/Applications/Safari.app",
        "/Applications/Mail.app",
        "/Applications/Messages.app",
        "/Applications/FaceTime.app",
        "/Applications/Photos.app",
        "/Applications/Music.app",
        "/Applications/TV.app",
        "/Applications/News.app",
        "/Applications/Maps.app",
        "/Applications/Books.app",
        "/Applications/Podcasts.app",
        "/Applications/App Store.app",
        "/Applications/System Settings.app",
        "/Applications/System Preferences.app",
        "/Applications/Preview.app",
        "/Applications/TextEdit.app",
        "/Applications/Calculator.app",
        "/Applications/Calendar.app",
        "/Applications/Contacts.app",
        "/Applications/Notes.app",
        "/Applications/Reminders.app",
        "/Applications/Freeform.app",
        "/Applications/Home.app",
        "/Applications/FindMy.app",
        "/Applications/Shortcuts.app",
        "/Applications/VoiceMemos.app",
        "/Applications/Clock.app",
        "/Applications/Weather.app",
        "/Applications/Stocks.app",
        "/Applications/Chess.app",
        "/Applications/Dictionary.app",
        "/Applications/Image Capture.app",
        "/Applications/QuickTime Player.app",
        "/Applications/Time Machine.app",
        "/Applications/Mission Control.app",
        "/Applications/Launchpad.app",
        "/Applications/Automator.app",
        "/Applications/Script Editor.app",
        "/Applications/Terminal.app",
        "/Applications/Console.app",
        "/Applications/Activity Monitor.app",
        "/Applications/Disk Utility.app",
        "/Applications/Migration Assistant.app",
        "/Applications/AirPort Utility.app",
        "/Applications/Bluetooth File Exchange.app",
        "/Applications/Audio MIDI Setup.app",
        "/Applications/ColorSync Utility.app",
        "/Applications/Digital Color Meter.app",
        "/Applications/Grapher.app",
        "/Applications/Keychain Access.app",
        "/Applications/Screenshot.app",
        "/Applications/Boot Camp Assistant.app",
        "/Applications/iMovie.app",
        "/Applications/GarageBand.app",
        "/Applications/Keynote.app",
        "/Applications/Numbers.app",
        "/Applications/Pages.app",
        "/Applications/Xcode.app",
        "/Applications/Developer.app",
        "/Applications/TestFlight.app",
        "/Applications/SF Symbols.app",
        "/Applications/Icon Composer.app",
        "/Applications/Reality Composer.app",
        "/Applications/Instruments.app",
        "/Applications/Simulator.app",
        "/Applications/Create ML.app",
        "/Applications/Font Book.app",
        "/Applications/Stickies.app",
        "/Applications/Photo Booth.app",
        "/Applications/DVD Player.app",
        "/Applications/Siri.app",
        "/Applications/Tips.app",
        "/Applications/VoiceOver Utility.app",
        "/Applications/System Information.app",
        "/Applications/Archive Utility.app",
        "/Applications/Directory Utility.app",
        "/Applications/Network Utility.app",
        "/Applications/RAID Utility.app",
        "/Applications/Wireless Diagnostics.app",
        "/Applications/Crash Reporter.app",
        "/Applications/Feedback Assistant.app",
        "/Applications/Apple Configurator.app",
        "/Applications/Translocation Removal Tool.app",
        "/Library/Developer/",
        "/Library/Application Support/Apple/",
        "/Library/Apple/",
        "/Library/PrivilegedHelperTools/com.apple.",
    ]

    private static let knownSystemProcessNames: Set<String> = [
        "kernel_task",
        "launchd",
        "UserEventAgent",
        "logd",
        "configd",
        "powerd",
        "notifyd",
        "securityd",
        "trustd",
        "opendirectoryd",
        "diskarbitrationd",
        "fseventsd",
        "coreaudiod",
        "WindowServer",
        "loginwindow",
        "SystemUIServer",
        "Dock",
        "Finder",
        "ControlCenter",
        "NotificationCenter",
        "Spotlight",
        "mds",
        "mds_stores",
        "mdworker",
        "mdworker_shared",
        "coreservicesd",
        "cfprefsd",
        "distnoted",
        "tccd",
        "syspolicyd",
        "amfid",
        "sandboxd",
        "secd",
        "accountsd",
        "sharingd",
        "bluetoothd",
        "wifid",
        "airportd",
        "corebrightnessd",
        "hidd",
        "IOMFB_bics_daemon",
        "thermalmonitord",
        "thermald",
        "dasd",
        "duetexpertd",
        "cloudd",
        "bird",
        "nsurlsessiond",
        "networkd",
        "mDNSResponder",
        "symptomsd",
        "rapportd",
        "coreduetd",
        "biometrickitd",
        "appleeventsd",
        "pboard",
        "pasteboard",
        "lsd",
        "filecoordinationd",
        "runningboardd",
        "mediaanalysisd",
        "photoanalysisd",
        "knowledge-agent",
        "suggestd",
        "parsecd",
        "siriknowledged",
        "assistantd",
        "Siri",
        "siriinferenced",
        "corespotlightd",
        "searchpartyuseragent",
        "locationd",
        "routined",
        "geod",
        "CalendarAgent",
        "AddressBookSourceSync",
        "imagent",
        "IMTransferAgent",
        "callservicesd",
        "CommCenter",
        "identityservicesd",
        "apsd",
        "pushagent",
        "usermanagerd",
        "loginwindow",
        "talagentd",
        "UniversalControl",
        "AirPlayXPCHelper",
        "coremltest",
        "neuralengined",
        "aned",
        "AppleSpell",
        "TextInputMenuAgent",
        "TextInputSwitcher",
        "ViewBridgeAuxiliary",
        "com.apple.WebKit.WebContent",
        "com.apple.WebKit.Networking",
        "com.apple.WebKit.GPU",
        "com.apple.Safari.WebApp",
        "SafariLaunchAgent",
        "SoftwareUpdateNotificationManager",
        "softwareupdated",
        "storeuid",
        "storeaccountd",
        "storeassetd",
        "storedownloadd",
        "commerce",
        "appstoreagent",
        "AppStoreDaemon",
        "installd",
        "system_installd",
        "package_script_service",
        "mobileassetd",
        "AssetCache",
        "AssetCacheLocatorService",
        "AssetCacheTetheratorService",
        "containermanagerd",
        "trustd",
        "secinitd",
        "sysmond",
        "systemstats",
        "spindump",
        "ReportCrash",
        "DiagnosticReport",
        "SubmitDiagInfo",
        "CrashReporterSupportHelper",
        "osanalyticshelper",
        "analyticsd",
        "corecaptured",
        "rtcreportingd",
        "watchdogd",
        "kernelmanagerd",
        "kextcache",
        "kmutil",
        "diskmanagementd",
        "storagekitd",
        "fsck",
        "hfs.util",
        "apfsd",
        "fskitd",
        "automountd",
        "nfsd",
        "smbd",
        "cupsd",
        "cups-lpd",
        "spoolss",
        "sshd",
        "ssh-agent",
        "cron",
        "atrun",
        "syslogd",
        "aslmanager",
        "newsyslog",
        "timed",
        "ntpd",
        "sntp",
        "usbd",
        "IOUserBluetoothSerialDriver",
        "bluetoothuserd",
        "nearbyd",
        "remoted",
        "RemoteManagementAgent",
        "screensharingd",
        "AppleVNCServer",
        "ARDAgent",
        "ScreensharingAgent",
        "cmiodalassistants",
        "VDCAssistant",
        "AppleCameraAssistant",
        "coreaudiod",
        "audiomxd",
        "AirPlayUIAgent",
        "AirPlayXPCHelper",
        "mediaremoted",
        "mediaanalysisd",
        "mediastream",
        "VTDecoderXPCService",
        "VTEncoderXPCService",
        "com.apple.audio.SandboxHelper",
        "com.apple.audio.Core-Audio-Driver-Service",
        "WindowManager",
        "WindowServer",
        "SkyLight",
        "loginwindow",
        "SystemUIServer",
        "ControlStrip",
        "TouchBarServer",
        "NowPlayingTouchUI",
        "Dock",
        "Finder",
        "System Events",
        "osascript",
        "AppleScript",
        "automator",
        "WorkflowServiceRunner",
        "QuickLookUIService",
        "quicklookd",
        "quicklookthumbnailing",
        "thumbnailserver",
        "iconservicesd",
        "iconservicesagent",
        "fontd",
        "fontworker",
        "ATSServer",
        "ctkd",
        "trustdHelper",
        "securityd_system",
        "authd",
        "authorizationhost",
        "SecurityAgent",
        "coreauthd",
        "LocalAuthenticationRemoteService",
        "biometrickitd",
        "coreduetd",
        "duetexpertd",
        "knowledgeconstructiond",
        "ContextStoreAgent",
        "contextstored",
        "proactiveeventtrackerd",
        "triald",
        "triald_system",
        "modelmanagerd",
        "modelcatalogd",
        "intelligenceplatformd",
        "PrivateCloudCompute",
        "appleh16camerad",
        "cameracaptured",
        "avconferenced",
        "videoconference_agent",
        "replayd",
        "screencapture",
        "ScreenTimeAgent",
        "UsageTrackingAgent",
        "FamilyControlsAgent",
        "ManagedSettingsAgent",
        "dmd",
        "teslad",
        "profiled",
        "mdmclient",
        "ManagedClient",
        "MCXTools",
        "cloudpaird",
        "companiond",
        "CompanionLink",
        "sharingd",
        "rapportd",
        "RPRemoteDisplayAgent",
        "replayd",
        "universalaccessd",
        "AXVisualSupportAgent",
        "VoiceOver",
        "VoiceOver Quickstart",
        "AccessibilityUIServer",
        "HearingAids",
        "audiomxd",
        "coreaudiod",
        "AirPlayUIAgent",
        "WirelessRadioManagerd",
        "wifip2pd",
        "WiFiAgent",
        "AirPort Base Station Agent",
        "bluetoothd",
        "bluetoothaudiod",
        "BTLEServer",
        "BTServer",
        "gamecontrollerd",
        "Game Center",
        "gamed",
        "GamePolicyAgent",
        "gamepolicyd",
        "metalfe_proxy",
        "MTLCompilerService",
        "gpucompilerd",
        "WindowServer",
        "loginwindow",
        "backgroundtaskmanagementd",
        "BackgroundTaskManagementAgent",
        "suggestd",
        "reversetemplated",
        "parsecd",
        "searchpartyd",
        "findmydevice-user-agent",
        "fmfd",
        "fmflocatord",
        "FindMyMacd",
        "icloudmailagent",
        "com.apple.iCloudHelper",
        "bird",
        "cloudd",
        "cloudphotod",
        "protectedcloudstorage",
        "Keychain Circle Notification",
        "secd",
        "ckksctl",
        "SyncedDefaults",
        "com.apple.Safari.History",
        "com.apple.Safari.SearchHelper",
        "com.apple.Safari.SafeBrowsing.Service",
        "WebKit.Networking",
        "WebKit.WebContent",
        "WebKit.GPU",
        "com.apple.WebKit.Plugin.64",
        "SafariBookmarksSyncAgent",
        "SafariNotificationAgent",
        "swcd",
        "neagent",
        "nesessionmanager",
        "nehelper",
        "networkserviceproxy",
        "netbiosd",
        "mDNSResponderHelper",
        "configd",
        "networkd_privileged",
        "symptomsd",
        "networkqualityd",
        "usbmuxd",
        "lockdownd",
        "MobileDeviceUpdater",
        "AMPDevicesAgent",
        "AMPDeviceDiscoveryAgent",
        "iTunesHelper",
        "AMPLibraryAgent",
        "mediaanalysisd",
        "photoanalysisd",
        "cloudphotod",
        "photolibraryd",
        "AssetsLibraryService",
        "mediastream",
        "com.apple.geod",
        "locationd",
        "routined",
        "navd",
        "Maps",
        "mapspushd",
        "WeatherWidget",
        "weatherd",
        "Stocks",
        "stocksagent",
        "NewsToday2",
        "newsd",
        "donotdisturbd",
        "UserNotificationsCenter",
        "NotificationCenter",
        "usernoted",
        "distnoted",
        "cfprefsd",
        "defaults",
        "plutil",
        "pboard",
        "pbs",
        "talagentd",
        "launchservicesd",
        "lsd",
        "coreservicesd",
        "CarbonComponentScannerXPC",
        "sharedfilelistd",
        "fileproviderd",
        "FileProvider",
        "bird",
        "cloudd",
        "ContainerDatabase",
        "containermanagerd",
        "appplaceholdersyncd",
        "installcoordinationd",
        "appstoreagent",
        "storeuid",
        "commerce",
        "AppStore",
        "Software Update",
        "softwareupdated",
        "mobileassetd",
        "AssetCacheManagerService",
        "deleted",
        "deleted_helper",
        "cache_delete",
        "sysdiagnose",
        "sysdiagnose_helper",
        "spindump_agent",
        "ReportMemoryException",
        "memorystatus_control",
        "jetsamctl",
        "memory_pressure",
        "taskgated",
        "taskgated-helper",
        "amfid",
        "syspolicyd",
        "XprotectService",
        "XProtect",
        "XProtectFramework",
        "MRT",
        "Gatekeeper",
        "gk",
        "codesign",
        "security",
        "spctl",
        "tccd",
        "TransparencyUIServer",
        "TransparencyAgent",
        "endpointsecurityd",
        "ESDaemonService",
        "sysextd",
        "systemextensionsctl",
        "DriverKit",
        "kernelmanagerd",
        "IOUserServer",
        "corebrightnessd",
        "displaypolicyd",
        "WindowManager",
        "DockHelper",
        "com.apple.dock.extra",
        "wallpaperAgent",
        "SystemUIServer",
        "ControlCenter",
        "ControlStrip",
        "WiFiAgent",
        "BluetoothUIServer",
        "AirPlayUIAgent",
        "NowPlayingTouchUI",
        "UserNotificationCenter",
        "NotificationCenter",
        "usernotificationsd",
        "distributed notification center",
        "coreautha",
        "authenticationmanagerhelper",
        "AuthorizationHostHelper",
        "SecurityAgentHelper",
        "coreauthd",
        "LocalAuthentication",
        "biometrickitd",
        "TouchIdControlCenterModule",
        "universalaccessd",
        "AccessibilityUIServer",
        "VoiceOver",
        "ZoomWindow",
        "Switch Control",
        "Dwell Control",
        "AXVisualSupportAgent",
        "hearingd",
        "LiveSpeechUIService",
        "AccessibilitySettingsExtension",
        "siriinferenced",
        "assistantd",
        "siriknowledged",
        "parsed",
        "coreduetd",
        "knowledge-agent",
        "duetexpertd",
        "proactiveeventtrackerd",
        "triald",
        "modelmanagerd",
        "intelligencecontextd",
        "PrivateCloudComputeAgent",
        "generativeexperiencesd",
        "textunderstandingd",
        "linkd",
        "BiomeAgent",
        "biomesyncd",
        "BiomeEventStreams",
        "ContextStoreAgent",
        "contextstored",
        "peopleanalyticsd",
        "sociallayerd",
        "ContactProviderService",
        "contactsdonationagent",
        "AddressBookSourceSync",
        "DataAccess",
        "dataaccessd",
        "Exchange",
        "Mail",
        "maild",
        "MailServiceAgent",
        "imap",
        "smtp",
        "Notes",
        "notesd",
        "NotesSync",
        "CalendarAgent",
        "CalendarWidget",
        "calaccessd",
        "Reminders",
        "remindd",
        "Freeform",
        "freeformd",
        "Messages",
        "imagent",
        "IMRemoteURLConnectionAgent",
        "IMTransferAgent",
        "avconferenced",
        "callservicesd",
        "CommCenter",
        "CommCenterMobileHelper",
        "identityservicesd",
        "IDSRemoteURLConnectionAgent",
        "facetime",
        "FaceTime",
        "TelephonyUtilities",
        "Phone",
        "MobilePhone",
        "statuskitd",
        "statusd",
        "focusd",
        "donotdisturbd",
        "DoNotDisturb",
        "focus-modes-test",
        "ScreenTimeAgent",
        "UsageTrackingAgent",
        "DeviceActivityReportService",
        "FamilyControlsAgent",
        "ManagedSettingsAgent",
        "screentime",
        "parentalcontrolsd",
        "familycircled",
        "Family",
        "askpermissiond",
        "AskPermissionUI",
        "StoreKitUIService",
        "storekitagent",
        "commerce",
        "appstoreagent",
        "AppStoreDaemon",
        "storedownloadd",
        "storeassetd",
        "storeaccountd",
        "bookassetd",
        "iBooks",
        "Books",
        "Podcasts",
        "podcasts",
        "Music",
        "AMPLibraryAgent",
        "AMPDevicesAgent",
        "TV",
        "TVRemoteConnectionService",
        "mediaremoteagent",
        "mediaanalysisd",
        "photoanalysisd",
        "cloudphotod",
        "photolibraryd",
        "Photos",
        "photoanalysisd",
        "mediastream",
        "avassetd",
        "com.apple.geod",
        "locationd",
        "routined",
        "navd",
        "Maps",
        "mapspushd",
        "Weather",
        "weatherd",
        "Stocks",
        "stocksagent",
        "News",
        "newsd",
        "Home",
        "homed",
        "HomeKit",
        "HomeControlService",
        "HomeUIService",
        "HomeWidget",
        "HomeEnergyDaemon",
        "HomeEnergyUIService",
        "HomeLabConfigUIService",
        "HomeUIService",
        "HomeControlService",
        "HomeWidget.Interactive",
        "HomeWidget.Static",
        "HomeWidget.Control",
        "HomeWidget.Accessory",
        "HomeWidget.Camera",
        "HomeWidget.LockScreen",
        "HomeWidget.HomeControl",
        "HomeWidget.HomeEnergy",
        "HomeWidget.HomeLab",
        "HomeWidget.HomeUI",
        "HomeWidget.HomeKit",
        "HomeWidget.HomeControlService",
        "HomeWidget.HomeEnergyDaemon",
        "HomeWidget.HomeEnergyUIService",
        "HomeWidget.HomeLabConfigUIService",
        "HomeWidget.HomeUIService",
        "HomeWidget.HomeControlService",
        "HomeWidget.HomeEnergyDaemon",
        "HomeWidget.HomeEnergyUIService",
        "HomeWidget.HomeLabConfigUIService",
        "HomeWidget.HomeUIService",
    ]

    // MARK: - Public API

    static func classify(path: String, name: String, bundleID: String?) -> (ProcessCategory, ProcessKind) {
        let kind = detectKind(path: path, name: name, bundleID: bundleID)

        if isKernelOrBootstrap(name: name, path: path) {
            return (.appleSystem, .kernel)
        }

        if let bid = bundleID, isAppleBundleID(bid) {
            if isSystemPath(path) || kind == .daemon || kind == .helper {
                return (.appleSystem, kind)
            }
            return (.appleApp, kind)
        }

        if isSystemPath(path) {
            return (.appleSystem, kind)
        }

        if isAppleAppPath(path) {
            return (.appleApp, kind)
        }

        if knownSystemProcessNames.contains(name) {
            return (.appleSystem, kind)
        }

        // 名称前缀 com.apple.*
        if name.hasPrefix("com.apple.") {
            return (.appleSystem, kind)
        }

        if path.isEmpty && name.hasPrefix("kernel") {
            return (.appleSystem, .kernel)
        }

        if path.isEmpty {
            // 无路径时，常见系统短名
            if knownSystemProcessNames.contains(name) || name.hasPrefix("com.apple") {
                return (.appleSystem, kind)
            }
            return (.unknown, kind)
        }

        return (.thirdParty, kind)
    }

    // MARK: - Helpers

    private static func isKernelOrBootstrap(name: String, path: String) -> Bool {
        name == "kernel_task" || name == "launchd" || pidZeroNames.contains(name)
    }

    private static let pidZeroNames: Set<String> = ["kernel_task"]

    private static func isAppleBundleID(_ bid: String) -> Bool {
        bid.hasPrefix("com.apple.") ||
        bid.hasPrefix("com.apple") ||
        bid == "com.apple" ||
        bid.hasPrefix("edu.mit.Kerberos") // 系统集成
    }

    private static func isSystemPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        return systemPathPrefixes.contains { path.hasPrefix($0) }
    }

    private static func isAppleAppPath(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        if appleAppPathPrefixes.contains(where: { path.hasPrefix($0) || path == $0 }) {
            return true
        }
        // /Applications/*.app 且为 Apple 签名的情况在路径层面再兜底：
        // 位于 /System/Volumes/Preboot, /System/Library 等
        if path.hasPrefix("/System/Volumes/") {
            return true
        }
        if path.contains("/Contents/MacOS/") {
            // 尝试从路径解析 .app 名并匹配已知 Apple 应用
            if let appName = extractAppName(from: path),
               knownAppleAppNames.contains(appName) {
                return true
            }
        }
        return false
    }

    private static func extractAppName(from path: String) -> String? {
        let components = path.components(separatedBy: "/")
        for component in components where component.hasSuffix(".app") {
            return String(component.dropLast(4))
        }
        return nil
    }

    private static let knownAppleAppNames: Set<String> = [
        "Safari", "Mail", "Messages", "FaceTime", "Photos", "Music", "TV",
        "News", "Maps", "Books", "Podcasts", "App Store", "System Settings",
        "System Preferences", "Preview", "TextEdit", "Calculator", "Calendar",
        "Contacts", "Notes", "Reminders", "Freeform", "Home", "FindMy",
        "Shortcuts", "VoiceMemos", "Clock", "Weather", "Stocks", "Chess",
        "Dictionary", "Image Capture", "QuickTime Player", "Time Machine",
        "Mission Control", "Launchpad", "Automator", "Script Editor",
        "Terminal", "Console", "Activity Monitor", "Disk Utility",
        "Migration Assistant", "AirPort Utility", "Bluetooth File Exchange",
        "Audio MIDI Setup", "ColorSync Utility", "Digital Color Meter",
        "Grapher", "Keychain Access", "Screenshot", "Boot Camp Assistant",
        "iMovie", "GarageBand", "Keynote", "Numbers", "Pages", "Xcode",
        "Developer", "TestFlight", "SF Symbols", "Font Book", "Stickies",
        "Photo Booth", "Siri", "Tips", "VoiceOver Utility", "System Information",
        "Archive Utility", "Feedback Assistant", "Apple Configurator",
        "Finder", "Dock", "SystemUIServer", "Control Center", "Notification Center",
        "Login Window", "WindowServer", "Spotlight", "Quick Look",
    ]

    private static func detectKind(path: String, name: String, bundleID: String?) -> ProcessKind {
        if name == "kernel_task" { return .kernel }
        if name == "launchd" { return .daemon }

        let lower = path.lowercased()
        if lower.contains(".appex/") || lower.contains("xpcservices") || name.hasSuffix("Helper") || name.hasSuffix("Agent") {
            return .helper
        }
        if lower.contains("/launchdaemons/") || lower.contains("/launchagents/") ||
            lower.hasPrefix("/usr/libexec/") || lower.hasPrefix("/usr/sbin/") ||
            lower.hasPrefix("/System/Library/CoreServices/") && !lower.hasSuffix(".app/contents/macos/" + name.lowercased()) {
            // CoreServices 里既有 app 也有 daemon
            if path.hasSuffix(".app") || path.contains(".app/") {
                return .app
            }
            return .daemon
        }
        if path.contains(".app/") || (bundleID != nil && path.hasPrefix("/Applications/")) {
            return .app
        }
        if ["bash", "zsh", "sh", "fish", "tcsh", "csh", "dash"].contains(name) {
            return .shell
        }
        if path.hasPrefix("/usr/bin/") || path.hasPrefix("/bin/") {
            return .other
        }
        return .other
    }

    // 按路径缓存 bid / 图标，避免反复 Bundle(url:) 与 NSWorkspace 全局缓存膨胀
    private static let bidCacheLock = NSLock()
    private static var bidCache: [String: String?] = [:]
    private static let bidCacheLimit = 512
    private static let iconCache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 256
        c.totalCostLimit = 8 * 1024 * 1024
        return c
    }()

    /// 尝试读取 Bundle Identifier（优先 Info.plist，避免 Bundle 全局缓存）
    static func bundleIdentifier(forPath path: String) -> String? {
        guard !path.isEmpty else { return nil }

        bidCacheLock.lock()
        if let cached = bidCache[path] {
            bidCacheLock.unlock()
            return cached
        }
        bidCacheLock.unlock()

        let resolved = resolveBundleIdentifier(forPath: path)

        bidCacheLock.lock()
        if bidCache.count >= bidCacheLimit {
            bidCache.removeAll(keepingCapacity: true)
        }
        bidCache[path] = resolved
        bidCacheLock.unlock()
        return resolved
    }

    private static func resolveBundleIdentifier(forPath path: String) -> String? {
        // 从可执行文件路径回溯到 .app，只读 Info.plist（不走 Bundle(url:)）
        var url = URL(fileURLWithPath: path)
        while url.path != "/" {
            if url.pathExtension == "app" {
                let infoPlist = url.appendingPathComponent("Contents/Info.plist")
                if let dict = NSDictionary(contentsOf: infoPlist) as? [String: Any],
                   let bid = dict["CFBundleIdentifier"] as? String {
                    return bid
                }
                return nil
            }
            url.deleteLastPathComponent()
        }

        let dir = URL(fileURLWithPath: path).deletingLastPathComponent()
        let infoPlist = dir.appendingPathComponent("Info.plist")
        if let dict = NSDictionary(contentsOf: infoPlist) as? [String: Any],
           let bid = dict["CFBundleIdentifier"] as? String {
            return bid
        }
        return nil
    }

    /// 获取应用图标（进程级 NSCache，限制数量与成本）
    static func icon(for path: String, name: String) -> NSImage {
        let cacheKey = (path.isEmpty ? name : path) as NSString
        if let cached = iconCache.object(forKey: cacheKey) {
            return cached
        }

        let image: NSImage
        if !path.isEmpty {
            var url = URL(fileURLWithPath: path)
            var found: NSImage?
            while url.path != "/" {
                if url.pathExtension == "app" {
                    found = NSWorkspace.shared.icon(forFile: url.path)
                    break
                }
                url.deleteLastPathComponent()
            }
            image = found ?? NSWorkspace.shared.icon(forFile: path)
        } else {
            image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: name) ?? NSImage()
        }
        // 列表统一 16pt，降低位图成本
        image.size = NSSize(width: 16, height: 16)
        iconCache.setObject(image, forKey: cacheKey, cost: 16 * 16 * 4)
        return image
    }
}
