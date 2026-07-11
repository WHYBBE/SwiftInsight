import AppKit
import Combine

/// 监听 Control 键：按住时暂停自动刷新，便于稳定查看与操作列表
@MainActor
final class ControlKeyMonitor: ObservableObject {
    @Published private(set) var isControlPressed = false

    private var localMonitor: Any?
    private var globalMonitor: Any?
    private weak var processMonitor: ProcessMonitor?

    func start(processMonitor: ProcessMonitor) {
        self.processMonitor = processMonitor
        stop()

        let handler: (NSEvent) -> NSEvent? = { [weak self] event in
            Task { @MainActor in
                self?.updateControlState(from: event.modifierFlags)
            }
            return event
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: handler)
        // 应用失去焦点时也能感知 Control 松开
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            Task { @MainActor in
                self?.updateControlState(from: event.modifierFlags)
            }
        }

        // 同步当前修饰键状态
        updateControlState(from: NSEvent.modifierFlags)
    }

    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        isControlPressed = false
        processMonitor?.setRefreshPaused(false)
    }

    private func updateControlState(from flags: NSEvent.ModifierFlags) {
        let pressed = flags.contains(.control)
        guard isControlPressed != pressed else { return }
        isControlPressed = pressed
        processMonitor?.setRefreshPaused(pressed)
    }
}
