import SwiftUI
import AppKit

struct ProcessTableView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @Binding var selectedPID: Int32?

    var body: some View {
        Table(of: MonitoredProcess.self, selection: $selectedPID) {
            TableColumn("名称") { (process: MonitoredProcess) in
                HStack(spacing: 8) {
                    ProcessIconView(path: process.path, name: process.name)
                        .frame(width: 18, height: 18)
                    Text(process.name)
                        .lineLimit(1)
                    CategoryBadge(category: process.category)
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("CPU %") { (process: MonitoredProcess) in
                Text(process.cpuFormatted)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .foregroundStyle(cpuColor(process.cpuPercent))
            }
            .width(min: 60, ideal: 70)

            TableColumn("内存") { (process: MonitoredProcess) in
                Text(process.memoryFormatted)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 70, ideal: 90)

            TableColumn("线程") { (process: MonitoredProcess) in
                Text("\(process.threadCount)")
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 45, ideal: 55)

            TableColumn("PID") { (process: MonitoredProcess) in
                Text("\(process.pid)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)

            TableColumn("用户") { (process: MonitoredProcess) in
                Text(process.username)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 80)
        } rows: {
            ForEach(monitor.displayedProcesses) { process in
                TableRow(process)
                    .contextMenu {
                        processContextMenu(process)
                    }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .onChange(of: monitor.sortColumn) { _, _ in }
        .safeAreaInset(edge: .top, spacing: 0) {
            sortHeader
        }
    }

    private var sortHeader: some View {
        HStack(spacing: 12) {
            Text("排序:")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(SortColumn.allCases) { col in
                Button {
                    monitor.toggleSort(col)
                } label: {
                    HStack(spacing: 2) {
                        Text(col.displayName)
                            .font(.caption.weight(monitor.sortColumn == col ? .semibold : .regular))
                        if monitor.sortColumn == col {
                            Image(systemName: monitor.sortAscending ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        monitor.sortColumn == col
                            ? Color.accentColor.opacity(0.15)
                            : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text("\(monitor.displayedProcesses.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private func processContextMenu(_ process: MonitoredProcess) -> some View {
        Button("退出") {
            monitor.terminate(pid: process.pid, force: false)
        }
        Button("强制退出", role: .destructive) {
            monitor.terminate(pid: process.pid, force: true)
        }
        Divider()
        if !process.path.isEmpty {
            Button("在 Finder 中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.path)])
            }
            Button("复制路径") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(process.path, forType: .string)
            }
        }
        if let bid = process.bundleIdentifier {
            Button("复制 Bundle ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(bid, forType: .string)
            }
        }
        Divider()
        Button("筛选此分类") {
            monitor.categoryFilter = process.category
        }
    }

    private func cpuColor(_ cpu: Double) -> Color {
        if cpu >= 50 { return .red }
        if cpu >= 20 { return .orange }
        if cpu >= 5 { return .primary }
        return .secondary
    }
}

// Table selection 需要 Hashable 的 ID；MonitoredProcess.id 是 pid
