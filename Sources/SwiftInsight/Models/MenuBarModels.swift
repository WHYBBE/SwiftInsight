import Foundation

/// 菜单栏图标展示模式
enum MenuBarIconMode: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case combined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: return L("icon.cpu")
        case .memory: return L("icon.memory")
        case .combined: return L("icon.combined")
        }
    }

    var shortName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return L("icon.short.memory")
        case .combined: return L("icon.short.combined")
        }
    }
}
