import Foundation
import Darwin

/// 以 root 运行时，可读取普通用户无法访问的 PROC_PIDTASKINFO。
/// 输出 JSON 行协议，供主应用合并指标。

private let PROC_ALL_PIDS: Int32 = 1
private let PROC_PIDTASKINFO: Int32 = 4

@_silgen_name("proc_listpids")
private func proc_listpids(_ type: UInt32, _ typeinfo: UInt32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

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

@main
struct SwiftInsightHelperMain {
    static func main() {
        let args = CommandLine.arguments
        let command = args.dropFirst().first ?? "sample"

        switch command {
        case "sample":
            sample()
        case "status":
            status()
        default:
            fputs("usage: SwiftInsightHelper [sample|status]\n", stderr)
            exit(2)
        }
    }

    private static func status() {
        let root = geteuid() == 0
        let payload: [String: Any] = [
            "root": root,
            "uid": getuid(),
            "euid": geteuid(),
        ]
        writeJSON(payload)
    }

    private static func sample() {
        var pids = [Int32](repeating: 0, count: 8192)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(MemoryLayout<Int32>.size * pids.count))
        guard bytes > 0 else {
            writeJSON(["processes": [[String: Any]](), "root": geteuid() == 0])
            return
        }

        let count = Int(bytes) / MemoryLayout<Int32>.size
        var items: [[String: Any]] = []
        items.reserveCapacity(count)
        let taskSize = Int32(MemoryLayout<proc_taskinfo>.stride)

        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            var info = proc_taskinfo()
            let result = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, taskSize)
            guard result == taskSize else { continue }
            items.append([
                "pid": pid,
                "resident": info.pti_resident_size,
                "virtual": info.pti_virtual_size,
                "threads": info.pti_threadnum,
                "user_ns": info.pti_total_user,
                "system_ns": info.pti_total_system,
            ])
        }

        writeJSON([
            "root": geteuid() == 0,
            "count": items.count,
            "processes": items,
        ])
    }

    private static func writeJSON(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            fputs("{\"error\":\"encode\"}\n", stderr)
            exit(1)
        }
        print(text)
    }
}
