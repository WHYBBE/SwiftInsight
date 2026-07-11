import SwiftUI

/// 设置页兼容视图
struct MenuBarCompactView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @EnvironmentObject private var menuBar: MenuBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("menubar.icon"))
                .font(.headline)
            Picker(L("menubar.mode"), selection: $menuBar.iconMode) {
                ForEach(MenuBarIconMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(String(
                format: L("status.cpu_mem"),
                monitor.systemMetrics.cpuUsed,
                monitor.systemMetrics.memoryUsedPercent
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}
