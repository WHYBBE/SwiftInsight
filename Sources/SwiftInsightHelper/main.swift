import Foundation
import Darwin
import IOKit

/// 以 root 运行时，可读取普通用户无法访问的 PROC_PIDTASKINFO，
/// 以及 CPU 频率 / 温度（powermetrics + SMC）。
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
        case "sensors":
            sensors()
        default:
            fputs("usage: SwiftInsightHelper [sample|status|sensors]\n", stderr)
            exit(2)
        }
    }

    private static func status() {
        let root = geteuid() == 0
        writeJSON([
            "root": root,
            "uid": getuid(),
            "euid": geteuid(),
            "sensors": root,
        ])
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

    /// CPU 频率 / 温度。需要 root（setuid）。
    private static func sensors() {
        var payload: [String: Any] = [
            "root": geteuid() == 0,
        ]
        guard geteuid() == 0 else {
            payload["error"] = "need_root"
            writeJSON(payload)
            return
        }

        if let pm = PowermetricsSensors.read() {
            for (k, v) in pm { payload[k] = v }
        }
        // SMC 补温度（若 powermetrics 未给出）
        if payload["cpu_temp_c"] == nil, let t = SMCSensors.cpuTemperatureC() {
            payload["cpu_temp_c"] = t
            payload["temp_source"] = "smc"
        }
        // Intel sysctl 频率回退
        if payload["cpu_freq_mhz"] == nil {
            var hz: UInt64 = 0
            var size = MemoryLayout<UInt64>.size
            if sysctlbyname("hw.cpufrequency", &hz, &size, nil, 0) == 0, hz > 0 {
                payload["cpu_freq_mhz"] = Double(hz) / 1_000_000.0
                payload["freq_source"] = "sysctl"
            }
        }
        writeJSON(payload)
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

// MARK: - powermetrics

private enum PowermetricsSensors {
    static func read() -> [String: Any]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        // 短采样；cpu_power 含频率，thermal 含压力
        process.arguments = [
            "-n", "1",
            "-i", "250",
            "-s", "cpu_power,thermal",
            "-f", "text",
        ]
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
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return parse(text)
    }

    static func parse(_ text: String) -> [String: Any] {
        var result: [String: Any] = ["freq_source": "powermetrics"]
        var eFreq: Double?
        var pFreq: Double?
        var hwFreq: Double?
        var temps: [Double] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()

            if let mhz = firstMHz(in: line) {
                if lower.contains("e-cluster") || lower.contains("e cluster") || lower.contains("efficiency") {
                    eFreq = mhz
                } else if lower.contains("p-cluster") || lower.contains("p cluster") || lower.contains("performance") {
                    pFreq = mhz
                } else if lower.contains("cpu hw active frequency")
                            || lower.contains("cpu active frequency")
                            || lower.contains("hw active frequency")
                            || (lower.contains("cpu") && lower.contains("frequency") && !lower.contains("gpu")) {
                    if hwFreq == nil || lower.contains("hw active") {
                        hwFreq = mhz
                    }
                }
            }

            if lower.contains("temperature") || lower.contains("temp:") || lower.contains("°c") || lower.contains(" deg") {
                if let t = firstCelsius(in: line) {
                    // 优先 die / package / cpu
                    if lower.contains("die") || lower.contains("package") || lower.contains("cpu") || lower.contains("soc") {
                        temps.insert(t, at: 0)
                    } else {
                        temps.append(t)
                    }
                }
            }

            if lower.contains("thermal pressure") {
                // e.g. "Current pressure level: Nominal"
                if let idx = lower.range(of: "pressure") {
                    let rest = String(line[idx.upperBound...])
                    if rest.lowercased().contains("nominal") { result["thermal_pressure"] = "nominal" }
                    else if rest.lowercased().contains("moderate") { result["thermal_pressure"] = "moderate" }
                    else if rest.lowercased().contains("heavy") { result["thermal_pressure"] = "heavy" }
                    else if rest.lowercased().contains("sleeping") { result["thermal_pressure"] = "sleeping" }
                    else if rest.lowercased().contains("trapping") { result["thermal_pressure"] = "trapping" }
                }
            }
        }

        if let e = eFreq { result["e_freq_mhz"] = e }
        if let p = pFreq { result["p_freq_mhz"] = p }
        if let hw = hwFreq {
            result["cpu_freq_mhz"] = hw
        } else if let p = pFreq, let e = eFreq {
            // 加权粗估：有 P/E 时取较高的活跃簇（更接近体感主频）
            result["cpu_freq_mhz"] = max(p, e)
        } else if let p = pFreq {
            result["cpu_freq_mhz"] = p
        } else if let e = eFreq {
            result["cpu_freq_mhz"] = e
        }

        if let t = temps.first, t > 0, t < 150 {
            result["cpu_temp_c"] = t
            result["temp_source"] = "powermetrics"
        }
        return result
    }

    private static func firstMHz(in line: String) -> Double? {
        // "2048 MHz" / "2.05 GHz"
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(MHz|GHz|mhz|ghz)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range),
              let nRange = Range(m.range(at: 1), in: line),
              let uRange = Range(m.range(at: 2), in: line),
              let value = Double(line[nRange]) else { return nil }
        let unit = line[uRange].lowercased()
        return unit.hasPrefix("g") ? value * 1000 : value
    }

    private static func firstCelsius(in line: String) -> Double? {
        let pattern = #"([0-9]+(?:\.[0-9]+)?)\s*(?:°\s*)?C\b"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let m = re.firstMatch(in: line, range: range),
              let nRange = Range(m.range(at: 1), in: line),
              let value = Double(line[nRange]) else { return nil }
        return value
    }
}

// MARK: - SMC temperature (root)

private enum SMCSensors {
    private static let kernelIndexSMC: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdReadKeyInfo: UInt8 = 9

    static func cpuTemperatureC() -> Double? {
        var conn: io_connect_t = 0
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &conn) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(conn) }

        // Apple Silicon + Intel 常见键
        let keys = [
            "Tp01", "Tp05", "Tp09", "Tp0T", "Tp0b", "Tp0d", "Tp0f",
            "TC0P", "TC0E", "TC0F", "TC0D", "TC0H", "TCAD",
            "Tg0f", "Tg0G",
        ]
        var best: Double?
        for key in keys {
            if let t = readTemp(conn: conn, key: key), t > 20, t < 120 {
                if best == nil || t > best! { best = t }
            }
        }
        return best
    }

    private static func fourCC(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for u in s.utf8.prefix(4) { r = (r << 8) | UInt32(u) }
        return r
    }

    private static func readTemp(conn: io_connect_t, key: String) -> Double? {
        var input = SMCKeyData()
        input.key = fourCC(key)
        input.data8 = cmdReadKeyInfo
        guard let info = call(conn, &input) else { return nil }
        let size = info.keyInfo.dataSize
        let type = info.keyInfo.dataType
        var input2 = SMCKeyData()
        input2.key = fourCC(key)
        input2.keyInfo.dataSize = size
        input2.data8 = cmdReadBytes
        guard let data = call(conn, &input2) else { return nil }
        let b = data.bytes
        let bytes: [UInt8] = [
            b.0, b.1, b.2, b.3, b.4, b.5, b.6, b.7,
            b.8, b.9, b.10, b.11, b.12, b.13, b.14, b.15,
        ]
        // sp78
        if type == fourCC("sp78"), size >= 2 {
            let raw = (Int16(bytes[0]) << 8) | Int16(bytes[1])
            return Double(raw) / 256.0
        }
        // flt  (little-endian float common on AS)
        if type == fourCC("flt "), size >= 4 {
            let le = Float(bitPattern:
                UInt32(bytes[0])
                | (UInt32(bytes[1]) << 8)
                | (UInt32(bytes[2]) << 16)
                | (UInt32(bytes[3]) << 24)
            )
            if le.isFinite { return Double(le) }
        }
        return nil
    }

    private static func call(_ conn: io_connect_t, _ input: inout SMCKeyData) -> SMCKeyData? {
        let inSize = MemoryLayout<SMCKeyData>.stride
        var output = SMCKeyData()
        var outSize = inSize
        let kr = withUnsafeMutablePointer(to: &input) { ip in
            withUnsafeMutablePointer(to: &output) { op in
                IOConnectCallStructMethod(conn, kernelIndexSMC, ip, inSize, op, &outSize)
            }
        }
        return kr == KERN_SUCCESS ? output : nil
    }
}

private struct SMCKeyData_vers {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved0: UInt8 = 0
    var reserved1: UInt8 = 0
    var release: UInt16 = 0
}

private struct SMCKeyData_pLimitData {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

private struct SMCKeyData_keyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCKeyData {
    var key: UInt32 = 0
    var vers = SMCKeyData_vers()
    var pLimitData = SMCKeyData_pLimitData()
    var keyInfo = SMCKeyData_keyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}
