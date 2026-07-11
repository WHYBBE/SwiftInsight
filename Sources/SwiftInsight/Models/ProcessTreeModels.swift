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
    case parentTree

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .flat: return L("mode.flat")
        case .tree: return L("mode.tree")
        case .parentTree: return L("mode.parentTree")
        }
    }
}

// MARK: - History samples

struct MetricSample: Identifiable, Equatable {
    let id: Date
    let date: Date
    let cpu: Double
    let memoryBytes: UInt64

    init(date: Date = Date(), cpu: Double, memoryBytes: UInt64) {
        self.id = date
        self.date = date
        self.cpu = cpu
        self.memoryBytes = memoryBytes
    }
}

struct SystemHistorySample: Identifiable, Equatable {
    let id: Date
    let date: Date
    let cpu: Double
    let memoryPercent: Double
    let thirdPartyCPU: Double
    let appleCPU: Double

    init(
        date: Date = Date(),
        cpu: Double,
        memoryPercent: Double,
        thirdPartyCPU: Double,
        appleCPU: Double
    ) {
        self.id = date
        self.date = date
        self.cpu = cpu
        self.memoryPercent = memoryPercent
        self.thirdPartyCPU = thirdPartyCPU
        self.appleCPU = appleCPU
    }
}

enum HistoryWindow: TimeInterval, CaseIterable, Identifiable {
    case thirtySeconds = 30
    case twoMinutes = 120
    case fiveMinutes = 300

    var id: TimeInterval { rawValue }

    var displayName: String {
        switch self {
        case .thirtySeconds: return L("history.30s")
        case .twoMinutes: return L("history.2m")
        case .fiveMinutes: return L("history.5m")
        }
    }
}
