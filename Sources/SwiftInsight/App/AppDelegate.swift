import AppKit

/// 仅负责激活策略与主窗口生命周期；采样与菜单栏由 SwiftUI @StateObject 持有
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            if let window = NSApp.windows.first(where: {
                $0.styleMask.contains(.titled) && !($0 is NSPanel)
            }) {
                MainWindowCoordinator.attachMainWindow(window)
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            MainWindowCoordinator.updateDockVisibility()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowCoordinator.showMainWindow()
        return true
    }
}
