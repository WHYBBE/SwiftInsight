import SwiftUI
import AppKit

@main
struct SwiftInsightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = ProcessMonitor()
    @StateObject private var controlKeyMonitor = ControlKeyMonitor()
    @StateObject private var menuBar = MenuBarController()
    @StateObject private var prefs = AppPreferences.shared

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(menuBar)
                .environmentObject(prefs)
                .frame(minWidth: 1180, minHeight: 680)
                .id(prefs.language)
                .background(MainWindowAccessor())
                .background(MainWindowOpenBridge())
                .onAppear {
                    monitor.start()
                    controlKeyMonitor.start(processMonitor: monitor)
                    menuBar.onOpenMain = {
                        MainWindowCoordinator.showMainWindow()
                    }
                    DispatchQueue.main.async {
                        menuBar.install(monitor: monitor)
                        prefs.applyTheme()
                        if let window = NSApp.windows.first(where: { MainWindowCoordinator.isMainWindow($0) }) {
                            MainWindowCoordinator.attachMainWindow(window)
                        }
                    }
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
                .onChange(of: prefs.language) { _, _ in
                    menuBar.refreshLocalizedUI()
                }
        }
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L("cmd.about")) {
                    openAboutWindow()
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu(L("cmd.process")) {
                Button(L("cmd.refresh")) {
                    monitor.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button(L("cmd.show_all")) {
                    monitor.categoryFilter = nil
                    monitor.showOnlyApps = false
                }
                Button(L("cmd.only_system")) {
                    monitor.categoryFilter = .appleSystem
                }
                Button(L("cmd.only_app")) {
                    monitor.categoryFilter = .appleApp
                }
                Button(L("cmd.only_third")) {
                    monitor.categoryFilter = .thirdParty
                }
            }
            CommandMenu(L("cmd.menubar")) {
                ForEach(MenuBarIconMode.allCases) { mode in
                    Button(mode.displayName) {
                        menuBar.iconMode = mode
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .environmentObject(menuBar)
                .environmentObject(prefs)
                .onAppear {
                    // 设置打开时显示 Dock
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
    }

    private func openAboutWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let existing = NSApp.windows.first(where: { $0.identifier?.rawValue == "about-swiftinsight" }) {
            existing.makeKeyAndOrderFront(nil)
            MainWindowCoordinator.updateDockVisibility()
            return
        }

        let view = AboutView()
            .environmentObject(prefs)
            .id(prefs.language)
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
