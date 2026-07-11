import Foundation

/// 菜单栏图标展示模式
enum MenuBarIconMode: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case combined

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: return "CPU 状态条"
        case .memory: return "内存状态条"
        case .combined: return "CPU + 内存"
        }
    }

    var shortName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .combined: return "叠加"
        }
    }
}
