import SwiftUI
import Charts

// MARK: - Mini sparkline (system overview)

struct SystemHistoryCharts: View {
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        let samples = monitor.systemHistory
        HStack(spacing: 12) {
            chartCard(title: "CPU 趋势", unit: "%") {
                Chart(samples) { s in
                    LineMark(
                        x: .value("t", s.date),
                        y: .value("cpu", s.cpu)
                    )
                    .foregroundStyle(Color.accentColor)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("t", s.date),
                        y: .value("cpu", s.cpu)
                    )
                    .foregroundStyle(Color.accentColor.opacity(0.12))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...max(100, (samples.map(\.cpu).max() ?? 1) * 1.1))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }

            chartCard(title: "内存 趋势", unit: "%") {
                Chart(samples) { s in
                    LineMark(
                        x: .value("t", s.date),
                        y: .value("mem", s.memoryPercent)
                    )
                    .foregroundStyle(Color.orange)
                    .interpolationMethod(.catmullRom)

                    AreaMark(
                        x: .value("t", s.date),
                        y: .value("mem", s.memoryPercent)
                    )
                    .foregroundStyle(Color.orange.opacity(0.12))
                    .interpolationMethod(.catmullRom)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }

            chartCard(title: "分类 CPU", unit: "%") {
                Chart {
                    ForEach(samples) { s in
                        LineMark(
                            x: .value("t", s.date),
                            y: .value("第三方", s.thirdPartyCPU)
                        )
                        .foregroundStyle(by: .value("系列", "第三方"))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("t", s.date),
                            y: .value("Apple", s.appleCPU)
                        )
                        .foregroundStyle(by: .value("系列", "Apple"))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartForegroundStyleScale([
                    "第三方": Color.orange,
                    "Apple": Color.cyan,
                ])
                .chartLegend(position: .top, alignment: .trailing, spacing: 4)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text("历史")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Picker("", selection: $monitor.historyWindow) {
                    ForEach(HistoryWindow.allCases) { w in
                        Text(w.displayName).tag(w)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 88)

                if samples.isEmpty {
                    Text("采集中…")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text("\(samples.count) 点")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .frame(height: 72)
    }

    private func chartCard<Content: View>(title: String, unit: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(unit)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Process history chart (detail)

struct ProcessHistoryChart: View {
    let samples: [MetricSample]
    let window: HistoryWindow

    var body: some View {
        if samples.count < 2 {
            HStack {
                Text("历史曲线采集中（需 \(window.displayName) 内多个采样点）")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .frame(height: 56)
        } else {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Chart(samples) { s in
                        LineMark(
                            x: .value("t", s.date),
                            y: .value("cpu", s.cpu)
                        )
                        .foregroundStyle(Color.accentColor)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("t", s.date),
                            y: .value("cpu", s.cpu)
                        )
                        .foregroundStyle(Color.accentColor.opacity(0.15))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: 0...max(5, (samples.map(\.cpu).max() ?? 1) * 1.15))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("内存")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Chart(samples) { s in
                        LineMark(
                            x: .value("t", s.date),
                            y: .value("mem", Double(s.memoryBytes) / 1_048_576.0)
                        )
                        .foregroundStyle(Color.orange)
                        .interpolationMethod(.catmullRom)
                        AreaMark(
                            x: .value("t", s.date),
                            y: .value("mem", Double(s.memoryBytes) / 1_048_576.0)
                        )
                        .foregroundStyle(Color.orange.opacity(0.15))
                        .interpolationMethod(.catmullRom)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                }

                VStack(alignment: .trailing, spacing: 2) {
                    if let last = samples.last {
                        Text(String(format: "%.1f%%", last.cpu))
                            .font(.caption.monospacedDigit().weight(.semibold))
                        Text(ByteCountFormatter.string(fromByteCount: Int64(last.memoryBytes), countStyle: .memory))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(window.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(width: 64)
            }
            .frame(height: 56)
        }
    }
}
