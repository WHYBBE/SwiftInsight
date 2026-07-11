import SwiftUI
import AppKit

@main
struct SwiftInsightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = ProcessMonitor()
    @StateObject private var controlKeyMonitor = ControlKeyMonitor()
    @StateObject private var menuBar = MenuBarController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(menuBar)
                .frame(minWidth: 1180, minHeight: 680)
                .onAppear {
                    monitor.start()
                    controlKeyMonitor.start(processMonitor: monitor)
                    // 等窗口/RunLoop 就绪后再挂状态栏
                    DispatchQueue.main.async {
                        menuBar.attach(monitor: monitor)
                    }
                    activateAsRegularApp()
                }
        }
        .defaultSize(width: 1360, height: 860)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("进程") {
                Button("刷新") {
                    monitor.refresh()
                }
                .keyboardShortcut("r", modifiers: .command)

                Divider()

                Button("显示全部") {
                    monitor.categoryFilter = nil
                    monitor.showOnlyApps = false
                }
                Button("仅 Apple 系统") {
                    monitor.categoryFilter = .appleSystem
                }
                Button("仅 Apple 应用") {
                    monitor.categoryFilter = .appleApp
                }
                Button("仅第三方") {
                    monitor.categoryFilter = .thirdParty
                }
            }
            CommandMenu("菜单栏") {
                ForEach(MenuBarIconMode.allCases) { mode in
                    Button(mode.displayName) {
                        menuBar.iconMode = mode
                    }
                }
            }
        }

        // 不使用 MenuBarExtra：在 macOS 27 + 自定义 label 下锚定异常
        // 菜单栏由 MenuBarController / NSStatusItem 负责

        Settings {
            SettingsView()
                .environmentObject(monitor)
                .environmentObject(menuBar)
        }
    }

    private func activateAsRegularApp() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
