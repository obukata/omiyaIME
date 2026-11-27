import AppKit
import OmiyaWalkCore

/// The treasure list opened from the chest icon. Found treasures show their picture,
/// the rest a question mark.
@MainActor
public final class TreasureWindowController {
    public static let shared = TreasureWindowController()

    private var window: NSWindow?
    private let file: WalkProgressFile

    public init(file: WalkProgressFile = WalkProgressFile()) {
        self.file = file
    }

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        // Read the latest finds every time it opens.
        window.contentView = TreasureGridView(found: file.load().found)
        if !window.isVisible { window.center() }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let view = TreasureGridView(found: [:])
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: view.frame.size),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "おみや君のたからもの"
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = view
        return window
    }

    /// For checking the look without showing the window.
    public static func snapshotPNG(found: [String: Int]) -> Data? {
        let view = TreasureGridView(found: found)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

/// A dark grid of treasure slots, like an achievements screen.
@MainActor
final class TreasureGridView: NSView {
    private let treasures = TreasureCatalog.all
    private let found: [String: Int]
    private var images: [String: CGImage] = [:]
    private let columns = 8
    private let cell: CGFloat = 48
    private let padding: CGFloat = 20
    private let header: CGFloat = 40
    private let mark = PixelArt.questionMark(color: PixelArt.RGBA(r: 120, g: 32, b: 32, a: 255))
    private let markShadow = PixelArt.questionMark(color: PixelArt.RGBA(r: 20, g: 6, b: 6, a: 255))

    init(found: [String: Int]) {
        self.found = found
        let rows = (treasures.count + 7) / 8
        super.init(frame: CGRect(x: 0, y: 0, width: padding * 2 + cell * 8,
                                 height: header + padding + cell * CGFloat(rows) + padding))
        for (index, treasure) in treasures.enumerated() {
            let isFound = (found[treasure.id] ?? 0) > 0
            if isFound { images[treasure.id] = WalkArt.image(named: treasure.id) }
            let tip = isFound ? treasure.name : "？？？（まだ見つけていない）"
            addToolTip(cellRect(index), owner: tip as NSString, userData: nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    private func cellRect(_ index: Int) -> CGRect {
        CGRect(x: padding + CGFloat(index % columns) * cell, y: header + padding + CGFloat(index / columns) * cell,
               width: cell, height: cell)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1),
                   ending: NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1))?
            .draw(in: bounds, angle: 90)

        let foundKinds = treasures.filter { (found[$0.id] ?? 0) > 0 }.count
        let title = NSAttributedString(string: "見つけた数  \(foundKinds) / \(treasures.count)", attributes: [
            .font: NSFont(name: "HiraginoSans-W6", size: 13) ?? .boldSystemFont(ofSize: 13),
            .foregroundColor: NSColor(white: 1, alpha: 0.75)
        ])
        title.draw(at: CGPoint(x: padding, y: padding))

        context.interpolationQuality = .none
        let dot: CGFloat = 4
        let size = CGSize(width: 5 * dot, height: 7 * dot)
        for (index, treasure) in treasures.enumerated() {
            let rect = cellRect(index)
            if let image = images[treasure.id] {
                let side: CGFloat = 32
                context.saveGState()
                context.translateBy(x: rect.midX - side / 2, y: rect.midY + side / 2)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
                context.restoreGState()
                if let count = found[treasure.id], count > 1 {
                    NSAttributedString(string: "×\(count)", attributes: [
                        .font: NSFont.boldSystemFont(ofSize: 9), .foregroundColor: NSColor(white: 1, alpha: 0.7)
                    ]).draw(at: CGPoint(x: rect.maxX - 16, y: rect.maxY - 14))
                }
                continue
            }
            let origin = CGPoint(x: (rect.midX - size.width / 2).rounded(), y: (rect.midY - size.height / 2).rounded())
            // Flip each image back upright inside the flipped view.
            for (image, offset) in [(markShadow, CGFloat(2)), (mark, CGFloat(0))] {
                guard let image else { continue }
                context.saveGState()
                context.translateBy(x: origin.x + offset, y: origin.y + offset + size.height)
                context.scaleBy(x: 1, y: -1)
                context.draw(image, in: CGRect(origin: .zero, size: size))
                context.restoreGState()
            }
        }
    }
}
