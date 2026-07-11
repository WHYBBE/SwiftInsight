import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @State private var selectedPID: Int32?
    @State private var showTerminateConfirm = false
    @State private var terminateForce = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedPID: $selectedPID)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            VStack(spacing: 0) {
                SystemOverviewBar()
                Divider()
                SystemHistoryCharts()
                Divider()
                SummaryBarView()
                Divider()
                ProcessTableView(selectedPID: $selectedPID)
                if let pid = selectedPID,
                   let process = monitor.processes.first(where: { $0.pid == pid }) {
                    Divider()
                    ProcessDetailPanel(
                        process: process,
                        onTerminate: {
                            terminateForce = false
                            showTerminateConfirm = true
                        },
                        onForceQuit: {
                            terminateForce = true
                            showTerminateConfirm = true
                        }
                    )
                }
            }
        }
        .searchable(text: $monitor.filterText, prompt: "搜索名称、PID、路径、Bundle ID…")
        .onChange(of: selectedPID) { _, pid in
            monitor.inspectedPID = pid
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("视图", selection: $monitor.displayMode) {
                    ForEach(ListDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Picker("刷新", selection: $monitor.refreshInterval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .disabled(monitor.isRefreshPaused)

                Button {
                    monitor.refresh()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("立即刷新")
                .disabled(monitor.isRefreshPaused)
            }
        }
        .alert(
            terminateForce ? "强制退出进程？" : "退出进程？",
            isPresented: $showTerminateConfirm
        ) {
            Button("取消", role: .cancel) {}
            Button(terminateForce ? "强制退出" : "退出", role: .destructive) {
                if let pid = selectedPID {
                    monitor.terminate(pid: pid, force: terminateForce)
                    selectedPID = nil
                }
            }
        } message: {
            if let pid = selectedPID,
               let p = monitor.processes.first(where: { $0.pid == pid }) {
                Text("\(p.name) (PID \(p.pid))")
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @Binding var selectedPID: Int32?

    private var selectedFilter: Binding<CategoryFilterItem?> {
        Binding(
            get: { CategoryFilterItem.from(category: monitor.categoryFilter) },
            set: { newValue in
                // 点击同一项时 SwiftUI 可能传 nil，保持当前筛选
                let item = newValue ?? .all
                monitor.categoryFilter = item.category
            }
        )
    }

    var body: some View {
        List(selection: selectedFilter) {
            Section("分类") {
                ForEach(CategoryFilterItem.allCases) { item in
                    HStack {
                        Label(item.title, systemImage: item.symbolName)
                        Spacer()
                        Text("\(count(for: item))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .tag(item)
                    .contentShape(Rectangle())
                }
            }

            Section("筛选") {
                Toggle("仅显示 App", isOn: $monitor.showOnlyApps)
            }

            Section("资源占用对比") {
                ResourceBreakdownView()
            }

            Section("谁在吃资源") {
                CategoryRankingsView { pid in
                    selectedPID = pid
                    monitor.inspectedPID = pid
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("SwiftInsight")
    }

    private func count(for item: CategoryFilterItem) -> Int {
        let s = monitor.summary
        switch item {
        case .all: return s.totalCount
        case .appleSystem: return s.appleSystemCount
        case .appleApp: return s.appleAppCount
        case .thirdParty: return s.thirdPartyCount
        case .unknown: return s.unknownCount
        }
    }
}

// MARK: - Resource breakdown

struct ResourceBreakdownView: View {
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        let s = monitor.summary
        VStack(alignment: .leading, spacing: 10) {
            Text("CPU")
                .font(.caption)
                .foregroundStyle(.secondary)
            stackedBar(
                segments: [
                    (.blue, s.appleSystemCPU),
                    (.cyan, s.appleAppCPU),
                    (.orange, s.thirdPartyCPU),
                    (.gray, s.unknownCPU),
                ],
                total: max(s.totalCPU, 1)
            )
            legendRow(color: .blue, title: "系统", value: String(format: "%.1f%%", s.appleSystemCPU))
            legendRow(color: .cyan, title: "Apple 应用", value: String(format: "%.1f%%", s.appleAppCPU))
            legendRow(color: .orange, title: "第三方", value: String(format: "%.1f%%", s.thirdPartyCPU))

            Divider().padding(.vertical, 4)

            Text("内存")
                .font(.caption)
                .foregroundStyle(.secondary)
            stackedBar(
                segments: [
                    (.blue, Double(s.appleSystemMemory)),
                    (.cyan, Double(s.appleAppMemory)),
                    (.orange, Double(s.thirdPartyMemory)),
                    (.gray, Double(s.unknownMemory)),
                ],
                total: max(Double(s.totalMemory), 1)
            )
            legendRow(color: .blue, title: "系统", value: byteString(s.appleSystemMemory))
            legendRow(color: .cyan, title: "Apple 应用", value: byteString(s.appleAppMemory))
            legendRow(color: .orange, title: "第三方", value: byteString(s.thirdPartyMemory))

            Divider().padding(.vertical, 4)

            HStack {
                Text("Apple 合计")
                    .font(.caption.weight(.semibold))
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(String(format: "CPU %.1f%%", s.appleCPU))
                        .font(.caption2)
                        .monospacedDigit()
                    Text(byteString(s.appleMemory))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func stackedBar(segments: [(Color, Double)], total: Double) -> some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                    let w = max(0, geo.size.width * CGFloat(seg.1 / total))
                    if w > 0.5 {
                        Rectangle()
                            .fill(seg.0)
                            .frame(width: w)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
        }
        .frame(height: 8)
    }

    private func legendRow(color: Color, title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(.caption2)
            Spacer()
            Text(value).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private func byteString(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
    }
}

// MARK: - Summary bar

/// 刷新状态指示（汇总栏右侧）
struct RefreshStatusView: View {
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: monitor.isRefreshPaused ? "pause.circle.fill" : "circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(monitor.isRefreshPaused ? Color.orange : Color.green)
                .symbolRenderingMode(.hierarchical)
            Text(monitor.statusText)
                .font(.caption)
                .foregroundStyle(monitor.isRefreshPaused ? Color.primary : Color.secondary)
                .monospacedDigit()
        }
        .help(monitor.isRefreshPaused ? "按住 Control 暂停刷新中" : "按住 Control 可暂停自动刷新")
        .animation(.easeInOut(duration: 0.15), value: monitor.isRefreshPaused)
        .accessibilityLabel(monitor.statusText)
    }
}

struct SummaryBarView: View {
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        let s = monitor.summary
        HStack(spacing: 16) {
            summaryChip(
                title: "Apple 系统",
                cpu: s.appleSystemCPU,
                memory: s.appleSystemMemory,
                count: s.appleSystemCount,
                color: .blue
            )
            summaryChip(
                title: "Apple 应用",
                cpu: s.appleAppCPU,
                memory: s.appleAppMemory,
                count: s.appleAppCount,
                color: .cyan
            )
            summaryChip(
                title: "第三方",
                cpu: s.thirdPartyCPU,
                memory: s.thirdPartyMemory,
                count: s.thirdPartyCount,
                color: .orange
            )
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                RefreshStatusView()
                HStack(spacing: 8) {
                    Text("共 \(s.totalCount) 个进程")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if monitor.lastUpdate != .distantPast {
                        Text("更新于 \(monitor.lastUpdate, style: .time)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.15), value: monitor.isRefreshPaused)
    }

    private func summaryChip(title: String, cpu: Double, memory: UInt64, count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(color.gradient).frame(width: 6, height: 6)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("· \(count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 10) {
                Text(String(format: "%.1f%%", cpu))
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(ByteCountFormatter.string(fromByteCount: Int64(memory), countStyle: .memory))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.08))
        }
    }
}

// MARK: - Detail bar

struct ProcessDetailBar: View {
    let process: MonitoredProcess
    var onTerminate: () -> Void
    var onForceQuit: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            ProcessIconView(path: process.path, name: process.name)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(process.name)
                        .font(.headline)
                    CategoryBadge(category: process.category)
                }
                Text(process.path.isEmpty ? "路径不可用" : process.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            detailStat("PID", "\(process.pid)")
            detailStat("用户", process.username)
            detailStat("线程", "\(process.threadCount)")
            detailStat("CPU", process.cpuFormatted)
            detailStat("内存", process.memoryFormatted)

            if let bid = process.bundleIdentifier {
                detailStat("Bundle", bid)
            }

            Menu {
                Button("退出", action: onTerminate)
                Button("强制退出", role: .destructive, action: onForceQuit)
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
            } label: {
                Label("操作", systemImage: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 70)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func detailStat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

struct CategoryBadge: View {
    let category: ProcessCategory

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tagColor)
                .frame(width: 5, height: 5)
            Text(category.shortName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(category.displayName)
    }

    private var tagColor: Color {
        switch category {
        case .appleSystem: return Color(red: 0.35, green: 0.55, blue: 0.95)
        case .appleApp:    return Color(red: 0.25, green: 0.72, blue: 0.78)
        case .thirdParty:  return Color(red: 0.92, green: 0.55, blue: 0.28)
        case .unknown:     return Color.secondary
        }
    }
}

struct ProcessIconView: View {
    let path: String
    let name: String

    var body: some View {
        Image(nsImage: ProcessClassifier.icon(for: path, name: name))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
    }
}
