import SwiftUI
import AppKit

@main
struct SwiftInsightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // 无 WindowGroup：仅菜单栏启动时不创建主窗口，从根上消除闪屏
        // 主窗口由 MainWindowCoordinator 按需以 AppKit 创建
        // 注意：不要在属性初始化里碰 AppSession（NSApp 可能尚未就绪）
        Settings {
            SettingsRootView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("cmd.about")) {
                    openAboutWindow()
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L("cmd.process")) {
                Button(L("cmd.refresh")) {
                    AppSession.shared.monitor.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button(L("cmd.show_all")) {
                    AppSession.shared.monitor.categoryFilter = nil
                    AppSession.shared.monitor.showOnlyApps = false
                }
                Button(L("cmd.only_system")) {
                    AppSession.shared.monitor.categoryFilter = .appleSystem
                }
                Button(L("cmd.only_app")) {
                    AppSession.shared.monitor.categoryFilter = .appleApp
                }
                Button(L("cmd.only_third")) {
                    AppSession.shared.monitor.categoryFilter = .thirdParty
                }
            }
            CommandMenu(L("cmd.menubar")) {
                ForEach(MenuBarIconMode.allCases) { mode in
                    Button(mode.displayName) {
                        AppSession.shared.menuBar.iconMode = mode
                    }
                }
            }
            CommandGroup(after: .windowList) {
                Button(L("mb.open_main")) {
                    MainWindowCoordinator.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }

    private func openAboutWindow() {
        let session = AppSession.shared
        session.bootstrapIfNeeded()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "about-swiftinsight" }) {
            existing.makeKeyAndOrderFront(nil)
            MainWindowCoordinator.updateDockVisibility()
            return
        }

        let view = AboutView()
            .environmentObject(session.prefs)
            .id(session.prefs.language)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.identifier = NSUserInterfaceItemIdentifier("about-swiftinsight")
        window.title = L("cmd.about")
        window.styleMask = NSWindow.StyleMask([.titled, .closable, .fullSizeContentView])
        window.titlebarAppearsTransparent = true
        window.setContentSize(NSSize(width: 400, height: 360))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        MainWindowCoordinator.updateDockVisibility()
    }
}

/// Settings 在真正打开时再取 session，避免启动期过早初始化
private struct SettingsRootView: View {
    var body: some View {
        let session = AppSession.shared
        SettingsView()
            .environmentObject(session.monitor)
            .environmentObject(session.menuBar)
            .environmentObject(session.prefs)
            .onAppear {
                session.bootstrapIfNeeded()
                NSApp.setActivationPolicy(.regular)
                NSApp.activate(ignoringOtherApps: true)
                MainWindowCoordinator.updateDockVisibility()
            }
    }
}
