import AppKit

extension Notification.Name {
    static let showMainWindow = Notification.Name("me.whynbnb.SwiftInsight.showMainWindow")
}

/// 主窗口生命周期：关闭 → 隐藏（不销毁）+ 无主窗口时退出 Dock；菜单栏可再打开
enum MainWindowCoordinator {
    static let mainWindowID = "main-swiftinsight"
    private static var closeHandlers: [ObjectIdentifier: WindowCloseHandler] = [:]

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

    /// 由 MainWindowAccessor 调用：标记为主窗口并拦截关闭
    static func attachMainWindow(_ window: NSWindow) {
        window.identifier = NSUserInterfaceItemIdentifier(mainWindowID)
        window.isReleasedWhenClosed = false
        let key = ObjectIdentifier(window)
        if closeHandlers[key] == nil {
            let handler = WindowCloseHandler(window: window)
            closeHandlers[key] = handler
            window.delegate = handler
        }
    }

    static func showMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let mains = allMainWindows()
        if let window = mains.first(where: { $0.isVisible })
            ?? mains.first(where: { $0.isMiniaturized })
            ?? mains.first {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            updateDockVisibility()
            return
        }

        // 没有存活主窗口：通知 SwiftUI 打开 WindowGroup
        NotificationCenter.default.post(name: .showMainWindow, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let window = allMainWindows().first {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else if let fallback = NSApp.windows.first(where: {
                $0.styleMask.contains(.titled)
                    && !($0 is NSPanel)
                    && $0.identifier?.rawValue != "about-swiftinsight"
                    && $0.frame.width >= 800
            }) {
                attachMainWindow(fallback)
                fallback.makeKeyAndOrderFront(nil)
            }
            updateDockVisibility()
        }
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
        DispatchQueue.main.async {
            MainWindowCoordinator.updateDockVisibility()
        }
        return false
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            MainWindowCoordinator.updateDockVisibility()
        }
    }
}
