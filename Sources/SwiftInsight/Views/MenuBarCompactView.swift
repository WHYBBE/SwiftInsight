import SwiftUI

/// 设置页兼容视图
struct MenuBarCompactView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @EnvironmentObject private var menuBar: MenuBarController

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("菜单栏图标")
                .font(.headline)
            Picker("模式", selection: $menuBar.iconMode) {
                ForEach(MenuBarIconMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(String(
                format: "CPU %.0f%% · 内存 %.0f%%",
                monitor.systemMetrics.cpuUsed,
                monitor.systemMetrics.memoryUsedPercent
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding()
    }
}
