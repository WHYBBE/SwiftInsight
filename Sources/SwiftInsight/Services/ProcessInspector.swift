import Foundation
import Darwin

/// 选中进程的增强信息：打开文件 / 套接字等
enum ProcessInspector {

    static func inspect(pid: Int32, processes: [MonitoredProcess]) -> ProcessDetailInfo {
        var info = ProcessDetailInfo()
        if let proc = processes.first(where: { $0.pid == pid }) {
            info.parentName = processes.first(where: { $0.pid == proc.ppid })?.name
        }
        let files = openFiles(for: pid)
        info.openFiles = Array(files.prefix(50))
        info.openFileCount = files.count
        if files.isEmpty {
            info.sampleNote = "无法读取打开文件（权限不足或进程已退出）"
        } else {
            info.sampleNote = "共 \(files.count) 个打开的文件/套接字"
        }
        return info
    }

    static func openFiles(for pid: Int32) -> [ProcessOpenFile] {
        let listSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard listSize > 0 else { return [] }

        let count = Int(listSize) / MemoryLayout<proc_fdinfo>.stride
        var buffer = [proc_fdinfo](repeating: proc_fdinfo(), count: max(count, 1))
        let filled = proc_pidinfo(
            pid,
            PROC_PIDLISTFDS,
            0,
            &buffer,
            Int32(buffer.count * MemoryLayout<proc_fdinfo>.stride)
        )
        guard filled > 0 else { return [] }

        let actual = Int(filled) / MemoryLayout<proc_fdinfo>.stride
        var result: [ProcessOpenFile] = []
        result.reserveCapacity(min(actual, 200))

        for i in 0..<actual {
            let fdInfo = buffer[i]
            let fd = fdInfo.proc_fd
            switch fdInfo.proc_fdtype {
            case PROX_FDTYPE_VNODE:
                if let path = vnodePath(pid: pid, fd: fd) {
                    result.append(ProcessOpenFile(id: fd, fd: fd, path: path, kind: "文件"))
                }
            case PROX_FDTYPE_SOCKET:
                result.append(ProcessOpenFile(id: fd, fd: fd, path: "socket", kind: "套接字"))
            case PROX_FDTYPE_PIPE:
                result.append(ProcessOpenFile(id: fd, fd: fd, path: "pipe", kind: "管道"))
            case PROX_FDTYPE_KQUEUE:
                result.append(ProcessOpenFile(id: fd, fd: fd, path: "kqueue", kind: "kqueue"))
            default:
                continue
            }
            if result.count >= 200 { break }
        }
        return result
    }

    private static func vnodePath(pid: Int32, fd: Int32) -> String? {
        // vnode_fdinfowithpath 布局因 SDK 略有差异，用原始缓冲扫描以 '/' 开头的路径
        var buffer = [UInt8](repeating: 0, count: 2048)
        let result = buffer.withUnsafeMutableBytes { raw in
            proc_pidfdinfo(pid, fd, PROC_PIDFDVNODEPATHINFO, raw.baseAddress, Int32(raw.count))
        }
        guard result > 0 else { return nil }
        return buffer.withUnsafeBufferPointer { buf in
            let start = min(100, max(0, buf.count - 2))
            for i in start..<buf.count {
                if buf[i] == UInt8(ascii: "/") {
                    var end = i
                    while end < buf.count && buf[end] != 0 { end += 1 }
                    if end > i, let s = String(bytes: buf[i..<end], encoding: .utf8), s.hasPrefix("/") {
                        return s
                    }
                }
            }
            return nil
        }
    }
}

// MARK: - libproc

private let PROC_PIDLISTFDS: Int32 = 1
private let PROC_PIDFDVNODEPATHINFO: Int32 = 2

private let PROX_FDTYPE_VNODE: UInt32 = 1
private let PROX_FDTYPE_SOCKET: UInt32 = 2
private let PROX_FDTYPE_KQUEUE: UInt32 = 5
private let PROX_FDTYPE_PIPE: UInt32 = 6

@_silgen_name("proc_pidinfo")
private func proc_pidinfo(_ pid: Int32, _ flavor: Int32, _ arg: UInt64, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

@_silgen_name("proc_pidfdinfo")
private func proc_pidfdinfo(_ pid: Int32, _ fd: Int32, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer?, _ buffersize: Int32) -> Int32

private struct proc_fdinfo {
    var proc_fd: Int32 = 0
    var proc_fdtype: UInt32 = 0
}
