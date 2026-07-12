import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var monitor: ProcessMonitor
    @EnvironmentObject private var menuBar: MenuBarController
    @EnvironmentObject private var prefs: AppPreferences

    @State private var helperBusy = false
    @State private var helperMessage: String?
    @State private var helperMessageIsError = false

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
                        .foregroundStyle(helperStatusColor)
                }
                Text(L("settings.helper.body"))
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if !HelperInstaller.hasBundledHelper {
                    Text(L("settings.helper.no_bundle"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                HStack(spacing: 12) {
                    Button(L("settings.helper.install_btn")) {
                        runHelperAction(.install)
                    }
                    .disabled(helperBusy || !HelperInstaller.hasBundledHelper || monitor.privilegedHelperRoot)

                    Button(L("settings.helper.uninstall_btn"), role: .destructive) {
                        runHelperAction(.uninstall)
                    }
                    .disabled(helperBusy || !monitor.privilegedHelperInstalled)

                    Button(L("settings.helper.recheck")) {
                        monitor.refreshHelperStatus()
                        helperMessage = nil
                    }
                    .disabled(helperBusy)
                }

                if let helperMessage {
                    Text(helperMessage)
                        .font(.caption)
                        .foregroundStyle(helperMessageIsError ? Color.red : Color.secondary)
                }

                Text(L("settings.helper.path_hint"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
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
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 620)
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
        if HelperInstaller.hasBundledHelper {
            return L("settings.helper.bundled")
        }
        return L("settings.helper.missing")
    }

    private var helperStatusColor: Color {
        if monitor.privilegedHelperRoot { return .green }
        if HelperInstaller.hasBundledHelper { return .orange }
        return .secondary
    }

    private enum HelperAction {
        case install
        case uninstall
    }

    private func runHelperAction(_ action: HelperAction) {
        helperBusy = true
        helperMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let outcome: HelperInstaller.Outcome
            switch action {
            case .install: outcome = HelperInstaller.install()
            case .uninstall: outcome = HelperInstaller.uninstall()
            }
            DispatchQueue.main.async {
                helperBusy = false
                monitor.refreshHelperStatus()
                switch outcome {
                case .success:
                    helperMessageIsError = false
                    helperMessage = action == .install
                        ? L("settings.helper.install_ok")
                        : L("settings.helper.uninstall_ok")
                case .cancelled:
                    helperMessageIsError = false
                    helperMessage = L("settings.helper.cancelled")
                case .missingBundle:
                    helperMessageIsError = true
                    helperMessage = L("settings.helper.no_bundle")
                case .failed(let msg):
                    helperMessageIsError = true
                    helperMessage = String(format: L("settings.helper.failed"), msg)
                }
            }
        }
    }
}
