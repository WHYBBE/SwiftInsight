import SwiftUI
import Charts

// MARK: - Mini sparkline (system overview)

struct SystemHistoryCharts: View {
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        let samples = monitor.systemHistory
        HStack(spacing: 12) {
            chartCard(title: L("chart.cpu"), unit: "%") {
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

            chartCard(title: L("chart.memory"), unit: "%") {
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

            chartCard(title: L("chart.category"), unit: "%") {
                Chart {
                    ForEach(samples) { s in
                        LineMark(
                            x: .value("t", s.date),
                            y: .value(L("chart.series.third"), s.thirdPartyCPU)
                        )
                        .foregroundStyle(by: .value("series", L("chart.series.third")))
                        .interpolationMethod(.catmullRom)

                        LineMark(
                            x: .value("t", s.date),
                            y: .value("Apple", s.appleCPU)
                        )
                        .foregroundStyle(by: .value("series", L("chart.series.apple")))
                        .interpolationMethod(.catmullRom)
                    }
                }
                .chartForegroundStyleScale([
                    L("chart.series.third"): Color.orange,
                    L("chart.series.apple"): Color.cyan,
                ])
                .chartLegend(position: .top, alignment: .trailing, spacing: 4)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }

            VStack(alignment: .trailing, spacing: 4) {
                Text(L("chart.history"))
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
                    Text(L("chart.collecting"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(String(format: L("chart.points"), samples.count))
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
                Text(String(format: L("chart.need_samples"), window.displayName))
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
                    Text(L("metric.memory"))
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
