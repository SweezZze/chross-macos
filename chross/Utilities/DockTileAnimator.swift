import AppKit

/// Drives a subtle pulsing lime dot overlay + a live elapsed-time badge on the Dock
/// icon while a session is running, reverting to the plain icon on stop.
@MainActor
enum DockTileAnimator {
    private static var pulseView: PulseDockView?

    static func start() {
        guard pulseView == nil else { return }
        let view = PulseDockView(frame: NSRect(x: 0, y: 0, width: 128, height: 128))
        NSApp.dockTile.contentView = view
        pulseView = view
        NSApp.dockTile.display()
    }

    static func updateBadge(elapsedSeconds: TimeInterval) {
        guard pulseView != nil else { return }
        NSApp.dockTile.badgeLabel = DurationFormatter.formatShort(elapsedSeconds)
        NSApp.dockTile.display()
    }

    static func stop() {
        pulseView = nil
        NSApp.dockTile.contentView = nil
        NSApp.dockTile.badgeLabel = nil
        NSApp.dockTile.display()
    }
}

private final class PulseDockView: NSView {
    private let dotLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used for a programmatically created dock tile view")
    }

    override func layout() {
        super.layout()
        guard let layer else { return }
        layer.sublayers?.removeAll()

        let iconLayer = CALayer()
        iconLayer.frame = bounds
        iconLayer.contents = NSApp.applicationIconImage
        layer.addSublayer(iconLayer)

        let size = bounds.width * 0.22
        dotLayer.frame = CGRect(x: bounds.width - size - 4, y: 4, width: size, height: size)
        dotLayer.backgroundColor = NSColor(red: 0.839, green: 1.0, blue: 0.247, alpha: 1).cgColor
        dotLayer.cornerRadius = size / 2
        dotLayer.borderColor = NSColor.black.withAlphaComponent(0.6).cgColor
        dotLayer.borderWidth = 1
        layer.addSublayer(dotLayer)
        startPulsing()
    }

    private func startPulsing() {
        dotLayer.removeAnimation(forKey: "pulse")
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 0.85
        pulse.toValue = 1.2
        pulse.duration = 0.9
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dotLayer.add(pulse, forKey: "pulse")
    }
}
