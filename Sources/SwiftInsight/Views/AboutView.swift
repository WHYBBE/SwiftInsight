import SwiftUI
import AppKit

/// 应用菜单「关于 SwiftInsight」窗口内容
struct AboutView: View {
    private let repoURL = URL(string: "https://github.com/WHYBBE/SwiftInsight")!
    private let licenseURL = URL(string: "https://github.com/WHYBBE/SwiftInsight/blob/main/LICENSE")!
    private let repoDisplay = "WHYBBE/SwiftInsight"

    private let labelWidth: CGFloat = 72

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: AppInfo.icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 3)

                Text(AppInfo.name)
                    .font(.title.weight(.semibold))

                Text(L("settings.purpose.value"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
            .padding(.top, 28)
            .padding(.bottom, 20)

            Divider()

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text(L("settings.version"))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                        .frame(width: labelWidth, alignment: .trailing)
                    Text(AppInfo.version)
                        .font(.body.monospacedDigit())
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text(L("settings.bundle_id"))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                        .frame(width: labelWidth, alignment: .trailing)
                    Text(AppInfo.bundleIdentifier)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text(L("settings.repository"))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                        .frame(width: labelWidth, alignment: .trailing)
                    Link(repoDisplay, destination: repoURL)
                        .font(.callout)
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    Text(L("settings.license"))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                        .frame(width: labelWidth, alignment: .trailing)
                    Link("MIT License", destination: licenseURL)
                        .font(.callout)
                        .gridColumnAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 36)
            .padding(.vertical, 20)

            Spacer(minLength: 4)
        }
        .frame(width: 400, height: 360)
        .background(.background)
    }
}

enum AppInfo {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "SwiftInsight"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "me.whynbnb.SwiftInsight"
    }

    static var icon: NSImage {
        // 优先从 AppIcon 资源读取，避免 NSApp.applicationIconImage 在开发时变成通用文件夹图标
        if let img = loadAppIconFromBundle() {
            return img
        }
        if let icon = NSApplication.shared.applicationIconImage {
            // 过滤明显是占位/通用文档图标的情况（小尺寸或系统默认）
            let size = max(icon.size.width, icon.size.height)
            if size >= 64 {
                return icon
            }
        }
        if let symbol = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent", accessibilityDescription: name) {
            let config = NSImage.SymbolConfiguration(pointSize: 64, weight: .medium)
            return symbol.withSymbolConfiguration(config) ?? symbol
        }
        return NSImage(size: NSSize(width: 96, height: 96))
    }

    private static func loadAppIconFromBundle() -> NSImage? {
        // Assets.car / AppIcon name
        if let img = NSImage(named: "AppIcon"), max(img.size.width, img.size.height) >= 32 {
            return img
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        let resourceRoots = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources"),
            Bundle.main.bundleURL,
        ].compactMap { $0 }

        for root in resourceRoots {
            let icns = root.appendingPathComponent("AppIcon.icns")
            if let img = NSImage(contentsOf: icns) { return img }
        }

        // 源码树（swift run / 开发）
        let pngNames = [
            "appicon-mac-512@1x.png",
            "appicon-mac-256@1x.png",
            "appicon-mac-256@2x.png",
        ]
        let searchDirs = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset"),
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Resources/Assets.xcassets/AppIcon.appiconset"),
        ]
        for dir in searchDirs {
            for name in pngNames {
                let url = dir.appendingPathComponent(name)
                if let img = NSImage(contentsOf: url) { return img }
            }
        }
        return nil
    }
}
