import AppKit
import Combine

/// 菜单栏
/// - 数据：AppKit 面板 + 强引用 ProcessMonitor（与 @StateObject 同一实例）
/// - 定位：NSPanel + convertToScreen（SPM / .app 都可靠；避免 NSPopover 在 regular 主窗口 App 下错位）
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    @Published var iconMode: MenuBarIconMode {
        didSet {
            UserDefaults.standard.set(iconMode.rawValue, forKey: Self.modeKey)
            refreshIcon()
        }
    }

    var onOpenMain: (() -> Void)?

    private var monitor: ProcessMonitor?
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var panelContent: MenuBarPanelView?
    private var cancellables = Set<AnyCancellable>()
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var keyEventMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var otherAppObserver: NSObjectProtocol?

    private static let modeKey = "menuBarIconMode"
    private let contentSize = NSSize(width: 320, height: 360)
    private let panelGap: CGFloat = 4

    override init() {
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let mode = MenuBarIconMode(rawValue: raw) {
            iconMode = mode
        } else {
            iconMode = .combined
        }
        super.init()
    }

    func install(monitor: ProcessMonitor) {
        self.monitor = monitor

        if statusItem != nil {
            bindData(monitor)
            return
        }

        let content = MenuBarPanelView(frame: NSRect(origin: .zero, size: contentSize))
        content.onOpenMain = { [weak self] in self?.openMainWindow() }
        content.onQuit = { [weak self] in self?.quit() }
        panelContent = content

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = content
        panel.setContentSize(contentSize)
        self.panel = panel

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "SwiftInsight"
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        statusItem = item

        installFocusObservers()
        bindData(monitor)
    }

    /// 失焦 / 切空间 / 其它 App 激活时自动关面板
    private func installFocusObservers() {
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.closePanel() }
            }
        }
        if spaceObserver == nil {
            spaceObserver = NotificationCenter.default.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.closePanel() }
            }
        }
        if otherAppObserver == nil {
            otherAppObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] note in
                let other = note.userInfo?["NSWorkspaceApplicationKey"] as? NSRunningApplication
                if other?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    Task { @MainActor in self?.closePanel() }
                }
            }
        }
    }

    private func bindData(_ monitor: ProcessMonitor) {
        cancellables.removeAll()
        Publishers.CombineLatest3(monitor.$systemMetrics, monitor.$summary, monitor.$rankings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                guard let self, let monitor = self.monitor else { return }
                self.refreshIcon()
                self.panelContent?.reload(from: monitor)
            }
            .store(in: &cancellables)
        refreshIcon()
        panelContent?.reload(from: monitor)
    }

    private var isVisible: Bool { panel?.isVisible == true }

    @objc private func togglePanel(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown {
            showContextMenu()
            return
        }
        if isVisible {
            closePanel()
            return
        }
        showPanel()
    }

    private func showPanel() {
        guard let button = statusItem?.button, let panel else { return }

        if let monitor {
            panelContent?.reload(from: monitor)
            panelContent?.layoutSubtreeIfNeeded()
            monitor.refresh()
        }
        panel.setContentSize(contentSize)

        let frame = panelFrame(relativeTo: button)
        panel.setFrame(frame, display: false)
        panel.orderFrontRegardless()
        panel.setFrame(frame, display: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.startEventMonitors()
        }
    }

    func closePopover() { closePanel() }

    private func closePanel() {
        stopEventMonitors()
        panel?.orderOut(nil)
    }

    private func panelFrame(relativeTo button: NSStatusBarButton) -> NSRect {
        let size = contentSize
        let mouse = NSEvent.mouseLocation
        let btnScreen = convertedButtonScreenRect(button)

        var anchorX = mouse.x
        var anchorBottomY = mouse.y - 10

        if let btn = btnScreen, isPlausibleMenuBarRect(btn, near: mouse) {
            anchorX = btn.midX
            anchorBottomY = btn.minY
        }

        var origin = NSPoint(
            x: anchorX - size.width / 2,
            y: anchorBottomY - size.height - panelGap
        )

        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) })
            ?? button.window?.screen
            ?? NSScreen.main

        if let screen {
            let vf = screen.visibleFrame
            origin.x = min(max(origin.x, vf.minX + 6), vf.maxX - size.width - 6)
            let maxY = vf.maxY - size.height - 2
            let minY = vf.minY + 6
            origin.y = min(max(origin.y, minY), maxY)
        }

        return NSRect(
            x: origin.x.rounded(),
            y: origin.y.rounded(),
            width: size.width,
            height: size.height
        )
    }

    private func convertedButtonScreenRect(_ button: NSStatusBarButton) -> NSRect? {
        guard let window = button.window else { return nil }
        let inWindow = button.convert(button.bounds, to: nil)
        let screen = window.convertToScreen(inWindow)
        guard screen.width > 1, screen.height > 1 else { return nil }
        return screen
    }

    private func isPlausibleMenuBarRect(_ rect: NSRect, near mouse: NSPoint) -> Bool {
        if abs(rect.midX - mouse.x) > 48 { return false }
        if abs(rect.midY - mouse.y) > 40 { return false }

        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main else {
            return true
        }
        let menuBarBand = screen.frame.maxY - 48
        if rect.midY < menuBarBand { return false }
        return true
    }

    private func startEventMonitors() {
        stopEventMonitors()

        // 本 App 内点击（主窗口等）
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleOutsideClick(event)
            return event
        }

        // 其他 App / 桌面点击
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleOutsideClick(event)
        }

        // Esc 关闭
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.closePanel()
                return nil
            }
            return event
        }
    }

    private func stopEventMonitors() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let globalEventMonitor {
            NSEvent.removeMonitor(globalEventMonitor)
            self.globalEventMonitor = nil
        }
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
            self.keyEventMonitor = nil
        }
    }

    private func handleOutsideClick(_ event: NSEvent) {
        guard isVisible, let panel else { return }

        // 点在面板窗口内：保留
        if let win = event.window, win === panel { return }

        let clickScreen: NSPoint
        if let win = event.window {
            clickScreen = win.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
        } else {
            clickScreen = NSEvent.mouseLocation
        }

        if panel.frame.insetBy(dx: -2, dy: -2).contains(clickScreen) { return }

        // 仅忽略「点在状态栏图标小区域内」；rect 过大/不可信则直接关
        if let button = statusItem?.button,
           let r = convertedButtonScreenRect(button),
           r.width <= 40, r.height <= 40,
           abs(r.midX - clickScreen.x) < 24,
           abs(r.midY - clickScreen.y) < 24,
           r.insetBy(dx: -4, dy: -4).contains(clickScreen) {
            return
        }

        closePanel()
    }

    private func showContextMenu() {
        closePanel()
        let menu = NSMenu()
        let open = NSMenuItem(title: "打开主窗口", action: #selector(openMainFromMenu), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 SwiftInsight", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func openMainFromMenu() { openMainWindow() }
    @objc private func quitFromMenu() { quit() }

    private func refreshIcon() {
        guard let monitor, let button = statusItem?.button else { return }
        let cpu = monitor.systemMetrics.cpuUsed
        let mem = monitor.systemMetrics.memoryUsedPercent
        let image = MenuBarIconRenderer.image(mode: iconMode, cpu: cpu, memory: mem)
        image.size = NSSize(width: 18, height: 18)
        button.image = image
        button.toolTip = String(format: "CPU %.0f%% · 内存 %.0f%%", cpu, mem)
    }

    func openMainWindow() {
        closePanel()
        if let onOpenMain {
            onOpenMain()
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.styleMask.contains(.titled) })?.makeKeyAndOrderFront(nil)
    }

    func quit() {
        closePanel()
        NSApp.terminate(nil)
    }
}

// MARK: - AppKit 面板（显式 reload，数据可靠）

final class MenuBarPanelView: NSView {
    var onOpenMain: (() -> Void)?
    var onQuit: (() -> Void)?

    private let background = NSVisualEffectView()
    private let stroke = NSView()

    private let cpuCard = MetricCardView(title: "CPU")
    private let memCard = MetricCardView(title: "内存")
    private let swapCard = MetricCardView(title: "交换")

    private let compositionTitle = makeLabel("构成", size: 11, color: .secondaryLabelColor, weight: .semibold)
    private let compositionBar = CompositionBarView()
    private let sysLegend = makeLabel("", size: 11, color: .labelColor)
    private let appLegend = makeLabel("", size: 11, color: .labelColor)
    private let thirdLegend = makeLabel("", size: 11, color: .labelColor)

    private let topsTitle = makeLabel("高占用", size: 11, color: .secondaryLabelColor, weight: .semibold)
    private let cpuTopHeader = makeLabel("CPU", size: 10, color: .secondaryLabelColor, weight: .medium)
    private let memTopHeader = makeLabel("内存", size: 10, color: .secondaryLabelColor, weight: .medium)
    private let cpuTopRows: [TopRowView] = (0..<3).map { TopRowView(index: $0 + 1) }
    private let memTopRows: [TopRowView] = (0..<3).map { TopRowView(index: $0 + 1) }

    private let openButton = NSButton(title: "完整窗口", target: nil, action: nil)
    private let quitButton = NSButton(title: "退出", target: nil, action: nil)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        addSubview(background)

        stroke.wantsLayer = true
        stroke.layer?.cornerRadius = 12
        stroke.layer?.borderWidth = 1
        stroke.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        addSubview(stroke)

        let children: [NSView] = [
            cpuCard, memCard, swapCard,
            compositionTitle, compositionBar, sysLegend, appLegend, thirdLegend,
            topsTitle, cpuTopHeader, memTopHeader,
        ] + cpuTopRows + memTopRows + [openButton, quitButton]
        children.forEach { addSubview($0) }

        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openMain)
        openButton.controlSize = .small

        quitButton.bezelStyle = .rounded
        quitButton.target = self
        quitButton.action = #selector(quit)
        quitButton.controlSize = .small
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 320, height: 360) }

    func reload(from monitor: ProcessMonitor) {
        let m = monitor.systemMetrics
        let s = monitor.summary

        cpuCard.configure(
            value: String(format: "%.0f%%", m.cpuUsed),
            detail: String(format: "用户 %.0f  系统 %.0f", m.cpuUser, m.cpuSystem),
            level: m.cpuUsed
        )
        memCard.configure(
            value: String(format: "%.0f%%", m.memoryUsedPercent),
            detail: ByteCountFormatter.string(fromByteCount: Int64(m.usedMemory), countStyle: .memory),
            level: m.memoryUsedPercent
        )
        let swapLevel: Double
        if m.swapTotal > 0 {
            swapLevel = min(100, Double(m.swapUsed) / Double(m.swapTotal) * 100)
        } else {
            swapLevel = m.swapUsed > 0 ? 30 : 0
        }
        let swapTotal = m.swapTotal > 0
            ? ByteCountFormatter.string(fromByteCount: Int64(m.swapTotal), countStyle: .memory)
            : "—"
        swapCard.configure(
            value: ByteCountFormatter.string(fromByteCount: Int64(m.swapUsed), countStyle: .memory),
            detail: m.swapUsed > 0 ? "共 \(swapTotal)" : "未使用",
            level: swapLevel
        )

        compositionBar.setSegments([
            (.systemBlue, s.appleSystemCPU),
            (.systemTeal, s.appleAppCPU),
            (.systemOrange, s.thirdPartyCPU),
        ])
        sysLegend.attributedStringValue = legend("系统", s.appleSystemCPU, .systemBlue)
        appLegend.attributedStringValue = legend("官方", s.appleAppCPU, .systemTeal)
        thirdLegend.attributedStringValue = legend("三方", s.thirdPartyCPU, .systemOrange)

        fillTop(rows: cpuTopRows, items: Array(monitor.rankings.thirdPartyByCPU.prefix(3)))
        fillTop(rows: memTopRows, items: Array(monitor.rankings.thirdPartyByMemory.prefix(3)))
        needsLayout = true
    }

    private func fillTop(rows: [TopRowView], items: [ProcessRankingItem]) {
        for (i, row) in rows.enumerated() {
            if i < items.count {
                row.isHidden = false
                row.configure(name: items[i].process.name, value: items[i].metricLabel, empty: false)
            } else {
                row.configure(name: i == 0 ? "暂无" : "", value: "", empty: true)
                row.isHidden = i > 0
            }
        }
    }

    override func layout() {
        super.layout()
        let b = bounds
        background.frame = b.insetBy(dx: 1, dy: 1)
        stroke.frame = b.insetBy(dx: 1, dy: 1)

        let inset: CGFloat = 14
        let gap: CGFloat = 8
        let cardW = (b.width - inset * 2 - gap * 2) / 3
        let cardH: CGFloat = 78
        let topY = b.height - inset - cardH

        cpuCard.frame = NSRect(x: inset, y: topY, width: cardW, height: cardH)
        memCard.frame = NSRect(x: inset + cardW + gap, y: topY, width: cardW, height: cardH)
        swapCard.frame = NSRect(x: inset + (cardW + gap) * 2, y: topY, width: cardW, height: cardH)

        var y = topY - 18
        compositionTitle.frame = NSRect(x: inset, y: y - 13, width: 80, height: 14)
        y -= 22
        compositionBar.frame = NSRect(x: inset, y: y - 8, width: b.width - inset * 2, height: 7)
        y -= 20
        let legendW = (b.width - inset * 2) / 3
        sysLegend.frame = NSRect(x: inset, y: y - 13, width: legendW, height: 14)
        appLegend.frame = NSRect(x: inset + legendW, y: y - 13, width: legendW, height: 14)
        thirdLegend.frame = NSRect(x: inset + legendW * 2, y: y - 13, width: legendW, height: 14)

        y -= 28
        topsTitle.frame = NSRect(x: inset, y: y - 13, width: 80, height: 14)
        y -= 20

        let colGap: CGFloat = 12
        let colW = (b.width - inset * 2 - colGap) / 2
        let leftX = inset
        let rightX = inset + colW + colGap
        cpuTopHeader.frame = NSRect(x: leftX, y: y - 12, width: colW, height: 13)
        memTopHeader.frame = NSRect(x: rightX, y: y - 12, width: colW, height: 13)
        y -= 18

        for i in 0..<3 {
            let rowY = y - 16
            if !cpuTopRows[i].isHidden {
                cpuTopRows[i].frame = NSRect(x: leftX, y: rowY, width: colW, height: 16)
            }
            if !memTopRows[i].isHidden {
                memTopRows[i].frame = NSRect(x: rightX, y: rowY, width: colW, height: 16)
            }
            y -= 20
        }

        let btnY = inset
        let quitW: CGFloat = 56
        openButton.frame = NSRect(x: inset, y: btnY, width: b.width - inset * 2 - quitW - 8, height: 24)
        quitButton.frame = NSRect(x: b.width - inset - quitW, y: btnY, width: quitW, height: 24)
    }

    @objc private func openMain() { onOpenMain?() }
    @objc private func quit() { onQuit?() }

    private func legend(_ title: String, _ value: Double, _ color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "● ", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: color,
        ]))
        result.append(NSAttributedString(string: "\(title) ", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        result.append(NSAttributedString(string: String(format: "%.0f%%", value), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]))
        return result
    }

    private static func makeLabel(_ text: String, size: CGFloat, color: NSColor, weight: NSFont.Weight = .regular) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        l.drawsBackground = false
        l.isBezeled = false
        l.isEditable = false
        return l
    }
}

private final class MetricCardView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let barTrack = NSView()
    private let barFill = NSView()
    private var level: Double = 0

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        valueLabel.lineBreakMode = .byClipping
        detailLabel.font = .systemFont(ofSize: 10)
        detailLabel.textColor = .tertiaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        barTrack.wantsLayer = true
        barTrack.layer?.cornerRadius = 1.5
        barTrack.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
        barFill.wantsLayer = true
        barFill.layer?.cornerRadius = 1.5
        for tf in [titleLabel, valueLabel, detailLabel] {
            tf.drawsBackground = false
            tf.isBezeled = false
            tf.isEditable = false
            addSubview(tf)
        }
        addSubview(barTrack)
        barTrack.addSubview(barFill)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(value: String, detail: String, level: Double) {
        valueLabel.stringValue = value
        detailLabel.stringValue = detail
        self.level = min(100, max(0, level))
        let c = color(for: self.level)
        valueLabel.textColor = c
        barFill.layer?.backgroundColor = c.withAlphaComponent(0.9).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 9
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 18, width: bounds.width - inset * 2, height: 12)
        valueLabel.frame = NSRect(x: inset, y: bounds.height - 42, width: bounds.width - inset * 2, height: 22)
        detailLabel.frame = NSRect(x: inset, y: 16, width: bounds.width - inset * 2, height: 13)
        barTrack.frame = NSRect(x: inset, y: 8, width: bounds.width - inset * 2, height: 3)
        barFill.frame = NSRect(x: 0, y: 0, width: max(2, barTrack.bounds.width * CGFloat(level / 100)), height: 3)
    }

    private func color(for level: Double) -> NSColor {
        if level >= 85 { return .systemRed }
        if level >= 60 { return .systemOrange }
        return .labelColor
    }
}

private final class CompositionBarView: NSView {
    private var segments: [(NSColor, Double)] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func setSegments(_ segments: [(NSColor, Double)]) {
        self.segments = segments
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let total = max(segments.reduce(0) { $0 + max(0, $1.1) }, 0.0001)
        var x: CGFloat = 0
        for (i, seg) in segments.enumerated() {
            var width = bounds.width * CGFloat(max(0, seg.1) / total)
            if i == segments.count - 1 { width = max(0, bounds.width - x) }
            if width > 0.5 {
                seg.0.setFill()
                NSBezierPath(rect: NSRect(x: x, y: 0, width: width, height: bounds.height)).fill()
            }
            x += width
        }
    }
}

private final class TopRowView: NSView {
    private let indexLabel = NSTextField(labelWithString: "")
    private let nameLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    init(index: Int) {
        super.init(frame: .zero)
        indexLabel.stringValue = "\(index)."
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        indexLabel.textColor = .tertiaryLabelColor
        nameLabel.font = .systemFont(ofSize: 11)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        for l in [indexLabel, nameLabel, valueLabel] {
            l.isBezeled = false
            l.isEditable = false
            l.drawsBackground = false
            addSubview(l)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func configure(name: String, value: String, empty: Bool) {
        nameLabel.stringValue = name
        valueLabel.stringValue = value
        nameLabel.textColor = empty ? .tertiaryLabelColor : .labelColor
        toolTip = empty ? nil : "\(name)  \(value)"
        needsLayout = true
    }
    override func layout() {
        super.layout()
        let valueW: CGFloat = 44
        indexLabel.frame = NSRect(x: 0, y: 0, width: 14, height: bounds.height)
        valueLabel.frame = NSRect(x: bounds.width - valueW, y: 0, width: valueW, height: bounds.height)
        nameLabel.frame = NSRect(x: 16, y: 0, width: max(20, bounds.width - valueW - 18), height: bounds.height)
    }
}
