import AppKit

/// 绘制菜单栏迷你状态条图标
enum MenuBarIconRenderer {
    static let iconSize = NSSize(width: 18, height: 18)

    static func image(mode: MenuBarIconMode, cpu: Double, memory: Double) -> NSImage {
        let size = iconSize
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let cpuLevel = CGFloat(min(100, max(0, cpu)) / 100)
        let memLevel = CGFloat(min(100, max(0, memory)) / 100)

        switch mode {
        case .cpu:
            drawSingleBar(in: rect, level: cpuLevel, color: color(for: cpu))
        case .memory:
            drawSingleBar(in: rect, level: memLevel, color: color(for: memory))
        case .combined:
            drawDualBars(
                in: rect,
                cpu: cpuLevel,
                memory: memLevel,
                cpuColor: color(for: cpu),
                memColor: color(for: memory)
            )
        }

        image.unlockFocus()
        image.isTemplate = false
        image.size = size
        return image
    }

    private static func drawSingleBar(in rect: NSRect, level: CGFloat, color: NSColor) {
        let inset: CGFloat = 2.5
        let bar = NSRect(
            x: rect.minX + inset,
            y: rect.minY + inset,
            width: 5,
            height: rect.height - inset * 2
        )
        NSColor.labelColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 1.5, yRadius: 1.5).fill()

        let fillHeight = max(1.5, bar.height * level)
        let fill = NSRect(x: bar.minX, y: bar.minY, width: bar.width, height: fillHeight)
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()

        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .semibold),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: style,
        ]
        let text = "\(Int((level * 100).rounded()))"
        let textRect = NSRect(
            x: bar.maxX + 1,
            y: rect.minY + 3,
            width: rect.width - bar.maxX - 1,
            height: rect.height - 6
        )
        text.draw(in: textRect, withAttributes: attrs)
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
        drawBar(track: cpuBar, level: cpu, color: cpuColor)
        drawBar(track: memBar, level: memory, color: memColor)
    }

    private static func drawBar(track: NSRect, level: CGFloat, color: NSColor) {
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
