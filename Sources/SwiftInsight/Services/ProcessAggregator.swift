import Foundation

/// 将多进程应用（Edge / Chrome / Tauri / WebKit Helper 等）聚合为树
enum ProcessAggregator {

    struct Node {
        var process: MonitoredProcess
        var children: [Node]
        var groupKey: String
        /// 子树汇总（含自身）
        var totalCPU: Double
        var totalMemory: UInt64
        var totalThreads: Int
        var memberCount: Int

        var aggregatedProcess: MonitoredProcess {
            var p = process
            p.cpuPercent = totalCPU
            p.memoryBytes = totalMemory
            p.threadCount = totalThreads
            // 聚合后视为可用（已对可用子进程求和）
            p.cpuAvailable = true
            p.memoryAvailable = true
            return p
        }
    }

    // MARK: - Public

    static func buildForest(from processes: [MonitoredProcess]) -> [Node] {
        guard !processes.isEmpty else { return [] }

        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var groupOf: [Int32: String] = [:]
        for p in processes {
            groupOf[p.pid] = groupKey(for: p, all: byPID)
        }

        // 按组收集
        var members: [String: [MonitoredProcess]] = [:]
        for p in processes {
            let key = groupOf[p.pid] ?? soloKey(p)
            members[key, default: []].append(p)
        }

        var roots: [Node] = []
        roots.reserveCapacity(members.count)

        for (key, group) in members {
            if group.count == 1, let only = group.first {
                // 单进程：若其父进程同组则不会出现在这里；独立节点
                roots.append(makeLeaf(only, groupKey: key))
                continue
            }
            roots.append(buildGroupTree(group, groupKey: key, byPID: byPID))
        }

        return roots
    }

    /// 展开为扁平展示行
    static func flatten(
        _ forest: [Node],
        expanded: Set<String>,
        sortColumn: SortColumn,
        sortAscending: Bool
    ) -> [ProcessDisplayRow] {
        let sortedRoots = sortNodes(forest, column: sortColumn, ascending: sortAscending)
        var rows: [ProcessDisplayRow] = []
        for root in sortedRoots {
            appendRows(root, depth: 0, expanded: expanded, sortColumn: sortColumn, sortAscending: sortAscending, into: &rows)
        }
        return rows
    }

    // MARK: - Group key

    static func groupKey(for process: MonitoredProcess, all: [Int32: MonitoredProcess]) -> String {
        // 1) 显式 .app 路径
        if let appPath = appBundlePath(from: process.path) {
            return "app:" + appPath
        }

        // 2) Bundle ID 族（去掉 Helper / WebContent 等后缀）
        if let bid = process.bundleIdentifier, !bid.isEmpty {
            return "bid:" + familyBundleID(bid)
        }

        // 3) 沿父链寻找同名应用族
        if let parentKey = inheritGroupFromParent(process, all: all) {
            return parentKey
        }

        // 4) 可执行文件目录（Helpers 常与主程序同根）
        if let root = executableFamilyRoot(path: process.path, name: process.name) {
            return "root:" + root
        }

        // 5) 名称族（Microsoft Edge Helper → Microsoft Edge）
        return "name:" + familyName(process.name)
    }

    private static func soloKey(_ p: MonitoredProcess) -> String {
        "pid:\(p.pid)"
    }

    private static func inheritGroupFromParent(_ process: MonitoredProcess, all: [Int32: MonitoredProcess]) -> String? {
        var current = process.ppid
        var guardCount = 0
        while current > 0, guardCount < 8 {
            guardCount += 1
            guard let parent = all[current] else { break }
            if let appPath = appBundlePath(from: parent.path) {
                // 子进程在同一 .app 或路径相关
                if process.path.hasPrefix(appPath) || relatedNames(process.name, parent.name) {
                    return "app:" + appPath
                }
            }
            if let pbid = parent.bundleIdentifier, let cbid = process.bundleIdentifier {
                if familyBundleID(pbid) == familyBundleID(cbid) {
                    return "bid:" + familyBundleID(pbid)
                }
            }
            if relatedNames(process.name, parent.name) {
                if let appPath = appBundlePath(from: parent.path) {
                    return "app:" + appPath
                }
                return "name:" + familyName(parent.name)
            }
            current = parent.ppid
        }
        return nil
    }

    // MARK: - Tree build

    private static func buildGroupTree(_ group: [MonitoredProcess], groupKey: String, byPID: [Int32: MonitoredProcess]) -> Node {
        let pids = Set(group.map(\.pid))
        var childrenMap: [Int32: [MonitoredProcess]] = [:]
        var roots: [MonitoredProcess] = []

        for p in group {
            if pids.contains(p.ppid), p.ppid != p.pid {
                childrenMap[p.ppid, default: []].append(p)
            } else {
                roots.append(p)
            }
        }

        // 无清晰根时：选主进程
        if roots.isEmpty {
            roots = [pickPrimary(group)]
            let primaryPID = roots[0].pid
            childrenMap = [:]
            for p in group where p.pid != primaryPID {
                childrenMap[primaryPID, default: []].append(p)
            }
        } else if roots.count > 1 {
            // 多个根：挂到主进程下
            let primary = pickPrimary(roots)
            let extra = roots.filter { $0.pid != primary.pid }
            roots = [primary]
            childrenMap[primary.pid, default: []].append(contentsOf: extra)
        }

        func build(_ p: MonitoredProcess) -> Node {
            let kids = (childrenMap[p.pid] ?? []).map(build)
            return finalize(Node(
                process: p,
                children: kids,
                groupKey: groupKey,
                totalCPU: p.cpuPercent,
                totalMemory: p.memoryBytes,
                totalThreads: p.threadCount,
                memberCount: 1
            ))
        }

        let rootNodes = roots.map(build)
        if rootNodes.count == 1 {
            return rootNodes[0]
        }
        // 理论上不会到这里
        return rootNodes[0]
    }

    private static func makeLeaf(_ p: MonitoredProcess, groupKey: String) -> Node {
        Node(
            process: p,
            children: [],
            groupKey: groupKey,
            totalCPU: p.cpuPercent,
            totalMemory: p.memoryBytes,
            totalThreads: p.threadCount,
            memberCount: 1
        )
    }

    private static func finalize(_ node: Node) -> Node {
        var n = node
        var cpu = n.process.cpuAvailable ? n.process.cpuPercent : 0
        var mem = n.process.memoryAvailable ? n.process.memoryBytes : 0
        var thr = n.process.threadCount
        var count = 1
        var finalizedChildren: [Node] = []
        for child in n.children {
            let c = finalize(child)
            finalizedChildren.append(c)
            cpu += c.totalCPU
            mem += c.totalMemory
            thr += c.totalThreads
            count += c.memberCount
        }
        n.children = finalizedChildren
        n.totalCPU = cpu
        n.totalMemory = mem
        n.totalThreads = thr
        n.memberCount = count
        return n
    }

    private static func pickPrimary(_ group: [MonitoredProcess]) -> MonitoredProcess {
        // 优先：.app 主可执行文件 / 非 Helper 名 / 最大内存 / 最小 pid
        let scored = group.max { a, b in
            primaryScore(a) < primaryScore(b)
        }
        return scored ?? group[0]
    }

    private static func primaryScore(_ p: MonitoredProcess) -> Int {
        var s = 0
        if p.kind == .app { s += 1000 }
        if p.path.contains(".app/Contents/MacOS/") { s += 500 }
        let lower = p.name.lowercased()
        if lower.contains("helper") { s -= 300 }
        if lower.contains("renderer") { s -= 200 }
        if lower.contains("gpu") { s -= 150 }
        if lower.contains("plugin") { s -= 150 }
        if lower.contains("webview") { s -= 150 }
        if lower.contains("webcontent") || lower.contains("networking") { s -= 200 }
        s += Int(min(p.memoryBytes / 1_048_576, 500))
        s -= Int(p.pid % 100) // 轻微偏向较小 pid
        return s
    }

    // MARK: - Flatten / sort

    private static func appendRows(
        _ node: Node,
        depth: Int,
        expanded: Set<String>,
        sortColumn: SortColumn,
        sortAscending: Bool,
        into rows: inout [ProcessDisplayRow]
    ) {
        let hasChildren = !node.children.isEmpty
        let expandKey = node.groupKey + "#\(node.process.pid)"
        let isExpanded = hasChildren && expanded.contains(expandKey)
        let showAggregated = hasChildren && !isExpanded

        let displayProcess: MonitoredProcess = {
            if showAggregated {
                return node.aggregatedProcess
            }
            return node.process
        }()

        rows.append(ProcessDisplayRow(
            id: expandKey,
            process: displayProcess,
            depth: depth,
            hasChildren: hasChildren,
            isExpanded: isExpanded,
            memberCount: node.memberCount,
            isGroupRoot: hasChildren,
            groupKey: expandKey
        ))

        if isExpanded {
            for child in sortNodes(node.children, column: sortColumn, ascending: sortAscending) {
                appendRows(child, depth: depth + 1, expanded: expanded, sortColumn: sortColumn, sortAscending: sortAscending, into: &rows)
            }
        }
    }

    private static func sortNodes(_ nodes: [Node], column: SortColumn, ascending: Bool) -> [Node] {
        nodes.sorted { a, b in
            let result: Bool
            switch column {
            case .cpu:     result = a.totalCPU < b.totalCPU
            case .memory:  result = a.totalMemory < b.totalMemory
            case .name:    result = a.process.name.localizedCaseInsensitiveCompare(b.process.name) == .orderedAscending
            case .pid:     result = a.process.pid < b.process.pid
            case .threads: result = a.totalThreads < b.totalThreads
            }
            return ascending ? result : !result
        }
    }

    // MARK: - Identity helpers

    static func appBundlePath(from path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        if let idx = parts.lastIndex(where: { $0.hasSuffix(".app") }) {
            return parts[...idx].joined(separator: "/")
        }
        return nil
    }

    static func familyBundleID(_ bid: String) -> String {
        var parts = bid.split(separator: ".").map(String.init)
        let dropSuffixes: Set<String> = [
            "helper", "helpers", "renderer", "gpu", "plugin", "webcontent",
            "networking", "gpuService", "xpc", "loginhelper", "nativemessaging",
            "alerter", "crashpad", "service", "agent", "extension", "appex",
            "webkit", "webapp", "npapi", "ppapi",
        ]
        while let last = parts.last?.lowercased(), dropSuffixes.contains(last) || last.hasPrefix("helper") {
            parts.removeLast()
        }
        // com.microsoft.edgemac.helper → com.microsoft.edgemac
        if parts.count >= 3 {
            return parts.joined(separator: ".")
        }
        return bid
    }

    static func familyName(_ name: String) -> String {
        var n = name
        let suffixes = [
            " Helper (Renderer)", " Helper (GPU)", " Helper (Plugin)",
            " Helper (Service)", " Helper", " Renderer", " GPU Process",
            " Networking", " WebContent", " Web App", " Crashpad Handler",
            " NPAPI Plugin", " Plugin", " Agent", " Service", " (GPU)",
            " (Renderer)", " (Plugin)",
        ]
        for s in suffixes {
            if let r = n.range(of: s, options: [.caseInsensitive, .backwards]) {
                n = String(n[..<r.lowerBound])
                break
            }
        }
        n = n.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? name : n
    }

    private static func relatedNames(_ a: String, _ b: String) -> Bool {
        let fa = familyName(a).lowercased()
        let fb = familyName(b).lowercased()
        if fa == fb { return true }
        if fa.hasPrefix(fb) || fb.hasPrefix(fa) { return true }
        // Edge / Microsoft Edge
        let ta = fa.replacingOccurrences(of: "microsoft ", with: "")
        let tb = fb.replacingOccurrences(of: "microsoft ", with: "")
        if ta == tb { return true }
        return false
    }

    private static func executableFamilyRoot(path: String, name: String) -> String? {
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent()
        // .../App.app/Contents/Frameworks/App Helper.app/Contents/MacOS → climb to .app
        if let app = appBundlePath(from: path) {
            return app
        }
        // Tauri / sidecar: same directory family
        let parent = dir.path
        if parent.contains("Frameworks") || parent.contains("Helpers") {
            return appBundlePath(from: parent) ?? parent
        }
        return nil
    }
}
