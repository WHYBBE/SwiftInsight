import Foundation
import ServiceManagement

/// 开机自启（macOS 13+ SMAppService；需正式 .app bundle）
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var isAvailable: Bool {
        // 非 .app（如 swift run）通常无法注册 login item
        Bundle.main.bundleURL.pathExtension.lowercased() == "app"
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return true }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered { return true }
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            return false
        }
    }

    static func toggle() -> Bool {
        setEnabled(!isEnabled)
    }
}
