import Foundation

struct SystemMetrics: Equatable {
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cpuIdle: Double = 0
    var cpuNice: Double = 0

    /// 每逻辑核利用率 0–100（顺序：先 E 核再 P 核，若可区分）
    var coreUsages: [Double] = []
    var performanceCoreCount: Int = 0
    var efficiencyCoreCount: Int = 0
    var performanceCoreUsage: Double = 0
    var efficiencyCoreUsage: Double = 0

    var physicalMemory: UInt64 = 0
    var usedMemory: UInt64 = 0
    var wiredMemory: UInt64 = 0
    var compressedMemory: UInt64 = 0
    var appMemory: UInt64 = 0
    var cachedFiles: UInt64 = 0
    var freeMemory: UInt64 = 0
    var swapUsed: UInt64 = 0
    var swapTotal: UInt64 = 0
    /// 内存压力 0–100（越高越紧张）
    var memoryPressure: Double = 0

    var networkInBytesPerSec: Double = 0
    var networkOutBytesPerSec: Double = 0
    var diskReadBytesPerSec: Double = 0
    var diskWriteBytesPerSec: Double = 0

    var loadAverage1: Double = 0
    var loadAverage5: Double = 0
    var loadAverage15: Double = 0
    var processorCount: Int = 0

    var cpuUsed: Double { max(0, min(100, cpuUser + cpuSystem + cpuNice)) }
    var memoryUsedPercent: Double {
        guard physicalMemory > 0 else { return 0 }
        return Double(usedMemory) / Double(physicalMemory) * 100
    }
    /// 可用 ≈ 空闲 + 文件缓存（展示用）
    var availableMemory: UInt64 {
        let sum = freeMemory &+ cachedFiles
        return min(sum, physicalMemory)
    }

    var cpuFormatted: String { String(format: "%.0f%%", cpuUsed) }
    var memoryFormatted: String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(usedMemory), countStyle: .memory)) / \(ByteCountFormatter.string(fromByteCount: Int64(physicalMemory), countStyle: .memory))"
    }
    var memoryDetailFormatted: String {
        let app = ByteCountFormatter.string(fromByteCount: Int64(appMemory), countStyle: .memory)
        let wired = ByteCountFormatter.string(fromByteCount: Int64(wiredMemory), countStyle: .memory)
        let comp = ByteCountFormatter.string(fromByteCount: Int64(compressedMemory), countStyle: .memory)
        return "应用 \(app) · 联动 \(wired) · 压缩 \(comp)"
    }
    var swapFormatted: String {
        ByteCountFormatter.string(fromByteCount: Int64(swapUsed), countStyle: .memory)
    }
    var networkFormatted: String {
        "↓\(rateString(networkInBytesPerSec))  ↑\(rateString(networkOutBytesPerSec))"
    }
    var diskFormatted: String {
        "R \(rateString(diskReadBytesPerSec))  W \(rateString(diskWriteBytesPerSec))"
    }
    var loadFormatted: String {
        String(format: "%.2f  %.2f  %.2f", loadAverage1, loadAverage5, loadAverage15)
    }
    var coreSummaryFormatted: String {
        if performanceCoreCount > 0 || efficiencyCoreCount > 0 {
            return String(format: "E %.0f%%  P %.0f%%", efficiencyCoreUsage, performanceCoreUsage)
        }
        return String(format: "%d 核", processorCount)
    }

    private func rateString(_ bytesPerSec: Double) -> String {
        let n = max(0, bytesPerSec)
        if n < 1024 { return String(format: "%.0f B/s", n) }
        if n < 1024 * 1024 { return String(format: "%.1f KB/s", n / 1024) }
        if n < 1024 * 1024 * 1024 { return String(format: "%.1f MB/s", n / (1024 * 1024)) }
        return String(format: "%.2f GB/s", n / (1024 * 1024 * 1024))
    }
}

struct ProcessRankingItem: Identifiable, Hashable {
    var id: Int32 { process.pid }
    let process: MonitoredProcess
    let metricLabel: String
}

struct CategoryRankings: Equatable {
    var thirdPartyByCPU: [ProcessRankingItem] = []
    var thirdPartyByMemory: [ProcessRankingItem] = []
    var appleSystemByCPU: [ProcessRankingItem] = []
    var appleAppByCPU: [ProcessRankingItem] = []
}

struct ProcessOpenFile: Identifiable, Hashable {
    let id: Int32
    let fd: Int32
    let path: String
    let kind: String
}

struct ProcessDetailInfo: Equatable {
    var openFiles: [ProcessOpenFile] = []
    var openFileCount: Int = 0
    var parentName: String?
    var sampleNote: String = ""
}
