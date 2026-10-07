import AppKit
import QuartzCore

/// A frosted curtain over every screen. Unlike the other apps' overlays, this one
/// CATCHES mouse and keyboard, so someone can't blindly type underneath it.
/// (It can't stop every input path — true protection is the "Lock the Mac" mode —
/// but it blocks the normal mouse and key events that reach the windows below.)
@MainActor
final class CurtainOverlay {
    private var windows: [NSWindow] = []
    private var visible = false

    func show(message: String) {
        rebuild(message: message)
        visible = true
        NSApp.activate(ignoringOtherApps: true)
        for window in windows {
            window.makeKeyAndOrderFront(nil)
            animate(window, to: 1)
        }
        // Grab keyboard focus so key presses land on the curtain, not the app underneath
        windows.first?.makeFirstResponder(windows.first?.contentView)
    }

    func hide() {
        guard visible else { return }
        visible = false
        for window in windows {
            animate(window, to: 0) { window.orderOut(nil) }
        }
    }

    private func rebuild(message: String) {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { screen in
            let window = CurtainWindow(contentRect: screen.frame, styleMask: .borderless,
                                       backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = false        // catch clicks
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.alphaValue = 0
            window.contentView = CurtainView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                             message: message)
            return window
        }
    }

    private func animate(_ window: NSWindow, to alpha: CGFloat, then: (() -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.4
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = alpha
        }, completionHandler: then)
    }
}

/// A window that is allowed to become key, so it can swallow keystrokes
final class CurtainWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class CurtainView: NSView {
    private let message: String

    init(frame: NSRect, message: String) {
        self.message = message
        super.init(frame: frame)
        wantsLayer = true

        // Frosted glass: blur whatever is behind
        let blur = NSVisualEffectView(frame: bounds)
        blur.autoresizingMask = [.width, .height]
        blur.material = .fullScreenUI
        blur.blendingMode = .behindWindow
        blur.state = .active
        addSubview(blur)

        // A slightly stronger, cooler tint so it clearly reads as "covered", not just blurry
        let tint = NSView(frame: bounds)
        tint.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        let gradient = CAGradientLayer()
        gradient.type = .radial
        gradient.frame = bounds
        gradient.colors = [
            NSColor(calibratedWhite: 1, alpha: 0.10).cgColor,
            NSColor(calibratedRed: 0.82, green: 0.88, blue: 1, alpha: 0.45).cgColor
        ]
        gradient.locations = [0, 1]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 1.1, y: 1.1)
        tint.layer?.addSublayer(gradient)
        blur.addSubview(tint)

        // Lock glyph + message in the center
        let lock = NSTextField(labelWithString: "􀎡")   // SF Symbol "lock.fill" as text fallback
        lock.font = .systemFont(ofSize: 64, weight: .regular)
        lock.textColor = NSColor.labelColor.withAlphaComponent(0.7)

        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 60, weight: .regular))
        image.contentTintColor = NSColor.labelColor.withAlphaComponent(0.65)
        image.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: message)
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        title.textColor = NSColor.labelColor.withAlphaComponent(0.8)
        title.alignment = .center
        title.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: "Sit back in front of the camera to unlock")
        hint.font = .systemFont(ofSize: 15, weight: .regular)
        hint.textColor = NSColor.secondaryLabelColor
        hint.alignment = .center
        hint.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [image, title, hint])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        _ = lock   // keep the fallback glyph object alive without using it
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Swallow all input so nothing reaches the apps underneath
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func keyDown(with event: NSEvent) {}
    override func keyUp(with event: NSEvent) {}
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
