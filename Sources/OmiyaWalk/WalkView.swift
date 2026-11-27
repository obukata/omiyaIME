import AppKit
import OmiyaWalkCore
import QuartzCore

/// Omiya's round stage: he walks in the middle and the street scrolls behind him.
/// Normally only Omiya shows and clicks pass through to the windows below. Resting the
/// pointer on him for a moment shows the whole stage, which then takes clicks until the
/// pointer leaves it.
/// The circle has a dotted white rim with a black shadow, a status plate overlaps its lower part,
/// and a gear button sits on the rim at the upper right. There is no window frame.
@MainActor
public final class WalkView: NSView {
    /// Tuning values for the prototype. All lengths are in points.
    public struct Layout: Sendable {
        /// Size of one dot of the frame, rim, shadow and gear.
        public var dot: CGFloat = 2
        /// Circle diameter in dots.
        public var diameterDots = 140
        public var rimDots = 2
        public var shadowDots = 2
        public var margin: CGFloat = 8
        /// Gap between the bottom of the status plate and the bottom of the circle.
        public var statusInset: CGFloat = 8
        /// Where the gear sits on the rim, in degrees up from the right.
        public var gearAngle: CGFloat = 40
        public var statusWidth = 220
        /// Size of one sprite frame (the PNGs are drawn at 2x).
        public var spriteSize = CGSize(width: 120, height: 80)
        /// Feet line inside a sprite frame, measured from its top.
        public var spriteBaseline: CGFloat = 75
        /// Where the dog's feet are, as a fraction of the circle's height from its top.
        /// A little below the middle, so more of the street shows than of the road.
        public var feetLine: CGFloat = 0.62
        /// Points per pixel of the street picture.
        public var streetScale: CGFloat = 0.6
        /// Sidewalk line in the street picture, in its pixels from the top.
        public var streetSidewalk: CGFloat = 592
        public var walkSpeed: CGFloat = 22
        public var framesPerSecond: Double = 6
        /// How long the pointer rests on Omiya before the stage opens.
        public var revealDelay: Double = 1.5
        /// How long the pointer stays away before the stage closes again.
        public var hideDelay: Double = 0.4
        public var fadeInDuration: Double = 0.3
        public var fadeOutDuration: Double = 0.2
        /// The small distance under Omiya while the stage is closed.
        public var footLabelSize: CGFloat = 10
        public var footLabelGap: CGFloat = 2
        public init() {}

        var diameter: CGFloat { CGFloat(diameterDots) * dot }
        var shadow: CGFloat { CGFloat(shadowDots) * dot }
    }

    /// What the plate under the circle shows.
    public struct Status: Sendable {
        public var distance: String
        public var place: String
        public init(distance: String, place: String) {
            self.distance = distance
            self.place = place
        }
        /// The place is fixed for now; places that change with distance are still to be decided.
        public static func walked(_ progress: WalkProgress) -> Status {
            Status(distance: progress.distanceText, place: "大阪")
        }
    }

    public var status = Status.walked(WalkProgress()) { didSet { drawStatus() } }
    public private(set) var isExpanded = false
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
    /// The distance under Omiya's feet while the stage is closed.
    private let footLabel = CALayer()
    private var feetPoint = CGPoint.zero
    private let gear = GearButton()
    /// Parts shown only while the stage is open.
    private let below = CALayer()
    private let above = CALayer()
    private var circleFrame = CGRect.zero
    private var gearFrame = CGRect.zero
    private var hoverStart: CFTimeInterval?
    private var leaveStart: CFTimeInterval?
    private let progressFile: WalkProgressFile?
    private var progressDate: Date?
    private var lastProgressCheck: CFTimeInterval = 0
    private let walkFrames: [CGImage]
    private var streetLoopWidth: CGFloat = 0
    private var offset: CGFloat = 0
    private var elapsed: Double = 0
    private var lastTick: CFTimeInterval?
    private var timer: Timer?

    public static func size(for layout: Layout) -> CGSize {
        CGSize(width: layout.diameter + layout.margin * 2,
               height: layout.margin + layout.diameter + layout.shadow + layout.margin)
    }

    /// `progressFile` is read about once a second for the distance; nil shows 0.
    public init(layout: Layout = Layout(), progressFile: WalkProgressFile? = WalkProgressFile()) {
        self.layout = layout
        self.progressFile = progressFile
        walkFrames = (0..<4).compactMap { WalkArt.image(named: "walk_\($0)") }
        super.init(frame: CGRect(origin: .zero, size: Self.size(for: layout)))
        wantsLayer = true
        setUpLayers()
        // Property observers do not run inside init, so draw the plate here.
        if let progressFile { status = .walked(progressFile.load()) }
        drawStatus()
        setExpanded(false, animated: false)
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
        circleFrame = circle
        for group in [below, above] {
            group.frame = scene.bounds
        }
        scene.addSublayer(below)

        // Black shadow: the same disc, a few dots lower.
        let shade = PixelArt.RGBA(r: 0, g: 0, b: 0, a: 110)
        below.addSublayer(pixelLayer(PixelArt.disc(n, color: shade), frame: circle.offsetBy(dx: 0, dy: layout.shadow)))

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
        feetPoint = CGPoint(x: m + center.x, y: m + feetY)
        footLabel.magnificationFilter = .nearest
        footLabel.contentsScale = 2
        scene.addSublayer(footLabel)

        scene.addSublayer(above)
        above.addSublayer(pixelLayer(PixelArt.ring(n, thickness: layout.rimDots, color: PixelArt.white), frame: circle))

        plateShadow.backgroundColor = CGColor(gray: 0, alpha: 110.0 / 255)
        plateShadow.mask = pixelLayer(nil, frame: .zero)
        above.addSublayer(plateShadow)
        plate.magnificationFilter = .nearest
        plate.contentsGravity = .resize
        above.addSublayer(plate)

        // The gear is drawn in the scene; a clear view on top of it takes the clicks.
        let gearSide = 18 * layout.dot
        let angle = layout.gearAngle * .pi / 180
        let gearCenter = CGPoint(x: m + side / 2 + side / 2 * cos(angle), y: m + side / 2 - side / 2 * sin(angle))
        let gearFrame = CGRect(x: (gearCenter.x - gearSide / 2).rounded(), y: (gearCenter.y - gearSide / 2).rounded(),
                               width: gearSide, height: gearSide)
        self.gearFrame = gearFrame
        above.addSublayer(pixelLayer(PixelArt.gear(), frame: gearFrame))
        gear.frame = CGRect(x: gearFrame.minX, y: bounds.height - gearFrame.maxY, width: gearSide, height: gearSide)
        addSubview(gear)
    }

    private func drawStatus() {
        let border = Int(CGFloat(layout.rimDots) * layout.dot)
        guard let image = PixelArt.plate(lines: [("距離", status.distance), ("場所", status.place)],
                                         width: layout.statusWidth, border: border) else { return }
        let size = CGSize(width: image.width / 2, height: image.height / 2)
        let origin = CGPoint(x: (bounds.width - size.width) / 2,
                             y: layout.margin + layout.diameter - layout.statusInset - size.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        plate.frame = CGRect(origin: origin, size: size)
        plate.contents = image
        plateShadow.frame = plate.frame.offsetBy(dx: 0, dy: layout.shadow)
        plateShadow.mask?.frame = plateShadow.bounds
        plateShadow.mask?.contents = image
        if let label = PixelArt.outlinedLabel(status.distance, size: layout.footLabelSize) {
            footLabel.contents = label.image
            footLabel.frame = CGRect(x: (feetPoint.x - label.points.width / 2).rounded(),
                                     y: feetPoint.y + layout.footLabelGap,
                                     width: label.points.width, height: label.points.height)
        }
        CATransaction.commit()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        timer?.invalidate()
        guard window != nil else { return }
        window?.ignoresMouseEvents = !isExpanded
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
        followPointer(now: now)
        if now - lastProgressCheck >= 1 {
            lastProgressCheck = now
            reloadProgress()
        }
    }

    /// Opens or closes the stage. Closed, only Omiya shows and clicks pass through.
    public func setExpanded(_ expanded: Bool, animated: Bool) {
        isExpanded = expanded
        window?.ignoresMouseEvents = !expanded
        gear.isHidden = !expanded
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? (expanded ? layout.fadeInDuration : layout.fadeOutDuration) : 0)
        CATransaction.setDisableActions(!animated)
        for part in [below, street, above] {
            part.opacity = expanded ? 1 : 0
        }
        footLabel.opacity = expanded ? 0 : 1
        CATransaction.commit()
    }

    /// Where the pointer is, in scene coordinates (origin at the top left), or nil.
    private func pointerInScene() -> CGPoint? {
        guard let window else { return nil }
        let inView = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        return CGPoint(x: inView.x, y: bounds.height - inView.y)
    }

    private func followPointer(now: CFTimeInterval) {
        guard let point = pointerInScene() else { return }
        if isExpanded {
            let r = circleFrame.width / 2
            let dx = point.x - circleFrame.midX, dy = point.y - circleFrame.midY
            let inside = dx * dx + dy * dy <= r * r || plate.frame.contains(point)
                || gearFrame.insetBy(dx: -4, dy: -4).contains(point) || gear.isShowingMenu
            if inside {
                leaveStart = nil
            } else if let start = leaveStart {
                if now - start >= layout.hideDelay { leaveStart = nil; setExpanded(false, animated: true) }
            } else {
                leaveStart = now
            }
        } else {
            // Omiya's own body, not the whole sprite frame.
            let body = dog.frame.offsetBy(dx: content.frame.minX, dy: content.frame.minY).insetBy(dx: 18, dy: 12)
            if body.contains(point) {
                if let start = hoverStart {
                    if now - start >= layout.revealDelay { hoverStart = nil; setExpanded(true, animated: true) }
                } else {
                    hoverStart = now
                }
            } else {
                hoverStart = nil
            }
        }
    }

    private func reloadProgress() {
        guard let progressFile else { return }
        let date = progressFile.modificationDate
        guard date != progressDate else { return }
        progressDate = date
        status = .walked(progressFile.load())
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
    private(set) var isShowingMenu = false

    init() {
        super.init(frame: .zero)
        toolTip = "おみや君の設定"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        isShowingMenu = true
        menuToShow?.popUp(positioning: nil, at: CGPoint(x: 0, y: -4), in: self)
        isShowingMenu = false
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
