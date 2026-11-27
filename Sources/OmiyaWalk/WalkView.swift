import AppKit
import QuartzCore

/// Omiya's round stage: he walks in the middle and the street scrolls behind him.
/// The circle has a dotted white rim with a black shadow, a status plate sits below it,
/// and a gear button sits at the upper right. There is no window frame.
@MainActor
public final class WalkView: NSView {
    /// Tuning values for the prototype. All lengths are in points.
    public struct Layout: Sendable {
        /// Size of one dot of the frame, rim, shadow and gear.
        public var dot: CGFloat = 2
        /// Circle diameter in dots.
        public var diameterDots = 170
        public var rimDots = 2
        public var shadowDots = 2
        public var margin: CGFloat = 8
        public var statusGap: CGFloat = 10
        public var statusWidth = 220
        /// Size of one sprite frame (the PNGs are drawn at 2x).
        public var spriteSize = CGSize(width: 120, height: 80)
        /// Feet line inside a sprite frame, measured from its top.
        public var spriteBaseline: CGFloat = 75
        /// Where the dog's feet are, as a fraction of the circle's height from its top.
        /// A little below the middle, so more of the street shows than of the road.
        public var feetLine: CGFloat = 0.64
        /// Points per pixel of the street picture.
        public var streetScale: CGFloat = 0.6
        /// Sidewalk line in the street picture, in its pixels from the top.
        public var streetSidewalk: CGFloat = 592
        public var walkSpeed: CGFloat = 22
        public var framesPerSecond: Double = 6
        public init() {}

        var diameter: CGFloat { CGFloat(diameterDots) * dot }
        var shadow: CGFloat { CGFloat(shadowDots) * dot }
    }

    /// What the plate under the circle shows. The prototype uses made-up values.
    public struct Status: Sendable {
        public var distance: String
        public var place: String
        public init(distance: String, place: String) {
            self.distance = distance
            self.place = place
        }
        public static let sample = Status(distance: "1,234.5 km", place: "大阪")
    }

    public var status = Status.sample { didSet { drawStatus() } }
    /// Shown when the gear is clicked.
    public var gearMenu: NSMenu? {
        get { gear.menuToShow }
        set { gear.menuToShow = newValue }
    }

    private let layout: Layout
    private let scene = CALayer()
    private let content = CALayer()
    private let street = CALayer()
    private let dog = CALayer()
    private let plate = CALayer()
    private let plateShadow = CALayer()
    private let gear = GearButton()
    private let walkFrames: [CGImage]
    private var streetLoopWidth: CGFloat = 0
    private var offset: CGFloat = 0
    private var elapsed: Double = 0
    private var lastTick: CFTimeInterval?
    private var timer: Timer?

    public static func size(for layout: Layout) -> CGSize {
        let plateHeight: CGFloat = 60
        return CGSize(width: layout.diameter + layout.margin * 2,
                      height: layout.margin + layout.diameter + layout.shadow + layout.statusGap
                          + plateHeight + layout.shadow + layout.margin)
    }

    public init(layout: Layout = Layout()) {
        self.layout = layout
        walkFrames = (0..<4).compactMap { WalkArt.image(named: "walk_\($0)") }
        super.init(frame: CGRect(origin: .zero, size: Self.size(for: layout)))
        wantsLayer = true
        setUpLayers()
        drawStatus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func pixelLayer(_ image: CGImage?, frame: CGRect) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.contents = image
        layer.contentsGravity = .resize
        layer.magnificationFilter = .nearest
        return layer
    }

    private func setUpLayers() {
        guard let root = layer else { return }
        root.backgroundColor = .clear
        scene.frame = bounds
        scene.isGeometryFlipped = true
        root.addSublayer(scene)

        let side = layout.diameter, m = layout.margin, n = layout.diameterDots
        let circle = CGRect(x: m, y: m, width: side, height: side)

        // Black shadow: the same disc, a few dots lower.
        let shade = PixelArt.RGBA(r: 0, g: 0, b: 0, a: 110)
        scene.addSublayer(pixelLayer(PixelArt.disc(n, color: shade), frame: circle.offsetBy(dx: 0, dy: layout.shadow)))

        content.frame = circle
        content.masksToBounds = true
        content.mask = pixelLayer(PixelArt.disc(n, color: PixelArt.black), frame: content.bounds)
        scene.addSublayer(content)

        let center = CGPoint(x: side / 2, y: side / 2)
        let feetY = side * layout.feetLine
        if let picture = WalkArt.image(named: "street"),
           let looped = WalkArt.mirroredLoop(of: picture, extraRows: picture.height) {
            let scale = layout.streetScale
            streetLoopWidth = CGFloat(picture.width) * 2 * scale
            street.contents = looped
            street.contentsGravity = .resize
            street.magnificationFilter = .nearest
            street.anchorPoint = .zero
            street.bounds = CGRect(x: 0, y: 0, width: CGFloat(looped.width) * scale, height: CGFloat(looped.height) * scale)
            street.position = CGPoint(x: 0, y: feetY - layout.streetSidewalk * scale)
            content.addSublayer(street)
        }

        dog.bounds = CGRect(origin: .zero, size: layout.spriteSize)
        dog.anchorPoint = .zero
        dog.position = CGPoint(x: center.x - layout.spriteSize.width / 2, y: feetY - layout.spriteBaseline)
        dog.contentsScale = 2
        dog.magnificationFilter = .nearest
        dog.contents = walkFrames.first
        content.addSublayer(dog)

        scene.addSublayer(pixelLayer(PixelArt.ring(n, thickness: layout.rimDots, color: PixelArt.white), frame: circle))

        plateShadow.backgroundColor = CGColor(gray: 0, alpha: 110.0 / 255)
        plateShadow.mask = pixelLayer(nil, frame: .zero)
        scene.addSublayer(plateShadow)
        plate.magnificationFilter = .nearest
        plate.contentsGravity = .resize
        scene.addSublayer(plate)

        // The gear is drawn in the scene; a clear view on top of it takes the clicks.
        let gearSide = 18 * layout.dot
        let gearFrame = CGRect(x: m + side - gearSide, y: m, width: gearSide, height: gearSide)
        scene.addSublayer(pixelLayer(PixelArt.gear(), frame: gearFrame))
        gear.frame = CGRect(x: gearFrame.minX, y: bounds.height - gearFrame.maxY, width: gearSide, height: gearSide)
        addSubview(gear)
    }

    private func drawStatus() {
        let border = Int(CGFloat(layout.rimDots) * layout.dot)
        guard let image = PixelArt.plate(lines: [("距離", status.distance), ("場所", status.place)],
                                         width: layout.statusWidth, border: border) else { return }
        let size = CGSize(width: image.width / 2, height: image.height / 2)
        let origin = CGPoint(x: (bounds.width - size.width) / 2,
                             y: layout.margin + layout.diameter + layout.shadow + layout.statusGap)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.frame = CGRect(origin: origin, size: size)
        plate.contents = image
        plateShadow.frame = plate.frame.offsetBy(dx: 0, dy: layout.shadow)
        plateShadow.mask?.frame = plateShadow.bounds
        plateShadow.mask?.contents = image
        CATransaction.commit()
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

/// The gear at the upper right. For now it only opens a small menu.
@MainActor
final class GearButton: NSView {
    var menuToShow: NSMenu?

    init() {
        super.init(frame: .zero)
        toolTip = "おみや君の設定"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        menuToShow?.popUp(positioning: nil, at: CGPoint(x: 0, y: -4), in: self)
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
