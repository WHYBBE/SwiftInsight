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
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(menuBar)
                .environmentObject(prefs)
                .frame(minWidth: 1180, minHeight: 680)
                .id(prefs.language)
                .onAppear {
                    monitor.start()
                    controlKeyMonitor.start(processMonitor: monitor)
                    menuBar.onOpenMain = {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        NSApp.windows.first(where: { $0.styleMask.contains(.titled) })?
                            .makeKeyAndOrderFront(nil)
                    }
                    DispatchQueue.main.async {
                        menuBar.install(monitor: monitor)
                        prefs.applyTheme()
                    }
                    activateAsRegularApp()
                }
                .onChange(of: prefs.language) { _, _ in
                    menuBar.refreshLocalizedUI()
                }
        }
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
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
        }
    }

    private func activateAsRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
