import SwiftUI
import AppKit

/// 兼容保留：主窗口已改为 AppKit 按需创建，不再依赖 SwiftUI WindowGroup
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
