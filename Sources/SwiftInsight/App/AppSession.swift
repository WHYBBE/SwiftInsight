import SwiftUI
import AppKit
import Combine

/// 进程级会话：不依赖 SwiftUI Window 存活，菜单栏-only 启动也能跑
@MainActor
final class AppSession: ObservableObject {
    static let shared = AppSession()

    let monitor = ProcessMonitor()
    let controlKeyMonitor = ControlKeyMonitor()
    let menuBar = MenuBarController()
    let prefs = AppPreferences.shared

    private var didBootstrap = false
    private var languageCancellable: AnyCancellable?

    private init() {}

    func bootstrapIfNeeded() {
        guard !didBootstrap else { return }
        didBootstrap = true

        MainWindowCoordinator.bindProcessMonitor(monitor)
        controlKeyMonitor.start(processMonitor: monitor)
        monitor.onMainWindowVisibilityChange = { [weak self] visible in
            self?.controlKeyMonitor.setEnabled(visible)
        }
        monitor.start()
        controlKeyMonitor.setEnabled(monitor.mainWindowVisible)

        menuBar.onOpenMain = {
            MainWindowCoordinator.showMainWindow()
        }
        menuBar.install(monitor: monitor)
        prefs.applyTheme()

        languageCancellable = prefs.$language
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.menuBar.refreshLocalizedUI()
                MainWindowCoordinator.reloadMainWindowContentIfNeeded()
            }
    }
}
