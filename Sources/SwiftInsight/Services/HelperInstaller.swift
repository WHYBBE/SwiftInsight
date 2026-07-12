import Foundation
import AppKit

/// 将 App 内嵌的 Helper 安装为 setuid root，无需目标机源码
enum HelperInstaller {
    static let installPath = "/usr/local/libexec/SwiftInsightHelper"
    private static let installDir = "/usr/local/libexec"
    private static let helperName = "SwiftInsightHelper"

    enum Outcome: Equatable {
        case success
        case cancelled
        case missingBundle
        case failed(String)
    }

    /// 包内 / 构建产物中的未提权 Helper（安装源）
    static var bundledHelperURL: URL? {
        var candidates: [URL] = []

        // 1) 正式 .app：Contents/MacOS/SwiftInsightHelper
        let appMacOS = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/\(helperName)")
        candidates.append(appMacOS)

        // 2) 与主可执行文件同目录（.app 与 SPM debug 都适用）
        if let exeDir = Bundle.main.executableURL?.deletingLastPathComponent() {
            candidates.append(exeDir.appendingPathComponent(helperName))
        }

        // 3) Resources 旁（兜底）
        if let res = Bundle.main.resourceURL?.deletingLastPathComponent()
            .appendingPathComponent("MacOS/\(helperName)") {
            candidates.append(res)
        }

        for url in candidates {
            let path = url.standardizedFileURL.path
            if path == installPath { continue }
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    static var hasBundledHelper: Bool { bundledHelperURL != nil }

    /// 安装：先拷到 /tmp（绕过 root 读 Downloads 的 TCC），再管理员写入 setuid
    @discardableResult
    static func install() -> Outcome {
        guard let source = bundledHelperURL else { return .missingBundle }

        // root 的 `do shell script` 往往读不了用户目录（Downloads/Desktop 等）→ Operation not permitted
        // 先用当前用户权限拷到 /tmp，再让管理员脚本只操作 /tmp 与 /usr/local
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftInsightHelper-install-\(ProcessInfo.processInfo.processIdentifier)")
        do {
            if FileManager.default.fileExists(atPath: staging.path) {
                try FileManager.default.removeItem(at: staging)
            }
            try FileManager.default.copyItem(at: source, to: staging)
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(0o755))],
                ofItemAtPath: staging.path
            )
        } catch {
            return .failed(error.localizedDescription)
        }

        let src = shellQuote(staging.path)
        let dstDir = shellQuote(installDir)
        let dst = shellQuote(installPath)
        let script = """
        mkdir -p \(dstDir) && \
        cp -f \(src) \(dst) && \
        chown root:wheel \(dst) && \
        chmod 4755 \(dst) && \
        rm -f \(src) && \
        \(dst) status
        """
        let outcome = runAdminShell(script)
        // 若管理员脚本失败，尽量清掉暂存
        try? FileManager.default.removeItem(at: staging)
        return outcome
    }

    /// 卸载已安装的 setuid Helper
    @discardableResult
    static func uninstall() -> Outcome {
        let dst = shellQuote(installPath)
        return runAdminShell("rm -f \(dst)")
    }

    private static func shellQuote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runAdminShell(_ shell: String) -> Outcome {
        // osascript 弹系统管理员密码；用户取消时返回 -128
        let escaped = shell
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let appleScript = "do shell script \"\(escaped)\" with administrator privileges"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        let box = OutputBox()
        outHandle.readabilityHandler = { h in
            let c = h.availableData
            if c.isEmpty { h.readabilityHandler = nil } else { box.appendOut(c) }
        }
        errHandle.readabilityHandler = { h in
            let c = h.availableData
            if c.isEmpty { h.readabilityHandler = nil } else { box.appendErr(c) }
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            outHandle.readabilityHandler = nil
            errHandle.readabilityHandler = nil
            return .failed(error.localizedDescription)
        }
        outHandle.readabilityHandler = nil
        errHandle.readabilityHandler = nil
        let tailOut = outHandle.readDataToEndOfFile()
        if !tailOut.isEmpty { box.appendOut(tailOut) }
        let tailErr = errHandle.readDataToEndOfFile()
        if !tailErr.isEmpty { box.appendErr(tailErr) }

        let status = process.terminationStatus
        if status == 0 { return .success }

        let msg = String(data: box.errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if msg.localizedCaseInsensitiveContains("canceled")
            || msg.localizedCaseInsensitiveContains("cancelled")
            || msg.localizedCaseInsensitiveContains("用户已取消")
            || msg.contains("-128") {
            return .cancelled
        }
        return .failed(msg.isEmpty ? "osascript exit \(status)" : msg)
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()
        func appendOut(_ d: Data) { lock.lock(); out.append(d); lock.unlock() }
        func appendErr(_ d: Data) { lock.lock(); err.append(d); lock.unlock() }
        var errData: Data { lock.lock(); defer { lock.unlock() }; return err }
    }
}
