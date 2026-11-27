import AppKit
import CoreText

/// Small bitmaps drawn one dot at a time, shown enlarged without smoothing so the edges stay square.
enum PixelArt {
    struct RGBA { var r: UInt8, g: UInt8, b: UInt8, a: UInt8 }
    static let white = RGBA(r: 255, g: 255, b: 255, a: 255)
    static let black = RGBA(r: 0, g: 0, b: 0, a: 255)

    /// Makes a `width`×`height` bitmap; `color` returns nil for a transparent dot.
    static func image(width: Int, height: Int, color: (Int, Int) -> RGBA?) -> CGImage? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                guard let c = color(x, y) else { continue }
                let i = (y * width + x) * 4
                let alpha = Int(c.a)
                // Premultiplied alpha.
                bytes[i] = UInt8(Int(c.r) * alpha / 255)
                bytes[i + 1] = UInt8(Int(c.g) * alpha / 255)
                bytes[i + 2] = UInt8(Int(c.b) * alpha / 255)
                bytes[i + 3] = c.a
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Distance of a dot's centre from the centre of an `n`×`n` grid.
    static func distance(_ x: Int, _ y: Int, in n: Int) -> Double {
        let c = Double(n) / 2
        return ((Double(x) + 0.5 - c) * (Double(x) + 0.5 - c) + (Double(y) + 0.5 - c) * (Double(y) + 0.5 - c)).squareRoot()
    }

    /// A filled disc that touches the edges of an `n`×`n` grid.
    static func disc(_ n: Int, color: RGBA) -> CGImage? {
        image(width: n, height: n) { x, y in distance(x, y, in: n) <= Double(n) / 2 - 0.9 ? color : nil }
    }

    /// The outermost `thickness` dots of `disc(n)`.
    static func ring(_ n: Int, thickness: Int, color: RGBA) -> CGImage? {
        let r = Double(n) / 2 - 0.9
        return image(width: n, height: n) { x, y in
            let d = distance(x, y, in: n)
            return d <= r && d > r - Double(thickness) ? color : nil
        }
    }

    /// An 18×18 gear: white teeth and body, black outline, hole in the middle.
    static func gear() -> CGImage? {
        let n = 18
        func inside(_ x: Int, _ y: Int) -> Bool {
            guard (0..<n).contains(x), (0..<n).contains(y) else { return false }
            let dx = Double(x) + 0.5 - 9, dy = Double(y) + 0.5 - 9
            let d = (dx * dx + dy * dy).squareRoot()
            if d <= 2.6 { return false }
            let tooth = cos(6 * atan2(dy, dx)) > 0.1
            return d <= (tooth ? 7.8 : 5.8)
        }
        return image(width: n, height: n) { x, y in
            if inside(x, y) { return white }
            let neighbours = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            return neighbours.contains(where: { inside($0.0, $0.1) }) ? black : nil
        }
    }

    /// Draws a picture from rows of letters, one letter per dot; '.' is transparent.
    /// Dots next to the shape that are still transparent become `outline`, if given.
    static func fromRows(_ rows: [String], palette: [Character: RGBA], outline: RGBA? = nil) -> CGImage? {
        let grid = rows.map(Array.init)
        let height = grid.count, width = grid.map(\.count).max() ?? 0
        func color(_ x: Int, _ y: Int) -> RGBA? {
            guard (0..<height).contains(y), (0..<width).contains(x), x < grid[y].count else { return nil }
            return palette[grid[y][x]]
        }
        return image(width: width, height: height) { x, y in
            if let c = color(x, y) { return c }
            guard let outline else { return nil }
            let around = [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
            return around.contains(where: { color($0.0, $0.1) != nil }) ? outline : nil
        }
    }

    /// An 18×18 treasure chest with a white edge, to match the gear.
    static func treasureChest() -> CGImage? {
        fromRows([
            "..................",
            "..................",
            "...KKKKKKKKKKKK...",
            "..KBBBBBBBBBBBBK..",
            ".KBDDDDDDDDDDDDBK.",
            ".KBBBBBBBBBBBBBBK.",
            ".KGGGGGGYYGGGGGGK.",
            ".KKKKKKKYYKKKKKKK.",
            ".KBBBBBKGGKBBBBBK.",
            ".KBDDDDKYYKDDDDBK.",
            ".KBBBBBBKKBBBBBBK.",
            ".KGGGGGGGGGGGGGGK.",
            ".KBBBBBBBBBBBBBBK.",
            ".KBDDDDDDDDDDDDBK.",
            ".KGGGGGGGGGGGGGGK.",
            "..KKKKKKKKKKKKKK..",
            "..................",
            ".................."
        ], palette: [
            "K": RGBA(r: 40, g: 24, b: 16, a: 255),
            "B": RGBA(r: 168, g: 104, b: 56, a: 255),
            "D": RGBA(r: 120, g: 70, b: 36, a: 255),
            "G": RGBA(r: 232, g: 176, b: 48, a: 255),
            "Y": RGBA(r: 255, g: 232, b: 128, a: 255)
        ], outline: white)
    }

    /// A 5×7 question mark for treasures not found yet.
    static func questionMark(color: RGBA) -> CGImage? {
        fromRows([
            ".###.",
            "#...#",
            "....#",
            "...#.",
            "..#..",
            ".....",
            "..#.."
        ], palette: ["#": color])
    }

    /// A status plate drawn at 2x: dark fill and a white border with cut corners.
    /// Sizes are in points; the text is drawn without smoothing.
    static func plate(lines: [(label: String, value: String)], width points: Int, border borderPoints: Int) -> CGImage? {
        let scale = 2
        let width = points * scale, border = borderPoints * scale
        let lineHeight = 20 * scale, padding = 10 * scale
        let height = padding * 2 + lineHeight * lines.count
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)
        context.setShouldSmoothFonts(false)
        context.interpolationQuality = .none
        let w = CGFloat(width), h = CGFloat(height), b = CGFloat(border)

        // Border: a rectangle with one border-width cut from each corner.
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: b, y: 0, width: w - 2 * b, height: h))
        context.fill(CGRect(x: 0, y: b, width: w, height: h - 2 * b))
        // Fill, cut the same way.
        context.setFillColor(CGColor(srgbRed: 0.13, green: 0.15, blue: 0.24, alpha: 0.92))
        context.clear(CGRect(x: b, y: b, width: w - 2 * b, height: h - 2 * b))
        context.fill(CGRect(x: 2 * b, y: b, width: w - 4 * b, height: h - 2 * b))
        context.fill(CGRect(x: b, y: 2 * b, width: w - 2 * b, height: h - 4 * b))

        let font = CTFontCreateWithName("HiraginoSans-W6" as CFString, CGFloat(13 * scale), nil)
        let s = CGFloat(scale)
        for (index, line) in lines.enumerated() {
            let baseline = h - CGFloat(padding + lineHeight * index) - 15 * s
            draw(line.label, font: font, color: NSColor(white: 1, alpha: 0.6), at: CGPoint(x: CGFloat(padding) + 4 * s, y: baseline), in: context)
            draw(line.value, font: font, color: .white, at: CGPoint(x: CGFloat(padding) + 52 * s, y: baseline), in: context)
        }
        return context.makeImage()
    }

    /// A white silhouette of `image` grown by `pixels` on every side, to draw behind it as an outline.
    static func outline(of image: CGImage, pixels: Int) -> CGImage? {
        let width = image.width, height = image.height
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .none
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        for dx in -pixels...pixels {
            for dy in -pixels...pixels {
                context.draw(image, in: rect.offsetBy(dx: CGFloat(dx), dy: CGFloat(dy)))
            }
        }
        // Keep the shape, make it solid white.
        context.setBlendMode(.sourceIn)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(rect)
        return context.makeImage()
    }

    /// Small white text with a one-point black outline, drawn at 2x without smoothing,
    /// so it stays readable on any desktop picture. Returns the image and its size in points.
    static func outlinedLabel(_ text: String, size: CGFloat) -> (image: CGImage, points: CGSize)? {
        let scale: CGFloat = 2, outline: CGFloat = 1
        let font = CTFontCreateWithName("HiraginoSans-W6" as CFString, size * scale, nil)
        let measured = CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font
            ])), nil, nil, nil)
        let pad = outline * scale
        let width = Int((CGFloat(measured) + pad * 2).rounded(.up))
        let height = Int((size * 1.4 * scale + pad * 2).rounded(.up))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setShouldAntialias(false)
        context.setAllowsAntialiasing(false)
        let origin = CGPoint(x: pad, y: pad + size * 0.35 * scale)
        let step = outline * scale
        for dx in [-step, 0, step] {
            for dy in [-step, 0, step] where dx != 0 || dy != 0 {
                draw(text, font: font, color: .black, at: CGPoint(x: origin.x + dx, y: origin.y + dy), in: context)
            }
        }
        draw(text, font: font, color: .white, at: origin, in: context)
        guard let image = context.makeImage() else { return nil }
        return (image, CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale))
    }

    private static func draw(_ text: String, font: CTFont, color: NSColor, at point: CGPoint, in context: CGContext) {
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor
        ])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = point
        CTLineDraw(line, context)
    }
}
