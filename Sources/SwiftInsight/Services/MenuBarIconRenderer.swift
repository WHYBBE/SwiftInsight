import AppKit

/// 绘制菜单栏迷你状态条图标
enum MenuBarIconRenderer {
    static let iconHeight: CGFloat = 18
    /// 仅 CPU / 仅内存：横向布局（标签 + 条）
    static let singleModeWidth: CGFloat = 22
    static let combinedWidth: CGFloat = 18

    private static let imageCache = NSCache<NSString, NSImage>()
    private static let labelAttrs: [NSAttributedString.Key: Any] = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return [
            .font: NSFont.systemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
    }()

    static func image(mode: MenuBarIconMode, cpu: Double, memory: Double) -> NSImage {
        let cpuBucket = Int(min(100, max(0, cpu)).rounded())
        let memBucket = Int(min(100, max(0, memory)).rounded())
        let cacheKey = "\(mode.rawValue)|\(cpuBucket)|\(memBucket)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) {
            return cached
        }

        let cpuLevel = CGFloat(cpuBucket) / 100
        let memLevel = CGFloat(memBucket) / 100

        let size: NSSize
        switch mode {
        case .cpu, .memory:
            size = NSSize(width: singleModeWidth, height: iconHeight)
        case .combined:
            size = NSSize(width: combinedWidth, height: iconHeight)
        }

        let image = NSImage(size: size, flipped: false) { rect in
            switch mode {
            case .cpu:
                drawLabeledHorizontal(
                    in: rect,
                    label: "CPU",
                    level: cpuLevel,
                    color: color(for: Double(cpuBucket))
                )
            case .memory:
                drawLabeledHorizontal(
                    in: rect,
                    label: "MEM",
                    level: memLevel,
                    color: color(for: Double(memBucket))
                )
            case .combined:
                drawDualBars(
                    in: rect,
                    cpu: cpuLevel,
                    memory: memLevel,
                    cpuColor: color(for: Double(cpuBucket)),
                    memColor: color(for: Double(memBucket))
                )
            }
            return true
        }
        image.isTemplate = false
        imageCache.countLimit = 64
        imageCache.setObject(image, forKey: cacheKey)
        return image
    }

    /// 上方标签 + 下方横向进度条
    private static func drawLabeledHorizontal(
        in rect: NSRect,
        label: String,
        level: CGFloat,
        color: NSColor
    ) {
        let padX: CGFloat = 0.5
        let labelHeight: CGFloat = 8
        let barHeight: CGFloat = 3
        let gap: CGFloat = 2.5

        // 垂直居中：标签在上、条在下（gap 拉开上下间距）
        let contentH = labelHeight + gap + barHeight
        let topY = rect.minY + (rect.height - contentH) / 2 + barHeight + gap

        let labelRect = NSRect(
            x: rect.minX,
            y: topY,
            width: rect.width,
            height: labelHeight
        )
        label.draw(in: labelRect, withAttributes: labelAttrs)

        let barRect = NSRect(
            x: rect.minX + padX,
            y: topY - gap - barHeight,
            width: max(10, rect.width - padX * 2),
            height: barHeight
        )
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 1.5, yRadius: 1.5).fill()

        let fillWidth = max(2, barRect.width * level)
        let fill = NSRect(x: barRect.minX, y: barRect.minY, width: fillWidth, height: barRect.height)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
    }

    private static func drawDualBars(
        in rect: NSRect,
        cpu: CGFloat,
        memory: CGFloat,
        cpuColor: NSColor,
        memColor: NSColor
    ) {
        let inset: CGFloat = 2
        let gap: CGFloat = 2
        let barWidth: CGFloat = 5
        let totalBarsWidth = barWidth * 2 + gap
        let startX = rect.midX - totalBarsWidth / 2
        let trackHeight = rect.height - inset * 2

        let cpuBar = NSRect(x: startX, y: rect.minY + inset, width: barWidth, height: trackHeight)
        let memBar = NSRect(
            x: startX + barWidth + gap,
            y: rect.minY + inset,
            width: barWidth,
            height: trackHeight
        )
        drawVerticalBar(track: cpuBar, level: cpu, color: cpuColor)
        drawVerticalBar(track: memBar, level: memory, color: memColor)
    }

    private static func drawVerticalBar(track: NSRect, level: CGFloat, color: NSColor) {
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: track, xRadius: 1.5, yRadius: 1.5).fill()
        let fillHeight = max(1.5, track.height * level)
        let fill = NSRect(x: track.minX, y: track.minY, width: track.width, height: fillHeight)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
    }

    private static func color(for percent: Double) -> NSColor {
        if percent >= 85 { return .systemRed }
        if percent >= 60 { return .systemOrange }
        if percent >= 30 { return .systemBlue }
        return .systemGreen
    }
}
