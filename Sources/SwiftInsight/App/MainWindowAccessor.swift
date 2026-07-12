import SwiftUI
import AppKit

/// 把 NSWindow 交给 MainWindowCoordinator 管理关闭/重开
struct MainWindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                MainWindowCoordinator.attachMainWindow(window)
            }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window {
                MainWindowCoordinator.attachMainWindow(window)
            }
        }
    }
}

/// 在视图树中保留 openWindow，响应菜单栏「打开主窗口」
struct MainWindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onReceive(NotificationCenter.default.publisher(for: .showMainWindow)) { _ in
                // 仅在没有存活主窗口时新建，避免重复窗口
                if MainWindowCoordinator.allMainWindows().isEmpty {
                    openWindow(id: "main")
                }
            }
    }
}
