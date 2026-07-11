import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: ProcessMonitor

    var body: some View {
        Form {
            Section("刷新") {
                Picker("刷新间隔", selection: $monitor.refreshInterval) {
                    Text("1 秒").tag(1.0)
                    Text("2 秒").tag(2.0)
                    Text("5 秒").tag(5.0)
                    Text("10 秒").tag(10.0)
                }
                LabeledContent("暂停刷新") {
                    Text("按住 ⌃ Control")
                        .foregroundStyle(.secondary)
                }
                Text("按住 Control 键时界面停止自动刷新，便于查看与选择进程；松开后立即恢复并刷新一次。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于分类") {
                Text("SwiftInsight 根据进程路径、Bundle Identifier 与已知系统进程名，区分：")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label("Apple 系统 — 内核、launchd、系统守护进程与 /System、/usr 等路径", systemImage: "gearshape.2.fill")
                    .font(.callout)
                Label("Apple 应用 — 带 com.apple.* Bundle ID 或系统自带应用", systemImage: "apple.logo")
                    .font(.callout)
                Label("第三方 — 其余用户安装的应用与进程", systemImage: "app.badge")
                    .font(.callout)
            }

            Section("关于") {
                LabeledContent("应用", value: "SwiftInsight")
                LabeledContent("用途", value: "活动监视器替代 · 侧重 Apple / 第三方资源对比")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 400)
    }
}
