import Foundation

/// 调用已安装的 root setuid helper，补全普通用户读不到的进程 CPU/内存
enum PrivilegedMetricsClient {

    static let defaultHelperPath = "/usr/local/libexec/SwiftInsightHelper"

    struct Sample {
        var resident: UInt64
        var virtual: UInt64
        var threads: Int
        var userTime: Double
        var systemTime: Double
    }

    struct Snapshot {
        var isRoot: Bool
        var byPID: [Int32: Sample]
    }

    static var helperURL: URL? {
        let candidates = [
            defaultHelperPath,
            (Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("SwiftInsightHelper").path),
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    static var isHelperInstalled: Bool {
        helperURL != nil
    }

    static func helperStatus() -> (installed: Bool, root: Bool) {
        guard let url = helperURL else { return (false, false) }
        guard let data = run(url, arguments: ["status"]) else { return (true, false) }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (true, false)
        }
        return (true, (obj["root"] as? Bool) ?? false)
    }

    static func sampleAll() -> Snapshot? {
        guard let url = helperURL else { return nil }
        guard let data = run(url, arguments: ["sample"]) else { return nil }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = obj["processes"] as? [[String: Any]] else {
            return nil
        }

        var map: [Int32: Sample] = [:]
        map.reserveCapacity(list.count)
        for item in list {
            guard let pid = int32(item["pid"]) else { continue }
            let userNs = u64(item["user_ns"])
            let sysNs = u64(item["system_ns"])
            map[pid] = Sample(
                resident: u64(item["resident"]),
                virtual: u64(item["virtual"]),
                threads: Int(int32(item["threads"]) ?? 0),
                userTime: Double(userNs) / 1_000_000_000.0,
                systemTime: Double(sysNs) / 1_000_000_000.0
            )
        }
        return Snapshot(isRoot: (obj["root"] as? Bool) ?? false, byPID: map)
    }

    private static func run(_ url: URL, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return data.isEmpty ? nil : data
    }

    private static func u64(_ any: Any?) -> UInt64 {
        if let v = any as? UInt64 { return v }
        if let v = any as? Int { return UInt64(max(0, v)) }
        if let v = any as? Double { return UInt64(max(0, v)) }
        if let v = any as? NSNumber { return v.uint64Value }
        return 0
    }

    private static func int32(_ any: Any?) -> Int32? {
        if let v = any as? Int32 { return v }
        if let v = any as? Int { return Int32(v) }
        if let v = any as? NSNumber { return v.int32Value }
        return nil
    }
}
