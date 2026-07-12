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
    private let contentSize = NSSize(width: 360, height: 545)
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
        let open = NSMenuItem(title: L("mb.open_main"), action: #selector(openMainFromMenu), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("mb.quit_app"), action: #selector(quitFromMenu), keyEquivalent: "q")
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
        button.toolTip = String(format: L("status.cpu_mem"), cpu, mem)
    }

    func openMainWindow() {
        closePanel()
        // 统一走主窗口协调器：恢复 Dock + 显示/重建主窗口
        if let onOpenMain {
            onOpenMain()
        } else {
            MainWindowCoordinator.showMainWindow()
        }
    }

    func quit() {
        closePanel()
        NSApp.terminate(nil)
    }

    /// 语言切换后刷新静态文案
    func refreshLocalizedUI() {
        panelContent?.applyLocalization()
        if let monitor {
            panelContent?.reload(from: monitor)
            refreshIcon()
        }
    }
}

// MARK: - AppKit 面板（显式 reload，数据可靠）

final class MenuBarPanelView: NSView {
    var onOpenMain: (() -> Void)?
    var onQuit: (() -> Void)?

    private let background = NSVisualEffectView()
    private let stroke = NSView()

    // 内存
    private let memSection = RoundedSectionView()
    private let pressureRing = RingGaugeView()
    private let memoryRing = MultiSegmentRingView()
    private let memLegendStack = NSStackView()

    // CPU
    private let cpuSection = RoundedSectionView()
    private let cpuTitleLabel = makeLabel("CPU", size: 12, color: .systemBlue, weight: .semibold)
    private let cpuMetaLabel = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let coreDots = CoreDotsView()
    private let eCoreLegend = makeLabel("", size: 11, color: .labelColor)
    private let pCoreLegend = makeLabel("", size: 11, color: .labelColor)
    private let userSysLegend = makeLabel("", size: 11, color: .labelColor)

    // 构成
    private let compositionTitle = makeLabel(L("mb.composition"), size: 11, color: .secondaryLabelColor, weight: .semibold)
    private let cpuCompLabel = makeLabel("CPU", size: 10, color: .secondaryLabelColor, weight: .medium)
    private let memCompLabel = makeLabel(L("metric.memory"), size: 10, color: .secondaryLabelColor, weight: .medium)
    private let cpuCompositionBar = CompositionBarView()
    private let memCompositionBar = CompositionBarView()
    private let cpuSysLegend = makeLabel("", size: 10, color: .labelColor)
    private let cpuAppLegend = makeLabel("", size: 10, color: .labelColor)
    private let cpuThirdLegend = makeLabel("", size: 10, color: .labelColor)
    private let memSysLegend = makeLabel("", size: 10, color: .labelColor)
    private let memAppLegend = makeLabel("", size: 10, color: .labelColor)
    private let memThirdLegend = makeLabel("", size: 10, color: .labelColor)

    // 高占用
    private let topsTitle = makeLabel(L("mb.tops"), size: 11, color: .secondaryLabelColor, weight: .semibold)
    private let cpuTopHeader = makeLabel("CPU", size: 10, color: .secondaryLabelColor, weight: .medium)
    private let memTopHeader = makeLabel(L("metric.memory"), size: 10, color: .secondaryLabelColor, weight: .medium)
    private let cpuTopRows: [TopRowView] = (0..<3).map { TopRowView(index: $0 + 1) }
    private let memTopRows: [TopRowView] = (0..<3).map { TopRowView(index: $0 + 1) }

    private let openButton = NSButton(title: L("mb.full_window"), target: nil, action: nil)
    private let quitButton = NSButton(title: L("mb.quit"), target: nil, action: nil)

    private let memLegendRows: [LegendRowView] = [
        LegendRowView(color: MenuBarPalette.appMem, title: L("metric.app")),
        LegendRowView(color: MenuBarPalette.wired, title: L("metric.wired")),
        LegendRowView(color: MenuBarPalette.compressed, title: L("metric.compressed")),
        LegendRowView(color: MenuBarPalette.available, title: L("metric.available")),
    ]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true

        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        addSubview(background)

        stroke.wantsLayer = true
        stroke.layer?.cornerRadius = 14
        stroke.layer?.borderWidth = 1
        stroke.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        addSubview(stroke)

        addSubview(memSection)
        memSection.addSubview(pressureRing)
        memSection.addSubview(memoryRing)
        memLegendStack.orientation = .vertical
        memLegendStack.alignment = .width
        memLegendStack.spacing = 6
        memLegendStack.distribution = .fillEqually
        memLegendRows.forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            memLegendStack.addArrangedSubview($0)
        }
        memSection.addSubview(memLegendStack)


        addSubview(cpuSection)
        [cpuTitleLabel, cpuMetaLabel, coreDots, eCoreLegend, pCoreLegend, userSysLegend].forEach {
            cpuSection.addSubview($0)
        }

        let rest: [NSView] = [
            compositionTitle, cpuCompLabel, memCompLabel,
            cpuCompositionBar, memCompositionBar,
            cpuSysLegend, cpuAppLegend, cpuThirdLegend,
            memSysLegend, memAppLegend, memThirdLegend,
            topsTitle, cpuTopHeader, memTopHeader,
        ] + cpuTopRows + memTopRows + [openButton, quitButton]
        rest.forEach { addSubview($0) }

        openButton.bezelStyle = .rounded
        openButton.target = self
        openButton.action = #selector(openMain)
        openButton.controlSize = .small

        quitButton.bezelStyle = .rounded
        quitButton.target = self
        quitButton.action = #selector(quit)
        quitButton.controlSize = .small

        pressureRing.lineWidth = 7
        memoryRing.lineWidth = 7
    }

    required init?(coder: NSCoder) { fatalError() }

    func applyLocalization() {
        compositionTitle.stringValue = L("mb.composition")
        cpuCompLabel.stringValue = "CPU"
        memCompLabel.stringValue = L("metric.memory")
        topsTitle.stringValue = L("mb.tops")
        cpuTopHeader.stringValue = "CPU"
        memTopHeader.stringValue = L("metric.memory")
        openButton.title = L("mb.full_window")
        quitButton.title = L("mb.quit")
        memLegendRows[0].setTitle(L("metric.app"))
        memLegendRows[1].setTitle(L("metric.wired"))
        memLegendRows[2].setTitle(L("metric.compressed"))
        memLegendRows[3].setTitle(L("metric.available"))
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 360, height: 545) }

    func reload(from monitor: ProcessMonitor) {
        let m = monitor.systemMetrics
        let s = monitor.summary

        // 压力环
        let pressureColor: NSColor = {
            switch m.memoryPressureLevel {
            case 4: return .systemRed
            case 2: return .systemOrange
            default: return MenuBarPalette.pressure
            }
        }()
        pressureRing.configure(
            percent: m.memoryPressure,
            title: m.memoryPressureLabel.uppercased(),
            color: pressureColor
        )
        pressureRing.toolTip = String(
            format: L("mb.pressure_tip"),
            m.memoryPressureLevel,
            m.memoryPressure
        )

        // 内存多段环：App / 联动 / 压缩 / 可用
        let phys = max(1, Double(m.physicalMemory))
        let app = Double(m.appMemory)
        let wired = Double(m.wiredMemory)
        let comp = Double(m.compressedMemory)
        let usedSum = app + wired + comp
        let availSeg = max(0, phys - usedSum)
        memoryRing.configure(
            segments: [
                (MenuBarPalette.appMem, app / phys),
                (MenuBarPalette.wired, wired / phys),
                (MenuBarPalette.compressed, comp / phys),
                (MenuBarPalette.available, availSeg / phys),
            ],
            centerPercent: m.memoryUsedPercent,
            centerTitle: L("metric.memory")
        )

        memLegendRows[0].setValue(byteString(m.appMemory))
        memLegendRows[1].setValue(byteString(m.wiredMemory))
        memLegendRows[2].setValue(byteString(m.compressedMemory))
        memLegendRows[3].setValue(byteString(m.availableMemory))

        // CPU
        let hw = m.cpuHWFormatted
        if hw.isEmpty {
            cpuMetaLabel.stringValue = String(format: "%.0f%% · " + String(format: L("metric.cores"), max(m.processorCount, m.coreUsages.count)), m.cpuUsed)
        } else {
            cpuMetaLabel.stringValue = String(format: "%.0f%% · %@", m.cpuUsed, hw)
        }
        cpuMetaLabel.toolTip = {
            var parts: [String] = [String(format: L("metric.cores"), max(m.processorCount, m.coreUsages.count))]
            if m.efficiencyFrequencyMHz > 0 { parts.append(String(format: "E %.0f MHz", m.efficiencyFrequencyMHz)) }
            if m.performanceFrequencyMHz > 0 { parts.append(String(format: "P %.0f MHz", m.performanceFrequencyMHz)) }
            if m.cpuTemperatureC > 0 { parts.append(String(format: "%.0f°C", m.cpuTemperatureC)) }
            if m.thermalState > 0 { parts.append(m.thermalStateLabel) }
            return parts.joined(separator: " · ")
        }()
        let eCount = m.efficiencyCoreCount
        let pCount = m.performanceCoreCount
        coreDots.configure(
            usages: m.coreUsages,
            efficiencyCount: eCount,
            performanceCount: pCount
        )
        eCoreLegend.attributedStringValue = legend(L("metric.efficiency"), m.efficiencyCoreUsage, MenuBarPalette.eCore)
        pCoreLegend.attributedStringValue = legend(L("metric.performance"), m.performanceCoreUsage, MenuBarPalette.pCore)
        userSysLegend.attributedStringValue = dualLegend(
            (L("metric.user"), m.cpuUser, MenuBarPalette.userCPU),
            (L("metric.system"), m.cpuSystem, MenuBarPalette.systemCPU)
        )

        // 构成：CPU 相对 100%；内存相对物理内存
        cpuCompositionBar.setSegments([
            (.systemBlue, s.appleSystemCPU),
            (.systemTeal, s.appleAppCPU),
            (.systemOrange, s.thirdPartyCPU),
        ], scale: 100)
        cpuSysLegend.attributedStringValue = legend(L("cat.short.system"), s.appleSystemCPU, .systemBlue, decimals: 1)
        cpuAppLegend.attributedStringValue = legend(L("cat.short.apple"), s.appleAppCPU, .systemTeal, decimals: 1)
        cpuThirdLegend.attributedStringValue = legend(L("cat.short.third"), s.thirdPartyCPU, .systemOrange, decimals: 1)

        let memScale = max(phys, 1)
        memCompositionBar.setSegments([
            (.systemBlue, Double(s.appleSystemMemory) / memScale * 100),
            (.systemTeal, Double(s.appleAppMemory) / memScale * 100),
            (.systemOrange, Double(s.thirdPartyMemory) / memScale * 100),
        ], scale: 100)
        memSysLegend.attributedStringValue = legendBytes(L("cat.short.system"), s.appleSystemMemory, .systemBlue)
        memAppLegend.attributedStringValue = legendBytes(L("cat.short.apple"), s.appleAppMemory, .systemTeal)
        memThirdLegend.attributedStringValue = legendBytes(L("cat.short.third"), s.thirdPartyMemory, .systemOrange)

        fillTop(rows: cpuTopRows, items: Array(monitor.rankings.thirdPartyByCPU.prefix(3)))
        fillTop(rows: memTopRows, items: Array(monitor.rankings.thirdPartyByMemory.prefix(3)))
        needsLayout = true
    }

    private func byteString(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 {
            return String(format: "%5.2f GB", gb)
        }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%5.1f MB", mb)
    }

    private func shortByte(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 1 { return String(format: "%.1fG", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1 { return String(format: "%.0fM", mb) }
        return String(format: "%.0fK", Double(bytes) / 1024)
    }


    private func fillTop(rows: [TopRowView], items: [ProcessRankingItem]) {
        for (i, row) in rows.enumerated() {
            if i < items.count {
                row.isHidden = false
                row.configure(name: items[i].process.name, value: items[i].metricLabel, empty: false)
            } else {
                row.configure(name: i == 0 ? L("mb.none") : "", value: "", empty: true)
                row.isHidden = i > 0
            }
        }
    }

    override func layout() {
        super.layout()
        let b = bounds
        background.frame = b.insetBy(dx: 1, dy: 1)
        stroke.frame = b.insetBy(dx: 1, dy: 1)

        let inset: CGFloat = 12
        let btnH: CGFloat = 26
        let btnArea: CGFloat = btnH + 16
        var y = b.height - inset

        // 内存区：环在上、图例在右（加宽后完整显示）
        let memH: CGFloat = 132
        y -= memH
        memSection.frame = NSRect(x: inset, y: y, width: b.width - inset * 2, height: memH)
        let ringSize: CGFloat = 86
        let ringY = (memH - ringSize) / 2
        let ringPad: CGFloat = 12
        pressureRing.frame = NSRect(x: ringPad, y: ringY, width: ringSize, height: ringSize)
        memoryRing.frame = NSRect(x: ringPad + ringSize + 10, y: ringY, width: ringSize, height: ringSize)
        let legendX = ringPad + ringSize * 2 + 22
        let legendW = max(100, memSection.bounds.width - legendX - 10)
        memLegendStack.frame = NSRect(x: legendX, y: 16, width: legendW, height: memH - 32)
        // 强制每行同宽，数值列对齐
        for row in memLegendRows {
            row.frame.size.width = legendW
        }


        y -= 10
        // CPU 区
        let cpuH: CGFloat = 112
        y -= cpuH
        cpuSection.frame = NSRect(x: inset, y: y, width: b.width - inset * 2, height: cpuH)
        cpuTitleLabel.frame = NSRect(x: 12, y: cpuH - 24, width: 40, height: 16)
        cpuMetaLabel.frame = NSRect(x: 52, y: cpuH - 24, width: cpuSection.bounds.width - 64, height: 16)
        cpuMetaLabel.alignment = .right
        coreDots.frame = NSRect(x: 10, y: 44, width: cpuSection.bounds.width - 20, height: 30)
        let half = (cpuSection.bounds.width - 24) / 2
        eCoreLegend.frame = NSRect(x: 12, y: 24, width: half, height: 14)
        pCoreLegend.frame = NSRect(x: 12 + half, y: 24, width: half, height: 14)
        userSysLegend.frame = NSRect(x: 12, y: 8, width: cpuSection.bounds.width - 24, height: 14)

        y -= 16
        compositionTitle.frame = NSRect(x: inset, y: y - 13, width: 80, height: 14)
        y -= 18

        // CPU 构成
        cpuCompLabel.frame = NSRect(x: inset, y: y - 11, width: 36, height: 12)
        y -= 14
        cpuCompositionBar.frame = NSRect(x: inset, y: y - 7, width: b.width - inset * 2, height: 6)
        y -= 14
        let legendColW = (b.width - inset * 2) / 3
        cpuSysLegend.frame = NSRect(x: inset, y: y - 12, width: legendColW, height: 13)
        cpuAppLegend.frame = NSRect(x: inset + legendColW, y: y - 12, width: legendColW, height: 13)
        cpuThirdLegend.frame = NSRect(x: inset + legendColW * 2, y: y - 12, width: legendColW, height: 13)
        y -= 18

        // 内存构成
        memCompLabel.frame = NSRect(x: inset, y: y - 11, width: 36, height: 12)
        y -= 14
        memCompositionBar.frame = NSRect(x: inset, y: y - 7, width: b.width - inset * 2, height: 6)
        y -= 14
        memSysLegend.frame = NSRect(x: inset, y: y - 12, width: legendColW, height: 13)
        memAppLegend.frame = NSRect(x: inset + legendColW, y: y - 12, width: legendColW, height: 13)
        memThirdLegend.frame = NSRect(x: inset + legendColW * 2, y: y - 12, width: legendColW, height: 13)

        y -= 22
        topsTitle.frame = NSRect(x: inset, y: y - 13, width: 80, height: 14)
        y -= 16

        let colGap: CGFloat = 12
        let colW = (b.width - inset * 2 - colGap) / 2
        let leftX = inset
        let rightX = inset + colW + colGap
        cpuTopHeader.frame = NSRect(x: leftX, y: y - 12, width: colW, height: 13)
        memTopHeader.frame = NSRect(x: rightX, y: y - 12, width: colW, height: 13)
        y -= 16

        // 高占用与按钮之间留足空隙
        let topsBottom = btnArea + 4
        let rowH: CGFloat = 17
        for i in 0..<3 {
            let rowY = y - rowH
            if rowY < topsBottom { break }
            if !cpuTopRows[i].isHidden {
                cpuTopRows[i].frame = NSRect(x: leftX, y: rowY, width: colW, height: 16)
            }
            if !memTopRows[i].isHidden {
                memTopRows[i].frame = NSRect(x: rightX, y: rowY, width: colW, height: 16)
            }
            y -= 19
        }

        let btnY: CGFloat = 10
        let quitW: CGFloat = 56
        openButton.frame = NSRect(x: inset, y: btnY, width: b.width - inset * 2 - quitW - 8, height: btnH)
        quitButton.frame = NSRect(x: b.width - inset - quitW, y: btnY, width: quitW, height: btnH)
    }

    @objc private func openMain() { onOpenMain?() }
    @objc private func quit() { onQuit?() }

    private func legend(
        _ title: String,
        _ value: Double,
        _ color: NSColor,
        decimals: Int = 0
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "● ", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: color,
        ]))
        result.append(NSAttributedString(string: "\(title) ", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        let fmt = decimals > 0 ? "%.\(decimals)f%%" : "%.0f%%"
        result.append(NSAttributedString(string: String(format: fmt, value), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]))
        return result
    }

    private func legendBytes(_ title: String, _ bytes: UInt64, _ color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "● ", attributes: [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .foregroundColor: color,
        ]))
        result.append(NSAttributedString(string: "\(title) ", attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        result.append(NSAttributedString(string: shortByte(bytes), attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium),
            .foregroundColor: NSColor.labelColor,
        ]))
        return result
    }

    private func dualLegend(
        _ a: (String, Double, NSColor),
        _ b: (String, Double, NSColor)
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        result.append(legend(a.0, a.1, a.2, decimals: 0))
        result.append(NSAttributedString(string: "    ", attributes: [:]))
        result.append(legend(b.0, b.1, b.2, decimals: 0))
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

// MARK: - Palette

private enum MenuBarPalette {
    static let pressure = NSColor(calibratedRed: 0.72, green: 0.42, blue: 0.92, alpha: 1)
    static let appMem = NSColor.systemBlue
    static let wired = NSColor.systemPink
    static let compressed = NSColor.systemOrange
    static let available = NSColor.labelColor.withAlphaComponent(0.28)
    static let eCore = NSColor.systemPink
    static let pCore = NSColor.systemBlue
    static let userCPU = NSColor.systemBlue
    static let systemCPU = NSColor.systemPink
}

// MARK: - Section chrome

private final class RoundedSectionView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Single-color ring gauge

private final class RingGaugeView: NSView {
    var lineWidth: CGFloat = 7
    private var percent: Double = 0
    private var title = ""
    private var color: NSColor = .systemPurple
    private let percentLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        percentLabel.alignment = .center
        percentLabel.drawsBackground = false
        percentLabel.isBezeled = false
        percentLabel.isEditable = false
        titleLabel.font = .systemFont(ofSize: 8, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        addSubview(percentLabel)
        addSubview(titleLabel)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(percent: Double, title: String, color: NSColor) {
        self.percent = max(0, min(100, percent))
        self.title = title
        self.color = color
        percentLabel.stringValue = String(format: "%.0f%%", self.percent)
        percentLabel.textColor = color
        titleLabel.stringValue = title.uppercased()
        needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        percentLabel.frame = NSRect(x: 4, y: midY - 4, width: bounds.width - 8, height: 22)
        titleLabel.frame = NSRect(x: 4, y: midY - 20, width: bounds.width - 8, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset = lineWidth / 2 + 1
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        let track = NSBezierPath()
        track.lineWidth = lineWidth
        track.lineCapStyle = .round
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        NSColor.labelColor.withAlphaComponent(0.12).setStroke()
        track.stroke()

        let angle = CGFloat(percent / 100) * 360
        guard angle > 0.5 else { return }
        let arc = NSBezierPath()
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        // 从顶部顺时针
        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - angle, clockwise: true)
        color.setStroke()
        arc.stroke()
    }
}

// MARK: - Multi-segment ring

private final class MultiSegmentRingView: NSView {
    var lineWidth: CGFloat = 7
    private var segments: [(NSColor, Double)] = []
    private var centerPercent: Double = 0
    private var centerTitle = ""
    private let percentLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        percentLabel.font = .monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
        percentLabel.alignment = .center
        percentLabel.drawsBackground = false
        percentLabel.isBezeled = false
        percentLabel.isEditable = false
        titleLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.alignment = .center
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        addSubview(percentLabel)
        addSubview(titleLabel)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(segments: [(NSColor, Double)], centerPercent: Double, centerTitle: String) {
        self.segments = segments
        self.centerPercent = max(0, min(100, centerPercent))
        self.centerTitle = centerTitle
        percentLabel.stringValue = String(format: "%.0f%%", self.centerPercent)
        percentLabel.textColor = .labelColor
        titleLabel.stringValue = centerTitle
        needsDisplay = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let midY = bounds.midY
        percentLabel.frame = NSRect(x: 4, y: midY - 4, width: bounds.width - 8, height: 22)
        titleLabel.frame = NSRect(x: 4, y: midY - 20, width: bounds.width - 8, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let inset = lineWidth / 2 + 1
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        let track = NSBezierPath()
        track.lineWidth = lineWidth
        track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        NSColor.labelColor.withAlphaComponent(0.1).setStroke()
        track.stroke()

        let total = max(segments.reduce(0) { $0 + max(0, $1.1) }, 0.0001)
        var start: CGFloat = 90
        for seg in segments {
            let fraction = CGFloat(max(0, seg.1) / total)
            let sweep = fraction * 360
            guard sweep > 0.3 else {
                start -= sweep
                continue
            }
            let arc = NSBezierPath()
            arc.lineWidth = lineWidth
            arc.lineCapStyle = .butt
            arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
            seg.0.setStroke()
            arc.stroke()
            start -= sweep
        }
    }
}

// MARK: - Core dots（自适应：圆环 / 双行 / 竖条直方图）

private final class CoreDotsView: NSView {
    private var usages: [Double] = []
    private var efficiencyCount = 0
    private var performanceCount = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(usages: [Double], efficiencyCount: Int, performanceCount: Int) {
        self.usages = usages
        self.efficiencyCount = efficiencyCount
        self.performanceCount = performanceCount
        toolTip = Self.tooltip(usages: usages, e: efficiencyCount, p: performanceCount)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !usages.isEmpty else { return }
        let plan = CoreLayout.plan(count: usages.count, width: bounds.width, height: bounds.height)
        switch plan {
        case .rings(let size, let gap, let cols, let rows):
            drawRings(size: size, gap: gap, cols: cols, rows: rows)
        case .bars(let barW, let gap):
            drawBars(barW: barW, gap: gap)
        }
    }

    private func drawRings(size: CGFloat, gap: CGFloat, cols: Int, rows: Int) {
        let n = usages.count
        let totalW = CGFloat(cols) * size + CGFloat(max(0, cols - 1)) * gap
        let totalH = CGFloat(rows) * size + CGFloat(max(0, rows - 1)) * gap
        let startX = max(0, (bounds.width - totalW) / 2)
        let startY = max(0, (bounds.height - totalH) / 2)
        let lineW = max(1.2, min(2.5, size * 0.14))

        for i in 0..<n {
            let col = i % cols
            let row = i / cols
            let x = startX + CGFloat(col) * (size + gap)
            // AppKit y 向上，row 0 在上
            let y = startY + CGFloat(rows - 1 - row) * (size + gap)
            let isE = efficiencyCount > 0 && i < efficiencyCount
            let color = isE ? MenuBarPalette.eCore : MenuBarPalette.pCore
            let rect = NSRect(x: x, y: y, width: size, height: size)
            let track = NSBezierPath(ovalIn: rect.insetBy(dx: lineW * 0.6, dy: lineW * 0.6))
            track.lineWidth = lineW
            NSColor.labelColor.withAlphaComponent(0.12).setStroke()
            track.stroke()
            let angle = CGFloat(max(0, min(100, usages[i])) / 100) * 360
            if angle > 1 {
                let arc = NSBezierPath()
                arc.lineWidth = lineW
                arc.lineCapStyle = .round
                let c = NSPoint(x: rect.midX, y: rect.midY)
                let r = (size - lineW * 1.2) / 2
                arc.appendArc(withCenter: c, radius: r, startAngle: 90, endAngle: 90 - angle, clockwise: true)
                color.setStroke()
                arc.stroke()
            }
        }
    }

    private func drawBars(barW: CGFloat, gap: CGFloat) {
        let n = usages.count
        let totalW = CGFloat(n) * barW + CGFloat(max(0, n - 1)) * gap
        let startX = max(0, (bounds.width - totalW) / 2)
        let maxH = max(4, bounds.height - 1)
        for i in 0..<n {
            let x = startX + CGFloat(i) * (barW + gap)
            let usage = max(0, min(100, usages[i]))
            let h = max(2, maxH * CGFloat(usage / 100))
            let isE = efficiencyCount > 0 && i < efficiencyCount
            let color = isE ? MenuBarPalette.eCore : MenuBarPalette.pCore
            // 底轨
            NSColor.labelColor.withAlphaComponent(0.08).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: maxH), xRadius: barW / 2, yRadius: barW / 2).fill()
            // 填充自下而上
            color.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: 0, width: barW, height: h), xRadius: barW / 2, yRadius: barW / 2).fill()
        }
    }

    private static func tooltip(usages: [Double], e: Int, p: Int) -> String {
        guard !usages.isEmpty else { return "" }
        if e > 0 || p > 0 {
            let eAvg = e > 0 ? usages.prefix(e).reduce(0, +) / Double(e) : 0
            let pAvg = p > 0 ? usages.suffix(p).reduce(0, +) / Double(p) : 0
            return String(format: L("mb.cores_tip"), usages.count, eAvg, pAvg)
        }
        let avg = usages.reduce(0, +) / Double(usages.count)
        return String(format: L("mb.cores_avg"), usages.count, avg)
    }
}

/// 根据宽高与核数选择布局
private enum CoreLayout {
    case rings(size: CGFloat, gap: CGFloat, cols: Int, rows: Int)
    case bars(barWidth: CGFloat, gap: CGFloat)

    static func plan(count: Int, width: CGFloat, height: CGFloat) -> CoreLayout {
        let n = max(count, 1)
        let minRing: CGFloat = 8
        let idealRing = min(22, max(minRing, height - 1))

        // 单行圆环
        if let one = fitRings(n: n, cols: n, rows: 1, width: width, height: height, minSize: minRing, ideal: idealRing) {
            return one
        }
        // 双行（核数较多时）
        if n > 8, height >= minRing * 2 + 2 {
            let cols = (n + 1) / 2
            if let two = fitRings(n: n, cols: cols, rows: 2, width: width, height: height, minSize: minRing, ideal: idealRing) {
                return two
            }
        }
        // 三行（超多核）
        if n > 16, height >= minRing * 3 + 4 {
            let cols = (n + 2) / 3
            if let three = fitRings(n: n, cols: cols, rows: 3, width: width, height: height, minSize: 7, ideal: idealRing) {
                return three
            }
        }
        // 竖条直方图：任意核数都能铺满宽度
        let gap: CGFloat = n > 24 ? 1 : (n > 16 ? 1.5 : 2)
        let barW = max(2, min(8, (width - gap * CGFloat(n - 1)) / CGFloat(n)))
        return .bars(barWidth: barW, gap: gap)
    }

    private static func fitRings(
        n: Int,
        cols: Int,
        rows: Int,
        width: CGFloat,
        height: CGFloat,
        minSize: CGFloat,
        ideal: CGFloat
    ) -> CoreLayout? {
        let gap: CGFloat = cols > 16 ? 2 : (cols > 10 ? 3 : 5)
        let sizeByW = (width - gap * CGFloat(max(0, cols - 1))) / CGFloat(cols)
        let sizeByH = (height - gap * CGFloat(max(0, rows - 1))) / CGFloat(rows)
        let size = min(ideal, sizeByW, sizeByH)
        guard size >= minSize else { return nil }
        return .rings(size: size, gap: gap, cols: cols, rows: rows)
    }
}

// MARK: - Memory legend row

private final class LegendRowView: NSView {
    private let dot = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let valueLabel = NSTextField(labelWithString: "")

    init(color: NSColor, title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 4
        dot.layer?.backgroundColor = color.cgColor
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.lineBreakMode = .byClipping
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        valueLabel.textColor = .labelColor
        valueLabel.alignment = .right
        valueLabel.drawsBackground = false
        valueLabel.isBezeled = false
        valueLabel.isEditable = false
        valueLabel.lineBreakMode = .byClipping
        addSubview(dot)
        addSubview(titleLabel)
        addSubview(valueLabel)
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setTitle(_ text: String) {
        titleLabel.stringValue = text
    }

    func setValue(_ text: String) {
        valueLabel.stringValue = text
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 18) }

    override func layout() {
        super.layout()
        // 固定右侧数值列，保证四行小数点对齐
        let valueW: CGFloat = 58
        let padR: CGFloat = 0
        dot.frame = NSRect(x: 0, y: (bounds.height - 8) / 2, width: 8, height: 8)
        valueLabel.frame = NSRect(
            x: bounds.width - valueW - padR,
            y: 0,
            width: valueW,
            height: bounds.height
        )
        titleLabel.frame = NSRect(
            x: 14,
            y: 0,
            width: max(20, bounds.width - valueW - padR - 18),
            height: bounds.height
        )
    }
}

// MARK: - Composition bar（相对 scale，默认 100%）

private final class CompositionBarView: NSView {
    private var segments: [(NSColor, Double)] = []
    private var scale: Double = 100
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 3
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        layer?.masksToBounds = true
    }
    required init?(coder: NSCoder) { fatalError() }
    /// value 与 scale 同单位；条宽 = value/scale * width（scale=100 表示 CPU%）
    func setSegments(_ segments: [(NSColor, Double)], scale: Double = 100) {
        self.segments = segments
        self.scale = max(scale, 0.0001)
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        var x: CGFloat = 0
        for seg in segments {
            let fraction = max(0, min(1, seg.1 / scale))
            let width = bounds.width * CGFloat(fraction)
            if width > 0.5 {
                seg.0.setFill()
                NSBezierPath(rect: NSRect(x: x, y: 0, width: width, height: bounds.height)).fill()
            }
            x += width
            if x >= bounds.width { break }
        }
    }
}


// MARK: - Top process row

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
