import Foundation

/// 调用已安装的 root setuid helper，补全普通用户读不到的进程 CPU/内存，
/// 以及 CPU 频率 / 温度（sensors 命令）。
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

    struct Sensors: Equatable {
        var cpuFrequencyMHz: Double = 0
        var efficiencyFrequencyMHz: Double = 0
        var performanceFrequencyMHz: Double = 0
        var cpuTemperatureC: Double = 0
        var thermalPressure: String = ""
        var isRoot: Bool = false
    }

    private static var cachedSensors = Sensors()
    private static var lastSensorSample: TimeInterval = 0
    private static var sensorInFlight = false
    /// powermetrics 较慢，后台节流
    private static let sensorInterval: TimeInterval = 3.0
    private static let sensorLock = NSLock()
    private static let sensorQueue = DispatchQueue(label: "com.swiftinsight.sensors", qos: .utility)

    /// 运行时优先用已 setuid 安装路径；包内未提权 Helper 不参与采样
    static var helperURL: URL? {
        if FileManager.default.isExecutableFile(atPath: defaultHelperPath) {
            return URL(fileURLWithPath: defaultHelperPath)
        }
        return nil
    }

    static var isHelperInstalled: Bool {
        FileManager.default.fileExists(atPath: defaultHelperPath)
    }

    static var hasBundledHelper: Bool {
        HelperInstaller.hasBundledHelper
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

    /// 仅读缓存，不阻塞（供主采样路径）
    static func currentSensors() -> Sensors {
        sensorLock.lock()
        defer { sensorLock.unlock() }
        return cachedSensors
    }

    /// 后台刷新频率/温度；不阻塞进程列表采样
    static func refreshSensorsAsync() {
        sensorLock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        if sensorInFlight || (lastSensorSample > 0 && now - lastSensorSample < sensorInterval) {
            sensorLock.unlock()
            return
        }
        sensorInFlight = true
        sensorLock.unlock()

        sensorQueue.async {
            let result = sampleSensorsBlocking()
            sensorLock.lock()
            if result.cpuFrequencyMHz > 0 || result.cpuTemperatureC > 0 || result.isRoot {
                var merged = result
                if merged.cpuFrequencyMHz <= 0 { merged.cpuFrequencyMHz = cachedSensors.cpuFrequencyMHz }
                if merged.efficiencyFrequencyMHz <= 0 { merged.efficiencyFrequencyMHz = cachedSensors.efficiencyFrequencyMHz }
                if merged.performanceFrequencyMHz <= 0 { merged.performanceFrequencyMHz = cachedSensors.performanceFrequencyMHz }
                if merged.cpuTemperatureC <= 0 { merged.cpuTemperatureC = cachedSensors.cpuTemperatureC }
                cachedSensors = merged
            }
            lastSensorSample = ProcessInfo.processInfo.systemUptime
            sensorInFlight = false
            sensorLock.unlock()
        }
    }

    private static func sampleSensorsBlocking() -> Sensors {
        guard let url = helperURL else { return Sensors() }
        guard let data = run(url, arguments: ["sensors"]) else { return Sensors() }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Sensors()
        }
        var s = Sensors()
        s.isRoot = (obj["root"] as? Bool) ?? false
        s.cpuFrequencyMHz = double(obj["cpu_freq_mhz"])
        s.efficiencyFrequencyMHz = double(obj["e_freq_mhz"])
        s.performanceFrequencyMHz = double(obj["p_freq_mhz"])
        s.cpuTemperatureC = double(obj["cpu_temp_c"])
        s.thermalPressure = (obj["thermal_pressure"] as? String) ?? ""
        return s
    }

    static func applySensors(_ sensors: Sensors, to metrics: inout SystemMetrics) {
        if sensors.cpuFrequencyMHz > 0 { metrics.cpuFrequencyMHz = sensors.cpuFrequencyMHz }
        if sensors.efficiencyFrequencyMHz > 0 { metrics.efficiencyFrequencyMHz = sensors.efficiencyFrequencyMHz }
        if sensors.performanceFrequencyMHz > 0 { metrics.performanceFrequencyMHz = sensors.performanceFrequencyMHz }
        if sensors.cpuTemperatureC > 0 { metrics.cpuTemperatureC = sensors.cpuTemperatureC }
    }

    private static func run(_ url: URL, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = url
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        // 必须边跑边读：sample JSON ~60–100KB，超过管道缓冲会在 waitUntilExit 上死锁
        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        let box = OutputBox()

        outHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                box.appendOut(chunk)
            }
        }
        errHandle.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
            } else {
                box.appendErr(chunk)
            }
        }

        do {
            try process.run()
        } catch {
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            return nil
        }

        process.waitUntilExit()
        outHandle.readabilityHandler = nil
        errHandle.readabilityHandler = nil

        // 排空残余
        let tailOut = outHandle.readDataToEndOfFile()
        if !tailOut.isEmpty { box.appendOut(tailOut) }
        _ = errHandle.readDataToEndOfFile()

        guard process.terminationStatus == 0 else { return nil }
        let data = box.outData
        return data.isEmpty ? nil : data
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()

        func appendOut(_ d: Data) {
            lock.lock(); out.append(d); lock.unlock()
        }
        func appendErr(_ d: Data) {
            lock.lock(); err.append(d); lock.unlock()
        }
        var outData: Data {
            lock.lock(); defer { lock.unlock() }
            return out
        }
    }

    private static func u64(_ any: Any?) -> UInt64 {
        if let v = any as? UInt64 { return v }
        if let v = any as? Int { return UInt64(max(0, v)) }
        if let v = any as? Double { return UInt64(max(0, v)) }
        if let v = any as? NSNumber { return v.uint64Value }
        return 0
    }

    private static func double(_ any: Any?) -> Double {
        if let v = any as? Double { return v }
        if let v = any as? Int { return Double(v) }
        if let v = any as? NSNumber { return v.doubleValue }
        return 0
    }

    private static func int32(_ any: Any?) -> Int32? {
        if let v = any as? Int32 { return v }
        if let v = any as? Int { return Int32(v) }
        if let v = any as? NSNumber { return v.int32Value }
        return nil
    }
}
