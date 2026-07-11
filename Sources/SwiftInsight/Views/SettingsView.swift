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

            Section("特权采样（自用）") {
                LabeledContent("Helper") {
                    Text(helperStatusText)
                        .foregroundStyle(monitor.privilegedHelperRoot ? Color.green : Color.secondary)
                }
                Text("活动监视器通过 sysmond + 私有 entitlement 读取系统保护进程。第三方 App 默认不行。自用可安装 setuid root Helper，用同一套 libproc 在 root 下采样并回传给主程序。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("安装（需管理员密码，仅本机自用）：")
                    .font(.caption.weight(.semibold))
                Text("cd \(projectHint) && ./scripts/install-privileged-helper.sh")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text("卸载：sudo rm -f /usr/local/libexec/SwiftInsightHelper")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button("重新检测 Helper") {
                    monitor.refreshHelperStatus()
                }
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
        .frame(width: 560, height: 560)
        .onAppear { monitor.refreshHelperStatus() }
    }

    private var helperStatusText: String {
        if monitor.privilegedHelperRoot {
            return "已安装 · root 生效"
        }
        if monitor.privilegedHelperInstalled {
            return "已找到但非 root（请重新 install）"
        }
        return "未安装"
    }

    private var projectHint: String {
        // 尽量给出可复制路径；SPM 运行时可能不在源码目录
        FileManager.default.currentDirectoryPath
    }
}
