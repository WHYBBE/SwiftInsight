import Foundation
import Darwin

/// 采集整机 CPU / 内存 / Swap / 网络 / 磁盘吞吐
/// 注意：sample() 应在同一后台队列串行调用，以维护差分状态
enum SystemMetricsCollector {

    private static var previousCPU: host_cpu_load_info?
    private static var previousNet: (inBytes: UInt64, outBytes: UInt64, time: TimeInterval)?
    private static var previousDisk: (read: UInt64, write: UInt64, time: TimeInterval)?
    /// 上一帧有效 CPU 结果，供首帧/无效差分时回退
    private static var lastValidCPU: (user: Double, system: Double, idle: Double, nice: Double)?

    static func sample() -> SystemMetrics {
        var metrics = SystemMetrics()
        metrics.processorCount = ProcessInfo.processInfo.activeProcessorCount
        metrics.physicalMemory = ProcessInfo.processInfo.physicalMemory

        fillCPU(&metrics)
        fillMemory(&metrics)
        fillSwap(&metrics)
        fillLoad(&metrics)
        fillNetwork(&metrics)
        fillDisk(&metrics)
        return metrics
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
            // 无符号环绕减法
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
            // 首帧：建立基线，不显示 100%。优先回退上次有效值，否则视为空闲。
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

    // MARK: - Memory（对齐活动监视器常用口径）
    // App Memory ≈ internal - purgeable
    // Wired Memory = wire
    // Compressed = compressor pages
    // Memory Used ≈ App + Wired + Compressed
    // Cached Files ≈ external

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

        // 应用内存：内部页减去可清除页（活动监视器 App Memory 近似）
        let appMemory: UInt64
        if internalPages >= purgeable {
            appMemory = internalPages - purgeable
        } else {
            // 旧系统无 internal 字段时的回退
            appMemory = active + inactive + speculative
        }

        // 已用内存 = 应用 + 联动 + 压缩（不要用 phys - free，会把文件缓存算进去导致接近 100%）
        var used = appMemory + wired + compressed
        if used > phys { used = phys }

        metrics.freeMemory = free + speculative
        metrics.wiredMemory = wired
        metrics.compressedMemory = compressed
        metrics.appMemory = appMemory
        metrics.cachedFiles = external
        metrics.usedMemory = used
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
