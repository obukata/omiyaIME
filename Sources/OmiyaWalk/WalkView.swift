import AppKit
import QuartzCore

/// A round view: Omiya walks in the middle and the street scrolls behind him.
/// The edge of the circle fades out, so there is no visible window frame.
@MainActor
public final class WalkView: NSView {
    /// Tuning values for the prototype. All lengths are in points.
    public struct Layout: Sendable {
        public var diameter: CGFloat = 200
        /// Fraction of the radius that stays fully visible before the fade starts.
        public var solidRadius: CGFloat = 0.45
        /// Size of one sprite frame (the PNGs are drawn at 2x).
        public var spriteSize = CGSize(width: 120, height: 80)
        /// Feet line inside a sprite frame, measured from its top.
        public var spriteBaseline: CGFloat = 75
        /// Vertical centre of the dog inside a sprite frame, measured from its top.
        public var spriteBodyCenter: CGFloat = 45
        /// Points per pixel of the street picture.
        public var streetScale: CGFloat = 0.5
        /// Sidewalk line in the street picture, in its pixels from the top.
        public var streetSidewalk: CGFloat = 592
        public var walkSpeed: CGFloat = 22
        public var framesPerSecond: Double = 6
        public init() {}
    }

    private let layout: Layout
    private let content = CALayer()
    private let street = CALayer()
    private let dog = CALayer()
    private let walkFrames: [CGImage]
    private var streetLoopWidth: CGFloat = 0
    private var offset: CGFloat = 0
    private var elapsed: Double = 0
    private var lastTick: CFTimeInterval?
    private var timer: Timer?

    public init(layout: Layout = Layout()) {
        self.layout = layout
        walkFrames = (0..<4).compactMap { WalkArt.image(named: "walk_\($0)") }
        super.init(frame: CGRect(x: 0, y: 0, width: layout.diameter, height: layout.diameter))
        wantsLayer = true
        setUpLayers()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setUpLayers() {
        guard let root = layer else { return }
        let side = layout.diameter
        root.backgroundColor = .clear
        content.frame = bounds
        content.isGeometryFlipped = true
        content.masksToBounds = true
        root.addSublayer(content)

        // Soft round mask: opaque in the middle, clear at the edge.
        let mask = CAGradientLayer()
        mask.type = .radial
        mask.frame = bounds
        mask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        mask.locations = [0, NSNumber(value: Double(layout.solidRadius)), 1]
        mask.startPoint = CGPoint(x: 0.5, y: 0.5)
        mask.endPoint = CGPoint(x: 1, y: 1)
        content.mask = mask

        let center = CGPoint(x: side / 2, y: side / 2)
        let feetY = center.y + (layout.spriteBaseline - layout.spriteBodyCenter)

        if let picture = WalkArt.image(named: "street"), let looped = WalkArt.mirroredLoop(of: picture, extraRows: picture.height) {
            let scale = layout.streetScale
            let height = CGFloat(looped.height) * scale
            streetLoopWidth = CGFloat(picture.width) * 2 * scale
            street.contents = looped
            street.contentsGravity = .resize
            street.magnificationFilter = .nearest
            street.anchorPoint = .zero
            street.bounds = CGRect(x: 0, y: 0, width: CGFloat(looped.width) * scale, height: height)
            street.position = CGPoint(x: 0, y: feetY - layout.streetSidewalk * scale)
            content.addSublayer(street)
        }

        dog.bounds = CGRect(origin: .zero, size: layout.spriteSize)
        dog.anchorPoint = .zero
        dog.position = CGPoint(x: center.x - layout.spriteSize.width / 2,
                               y: center.y - layout.spriteBodyCenter)
        dog.contentsScale = 2
        dog.magnificationFilter = .nearest
        dog.contents = walkFrames.first
        content.addSublayer(dog)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Renders the current picture to a PNG at 2x, for checking the look without a screen capture.
    public func snapshotPNG() -> Data? {
        guard let layer, let context = CGContext(
            data: nil, width: Int(bounds.width * 2), height: Int(bounds.height * 2), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: 2, y: 2)
        layer.render(in: context)
        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let delta = lastTick.map { now - $0 } ?? 0
        lastTick = now
        advance(by: delta)
    }

    /// Moves the walk forward by `delta` seconds.
    public func advance(by delta: Double) {
        elapsed += delta
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if streetLoopWidth > 0 {
            offset = (offset + layout.walkSpeed * delta).truncatingRemainder(dividingBy: streetLoopWidth)
            street.position.x = -offset
        }
        if !walkFrames.isEmpty {
            dog.contents = walkFrames[Int(elapsed * layout.framesPerSecond) % walkFrames.count]
        }
        CATransaction.commit()
    }
}

/// Loads the bundled draft art.
enum WalkArt {
    static func image(named name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Picture, its mirror, then the picture again. Scrolling by two widths and wrapping
    /// gives an endless street without a seam, even though the picture does not tile.
    /// The bottom row (the road) is stretched by `extraRows` so the circle never shows past it.
    static func mirroredLoop(of picture: CGImage, extraRows: Int = 0) -> CGImage? {
        let width = picture.width, height = picture.height
        guard let context = CGContext(data: nil, width: width * 3, height: height + extraRows, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let w = CGFloat(width), h = CGFloat(height), pad = CGFloat(extraRows)
        if extraRows > 0, let road = picture.cropping(to: CGRect(x: 0, y: height - 1, width: width, height: 1)) {
            for index in 0..<3 {
                context.draw(road, in: CGRect(x: CGFloat(index) * w, y: 0, width: w, height: pad))
            }
        }
        context.draw(picture, in: CGRect(x: 0, y: pad, width: w, height: h))
        context.saveGState()
        context.translateBy(x: 3 * w, y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(picture, in: CGRect(x: w, y: pad, width: w, height: h))
        context.restoreGState()
        context.draw(picture, in: CGRect(x: 2 * w, y: pad, width: w, height: h))
        return context.makeImage()
    }
}
