import SwiftUI

// MARK: - System overview strip

struct SystemOverviewBar: View {
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        let m = monitor.systemMetrics
        GeometryReader { geo in
            let gap: CGFloat = 10
            let total = max(0, geo.size.width - gap * 5)
            // 不均分：内存最宽，CPU/网络次之，交换/磁盘/负载更紧
            let wMem = total * 0.28
            let wCPU = total * 0.16
            let wNet = total * 0.16
            let wRest = total * 0.133

            HStack(spacing: gap) {
                metricBlock(
                    title: "CPU",
                    value: m.cpuFormatted,
                    detail: String(format: "用户 %.0f%%  系统 %.0f%%", m.cpuUser, m.cpuSystem),
                    level: m.cpuUsed
                )
                .frame(width: wCPU, alignment: .leading)

                memoryBlock(m)
                    .frame(width: wMem, alignment: .leading)

                metricBlock(
                    title: "交换",
                    value: m.swapFormatted,
                    detail: m.swapTotal > 0
                        ? "共 \(ByteCountFormatter.string(fromByteCount: Int64(m.swapTotal), countStyle: .memory))"
                        : "未使用",
                    level: m.swapUsed > 0 ? 40 : 0
                )
                .frame(width: wRest, alignment: .leading)

                metricBlock(title: "网络", value: "吞吐", detail: m.networkFormatted, level: 0)
                    .frame(width: wNet, alignment: .leading)

                metricBlock(title: "磁盘", value: "页换入出", detail: m.diskFormatted, level: 0)
                    .frame(width: wRest, alignment: .leading)

                metricBlock(
                    title: "负载",
                    value: String(format: "%.2f", m.loadAverage1),
                    detail: m.loadFormatted,
                    level: min(100, m.loadAverage1 / max(1, Double(m.processorCount)) * 100)
                )
                .frame(width: wRest, alignment: .leading)
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    /// 等宽卡片：左主值+总量，右三列「标签上 / 数值下」
    private func memoryBlock(_ m: SystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("内存")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f%%", m.memoryUsedPercent))
                        .font(.system(.callout, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(levelColor(m.memoryUsedPercent))
                    Text(m.memoryFormatted)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                HStack(spacing: 6) {
                    memPart(label: "应用", bytes: m.appMemory)
                    memPart(label: "联动", bytes: m.wiredMemory)
                    memPart(label: "压缩", bytes: m.compressedMemory)
                }
                .help(m.memoryDetailFormatted)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(levelColor(m.memoryUsedPercent).opacity(0.75))
                        .frame(width: max(2, geo.size.width * CGFloat(min(100, max(0, m.memoryUsedPercent)) / 100)))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func memPart(label: String, bytes: UInt64) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            Text(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private func metricBlock(
        title: String,
        value: String,
        detail: String,
        level: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(levelColor(level))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(detail)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.12))
                    Capsule()
                        .fill(levelColor(level).opacity(0.75))
                        .frame(width: max(2, geo.size.width * CGFloat(min(100, max(0, level)) / 100)))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func levelColor(_ level: Double) -> Color {
        if level >= 85 { return .red }
        if level >= 60 { return .orange }
        return .primary
    }
}

// MARK: - Category top rankings

struct CategoryRankingsView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    var onSelect: (Int32) -> Void

    var body: some View {
        let r = monitor.rankings
        VStack(alignment: .leading, spacing: 12) {
            rankSection(title: "第三方 · CPU", symbol: "flame", items: r.thirdPartyByCPU)
            rankSection(title: "第三方 · 内存", symbol: "memorychip", items: r.thirdPartyByMemory)
            rankSection(title: "Apple 系统 · CPU", symbol: "gearshape.2", items: r.appleSystemByCPU)
            rankSection(title: "Apple 应用 · CPU", symbol: "apple.logo", items: r.appleAppByCPU)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func rankSection(title: String, symbol: String, items: [ProcessRankingItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if items.isEmpty {
                Text("暂无数据")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        onSelect(item.process.pid)
                    } label: {
                        HStack(spacing: 6) {
                            Text("\(index + 1).")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                                .frame(width: 14, alignment: .trailing)
                            Text(item.process.name)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text(item.metricLabel)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Enhanced process detail panel

struct ProcessDetailPanel: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    let process: MonitoredProcess
    var onTerminate: () -> Void
    var onForceQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ProcessDetailBar(process: process, onTerminate: onTerminate, onForceQuit: onForceQuit)

            let detail = monitor.selectedDetail
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 16) {
                    if let parent = detail.parentName {
                        labelValue("父进程", "\(parent) (\(process.ppid))")
                    } else {
                        labelValue("父进程", "PID \(process.ppid)")
                    }
                    labelValue("打开文件", "\(detail.openFileCount)")
                    if let start = process.startTime {
                        labelValue("启动", start.formatted(date: .omitted, time: .shortened))
                    }
                    Text(detail.sampleNote)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }

                if !detail.openFiles.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(detail.openFiles.prefix(12)) { file in
                                Text("\(file.kind): \(shortPath(file.path))")
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.1), in: Capsule())
                                    .help(file.path)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private func labelValue(_ title: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func shortPath(_ path: String) -> String {
        if path.count <= 36 { return path }
        let url = URL(fileURLWithPath: path)
        return "…/" + url.lastPathComponent
    }
}
