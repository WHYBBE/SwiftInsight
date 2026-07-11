import Foundation
import Darwin
import Combine

/// 实时采集进程列表与资源占用，并按 Apple / 第三方分类汇总
@MainActor
final class ProcessMonitor: ObservableObject {

    @Published private(set) var processes: [MonitoredProcess] = []
    /// 已过滤/排序的稳定快照，供列表直接使用
    @Published private(set) var displayedProcesses: [MonitoredProcess] = []
    /// 树形/列表统一展示行
    @Published private(set) var displayRows: [ProcessDisplayRow] = []
    @Published private(set) var summary = ResourceSummary()
    @Published private(set) var systemMetrics = SystemMetrics()
    @Published private(set) var rankings = CategoryRankings()
    @Published private(set) var selectedDetail = ProcessDetailInfo()
    @Published private(set) var systemHistory: [SystemHistorySample] = []
    @Published private(set) var processHistory: [MetricSample] = []
    @Published private(set) var lastUpdate: Date = .distantPast
    @Published private(set) var isRunning = false
    /// 按住 Control 时为 true，自动刷新暂停
    @Published private(set) var isRefreshPaused = false
    @Published var refreshInterval: TimeInterval = 2.0 {
        didSet { restartTimer() }
    }

    @Published var sortColumn: SortColumn = .cpu {
        didSet { recomputeDisplayed() }
    }
    @Published var sortAscending = false {
        didSet { recomputeDisplayed() }
    }
    @Published var filterText = "" {
        didSet { recomputeDisplayed() }
    }
    @Published var categoryFilter: ProcessCategory? = nil {
        didSet { recomputeDisplayed() }
    }
    @Published var showOnlyApps = false {
        didSet { recomputeDisplayed() }
    }
    /// 列表 / 应用聚合 / PPID 父子树
    @Published var displayMode: ListDisplayMode = .tree {
        didSet { recomputeDisplayed() }
    }
    /// 历史窗口
    @Published var historyWindow: HistoryWindow = .twoMinutes {
        didSet { publishHistory() }
    }
    /// 展开的聚合/父子节点 key
    @Published private(set) var expandedGroups: Set<String> = []
    /// 当前选中 PID（用于详情增强与历史曲线）
    @Published var inspectedPID: Int32? = nil {
        didSet {
            refreshInspectedDetail()
            publishHistory()
        }
    }

    @Published private(set) var privilegedHelperInstalled = false
    @Published private(set) var privilegedHelperRoot = false

    private var timer: Timer?
    private var previousCPU: [Int32: (utime: Double, stime: Double, wall: TimeInterval)] = [:]
    private var classificationCache: [Int32: (path: String, category: ProcessCategory, kind: ProcessKind, bid: String?)] = [:]
    private var usernameCache: [uid_t: String] = [:]
    private var isSampling = false
    private let sampleQueue = DispatchQueue(label: "com.swiftinsight.process-sample", qos: .userInitiated)
    private let historyStore = MetricsHistoryStore()

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

    // MARK: - Lifecycle

    func start() {
        guard !isRunning else { return }
        isRunning = true
        refreshHelperStatus()
        // 预热系统指标基线，避免首帧 CPU 无差分
        sampleQueue.async {
            _ = SystemMetricsCollector.sample()
        }
        refresh()
        restartTimer()
    }

    func refreshHelperStatus() {
        let status = PrivilegedMetricsClient.helperStatus()
        privilegedHelperInstalled = status.installed
        privilegedHelperRoot = status.root
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func setRefreshPaused(_ paused: Bool) {
        guard isRefreshPaused != paused else { return }
        isRefreshPaused = paused
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

    func toggleSort(_ column: SortColumn) {
        if sortColumn == column {
            sortAscending.toggle()
        } else {
            sortColumn = column
            sortAscending = (column == .name || column == .pid)
        }
    }

    func toggleExpanded(_ groupKey: String) {
        if expandedGroups.contains(groupKey) {
            expandedGroups.remove(groupKey)
        } else {
            expandedGroups.insert(groupKey)
        }
        recomputeDisplayed()
    }

    func setExpanded(_ groupKey: String, _ expanded: Bool) {
        if expanded {
            expandedGroups.insert(groupKey)
        } else {
            expandedGroups.remove(groupKey)
        }
        recomputeDisplayed()
    }

    private func recomputeDisplayed() {
        let filtered = Self.filterProcesses(
            processes: processes,
            categoryFilter: categoryFilter,
            showOnlyApps: showOnlyApps,
            filterText: filterText
        )

        switch displayMode {
        case .flat:
            let sorted = Self.sortProcesses(filtered, column: sortColumn, ascending: sortAscending)
            displayedProcesses = sorted
            displayRows = sorted.map { p in
                ProcessDisplayRow(
                    id: "pid:\(p.pid)",
                    process: p,
                    depth: 0,
                    hasChildren: false,
                    isExpanded: false,
                    memberCount: 1,
                    isGroupRoot: false,
                    groupKey: "pid:\(p.pid)"
                )
            }
        case .tree:
            let forest = ProcessAggregator.buildForest(from: filtered)
            let rows = ProcessAggregator.flatten(
                forest,
                expanded: expandedGroups,
                sortColumn: sortColumn,
                sortAscending: sortAscending
            )
            displayRows = rows
            displayedProcesses = rows.map(\.process)
        case .parentTree:
            let forest = ProcessParentTree.buildForest(from: filtered)
            let rows = ProcessParentTree.flatten(
                forest,
                expanded: expandedGroups,
                sortColumn: sortColumn,
                sortAscending: sortAscending,
                rollupWhenCollapsed: false
            )
            displayRows = rows
            displayedProcesses = rows.map(\.process)
        }
    }

    private static func filterProcesses(
        processes: [MonitoredProcess],
        categoryFilter: ProcessCategory?,
        showOnlyApps: Bool,
        filterText: String
    ) -> [MonitoredProcess] {
        var list = processes

        if let cat = categoryFilter {
            list = list.filter { $0.category == cat }
        }

        if showOnlyApps {
            list = list.filter { $0.kind == .app || $0.path.contains(".app/") }
        }

        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !q.isEmpty {
            // 搜索命中时保留同组相关进程（通过名称族 / app 路径）
            let matched = list.filter {
                $0.name.lowercased().contains(q)
                    || $0.path.lowercased().contains(q)
                    || ($0.bundleIdentifier?.lowercased().contains(q) ?? false)
                    || String($0.pid).contains(q)
                    || $0.username.lowercased().contains(q)
            }
            if matched.isEmpty {
                list = []
            } else {
                let keys = Set(matched.map { ProcessAggregator.groupKey(for: $0, all: Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })) })
                let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
                list = list.filter { keys.contains(ProcessAggregator.groupKey(for: $0, all: byPID)) }
            }
        }
        return list
    }

    private static func sortProcesses(_ list: [MonitoredProcess], column: SortColumn, ascending: Bool) -> [MonitoredProcess] {
        list.sorted { a, b in
            let result: Bool
            switch column {
            case .cpu:     result = a.cpuPercent < b.cpuPercent
            case .memory:  result = a.memoryBytes < b.memoryBytes
            case .name:    result = a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            case .pid:     result = a.pid < b.pid
            case .threads: result = a.threadCount < b.threadCount
            }
            return ascending ? result : !result
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

    // MARK: - Core refresh（后台采集，主线程下一帧提交）

    func refresh() {
        guard !isSampling else { return }
        isSampling = true

        let previousCPU = self.previousCPU
        let classificationCache = self.classificationCache
        let usernameCache = self.usernameCache

        sampleQueue.async { [weak self] in
            // 若已安装 setuid helper，用 root 视角补全受限进程指标
            let privileged = PrivilegedMetricsClient.sampleAll()
            let snapshot = ProcessSampler.collect(
                previousCPU: previousCPU,
                classificationCache: classificationCache,
                usernameCache: usernameCache,
                privileged: privileged
            )
            DispatchQueue.main.async {
                self?.applySnapshot(snapshot)
            }
        }
    }

    private func applySnapshot(_ snapshot: ProcessSampler.Snapshot) {
        previousCPU = snapshot.previousCPU
        classificationCache = snapshot.classificationCache
        usernameCache = snapshot.usernameCache
        lastUpdate = snapshot.timestamp
        summary = snapshot.summary
        processes = snapshot.processes
        systemMetrics = snapshot.systemMetrics
        rankings = Self.buildRankings(from: snapshot.processes)

        historyStore.record(
            system: snapshot.systemMetrics,
            summary: snapshot.summary,
            processes: snapshot.processes,
            watchedPID: inspectedPID
        )
        publishHistory()

        recomputeDisplayed()
        refreshInspectedDetail()
        isSampling = false
    }

    private func publishHistory() {
        systemHistory = historyStore.systemHistory(window: historyWindow)
        if let pid = inspectedPID {
            processHistory = historyStore.processHistory(pid: pid, window: historyWindow)
        } else {
            processHistory = []
        }
    }

    private func refreshInspectedDetail() {
        guard let pid = inspectedPID else {
            selectedDetail = ProcessDetailInfo()
            return
        }
        // 打开文件扫描较重，放到后台
        let all = processes
        sampleQueue.async { [weak self] in
            let detail = ProcessInspector.inspect(pid: pid, processes: all)
            DispatchQueue.main.async {
                guard let self, self.inspectedPID == pid else { return }
                self.selectedDetail = detail
            }
        }
    }

    private static func buildRankings(from processes: [MonitoredProcess], limit: Int = 5) -> CategoryRankings {
        func top(_ list: [MonitoredProcess], by key: (MonitoredProcess) -> Double, label: (MonitoredProcess) -> String) -> [ProcessRankingItem] {
            list.sorted { key($0) > key($1) }
                .prefix(limit)
                .filter { key($0) > 0.01 || $0.memoryBytes > 1_048_576 }
                .map { ProcessRankingItem(process: $0, metricLabel: label($0)) }
        }

        let third = processes.filter { $0.category == .thirdParty }
        let appleSys = processes.filter { $0.category == .appleSystem }
        let appleApp = processes.filter { $0.category == .appleApp }

        return CategoryRankings(
            thirdPartyByCPU: top(third, by: { $0.cpuAvailable ? $0.cpuPercent : -1 }) {
                $0.cpuAvailable ? String(format: "%.1f%%", $0.cpuPercent) : "N/A"
            },
            thirdPartyByMemory: top(third, by: { $0.memoryAvailable ? Double($0.memoryBytes) : -1 }) {
                $0.memoryFormatted
            },
            appleSystemByCPU: top(appleSys, by: { $0.cpuAvailable ? $0.cpuPercent : -1 }) {
                $0.cpuAvailable ? String(format: "%.1f%%", $0.cpuPercent) : "N/A"
            },
            appleAppByCPU: top(appleApp, by: { $0.cpuAvailable ? $0.cpuPercent : -1 }) {
                $0.cpuAvailable ? String(format: "%.1f%%", $0.cpuPercent) : "N/A"
            }
        )
    }
}

// MARK: - Background sampler

private enum ProcessSampler {
    struct Snapshot {
        var processes: [MonitoredProcess]
        var summary: ResourceSummary
        var previousCPU: [Int32: (utime: Double, stime: Double, wall: TimeInterval)]
        var classificationCache: [Int32: (path: String, category: ProcessCategory, kind: ProcessKind, bid: String?)]
        var usernameCache: [uid_t: String]
        var systemMetrics: SystemMetrics
        var timestamp: Date
    }

    static func collect(
        previousCPU: [Int32: (utime: Double, stime: Double, wall: TimeInterval)],
        classificationCache: [Int32: (path: String, category: ProcessCategory, kind: ProcessKind, bid: String?)],
        usernameCache: [uid_t: String],
        privileged: PrivilegedMetricsClient.Snapshot? = nil
    ) -> Snapshot {
        let now = Date()
        let wallNow = ProcessInfo.processInfo.systemUptime
        let systemMetrics = SystemMetricsCollector.sample()

        var pids = [Int32](repeating: 0, count: 4096)
        let count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<Int32>.size * pids.count))
        guard count > 0 else {
            return Snapshot(
                processes: [],
                summary: ResourceSummary(),
                previousCPU: previousCPU,
                classificationCache: classificationCache,
                usernameCache: usernameCache,
                systemMetrics: systemMetrics,
                timestamp: now
            )
        }

        let pidCount = Int(count) / MemoryLayout<Int32>.size
        var result: [MonitoredProcess] = []
        result.reserveCapacity(pidCount)
        var newSummary = ResourceSummary()
        var seen: Set<Int32> = []
        var newPrev: [Int32: (utime: Double, stime: Double, wall: TimeInterval)] = [:]
        var newClassCache = classificationCache
        var newUserCache = usernameCache

        for i in 0..<pidCount {
            let pid = pids[i]
            guard pid > 0, !seen.contains(pid) else { continue }
            seen.insert(pid)

            guard let info = taskInfo(for: pid, privileged: privileged?.byPID[pid]) else { continue }

            let path = processPath(pid: pid)
            let name = processName(path: path, fallback: info.name)

            let bid: String?
            let category: ProcessCategory
            let kind: ProcessKind

            if let c = newClassCache[pid], c.path == path {
                bid = c.bid
                category = c.category
                kind = c.kind
            } else {
                let resolvedBID = ProcessClassifier.bundleIdentifier(forPath: path)
                let classified = ProcessClassifier.classify(path: path, name: name, bundleID: resolvedBID)
                bid = resolvedBID
                category = classified.0
                kind = classified.1
                newClassCache[pid] = (path, category, kind, bid)
            }

            let utime = info.userTime
            let stime = info.systemTime
            let cpu: Double
            let cpuAvailable: Bool
            if !info.metricsAvailable {
                cpu = 0
                cpuAvailable = false
            } else if let prev = previousCPU[pid] {
                let dUser = utime - prev.utime
                let dSys = stime - prev.stime
                let dWall = wallNow - prev.wall
                if dWall > 0 {
                    cpu = max(0, (dUser + dSys) / dWall * 100.0)
                } else {
                    cpu = 0
                }
                cpuAvailable = true
            } else {
                // 首帧尚无差分，显示 0.0%（已采到时间基线，不是权限失败）
                cpu = 0
                cpuAvailable = true
            }
            if info.metricsAvailable {
                newPrev[pid] = (utime, stime, wallNow)
            }

            let user = username(for: info.uid, cache: &newUserCache)

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
                username: user,
                startTime: info.startTime,
                cpuAvailable: cpuAvailable,
                memoryAvailable: info.metricsAvailable,
                metricsFromHelper: info.metricsFromHelper
            )
            result.append(process)
            newSummary.add(process)
        }

        newClassCache = newClassCache.filter { seen.contains($0.key) }

        return Snapshot(
            processes: result,
            summary: newSummary,
            previousCPU: newPrev,
            classificationCache: newClassCache,
            usernameCache: newUserCache,
            systemMetrics: systemMetrics,
            timestamp: now
        )
    }

    private struct RawTaskInfo {
        var name: String
        var residentSize: UInt64
        var virtualSize: UInt64
        var threadCount: Int
        var ppid: Int32
        var uid: uid_t
        var userTime: Double
        var systemTime: Double
        var startTime: Date?
        /// PROC_PIDTASKINFO 是否成功（失败时 CPU/内存不可用）
        var metricsAvailable: Bool
        /// 是否由 root helper 补全
        var metricsFromHelper: Bool
    }

    private static func taskInfo(for pid: Int32, privileged: PrivilegedMetricsClient.Sample? = nil) -> RawTaskInfo? {
        // 1) 完整 bsdinfo  2) short bsdinfo  3) sysctl(kinfo_proc)
        // 许多系统/特权进程对 PROC_PIDTBSDINFO 会失败；旧逻辑直接丢弃后列表只剩当前用户进程
        var uid: uid_t = 0
        var ppid: Int32 = 0
        var name = ""
        var start: Date?
        var gotIdentity = false

        var bsdInfo = proc_bsdinfo()
        let bsdSize = Int32(MemoryLayout<proc_bsdinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, bsdSize) == bsdSize {
            uid = bsdInfo.pbi_uid
            ppid = Int32(bsdInfo.pbi_ppid)
            name = cString(from: bsdInfo.pbi_name, capacity: Int(MAXCOMLEN) * 2)
            if name.isEmpty {
                name = cString(from: bsdInfo.pbi_comm, capacity: Int(MAXCOMLEN))
            }
            let sec = TimeInterval(bsdInfo.pbi_start_tvsec)
            start = sec > 0 ? Date(timeIntervalSince1970: sec) : nil
            gotIdentity = true
        } else {
            var shortInfo = proc_bsdshortinfo()
            let shortSize = Int32(MemoryLayout<proc_bsdshortinfo>.stride)
            if proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &shortInfo, shortSize) == shortSize {
                uid = shortInfo.pbsi_uid
                ppid = Int32(shortInfo.pbsi_ppid)
                name = cString(from: shortInfo.pbsi_comm, capacity: Int(MAXCOMLEN))
                gotIdentity = true
            } else if let kinfo = kinfoProc(for: pid) {
                uid = kinfo.uid
                ppid = kinfo.ppid
                name = kinfo.name
                start = kinfo.start
                gotIdentity = true
            }
        }

        guard gotIdentity else { return nil }

        var resident: UInt64 = 0
        var virtual: UInt64 = 0
        var threads = 0
        var userT: Double = 0
        var sysT: Double = 0
        var metricsAvailable = false
        var metricsFromHelper = false

        var taskInfo = proc_taskinfo()
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)
        if proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, taskSize) == taskSize {
            resident = taskInfo.pti_resident_size
            virtual = taskInfo.pti_virtual_size
            threads = Int(taskInfo.pti_threadnum)
            userT = Double(taskInfo.pti_total_user) / 1_000_000_000.0
            sysT = Double(taskInfo.pti_total_system) / 1_000_000_000.0
            metricsAvailable = true
            metricsFromHelper = false
        } else if let privileged {
            // root helper 补全：普通用户读不到的系统保护进程
            resident = privileged.resident
            virtual = privileged.virtual
            threads = max(1, privileged.threads)
            userT = privileged.userTime
            sysT = privileged.systemTime
            metricsAvailable = true
            metricsFromHelper = true
        }

        // 受限进程常读不到 taskinfo；线程数尽量回退，CPU/内存标为不可用
        if !metricsAvailable || threads <= 0 {
            if let listed = listThreadCount(for: pid), listed > 0 {
                threads = listed
            } else if threads <= 0 {
                threads = 1
            }
        }

        return RawTaskInfo(
            name: name.isEmpty ? "(\(pid))" : name,
            residentSize: resident,
            virtualSize: virtual,
            threadCount: threads,
            ppid: ppid,
            uid: uid,
            userTime: userT,
            systemTime: sysT,
            startTime: start,
            metricsAvailable: metricsAvailable,
            metricsFromHelper: metricsFromHelper
        )
    }

    /// 通过线程 ID 列表估算线程数（taskinfo 不可用时的回退）
    private static func listThreadCount(for pid: Int32) -> Int? {
        var buffer = [UInt64](repeating: 0, count: 1024)
        let bytes = proc_pidinfo(
            pid,
            PROC_PIDLISTTHREADS,
            0,
            &buffer,
            Int32(buffer.count * MemoryLayout<UInt64>.size)
        )
        guard bytes > 0 else { return nil }
        return Int(bytes) / MemoryLayout<UInt64>.size
    }

    private static func cString<T>(from value: T, capacity: Int) -> String {
        withUnsafePointer(to: value) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: capacity) {
                String(cString: $0)
            }
        }
    }

    private struct KinfoIdentity {
        var uid: uid_t
        var ppid: Int32
        var name: String
        var start: Date?
    }

    /// sysctl(KERN_PROC_PID) 兜底
    private static func kinfoProc(for pid: Int32) -> KinfoIdentity? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size >= MemoryLayout<kinfo_proc>.stride else {
            return nil
        }

        var kp = kinfo_proc()
        var bufferSize = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &kp, &bufferSize, nil, 0) == 0, bufferSize >= MemoryLayout<kinfo_proc>.stride else {
            return nil
        }

        let uid = kp.kp_eproc.e_ucred.cr_uid
        let ppid = kp.kp_eproc.e_ppid
        let name = withUnsafePointer(to: kp.kp_proc.p_comm) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                String(cString: $0)
            }
        }
        let sec = TimeInterval(kp.kp_proc.p_starttime.tv_sec)
        let start = sec > 0 ? Date(timeIntervalSince1970: sec) : nil
        return KinfoIdentity(uid: uid, ppid: ppid, name: name, start: start)
    }

    private static func processPath(pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let ret = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        if ret > 0 {
            return String(cString: buffer)
        }
        return ""
    }

    private static func processName(path: String, fallback: String) -> String {
        if !path.isEmpty {
            let base = URL(fileURLWithPath: path).lastPathComponent
            if !base.isEmpty { return base }
        }
        if !fallback.isEmpty { return fallback }
        return "unknown"
    }

    private static func username(for uid: uid_t, cache: inout [uid_t: String]) -> String {
        if let cached = cache[uid] { return cached }

        // 后台采样线程必须用可重入 API；getpwuid 有静态缓冲，并发时会串名/错名
        var pwd = passwd()
        var buffer = [CChar](repeating: 0, count: 16_384)
        var result: UnsafeMutablePointer<passwd>?
        let status = getpwuid_r(uid, &pwd, &buffer, buffer.count, &result)

        let name: String
        if status == 0, result != nil, let cName = pwd.pw_name {
            let resolved = String(cString: cName)
            name = resolved.isEmpty ? "\(uid)" : resolved
        } else if uid == 0 {
            name = "root"
        } else if uid == getuid() {
            let login = NSUserName()
            name = login.isEmpty ? "\(uid)" : login
        } else {
            name = "\(uid)"
        }

        cache[uid] = name
        return name
    }
}

// MARK: - Darwin helpers

import Darwin.sys.sysctl

private let PROC_ALL_PIDS: Int32 = 1
private let PROC_PIDTBSDINFO: Int32 = 3
private let PROC_PIDTASKINFO: Int32 = 4
private let PROC_PIDLISTTHREADS: Int32 = 6
private let PROC_PIDT_SHORTBSDINFO: Int32 = 13
private let MAXCOMLEN: Int32 = 16

@_silgen_name("proc_listpids")
private func proc_listpids(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidpath")
private func proc_pidpath(_ pid: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: UInt32) -> Int32

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

/// 与 sys/proc_info.h 中 struct proc_bsdshortinfo 对齐
private struct proc_bsdshortinfo {
    var pbsi_pid: UInt32 = 0
    var pbsi_ppid: UInt32 = 0
    var pbsi_pgid: UInt32 = 0
    var pbsi_status: UInt32 = 0
    var pbsi_comm: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                    CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar) =
        (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    var pbsi_flags: UInt32 = 0
    var pbsi_uid: uid_t = 0
    var pbsi_gid: gid_t = 0
    var pbsi_ruid: uid_t = 0
    var pbsi_rgid: gid_t = 0
    var pbsi_svuid: uid_t = 0
    var pbsi_svgid: gid_t = 0
    var pbsi_rfu: UInt32 = 0
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
