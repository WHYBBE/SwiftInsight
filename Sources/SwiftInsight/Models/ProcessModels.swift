import Foundation

/// 进程归属分类：核心能力是区分 Apple 第一方与第三方
enum ProcessCategory: String, CaseIterable, Identifiable, Codable {
    case appleSystem   // 系统核心 / 守护进程
    case appleApp      // Apple 第一方应用
    case thirdParty    // 第三方应用
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .appleSystem: return "Apple 系统"
        case .appleApp:    return "Apple 应用"
        case .thirdParty:  return "第三方"
        case .unknown:     return "未知"
        }
    }

    var shortName: String {
        switch self {
        case .appleSystem: return "系统"
        case .appleApp:    return "官方"
        case .thirdParty:  return "三方"
        case .unknown:     return "未知"
        }
    }

    var symbolName: String {
        switch self {
        case .appleSystem: return "gearshape.2.fill"
        case .appleApp:    return "apple.logo"
        case .thirdParty:  return "app.badge"
        case .unknown:     return "questionmark.circle"
        }
    }

    var isApple: Bool {
        self == .appleSystem || self == .appleApp
    }
}

enum ProcessKind: String, Codable {
    case app
    case daemon
    case helper
    case kernel
    case shell
    case other
}

struct MonitoredProcess: Identifiable, Hashable {
    let pid: Int32
    var id: Int32 { pid }

    var name: String
    var path: String
    var bundleIdentifier: String?
    var category: ProcessCategory
    var kind: ProcessKind

    /// 单核百分比累计（与活动监视器一致，可 >100%）
    var cpuPercent: Double
    /// 物理内存 RSS（字节）
    var memoryBytes: UInt64
    /// 虚拟内存
    var virtualMemoryBytes: UInt64
    /// 线程数
    var threadCount: Int
    /// 用户 / 系统 CPU 时间（秒）
    var userTime: Double
    var systemTime: Double
    /// 父进程 PID
    var ppid: Int32
    /// 用户 ID
    var uid: uid_t
    var username: String
    /// 启动时间
    var startTime: Date?

    var memoryMB: Double {
        Double(memoryBytes) / 1_048_576.0
    }

    var memoryFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }

    var cpuFormatted: String {
        String(format: "%.1f%%", cpuPercent)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pid)
    }

    static func == (lhs: MonitoredProcess, rhs: MonitoredProcess) -> Bool {
        lhs.pid == rhs.pid
    }
}

struct ResourceSummary: Equatable {
    var appleSystemCPU: Double = 0
    var appleAppCPU: Double = 0
    var thirdPartyCPU: Double = 0
    var unknownCPU: Double = 0

    var appleSystemMemory: UInt64 = 0
    var appleAppMemory: UInt64 = 0
    var thirdPartyMemory: UInt64 = 0
    var unknownMemory: UInt64 = 0

    var appleSystemCount: Int = 0
    var appleAppCount: Int = 0
    var thirdPartyCount: Int = 0
    var unknownCount: Int = 0

    var totalCPU: Double {
        appleSystemCPU + appleAppCPU + thirdPartyCPU + unknownCPU
    }

    var totalMemory: UInt64 {
        appleSystemMemory + appleAppMemory + thirdPartyMemory + unknownMemory
    }

    var appleCPU: Double { appleSystemCPU + appleAppCPU }
    var appleMemory: UInt64 { appleSystemMemory + appleAppMemory }
    var appleCount: Int { appleSystemCount + appleAppCount }

    var totalCount: Int {
        appleSystemCount + appleAppCount + thirdPartyCount + unknownCount
    }

    mutating func add(_ process: MonitoredProcess) {
        switch process.category {
        case .appleSystem:
            appleSystemCPU += process.cpuPercent
            appleSystemMemory += process.memoryBytes
            appleSystemCount += 1
        case .appleApp:
            appleAppCPU += process.cpuPercent
            appleAppMemory += process.memoryBytes
            appleAppCount += 1
        case .thirdParty:
            thirdPartyCPU += process.cpuPercent
            thirdPartyMemory += process.memoryBytes
            thirdPartyCount += 1
        case .unknown:
            unknownCPU += process.cpuPercent
            unknownMemory += process.memoryBytes
            unknownCount += 1
        }
    }
}

enum SortColumn: String, CaseIterable, Identifiable {
    case cpu
    case memory
    case name
    case pid
    case threads

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "内存"
        case .name: return "名称"
        case .pid: return "PID"
        case .threads: return "线程"
        }
    }
}
