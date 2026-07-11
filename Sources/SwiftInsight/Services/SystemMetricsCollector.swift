import Foundation
import Darwin

/// 采集整机 CPU / 内存 / Swap / 网络 / 磁盘吞吐
/// 注意：sample() 应在同一后台队列串行调用，以维护差分状态
enum SystemMetricsCollector {

    private static var previousCPU: host_cpu_load_info?
    private static var previousCoreTicks: [[UInt32]]?
    private static var previousNet: (inBytes: UInt64, outBytes: UInt64, time: TimeInterval)?
    private static var previousDisk: (read: UInt64, write: UInt64, time: TimeInterval)?
    /// 上一帧有效 CPU 结果，供首帧/无效差分时回退
    private static var lastValidCPU: (user: Double, system: Double, idle: Double, nice: Double)?
    private static var lastValidCores: [Double]?
    private static var cachedPCores: Int?
    private static var cachedECores: Int?

    static func sample() -> SystemMetrics {
        var metrics = SystemMetrics()
        metrics.processorCount = ProcessInfo.processInfo.activeProcessorCount
        metrics.physicalMemory = ProcessInfo.processInfo.physicalMemory
        metrics.thermalState = ProcessInfo.processInfo.thermalState.rawValue
        fillCoreTopology(&metrics)

        fillCPU(&metrics)
        fillPerCoreCPU(&metrics)
        fillSwap(&metrics)
        fillMemory(&metrics)
        fillLoad(&metrics)
        fillNetwork(&metrics)
        fillDisk(&metrics)
        // Intel 可公开读频率；Apple Silicon 需 helper sensors
        fillPublicFrequency(&metrics)
        return metrics
    }

    private static func fillPublicFrequency(_ metrics: inout SystemMetrics) {
        var hz: UInt64 = 0
        var size = MemoryLayout<UInt64>.size
        if sysctlbyname("hw.cpufrequency", &hz, &size, nil, 0) == 0, hz > 0 {
            metrics.cpuFrequencyMHz = Double(hz) / 1_000_000.0
        }
    }

    // MARK: - Topology (P/E)

    private static func fillCoreTopology(_ metrics: inout SystemMetrics) {
        if cachedPCores == nil {
            cachedPCores = sysctlInt("hw.perflevel0.logicalcpu")
            cachedECores = sysctlInt("hw.perflevel1.logicalcpu")
        }
        let p = cachedPCores ?? 0
        let e = cachedECores ?? 0
        metrics.performanceCoreCount = max(0, p)
        metrics.efficiencyCoreCount = max(0, e)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return 0 }
        return Int(value)
    }

    // MARK: - CPU（差分；首帧不显示 100%）

    private static func fillCPU(_ metrics: inout SystemMetrics) {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var cpuInfo = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &cpuInfo) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            applyLastCPU(&metrics)
            return
        }

        if let prev = previousCPU {
            let dUser = Double(cpuInfo.cpu_ticks.0 &- prev.cpu_ticks.0)
            let dSystem = Double(cpuInfo.cpu_ticks.1 &- prev.cpu_ticks.1)
            let dIdle = Double(cpuInfo.cpu_ticks.2 &- prev.cpu_ticks.2)
            let dNice = Double(cpuInfo.cpu_ticks.3 &- prev.cpu_ticks.3)
            let total = dUser + dSystem + dIdle + dNice
            if total > 0 {
                metrics.cpuUser = dUser / total * 100
                metrics.cpuSystem = dSystem / total * 100
                metrics.cpuIdle = dIdle / total * 100
                metrics.cpuNice = dNice / total * 100
                lastValidCPU = (metrics.cpuUser, metrics.cpuSystem, metrics.cpuIdle, metrics.cpuNice)
            } else {
                applyLastCPU(&metrics)
            }
        } else {
            if let last = lastValidCPU {
                metrics.cpuUser = last.user
                metrics.cpuSystem = last.system
                metrics.cpuIdle = last.idle
                metrics.cpuNice = last.nice
            } else {
                metrics.cpuUser = 0
                metrics.cpuSystem = 0
                metrics.cpuIdle = 100
                metrics.cpuNice = 0
            }
        }
        previousCPU = cpuInfo
    }

    private static func applyLastCPU(_ metrics: inout SystemMetrics) {
        if let last = lastValidCPU {
            metrics.cpuUser = last.user
            metrics.cpuSystem = last.system
            metrics.cpuIdle = last.idle
            metrics.cpuNice = last.nice
        } else {
            metrics.cpuIdle = 100
        }
    }

    // MARK: - Per-core CPU

    private static func fillPerCoreCPU(_ metrics: inout SystemMetrics) {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &infoArray,
            &infoCount
        )
        guard kr == KERN_SUCCESS, let info = infoArray, cpuCount > 0 else {
            if let last = lastValidCores {
                metrics.coreUsages = last
                applyEPAverages(&metrics)
            }
            return
        }
        defer {
            let bytes = vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), bytes)
        }

        let stride = Int(CPU_STATE_MAX)
        var ticks: [[UInt32]] = []
        ticks.reserveCapacity(Int(cpuCount))
        for i in 0..<Int(cpuCount) {
            let base = i * stride
            ticks.append([
                UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]),
            ])
        }

        var usages = [Double](repeating: 0, count: ticks.count)
        if let prev = previousCoreTicks, prev.count == ticks.count {
            for i in 0..<ticks.count {
                let dU = Double(ticks[i][0] &- prev[i][0])
                let dS = Double(ticks[i][1] &- prev[i][1])
                let dI = Double(ticks[i][2] &- prev[i][2])
                let dN = Double(ticks[i][3] &- prev[i][3])
                let total = dU + dS + dI + dN
                if total > 0 {
                    usages[i] = max(0, min(100, (dU + dS + dN) / total * 100))
                } else if let last = lastValidCores, i < last.count {
                    usages[i] = last[i]
                }
            }
        } else if let last = lastValidCores, last.count == ticks.count {
            usages = last
        }

        previousCoreTicks = ticks
        lastValidCores = usages
        metrics.coreUsages = usages
        applyEPAverages(&metrics)
    }

    /// Apple Silicon：核索引通常为 E 核在前、P 核在后
    private static func applyEPAverages(_ metrics: inout SystemMetrics) {
        let eCount = metrics.efficiencyCoreCount
        let pCount = metrics.performanceCoreCount
        let cores = metrics.coreUsages
        guard !cores.isEmpty else { return }

        if eCount + pCount == cores.count, eCount > 0 || pCount > 0 {
            if eCount > 0 {
                let slice = cores.prefix(eCount)
                metrics.efficiencyCoreUsage = slice.reduce(0, +) / Double(eCount)
            }
            if pCount > 0 {
                let slice = cores.suffix(pCount)
                metrics.performanceCoreUsage = slice.reduce(0, +) / Double(pCount)
            }
        } else {
            metrics.efficiencyCoreUsage = 0
            metrics.performanceCoreUsage = cores.reduce(0, +) / Double(cores.count)
        }
    }

    // MARK: - Memory（对齐活动监视器常用口径）

    private static func fillMemory(_ metrics: inout SystemMetrics) {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStat = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &vmStat) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)
        let phys = metrics.physicalMemory

        let free = UInt64(vmStat.free_count) * ps
        let active = UInt64(vmStat.active_count) * ps
        let inactive = UInt64(vmStat.inactive_count) * ps
        let wired = UInt64(vmStat.wire_count) * ps
        let compressed = UInt64(vmStat.compressor_page_count) * ps
        let speculative = UInt64(vmStat.speculative_count) * ps
        let purgeable = UInt64(vmStat.purgeable_count) * ps
        let external = UInt64(vmStat.external_page_count) * ps
        let internalPages = UInt64(vmStat.internal_page_count) * ps

        let appMemory: UInt64
        if internalPages >= purgeable {
            appMemory = internalPages - purgeable
        } else {
            appMemory = active + inactive + speculative
        }

        var used = appMemory + wired + compressed
        if used > phys { used = phys }

        metrics.freeMemory = free + speculative
        metrics.wiredMemory = wired
        metrics.compressedMemory = compressed
        metrics.appMemory = appMemory
        metrics.cachedFiles = external
        metrics.usedMemory = used
        applyMemoryPressure(&metrics)
    }

    /// 对齐活动监视器 / jetsam：
    /// - `kern.memorystatus_vm_pressure_level`：1 正常 · 2 警告 · 4 危急（内核离散档）
    /// - `kern.memorystatus_level`：0–100，越高表示 jetsam 视角越宽松
    /// 连续百分比 ≈ 100 − memorystatus_level，并按离散档夹紧到活动监视器三色区间
    private static func applyMemoryPressure(_ metrics: inout SystemMetrics) {
        let level = sysctlInt("kern.memorystatus_vm_pressure_level")
        // 未见过 0；缺省当正常
        let pressureLevel = level > 0 ? level : 1
        metrics.memoryPressureLevel = pressureLevel

        var status = sysctlInt("kern.memorystatus_level")
        if status <= 0 {
            // 回退：用可用内存比例近似「宽松度」
            let phys = metrics.physicalMemory
            if phys > 0 {
                let avail = Double(metrics.freeMemory &+ metrics.cachedFiles) / Double(phys) * 100
                status = Int(max(1, min(100, avail)))
            } else {
                status = 50
            }
        }
        status = min(100, max(0, status))

        // 连续值：与内核 jetsam 水位一致
        var continuous = Double(100 - status)

        switch pressureLevel {
        case 4: // 危急 — 活动监视器红区
            continuous = max(continuous, 85)
            continuous = min(100, continuous)
        case 2: // 警告 — 黄区
            continuous = max(continuous, 50)
            continuous = min(84, continuous)
        default: // 正常 — 绿区
            continuous = min(continuous, 49)
            continuous = max(0, continuous)
        }

        metrics.memoryPressure = continuous
    }

    // MARK: - Swap

    private static func fillSwap(_ metrics: inout SystemMetrics) {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        var mib: [Int32] = [CTL_VM, VM_SWAPUSAGE]
        if sysctl(&mib, 2, &usage, &size, nil, 0) == 0 {
            metrics.swapUsed = usage.xsu_used
            metrics.swapTotal = usage.xsu_total
        }
    }

    // MARK: - Load

    private static func fillLoad(_ metrics: inout SystemMetrics) {
        var loads = [Double](repeating: 0, count: 3)
        if getloadavg(&loads, 3) == 3 {
            metrics.loadAverage1 = loads[0]
            metrics.loadAverage5 = loads[1]
            metrics.loadAverage15 = loads[2]
        }
    }

    // MARK: - Network

    private static func fillNetwork(_ metrics: inout SystemMetrics) {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }

        var inBytes: UInt64 = 0
        var outBytes: UInt64 = 0
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let current = ptr {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if isUp, !isLoopback, let data = current.pointee.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self)
                inBytes += UInt64(networkData.pointee.ifi_ibytes)
                outBytes += UInt64(networkData.pointee.ifi_obytes)
            }
            ptr = current.pointee.ifa_next
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let prev = previousNet {
            let dt = now - prev.time
            if dt > 0.05 {
                metrics.networkInBytesPerSec = Double(inBytes &- prev.inBytes) / dt
                metrics.networkOutBytesPerSec = Double(outBytes &- prev.outBytes) / dt
            }
        }
        previousNet = (inBytes, outBytes, now)
    }

    // MARK: - Disk（用 pageins/pageouts 近似换页压力，非真实磁盘吞吐）

    private static func fillDisk(_ metrics: inout SystemMetrics) {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vmStat = vm_statistics64()
        let result = withUnsafeMutablePointer(to: &vmStat) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }

        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)
        let ps = UInt64(pageSize)
        let read = UInt64(vmStat.pageins) * ps
        let write = UInt64(vmStat.pageouts) * ps
        let now = ProcessInfo.processInfo.systemUptime

        if let prev = previousDisk {
            let dt = now - prev.time
            if dt > 0.05 {
                metrics.diskReadBytesPerSec = Double(read &- prev.read) / dt
                metrics.diskWriteBytesPerSec = Double(write &- prev.write) / dt
            }
        }
        previousDisk = (read, write, now)
    }
}

import Darwin.sys.sysctl

private let CTL_VM: Int32 = 2
private let VM_SWAPUSAGE: Int32 = 5

private struct xsw_usage {
    var xsu_total: UInt64 = 0
    var xsu_avail: UInt64 = 0
    var xsu_used: UInt64 = 0
    var xsu_pagesize: UInt32 = 0
    var xsu_encrypted: boolean_t = 0
}
