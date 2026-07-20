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
        .searchable(text: $monitor.filterText, prompt: L("search.prompt"))
        .onChange(of: selectedPID) { _, pid in
            monitor.inspectedPID = pid
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker(L("toolbar.view"), selection: $monitor.displayMode) {
                    ForEach(ListDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Picker(L("settings.refresh"), selection: $monitor.refreshInterval) {
                    Text(L("settings.1s")).tag(1.0)
                    Text(L("settings.2s")).tag(2.0)
                    Text(L("settings.5s")).tag(5.0)
                    Text(L("settings.10s")).tag(10.0)
                }
                .pickerStyle(.menu)
                .frame(width: 80)
                .disabled(monitor.isRefreshPaused)
                .help(L("settings.refresh.main.caption"))

                Button {
                    monitor.refresh()
                } label: {
                    Label(L("toolbar.refresh"), systemImage: "arrow.clockwise")
                }
                .help(L("toolbar.refresh.help"))
                .disabled(monitor.isRefreshPaused)
            }
        }
        .alert(
            terminateForce ? L("alert.force_quit") : L("alert.quit"),
            isPresented: $showTerminateConfirm
        ) {
            Button(L("alert.cancel"), role: .cancel) {}
            Button(terminateForce ? L("alert.force_quit_btn") : L("alert.quit_btn"), role: .destructive) {
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
            Section(L("sidebar.category")) {
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

            Section(L("sidebar.filter")) {
                Toggle(L("sidebar.apps_only"), isOn: $monitor.showOnlyApps)
            }

            Section(L("sidebar.resource")) {
                ResourceBreakdownView()
            }

            Section(L("sidebar.who")) {
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
                ],
                total: 100
            )
            legendRow(color: .blue, title: L("cat.short.system"), value: String(format: "%.1f%%", s.appleSystemCPU))
            legendRow(color: .cyan, title: L("cat.appleApp"), value: String(format: "%.1f%%", s.appleAppCPU))
            legendRow(color: .orange, title: L("cat.thirdParty"), value: String(format: "%.1f%%", s.thirdPartyCPU))

            Divider().padding(.vertical, 4)

            Text(L("metric.memory"))
                .font(.caption)
                .foregroundStyle(.secondary)
            let phys = Double(monitor.systemMetrics.physicalMemory)
            stackedBar(
                segments: [
                    (.blue, Double(s.appleSystemMemory)),
                    (.cyan, Double(s.appleAppMemory)),
                    (.orange, Double(s.thirdPartyMemory)),
                ],
                total: max(phys, 1)
            )
            legendRow(color: .blue, title: L("cat.short.system"), value: byteString(s.appleSystemMemory))
            legendRow(color: .cyan, title: L("cat.appleApp"), value: byteString(s.appleAppMemory))
            legendRow(color: .orange, title: L("cat.thirdParty"), value: byteString(s.thirdPartyMemory))

            Divider().padding(.vertical, 4)

            HStack {
                Text(L("sidebar.apple_total"))
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stackedBar(segments: [(Color, Double)], total: Double) -> some View {
        let values = segments.map { max(0, $0.1) }
        // total 为 100（CPU）或物理内存字节；按绝对比例铺色，剩余为空闲底轨
        let denom = max(total, 0.0001)

        return Canvas { context, size in
            let bg = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
            context.fill(bg, with: .color(Color.secondary.opacity(0.15)))

            var x: CGFloat = 0
            let h = size.height
            let w = size.width
            for (index, seg) in segments.enumerated() {
                let fraction = CGFloat(min(1, values[index] / denom))
                guard fraction > 0 else { continue }
                var segmentWidth = w * fraction
                if x + segmentWidth > w {
                    segmentWidth = max(0, w - x)
                }
                if segmentWidth > 0, segmentWidth < 1 { segmentWidth = 1 }
                guard segmentWidth > 0 else { continue }
                let rect = CGRect(x: x, y: 0, width: segmentWidth, height: h)
                context.fill(Path(rect), with: .color(seg.0))
                x += segmentWidth
                if x >= w { break }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 8)
        .clipShape(Capsule())
        .accessibilityHidden(true)
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
        .help(monitor.isRefreshPaused ? L("summary.pause_on") : L("summary.pause_off"))
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
                title: L("cat.appleSystem"),
                cpu: s.appleSystemCPU,
                memory: s.appleSystemMemory,
                count: s.appleSystemCount,
                color: .blue
            )
            summaryChip(
                title: L("cat.appleApp"),
                cpu: s.appleAppCPU,
                memory: s.appleAppMemory,
                count: s.appleAppCount,
                color: .cyan
            )
            summaryChip(
                title: L("cat.thirdParty"),
                cpu: s.thirdPartyCPU,
                memory: s.thirdPartyMemory,
                count: s.thirdPartyCount,
                color: .orange
            )
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                RefreshStatusView()
                HStack(spacing: 8) {
                    Text(String(format: L("summary.process_count"), s.totalCount))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if monitor.lastUpdate != .distantPast {
                        Text("\(L("summary.updated")) \(monitor.lastUpdate, style: .time)")
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
                Text(process.path.isEmpty ? L("detail.path_unavailable") : process.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            detailStat("PID", "\(process.pid)")
            detailStat(L("detail.user"), process.username)
            detailStat(L("detail.threads"), "\(process.threadCount)")
            detailStat("CPU", process.cpuFormatted)
            detailStat(L("detail.memory"), process.memoryFormatted)
            if process.metricsFromHelper {
                detailStat(L("detail.source"), "root Helper")
            }

            if let bid = process.bundleIdentifier {
                detailStat("Bundle", bid)
            }

            Menu {
                Button(L("alert.quit_btn"), action: onTerminate)
                Button(L("alert.force_quit_btn"), role: .destructive, action: onForceQuit)
                Divider()
                if !process.path.isEmpty {
                    Button(L("menu.reveal")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: process.path)])
                    }
                    Button(L("menu.copy_path")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(process.path, forType: .string)
                    }
                }
            } label: {
                Label(L("detail.actions"), systemImage: "ellipsis.circle")
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
