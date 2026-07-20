import AppKit

/// 启动入口：不依赖 WindowGroup，避免「先显示再隐藏」闪屏
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if MainWindowCoordinator.preferredMainWindowVisible {
            NSApp.setActivationPolicy(.regular)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppSession.shared.bootstrapIfNeeded()
            MainWindowCoordinator.applyLaunchState()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowCoordinator.showMainWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainWindowCoordinator.persistLaunchStateBeforeTerminate()
    }
}
