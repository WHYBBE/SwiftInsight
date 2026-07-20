import AppKit
import SwiftUI

extension Notification.Name {
    static let showMainWindow = Notification.Name("me.whynbnb.SwiftInsight.showMainWindow")
}

/// 主窗口生命周期：AppKit 按需创建，关闭只隐藏；仅菜单栏启动时根本不建窗（无闪屏）
@MainActor
enum MainWindowCoordinator {
    static let mainWindowID = "main-swiftinsight"
    private static let launchMainVisibleKey = "launchMainWindowVisible"
    private static var closeHandlers: [ObjectIdentifier: WindowCloseHandler] = [:]
    private static weak var processMonitor: ProcessMonitor?
    private static var hostedMainWindow: NSWindow?
    private static var launchSettled = false

    /// 上次退出时主窗口是否可见（默认 true：首次启动打开主界面）
    static var preferredMainWindowVisible: Bool {
        get {
            if UserDefaults.standard.object(forKey: launchMainVisibleKey) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: launchMainVisibleKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: launchMainVisibleKey)
        }
    }

    static func bindProcessMonitor(_ monitor: ProcessMonitor) {
        processMonitor = monitor
        notifyMainVisibility()
    }

    /// 启动：按偏好打开主窗或仅菜单栏（不先建窗再藏）
    static func applyLaunchState() {
        if preferredMainWindowVisible {
            showMainWindow()
        } else {
            NSApp.setActivationPolicy(.accessory)
            preferredMainWindowVisible = false
            notifyMainVisibility()
        }
        launchSettled = true
    }

    static func isMainWindow(_ window: NSWindow) -> Bool {
        if window.identifier?.rawValue == mainWindowID { return true }
        if window.identifier?.rawValue == "about-swiftinsight" { return false }
        if window is NSPanel { return false }
        return false
    }

    static func visibleMainWindows() -> [NSWindow] {
        NSApp.windows.filter { isMainWindow($0) && $0.isVisible && !$0.isMiniaturized }
    }

    static func allMainWindows() -> [NSWindow] {
        NSApp.windows.filter { isMainWindow($0) }
    }

    static func attachMainWindow(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(mainWindowID)
        window.isReleasedWhenClosed = false
        let key = ObjectIdentifier(window)
        if closeHandlers[key] == nil {
            let handler = WindowCloseHandler(window: window)
            closeHandlers[key] = handler
            window.delegate = handler
        }
        hostedMainWindow = window
        notifyMainVisibility()
    }

    static func showMainWindow() {
        preferredMainWindowVisible = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = hostedMainWindow ?? allMainWindows().first {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            updateDockVisibility()
            return
        }

        createAndShowMainWindow()
    }

    private static var mainHosting: NSHostingController<AnyView>?

    /// 按需创建主窗口（仅在需要显示时调用）
    private static func createAndShowMainWindow() {
        let hosting = NSHostingController(rootView: makeMainRootView())
        mainHosting = hosting
        let window = NSWindow(contentViewController: hosting)
        window.title = "SwiftInsight"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1360, height: 860))
        window.minSize = NSSize(width: 1180, height: 680)
        window.center()
        window.setFrameAutosaveName("SwiftInsightMainWindow")
        attachMainWindow(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        updateDockVisibility()
    }

    private static func makeMainRootView() -> AnyView {
        let session = AppSession.shared
        return AnyView(
            ContentView()
                .environmentObject(session.monitor)
                .environmentObject(session.menuBar)
                .environmentObject(session.prefs)
                .frame(minWidth: 1180, minHeight: 680)
                .id(session.prefs.language)
        )
    }

    /// 语言切换后刷新已打开的主窗口内容
    static func reloadMainWindowContentIfNeeded() {
        guard let hosting = mainHosting else { return }
        hosting.rootView = makeMainRootView()
    }

    static func updateDockVisibility() {
        let hasVisibleMain = !visibleMainWindows().isEmpty
        let hasAbout = NSApp.windows.contains {
            $0.identifier?.rawValue == "about-swiftinsight" && $0.isVisible
        }
        let hasSettings = NSApp.windows.contains { win in
            guard win.isVisible else { return false }
            let t = win.title.lowercased()
            return t.contains("settings") || t.contains("设置")
                || t.contains("preferences") || t.contains("偏好")
        }

        if hasVisibleMain || hasAbout || hasSettings {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        notifyMainVisibility()
    }

    fileprivate static func notifyMainVisibility() {
        let visible = !visibleMainWindows().isEmpty
        if launchSettled {
            preferredMainWindowVisible = visible
        }
        processMonitor?.setMainWindowVisible(visible)
    }

    static func persistLaunchStateBeforeTerminate() {
        preferredMainWindowVisible = !visibleMainWindows().isEmpty
    }
}

private final class WindowCloseHandler: NSObject, NSWindowDelegate {
    private weak var window: NSWindow?

    init(window: NSWindow) {
        self.window = window
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        Task { @MainActor in
            MainWindowCoordinator.preferredMainWindowVisible = false
            MainWindowCoordinator.updateDockVisibility()
        }
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        Task { @MainActor in
            MainWindowCoordinator.updateDockVisibility()
        }
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        Task { @MainActor in
            MainWindowCoordinator.updateDockVisibility()
        }
    }

    func windowDidBecomeKey(_ notification: Notification) {
        Task { @MainActor in
            MainWindowCoordinator.notifyMainVisibility()
        }
    }

    func windowWillClose(_ notification: Notification) {
        Task { @MainActor in
            MainWindowCoordinator.updateDockVisibility()
        }
    }
}
