import AppKit
import Combine

/// 菜单栏轻量面板
///
/// 正确路径（对照成熟菜单栏 App + 社区建议）：
/// 1. NSStatusItem 只管图标，不要挂 statusItem.menu
/// 2. 图形化内容用 NSPopover.show(relativeTo:of:preferredEdge:)
///    —— 由 AppKit 做锚定，避免手动算错坐标系
/// 3. 若 Popover 不可用，再 fallback 到 convertToScreen 精确定位的 NSPanel
@MainActor
final class MenuBarController: NSObject, ObservableObject {
    @Published var iconMode: MenuBarIconMode {
        didSet {
            UserDefaults.standard.set(iconMode.rawValue, forKey: Self.modeKey)
            refreshIcon()
            if let monitor {
                panelContent?.reload(from: monitor, iconMode: iconMode)
            }
        }
    }

    private weak var monitor: ProcessMonitor?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var panelContent: MenuBarPanelView?
    private var hostingController: NSViewController?
    private var cancellables = Set<AnyCancellable>()
    private var eventMonitor: Any?

    private static let modeKey = "menuBarIconMode"
    private let contentSize = NSSize(width: 300, height: 320)

    override init() {
        if let raw = UserDefaults.standard.string(forKey: Self.modeKey),
           let mode = MenuBarIconMode(rawValue: raw) {
            iconMode = mode
        } else {
            iconMode = .combined
        }
        super.init()
    }

    func attach(monitor: ProcessMonitor) {
        self.monitor = monitor
        installStatusItem()
        ensurePopover()
        bind(monitor)
        refreshIcon()
        panelContent?.reload(from: monitor, iconMode: iconMode)
    }

    func detach() {
        closePopover()
        cancellables.removeAll()
        if let statusItem {
            statusItem.button?.target = nil
            statusItem.button?.action = nil
            statusItem.menu = nil
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
        panelContent = nil
        hostingController = nil
        monitor = nil
    }

    // MARK: - Status item

    private func installStatusItem() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.isVisible = true

        if let button = item.button {
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "SwiftInsight"
            button.target = self
            button.action = #selector(togglePopover(_:))
            // mouseDown：与 stats 等项目一致；此时 button.window 已就绪
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        // 关键：不要设置 item.menu —— 会和 action/popover 冲突
        statusItem = item
    }

    private func bind(_ monitor: ProcessMonitor) {
        cancellables.removeAll()
        Publishers.CombineLatest3(monitor.$systemMetrics, monitor.$summary, monitor.$rankings)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                self.refreshIcon()
                if let monitor = self.monitor {
                    self.panelContent?.reload(from: monitor, iconMode: self.iconMode)
                }
            }
            .store(in: &cancellables)
    }

    private func refreshIcon() {
        guard let monitor, let button = statusItem?.button else { return }
        let cpu = monitor.systemMetrics.cpuUsed
        let mem = monitor.systemMetrics.memoryUsedPercent
        let image = MenuBarIconRenderer.image(mode: iconMode, cpu: cpu, memory: mem)
        image.size = NSSize(width: 18, height: 18)
        button.image = image
        button.toolTip = String(format: "CPU %.0f%% · 内存 %.0f%%", cpu, mem)
    }

    // MARK: - Popover

    private func ensurePopover() {
        guard popover == nil else { return }

        let content = MenuBarPanelView(frame: NSRect(origin: .zero, size: contentSize))
        content.onSelectIconMode = { [weak self] mode in
            self?.iconMode = mode
        }
        content.onOpenMain = { [weak self] in
            self?.closePopover()
            self?.openMainWindow()
        }
        content.onQuit = { [weak self] in
            self?.closePopover()
            self?.quit()
        }
        panelContent = content

        let host = NSViewController()
        host.view = content
        host.preferredContentSize = contentSize
        hostingController = host

        let popover = NSPopover()
        popover.contentSize = contentSize
        popover.behavior = .transient          // 点外部自动关
        popover.animates = true
        popover.contentViewController = host
        // 菜单风格外观（若系统支持）
        if #available(macOS 10.14, *) {
            popover.appearance = NSAppearance(named: .vibrantDark)
                ?? NSAppearance(named: .aqua)
        }
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        ensurePopover()
        guard let popover else { return }

        if popover.isShown {
            closePopover()
            return
        }

        if let monitor {
            panelContent?.reload(from: monitor, iconMode: iconMode)
            panelContent?.layoutSubtreeIfNeeded()
        }

        // ★ 核心：让 AppKit 相对状态栏按钮锚定，不要手算屏幕坐标
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // 额外兜底：部分系统上 .transient 不够稳
        startEventMonitor()
    }

    private func closePopover() {
        popover?.performClose(nil)
        stopEventMonitor()
    }

    private func startEventMonitor() {
        stopEventMonitor()
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.popover?.isShown == true else { return }
            self.closePopover()
        }
    }

    private func stopEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    // MARK: - Actions

    func openMainWindow() {
        closePopover()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.styleMask.contains(.titled) {
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func quit() {
        closePopover()
        NSApp.terminate(nil)
    }
}

// MARK: - Graphical panel content

final class MenuBarPanelView: NSView {
    var onSelectIconMode: ((MenuBarIconMode) -> Void)?
    var onOpenMain: (() -> Void)?
    var onQuit: (() -> Void)?

    private let background = NSVisualEffectView()
    private let stroke = NSView()

    private let cpuCard = MetricCardView(title: "CPU")
    private let memCard = MetricCardView(title: "内存")
    private let swapCard = MetricCardView(title: "交换")

    private let compositionTitle = makeLabel("构成", size: 11, color: .secondaryLabelColor, weight: .medium)
    private let compositionBar = CompositionBarView()
    private let sysLegend = makeLabel("", size: 11, color: .labelColor)
    private let appLegend = makeLabel("", size: 11, color: .labelColor)
    private let thirdLegend = makeLabel("", size: 11, color: .labelColor)

    private let topTitle = makeLabel("第三方占用", size: 11, color: .secondaryLabelColor, weight: .medium)
    private let topRows: [TopRowView] = (0..<3).map { TopRowView(index: $0 + 1) }

    private let modeTitle = makeLabel("图标", size: 11, color: .secondaryLabelColor, weight: .medium)
    private let modeControl = NSSegmentedControl(
        labels: ["CPU", "内存", "叠加"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

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

        for v in [cpuCard, memCard, swapCard, compositionTitle, compositionBar,
                  sysLegend, appLegend, thirdLegend, topTitle] + topRows
            + [modeTitle, modeControl, openButton, quitButton] {
            addSubview(v)
        }

        modeControl.segmentStyle = .rounded
        modeControl.target = self
        modeControl.action = #selector(modeChanged)
        modeControl.controlSize = .small

        openButton.bezelStyle = .rounded
        openButton.setButtonType(.momentaryPushIn)
        openButton.target = self
        openButton.action = #selector(openMain)
        openButton.controlSize = .small

        quitButton.bezelStyle = .rounded
        quitButton.target = self
        quitButton.action = #selector(quit)
        quitButton.controlSize = .small
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 300, height: 320)
    }

    func reload(from monitor: ProcessMonitor, iconMode: MenuBarIconMode) {
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
        swapCard.configure(
            value: ByteCountFormatter.string(fromByteCount: Int64(m.swapUsed), countStyle: .memory),
            detail: m.swapUsed > 0 ? "使用中" : "未使用",
            level: swapLevel
        )

        compositionBar.setSegments([
            (.systemBlue, s.appleSystemCPU),
            (.systemTeal, s.appleAppCPU),
            (.systemOrange, s.thirdPartyCPU),
            (.systemGray, s.unknownCPU),
        ])
        sysLegend.attributedStringValue = legend("系统", s.appleSystemCPU, .systemBlue)
        appLegend.attributedStringValue = legend("官方", s.appleAppCPU, .systemTeal)
        thirdLegend.attributedStringValue = legend("三方", s.thirdPartyCPU, .systemOrange)

        let tops = Array(monitor.rankings.thirdPartyByCPU.prefix(3))
        for (i, row) in topRows.enumerated() {
            if i < tops.count {
                row.isHidden = false
                row.configure(name: tops[i].process.name, value: tops[i].metricLabel, empty: false)
            } else {
                row.configure(name: i == 0 ? "暂无" : "", value: "", empty: true)
                row.isHidden = i > 0
            }
        }

        switch iconMode {
        case .cpu: modeControl.selectedSegment = 0
        case .memory: modeControl.selectedSegment = 1
        case .combined: modeControl.selectedSegment = 2
        }

        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let b = bounds
        background.frame = b.insetBy(dx: 1, dy: 1)
        stroke.frame = b.insetBy(dx: 1, dy: 1)

        let inset: CGFloat = 12
        let gap: CGFloat = 8
        let cardW = (b.width - inset * 2 - gap * 2) / 3
        let cardH: CGFloat = 74
        let topY = b.height - inset - cardH

        cpuCard.frame = NSRect(x: inset, y: topY, width: cardW, height: cardH)
        memCard.frame = NSRect(x: inset + cardW + gap, y: topY, width: cardW, height: cardH)
        swapCard.frame = NSRect(x: inset + (cardW + gap) * 2, y: topY, width: cardW, height: cardH)

        var y = topY - 16
        compositionTitle.frame = NSRect(x: inset, y: y - 12, width: 80, height: 14)
        y -= 22
        compositionBar.frame = NSRect(x: inset, y: y - 8, width: b.width - inset * 2, height: 8)
        y -= 20
        let legendW = (b.width - inset * 2) / 3
        sysLegend.frame = NSRect(x: inset, y: y - 12, width: legendW, height: 14)
        appLegend.frame = NSRect(x: inset + legendW, y: y - 12, width: legendW, height: 14)
        thirdLegend.frame = NSRect(x: inset + legendW * 2, y: y - 12, width: legendW, height: 14)

        y -= 28
        topTitle.frame = NSRect(x: inset, y: y - 12, width: 120, height: 14)
        y -= 18
        for row in topRows where !row.isHidden {
            row.frame = NSRect(x: inset, y: y - 16, width: b.width - inset * 2, height: 16)
            y -= 18
        }

        y -= 8
        modeTitle.frame = NSRect(x: inset, y: y - 12, width: 40, height: 14)
        y -= 28
        modeControl.frame = NSRect(x: inset, y: y - 22, width: b.width - inset * 2, height: 22)

        y -= 36
        openButton.frame = NSRect(x: inset, y: y - 24, width: b.width - inset * 2 - 68, height: 24)
        quitButton.frame = NSRect(x: b.width - inset - 60, y: y - 24, width: 60, height: 24)
    }

    @objc private func modeChanged() {
        let mode: MenuBarIconMode
        switch modeControl.selectedSegment {
        case 0: mode = .cpu
        case 1: mode = .memory
        default: mode = .combined
        }
        onSelectIconMode?(mode)
    }

    @objc private func openMain() { onOpenMain?() }
    @objc private func quit() { onQuit?() }

    private func legend(_ title: String, _ value: Double, _ color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "● ", attributes: [
            .font: NSFont.systemFont(ofSize: 10, weight: .bold),
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

    private static func makeLabel(
        _ text: String,
        size: CGFloat,
        color: NSColor,
        weight: NSFont.Weight = .regular
    ) -> NSTextField {
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

// MARK: - Subviews

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
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 10, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 16, weight: .semibold)
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
        let inset: CGFloat = 8
        titleLabel.frame = NSRect(x: inset, y: bounds.height - 18, width: bounds.width - inset * 2, height: 12)
        valueLabel.frame = NSRect(x: inset, y: bounds.height - 40, width: bounds.width - inset * 2, height: 20)
        detailLabel.frame = NSRect(x: inset, y: 16, width: bounds.width - inset * 2, height: 12)
        barTrack.frame = NSRect(x: inset, y: 8, width: bounds.width - inset * 2, height: 3)
        barFill.frame = NSRect(
            x: 0, y: 0,
            width: max(2, barTrack.bounds.width * CGFloat(level / 100)),
            height: 3
        )
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
        let w = bounds.width
        let h = bounds.height
        for (i, seg) in segments.enumerated() {
            var width = w * CGFloat(max(0, seg.1) / total)
            if i == segments.count - 1 { width = max(0, w - x) }
            if width > 0.5 {
                seg.0.setFill()
                NSBezierPath(rect: NSRect(x: x, y: 0, width: width, height: h)).fill()
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
        indexLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        indexLabel.textColor = .tertiaryLabelColor
        nameLabel.font = .systemFont(ofSize: 12)
        nameLabel.lineBreakMode = .byTruncatingTail
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
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
        needsLayout = true
    }

    override func layout() {
        super.layout()
        indexLabel.frame = NSRect(x: 0, y: 0, width: 16, height: bounds.height)
        valueLabel.frame = NSRect(x: bounds.width - 56, y: 0, width: 56, height: bounds.height)
        nameLabel.frame = NSRect(x: 20, y: 0, width: max(40, bounds.width - 80), height: bounds.height)
    }
}
