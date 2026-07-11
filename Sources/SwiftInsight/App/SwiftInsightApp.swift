import SwiftUI
import AppKit

@main
struct SwiftInsightApp: App {
    @StateObject private var monitor = ProcessMonitor()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(monitor)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { monitor.start() }
                .onDisappear { monitor.stop() }
        }
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
        }

        Settings {
            SettingsView()
                .environmentObject(monitor)
        }
    }
}
