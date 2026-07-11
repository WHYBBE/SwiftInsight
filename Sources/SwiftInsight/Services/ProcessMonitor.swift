import Foundation
import Darwin
import AppKit
import Combine

/// 实时采集进程列表与资源占用，并按 Apple / 第三方分类汇总
@MainActor
final class ProcessMonitor: ObservableObject {

    @Published private(set) var processes: [MonitoredProcess] = []
    @Published private(set) var summary = ResourceSummary()
    @Published private(set) var lastUpdate: Date = .distantPast
    @Published private(set) var isRunning = false
    /// 按住 Control 时为 true，自动刷新暂停
    @Published private(set) var isRefreshPaused = false
    @Published var refreshInterval: TimeInterval = 2.0 {
        didSet { restartTimer() }
    }

    @Published var sortColumn: SortColumn = .cpu
    @Published var sortAscending = false
    @Published var filterText = ""
    @Published var categoryFilter: ProcessCategory? = nil
    @Published var showOnlyApps = false

    private var timer: Timer?
    private var previousCPU: [Int32: (utime: Double, stime: Double, wall: TimeInterval)] = [:]
    private var classificationCache: [Int32: (path: String, category: ProcessCategory, kind: ProcessKind, bid: String?)] = [:]
    private var usernameCache: [uid_t: String] = [:]
    private let cpuCount: Double

    /// 状态栏文案
    var statusText: String {
        if !isRunning {
            return "已停止"
        }
        if isRefreshPaused {
            return "已暂停 · 松开 ⌃ 继续"
        }
        return "实时 · 每 \(Int(refreshInterval)) 秒"
    }

    init() {
        cpuCount = Double(ProcessInfo.processInfo.activeProcessorCount)
    }

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refresh()
        restartTimer()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func setRefreshPaused(_ paused: Bool) {
        guard isRefreshPaused != paused else { return }
        isRefreshPaused = paused
        // 松开 Control 后立刻补一次刷新，避免数据过旧
        if !paused, isRunning {
            refresh()
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        guard isRunning else { return }
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRunning, !self.isRefreshPaused else { return }
                self.refresh()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // MARK: - Filtering / Sorting

    var displayedProcesses: [MonitoredProcess] {
        var list = processes

        if let cat = categoryFilter {
            list = list.filter { $0.category == cat }
        }

        if showOnlyApps {
            list = list.filter { $0.kind == .app }
        }

        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.name.lowercased().contains(q)
                    || $0.path.lowercased().contains(q)
                    || ($0.bundleIdentifier?.lowercased().contains(q) ?? false)
                    || String($0.pid).contains(q)
                    || $0.username.lowercased().contains(q)
            }
        }

        list.sort { a, b in
            let result: Bool
            switch sortColumn {
            case .cpu:     result = a.cpuPercent < b.cpuPercent
            case .memory:  result = a.memoryBytes < b.memoryBytes
            case .name:    result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .pid:     result = a.pid < b.pid
            case .threads: result = a.threadCount < b.threadCount
            }
            return sortAscending ? result : !result
        }
        return list
    }

    func toggleSort(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = (column == .name || column == .pid)
        }
    }

    // MARK: - Kill / Sample

    func terminate(pid: Int32, force: Bool = false) {
        let sig = force ? SIGKILL : SIGTERM
        kill(pid, sig)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.refresh()
        }
    }

    // MARK: - Core refresh

    func refresh() {
        let now = Date()
        let wallNow = ProcessInfo.processInfo.systemUptime

        var pids = [Int32](repeating: 0, count: 4096)
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<Int32>.size * pids.count))
        guard count > 0 else { return }

        let pidCount = Int(count) / MemoryLayout<Int32>.size
        var result: [MonitoredProcess] = []
        result.reserveCapacity(pidCount)
        var newSummary = ResourceSummary()
        var seen: Set<Int32> = []
        var newPrev: [Int32: (utime: Double, stime: Double, wall: TimeInterval)] = [:]

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0, !seen.contains(pid) else { continue }
            seen.insert(pid)

            guard let info = taskInfo(for: pid) else { continue }

            let path = processPath(pid: pid)
            let name = processName(pid: pid, path: path, fallback: info.name)

            let cached = classificationCache[pid]
            let bid: String?
            let category: ProcessCategory
            let kind: ProcessKind

            if let c = cached, c.path == path {
                bid = c.bid
                category = c.category
                kind = c.kind
            } else {
                let resolvedBID = ProcessClassifier.bundleIdentifier(forPath: path)
                let classified = ProcessClassifier.classify(path: path, name: name, bundleID: resolvedBID)
                bid = resolvedBID
                category = classified.0
                kind = classified.1
                classificationCache[pid] = (path, category, kind, bid)
            }

            let (utime, stime) = cpuTimes(for: pid, taskInfo: info)
            let cpu: Double
            if let prev = previousCPU[pid] {
                let dUser = utime - prev.utime
                let dSys = stime - prev.stime
                let dWall = wallNow - prev.wall
                if dWall > 0 {
                    // 与活动监视器一致：总和可超过 100%（多核）
                    cpu = max(0, (dUser + dSys) / dWall * 100.0)
                } else {
                    cpu = 0
                }
            } else {
                cpu = 0
            }
            newPrev[pid] = (utime, stime, wallNow)

            let username = username(for: info.uid)
            let start = startTime(for: pid)

            let process = MonitoredProcess(
                pid: pid,
                name: name,
                path: path,
                bundleIdentifier: bid,
                category: category,
                kind: kind,
                cpuPercent: cpu,
                memoryBytes: info.residentSize,
                virtualMemoryBytes: info.virtualSize,
                threadCount: info.threadCount,
                userTime: utime,
                systemTime: stime,
                ppid: info.ppid,
                uid: info.uid,
                username: username,
                startTime: start
            )
            result.append(process)
            newSummary.add(process)
        }

        // 清理已退出进程缓存
        let live = seen
        classificationCache = classificationCache.filter { live.contains($0.key) }
        previousCPU = newPrev

        processes = result
        summary = newSummary
        lastUpdate = now
    }

    // MARK: - Low-level process info

    private struct RawTaskInfo {
        var name: String
        var residentSize: UInt64
        var virtualSize: UInt64
        var threadCount: Int
        var ppid: Int32
        var uid: uid_t
        var userTime: Double
        var systemTime: Double
    }

    private func taskInfo(for pid: Int32) -> RawTaskInfo? {
        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        let bsdResult = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize)
        guard bsdResult == bsdSize else { return nil }

        var taskInfo = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        let taskResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize)

        var resident: UInt64 = 0
        var virtual: UInt64 = 0
        var threads = 0
        var userT: Double = 0
        var sysT: Double = 0

        if taskResult == taskSize {
            resident = taskInfo.pti_resident_size
            virtual = taskInfo.pti_virtual_size
            threads = Int(taskInfo.pti_threadnum)
            // pti_total_user / pti_total_system 单位为纳秒（绝对时间）
            userT = Double(taskInfo.pti_total_user) / 1_000_000_000.0
            sysT = Double(taskInfo.pti_total_system) / 1_000_000_000.0
        }

        // pbi_name 是 CChar 元组
        let name = withUnsafePointer(to: bsdInfo.pbi_name) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) * 2) {
                String(cString: $0)
            }
        }

        return RawTaskInfo(
            name: name.isEmpty ? "(\(pid))" : name,
            residentSize: resident,
            virtualSize: virtual,
            threadCount: threads,
            ppid: Int32(bsdInfo.pbi_ppid),
            uid: bsdInfo.pbi_uid,
            userTime: userT,
            systemTime: sysT
        )
    }

    private func cpuTimes(for pid: Int32, taskInfo info: RawTaskInfo) -> (Double, Double) {
        (info.userTime, info.systemTime)
    }

    private func processPath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if ret > 0 {
            return String(cString: buffer)
        }
        return ""
    }

    private func processName(pid: Int32, path: String, fallback: String) -> String {
        if !path.isEmpty {
            let base = URL(fileURLWithPath: path).lastPathComponent
            if !base.isEmpty { return base }
        }
        if !fallback.isEmpty { return fallback }
        return "pid-\(pid)"
    }

    private func username(for uid: uid_t) -> String {
        if let cached = usernameCache[uid] { return cached }
        if let pw = getpwuid(uid), let name = pw.pointee.pw_name {
            let s = String(cString: name)
            usernameCache[uid] = s
            return s
        }
        let s = "\(uid)"
        usernameCache[uid] = s
        return s
    }

    private func startTime(for pid: Int32) -> Date? {
        var bsdInfo = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, size) == size else {
            return nil
        }
        // pbi_start_tvsec
        let sec = TimeInterval(bsdInfo.pbi_start_tvsec)
        if sec <= 0 { return nil }
        return Date(timeIntervalSince1970: sec)
    }
}

// MARK: - Darwin helpers

import Darwin.sys.sysctl

// proc_info 常量在 libproc 中
private let PROC_ALL_PIDS: Int32 = 1
private let PROC_PIDTBSDINFO: Int32 = 3
private let PROC_PIDTASKINFO: Int32 = 4
private let MAXCOMLEN: Int32 = 16

@_silgen_name("proc_listpids")
private func proc_listpids(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidpath")
private func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

// BSD / task info 结构（与 libproc.h 对齐）
private struct proc_bsdinfo {
    var pbi_flags: UInt32 = 0
    var pbi_status: UInt32 = 0
    var pbi_xstatus: UInt32 = 0
    var pbi_pid: UInt32 = 0
    var pbi_ppid: UInt32 = 0
    var pbi_uid: uid_t = 0
    var pbi_gid: gid_t = 0
    var pbi_ruid: uid_t = 0
    var pbi_rgid: gid_t = 0
    var pbi_svuid: uid_t = 0
    var pbi_svgid: gid_t = 0
    var rfu_1: UInt32 = 0
    var pbi_comm: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                   CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var pbi_name: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                   CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                   CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                   CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
         0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var pbi_nfiles: UInt32 = 0
    var pbi_pgid: UInt32 = 0
    var pbi_pjobc: UInt32 = 0
    var e_tdev: UInt32 = 0
    var e_tpgid: UInt32 = 0
    var pbi_nice: Int32 = 0
    var pbi_start_tvsec: UInt64 = 0
    var pbi_start_tvusec: UInt64 = 0
}

private struct proc_taskinfo {
    var pti_virtual_size: UInt64 = 0
    var pti_resident_size: UInt64 = 0
    var pti_total_user: UInt64 = 0
    var pti_total_system: UInt64 = 0
    var pti_threads_user: UInt64 = 0
    var pti_threads_system: UInt64 = 0
    var pti_policy: Int32 = 0
    var pti_faults: Int32 = 0
    var pti_pageins: Int32 = 0
    var pti_cow_faults: Int32 = 0
    var pti_messages_sent: Int32 = 0
    var pti_messages_received: Int32 = 0
    var pti_syscalls_mach: Int32 = 0
    var pti_syscalls_unix: Int32 = 0
    var pti_csw: Int32 = 0
    var pti_threadnum: Int32 = 0
    var pti_numrunning: Int32 = 0
    var pti_priority: Int32 = 0
}
