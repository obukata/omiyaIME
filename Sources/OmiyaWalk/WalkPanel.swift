import AppKit

/// A frameless, transparent panel that shows `WalkView` on the desktop like a desktop pet.
/// It never becomes the key window, so it does not take focus from the app being typed in.
@MainActor
public final class WalkPanel: NSPanel {
    public init(layout: WalkView.Layout = WalkView.Layout()) {
        super.init(contentRect: CGRect(origin: .zero, size: WalkView.size(for: layout)),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        contentView = WalkView(layout: layout)
    }

    public var walkView: WalkView? { contentView as? WalkView }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }

    /// Places the panel at the lower right of the main screen.
    public func placeAtLowerRight(margin: CGFloat = 24) {
        guard let area = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(CGPoint(x: area.maxX - frame.width - margin, y: area.minY + margin))
    }
}
