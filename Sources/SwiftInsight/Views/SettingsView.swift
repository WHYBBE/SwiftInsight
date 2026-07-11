import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @EnvironmentObject private var menuBar: MenuBarController
    @EnvironmentObject private var prefs: AppPreferences

    var body: some View {
        Form {
            Section(L("settings.appearance")) {
                Picker(L("settings.language"), selection: $prefs.language) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                Text(L("settings.language.caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(L("settings.theme"), selection: $prefs.theme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }
                Text(L("settings.theme.caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.refresh")) {
                Picker(L("settings.refresh_interval"), selection: $monitor.refreshInterval) {
                    Text(L("settings.1s")).tag(1.0)
                    Text(L("settings.2s")).tag(2.0)
                    Text(L("settings.5s")).tag(5.0)
                    Text(L("settings.10s")).tag(10.0)
                }
                LabeledContent(L("settings.pause_refresh")) {
                    Text(L("settings.hold_control"))
                        .foregroundStyle(.secondary)
                }
                Text(L("settings.pause.caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.menubar")) {
                Picker(L("settings.icon_mode"), selection: $menuBar.iconMode) {
                    ForEach(MenuBarIconMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(L("settings.menubar.caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(L("settings.helper")) {
                LabeledContent("Helper") {
                    Text(helperStatusText)
                        .foregroundStyle(monitor.privilegedHelperRoot ? Color.green : Color.secondary)
                }
                Text(L("settings.helper.body"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(L("settings.helper.install"))
                    .font(.caption.weight(.semibold))
                Text("cd \(projectHint) && ./scripts/install-privileged-helper.sh")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Text(L("settings.helper.uninstall"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Button(L("settings.helper.recheck")) {
                    monitor.refreshHelperStatus()
                }
            }

            Section(L("settings.classification")) {
                Text(L("settings.classification.intro"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label(L("settings.classification.system"), systemImage: "gearshape.2.fill")
                    .font(.callout)
                Label(L("settings.classification.app"), systemImage: "apple.logo")
                    .font(.callout)
                Label(L("settings.classification.third"), systemImage: "app.badge")
                    .font(.callout)
            }

            Section(L("settings.about")) {
                LabeledContent(L("settings.app"), value: "SwiftInsight")
                LabeledContent(L("settings.purpose"), value: L("settings.purpose.value"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 680)
        .id(prefs.language)
        .onAppear { monitor.refreshHelperStatus() }
    }

    private var helperStatusText: String {
        if monitor.privilegedHelperRoot {
            return L("settings.helper.ok")
        }
        if monitor.privilegedHelperInstalled {
            return L("settings.helper.not_root")
        }
        return L("settings.helper.missing")
    }

    private var projectHint: String {
        FileManager.default.currentDirectoryPath
    }
}
