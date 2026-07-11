import Foundation

/// 列表展示行（扁平或树）
struct ProcessDisplayRow: Identifiable, Hashable {
    /// 稳定 ID：叶子用 pid，聚合根用 groupKey 哈希
    let id: String
    let process: MonitoredProcess
    /// 缩进层级（0 = 根）
    let depth: Int
    /// 是否有子进程
    let hasChildren: Bool
    /// 是否展开
    let isExpanded: Bool
    /// 子进程数量（含自身为 1 时表示叶子）
    let memberCount: Int
    /// 是否为聚合组根（资源已汇总）
    let isGroupRoot: Bool
    /// 分组键，用于展开状态记忆
    let groupKey: String

    var pid: Int32 { process.pid }
}

enum ListDisplayMode: String, CaseIterable, Identifiable {
    case flat
    case tree

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flat: return "列表"
        case .tree: return "聚合"
        }
    }
}
