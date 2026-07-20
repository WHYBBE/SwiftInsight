import Foundation

/// 滚动历史缓冲：系统指标 + 按 PID 的进程指标
final class MetricsHistoryStore {
    private(set) var systemSamples: [SystemHistorySample] = []
    private var processSamples: [Int32: [MetricSample]] = [:]
    private let maxAge: TimeInterval = 5 * 60 + 15
    private let maxPoints = 400

    func record(
        system: SystemMetrics,
        summary: ResourceSummary,
        processes: [MonitoredProcess],
        watchedPID: Int32?
    ) {
        let now = Date()
        systemSamples.append(SystemHistorySample(
            date: now,
            cpu: system.cpuUsed,
            memoryPercent: system.memoryUsedPercent,
            thirdPartyCPU: summary.thirdPartyCPU,
            appleCPU: summary.appleCPU
        ))
        trimSystem(now: now)

        if let pid = watchedPID, let proc = processes.first(where: { $0.pid == pid }) {
            // 权限读不到时不写入历史，避免画出假的 0 曲线
            guard proc.cpuAvailable || proc.memoryAvailable else { return }
            var list = processSamples[pid] ?? []
            list.append(MetricSample(
                date: now,
                cpu: proc.cpuAvailable ? proc.cpuPercent : 0,
                memoryBytes: proc.memoryAvailable ? proc.memoryBytes : 0
            ))
            processSamples[pid] = trim(list, now: now)
        }

        // 清理已不存在的 PID 历史
        let live = Set(processes.map(\.pid))
        processSamples = processSamples.filter { live.contains($0.key) || $0.key == watchedPID }
    }

    /// 图表展示最多点数，降低 Charts 路径重建成本
    private let displayMaxPoints = 90

    func systemHistory(window: HistoryWindow) -> [SystemHistorySample] {
        let cutoff = Date().addingTimeInterval(-window.rawValue)
        let filtered = systemSamples.filter { $0.date >= cutoff }
        return downsample(filtered, maxPoints: displayMaxPoints)
    }

    func processHistory(pid: Int32, window: HistoryWindow) -> [MetricSample] {
        let cutoff = Date().addingTimeInterval(-window.rawValue)
        let filtered = (processSamples[pid] ?? []).filter { $0.date >= cutoff }
        return downsample(filtered, maxPoints: displayMaxPoints)
    }

    private func downsample<T>(_ list: [T], maxPoints: Int) -> [T] {
        guard list.count > maxPoints, maxPoints > 2 else { return list }
        let last = list.count - 1
        var result: [T] = []
        result.reserveCapacity(maxPoints)
        for i in 0..<maxPoints {
            let idx = (i * last) / (maxPoints - 1)
            result.append(list[idx])
        }
        return result
    }

    private func trimSystem(now: Date) {
        let cutoff = now.addingTimeInterval(-maxAge)
        systemSamples.removeAll { $0.date < cutoff }
        if systemSamples.count > maxPoints {
            systemSamples = Array(systemSamples.suffix(maxPoints))
        }
    }

    private func trim(_ list: [MetricSample], now: Date) -> [MetricSample] {
        let cutoff = now.addingTimeInterval(-maxAge)
        var next = list.filter { $0.date >= cutoff }
        if next.count > maxPoints {
            next = Array(next.suffix(maxPoints))
        }
        return next
    }
}
