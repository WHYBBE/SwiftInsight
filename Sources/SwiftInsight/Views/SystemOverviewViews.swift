import SwiftUI

// MARK: - System overview strip

struct SystemOverviewBar: View {
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        let m = monitor.systemMetrics
        GeometryReader { geo in
            let gap: CGFloat = 10
            let total = max(0, geo.size.width - gap * 5)
            let wMem = total * 0.30
            let wCPU = total * 0.18
            let wNet = total * 0.15
            let wRest = total * 0.123

            HStack(alignment: .top, spacing: gap) {
                cpuBlock(m)
                    .frame(width: wCPU, alignment: .leading)

                memoryBlock(m)
                    .frame(width: wMem, alignment: .leading)

                metricBlock(
                    title: L("metric.swap"),
                    value: m.swapFormatted,
                    detail: m.swapTotal > 0
                        ? String(format: L("metric.swap_total"), ByteCountFormatter.string(fromByteCount: Int64(m.swapTotal), countStyle: .memory))
                        : L("metric.swap_none"),
                    level: m.swapUsed > 0 ? 40 : 0
                )
                .frame(width: wRest, alignment: .leading)

                metricBlock(title: L("metric.network"), value: L("metric.throughput"), detail: m.networkFormatted, level: 0)
                    .frame(width: wNet, alignment: .leading)

                metricBlock(title: L("metric.disk"), value: L("metric.page_io"), detail: m.diskFormatted, level: 0)
                    .frame(width: wRest, alignment: .leading)

                metricBlock(
                    title: L("metric.load"),
                    value: String(format: "%.2f", m.loadAverage1),
                    detail: m.loadFormatted,
                    level: min(100, m.loadAverage1 / max(1, Double(m.processorCount)) * 100)
                )
                .frame(width: wRest, alignment: .leading)
            }
        }
        .frame(height: 62)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }

    private func cpuBlock(_ m: SystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("CPU")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if !m.cpuHWFormatted.isEmpty {
                    Text(m.cpuHWFormatted)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(cpuHWHelp(m))
                } else if m.efficiencyCoreCount > 0 || m.performanceCoreCount > 0 {
                    Text(m.coreSummaryFormatted)
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Text(m.cpuFormatted)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(levelColor(m.cpuUsed))

            Text(String(format: L("metric.user_system"), m.cpuUser, m.cpuSystem))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            CoreDotsStrip(
                usages: m.coreUsages,
                efficiencyCount: m.efficiencyCoreCount,
                performanceCount: m.performanceCoreCount
            )
            .frame(height: 12)
            .help(coreHelp(m))
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func cpuHWHelp(_ m: SystemMetrics) -> String {
        var parts: [String] = []
        if m.efficiencyFrequencyMHz > 0 {
            parts.append(String(format: "E %.0f MHz", m.efficiencyFrequencyMHz))
        }
        if m.performanceFrequencyMHz > 0 {
            parts.append(String(format: "P %.0f MHz", m.performanceFrequencyMHz))
        }
        if m.cpuTemperatureC > 0 {
            parts.append(String(format: "%.0f°C", m.cpuTemperatureC))
        }
        if m.thermalState > 0 {
            parts.append(m.thermalStateLabel)
        }
        return parts.isEmpty ? m.cpuHWFormatted : parts.joined(separator: " · ")
    }

    private func coreHelp(_ m: SystemMetrics) -> String {
        if m.efficiencyCoreCount > 0 || m.performanceCoreCount > 0 {
            return String(
                format: L("metric.ep_cores"),
                m.efficiencyCoreUsage,
                m.performanceCoreUsage,
                m.coreUsages.count
            )
        }
        return String(format: L("metric.logical_cores"), m.coreUsages.count)
    }

    private func memoryBlock(_ m: SystemMetrics) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(L("metric.memory"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(String(format: L("metric.pressure_fmt"), m.memoryPressure, m.memoryPressureLabel))
                    .font(.system(size: 9).monospacedDigit())
                    .foregroundStyle(pressureColor(m))
                    .help(String(format: "kern.memorystatus_vm_pressure_level = %d", m.memoryPressureLevel))
            }

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
                    memPart(label: L("metric.app"), bytes: m.appMemory, color: .blue)
                    memPart(label: L("metric.wired"), bytes: m.wiredMemory, color: .pink)
                    memPart(label: L("metric.compressed"), bytes: m.compressedMemory, color: .orange)
                }
                .help(m.memoryDetailFormatted)
            }

            MemoryCompositionBar(
                app: m.appMemory,
                wired: m.wiredMemory,
                compressed: m.compressedMemory,
                available: m.availableMemory,
                physical: m.physicalMemory
            )
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func memPart(label: String, bytes: UInt64, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            HStack(spacing: 3) {
                Circle().fill(color).frame(width: 5, height: 5)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func levelColor(_ level: Double) -> Color {
        if level >= 85 { return .red }
        if level >= 60 { return .orange }
        return .primary
    }

    private func pressureColor(_ m: SystemMetrics) -> Color {
        switch m.memoryPressureLevel {
        case 4: return .red
        case 2: return .orange
        default: return .purple.opacity(0.85)
        }
    }
}

// MARK: - Core dots (SwiftUI，自适应圆环 / 竖条)

private struct CoreDotsStrip: View {
    let usages: [Double]
    let efficiencyCount: Int
    let performanceCount: Int

    var body: some View {
        GeometryReader { geo in
            let plan = CoreStripLayout.plan(
                count: usages.count,
                width: geo.size.width,
                height: geo.size.height
            )
            Canvas { context, size in
                switch plan {
                case .rings(let dot, let gap, let cols, let rows):
                    drawRings(context: context, size: size, dot: dot, gap: gap, cols: cols, rows: rows)
                case .bars(let barW, let gap):
                    drawBars(context: context, size: size, barW: barW, gap: gap)
                }
            }
            .drawingGroup()
        }
        .help(helpText)
    }

    private var helpText: String {
        guard !usages.isEmpty else { return "" }
        if efficiencyCount > 0 || performanceCount > 0 {
            let e = efficiencyCount
            let p = performanceCount
            let eAvg = e > 0 ? usages.prefix(e).reduce(0, +) / Double(e) : 0
            let pAvg = p > 0 ? usages.suffix(p).reduce(0, +) / Double(p) : 0
            return String(format: L("mb.cores_tip"), usages.count, eAvg, pAvg)
        }
        let avg = usages.reduce(0, +) / Double(usages.count)
        return String(format: L("mb.cores_avg"), usages.count, avg)
    }

    private func drawRings(
        context: GraphicsContext,
        size: CGSize,
        dot: CGFloat,
        gap: CGFloat,
        cols: Int,
        rows: Int
    ) {
        let n = usages.count
        let totalW = CGFloat(cols) * dot + CGFloat(max(0, cols - 1)) * gap
        let totalH = CGFloat(rows) * dot + CGFloat(max(0, rows - 1)) * gap
        let startX = max(0, (size.width - totalW) / 2)
        let startY = max(0, (size.height - totalH) / 2)
        let lineW = max(1.0, min(1.8, dot * 0.14))

        for i in 0..<n {
            let col = i % cols
            let row = i / cols
            let x = startX + CGFloat(col) * (dot + gap)
            let y = startY + CGFloat(row) * (dot + gap)
            let isE = efficiencyCount > 0 && i < efficiencyCount
            let color: Color = isE ? .pink : .blue
            let rect = CGRect(x: x, y: y, width: dot, height: dot).insetBy(dx: lineW * 0.5, dy: lineW * 0.5)
            let style = StrokeStyle(lineWidth: lineW, lineCap: .round)
            context.stroke(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.18)), style: style)
            let fraction = max(0, min(1, usages[i] / 100))
            if fraction > 0.01 {
                var path = Path()
                path.addArc(
                    center: CGPoint(x: rect.midX, y: rect.midY),
                    radius: min(rect.width, rect.height) / 2,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * fraction),
                    clockwise: false
                )
                context.stroke(path, with: .color(color), style: style)
            }
        }
    }

    private func drawBars(context: GraphicsContext, size: CGSize, barW: CGFloat, gap: CGFloat) {
        let n = usages.count
        let totalW = CGFloat(n) * barW + CGFloat(max(0, n - 1)) * gap
        let startX = max(0, (size.width - totalW) / 2)
        let maxH = max(3, size.height)
        for i in 0..<n {
            let x = startX + CGFloat(i) * (barW + gap)
            let usage = max(0, min(100, usages[i]))
            let h = max(1.5, maxH * CGFloat(usage / 100))
            let isE = efficiencyCount > 0 && i < efficiencyCount
            let color: Color = isE ? .pink : .blue
            let track = CGRect(x: x, y: 0, width: barW, height: maxH)
            context.fill(
                Path(roundedRect: track, cornerRadius: barW / 2),
                with: .color(.secondary.opacity(0.12))
            )
            let fill = CGRect(x: x, y: maxH - h, width: barW, height: h)
            context.fill(
                Path(roundedRect: fill, cornerRadius: barW / 2),
                with: .color(color.opacity(0.9))
            )
        }
    }
}

private enum CoreStripLayout {
    case rings(size: CGFloat, gap: CGFloat, cols: Int, rows: Int)
    case bars(barWidth: CGFloat, gap: CGFloat)

    static func plan(count: Int, width: CGFloat, height: CGFloat) -> CoreStripLayout {
        let n = max(count, 1)
        let minRing: CGFloat = 6.5
        let ideal = min(13, max(minRing, height))

        if let one = fit(n: n, cols: n, rows: 1, width: width, height: height, minSize: minRing, ideal: ideal) {
            return one
        }
        if n > 8, height >= minRing * 2 {
            let cols = (n + 1) / 2
            if let two = fit(n: n, cols: cols, rows: 2, width: width, height: height, minSize: minRing, ideal: ideal) {
                return two
            }
        }
        let gap: CGFloat = n > 20 ? 1 : 1.5
        let barW = max(1.5, min(6, (width - gap * CGFloat(n - 1)) / CGFloat(n)))
        return .bars(barWidth: barW, gap: gap)
    }

    private static func fit(
        n: Int,
        cols: Int,
        rows: Int,
        width: CGFloat,
        height: CGFloat,
        minSize: CGFloat,
        ideal: CGFloat
    ) -> CoreStripLayout? {
        let gap: CGFloat = cols > 14 ? 1.5 : 2.5
        let sizeByW = (width - gap * CGFloat(max(0, cols - 1))) / CGFloat(cols)
        let sizeByH = (height - gap * CGFloat(max(0, rows - 1))) / CGFloat(rows)
        let size = min(ideal, sizeByW, sizeByH)
        guard size >= minSize else { return nil }
        return .rings(size: size, gap: gap, cols: cols, rows: rows)
    }
}

// MARK: - Memory composition bar

private struct MemoryCompositionBar: View {
    let app: UInt64
    let wired: UInt64
    let compressed: UInt64
    let available: UInt64
    let physical: UInt64

    var body: some View {
        GeometryReader { geo in
            let total = max(Double(physical), 1)
            let parts: [(Color, Double)] = [
                (.blue, Double(app) / total),
                (.pink, Double(wired) / total),
                (.orange, Double(compressed) / total),
            ]
            let used = parts.reduce(0) { $0 + $1.1 }
            HStack(spacing: 0) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if part.1 > 0.001 {
                        Rectangle()
                            .fill(part.0.opacity(0.85))
                            .frame(width: max(1, geo.size.width * CGFloat(part.1)))
                    }
                }
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: max(0, geo.size.width * CGFloat(max(0, 1 - used))))
            }
            .clipShape(Capsule())
        }
    }
}

// MARK: - Category top rankings

struct CategoryRankingsView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    var onSelect: (Int32) -> Void

    var body: some View {
        let r = monitor.rankings
        VStack(alignment: .leading, spacing: 12) {
            rankSection(title: L("rank.third_cpu"), symbol: "flame", items: r.thirdPartyByCPU)
            rankSection(title: L("rank.third_mem"), symbol: "memorychip", items: r.thirdPartyByMemory)
            rankSection(title: L("rank.sys_cpu"), symbol: "gearshape.2", items: r.appleSystemByCPU)
            rankSection(title: L("rank.app_cpu"), symbol: "apple.logo", items: r.appleAppByCPU)
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
                Text(L("rank.empty"))
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
            VStack(alignment: .leading, spacing: 8) {
                ProcessHistoryChart(samples: monitor.processHistory, window: monitor.historyWindow)

                HStack(spacing: 16) {
                    if let parent = detail.parentName {
                        labelValue(L("detail.parent"), "\(parent) (\(process.ppid))")
                    } else {
                        labelValue(L("detail.parent"), "PID \(process.ppid)")
                    }
                    labelValue(L("detail.open_files"), "\(detail.openFileCount)")
                    if let start = process.startTime {
                        labelValue(L("detail.started"), start.formatted(date: .omitted, time: .shortened))
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
