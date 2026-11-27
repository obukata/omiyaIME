import AppKit
import CoreText

// 入力メニュー（メニューバー）用のアイコンを生成する自作素材。外部の画像・記号素材は使わない。
//   Japanese.tiff: 柴犬の顔（おみや）。白い口元（裏白）は半透明で表す。
//   Roman.tiff:    角丸の四角から「A」を抜いた形。
// どちらも16ptのテンプレート画像（1x/2x）で、メニューバーの明暗に合わせてmacOSが色を付ける。
// 使い方: swift Scripts/make-icons.swift [プレビューPNGの出力先フォルダ]

let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Bundle/Resources", isDirectory: true)
let previewDirectory = CommandLine.arguments.dropFirst().first.map { URL(fileURLWithPath: $0, isDirectory: true) }

let points: CGFloat = 16

func render(scale: Int, _ draw: (NSGraphicsContext) -> Void) -> NSBitmapImageRep {
    let pixels = Int(points) * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: points, height: points)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    draw(context)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func oval(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: x - width / 2, y: y - height / 2, width: width, height: height))
}

func triangle(_ points: [NSPoint]) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    path.lineJoinStyle = .round
    return path
}

/// Shiba face, drawn on a 16pt grid (origin bottom-left).
func drawShiba(_ context: NSGraphicsContext) {
    let ink = NSColor.black
    ink.setFill()
    ink.setStroke()

    // Upright triangular ears.
    for side: CGFloat in [-1, 1] {
        let ear = triangle([NSPoint(x: 8 + side * 5.6, y: 8.2),
                            NSPoint(x: 8 + side * 4.9, y: 14.6),
                            NSPoint(x: 8 + side * 1.6, y: 11.6)])
        ear.lineWidth = 1
        ear.fill()
        ear.stroke()
    }
    // Head: slightly wider than tall, with full cheeks.
    oval(8, 7.3, 12.6, 10.4).fill()

    // Everything below is cut out of, or faded from, the solid head.
    context.compositingOperation = .destinationOut
    // Inner ears.
    NSColor.black.withAlphaComponent(0.55).setFill()
    for side: CGFloat in [-1, 1] {
        triangle([NSPoint(x: 8 + side * 4.6, y: 10.2),
                  NSPoint(x: 8 + side * 4.5, y: 13.1),
                  NSPoint(x: 8 + side * 2.6, y: 11.3)]).fill()
    }
    // White muzzle and cheeks (urajiro).
    NSColor.black.withAlphaComponent(0.55).setFill()
    oval(8, 4.6, 8.4, 5.4).fill()
    // Eyes and eyebrow dots.
    NSColor.black.setFill()
    oval(5.3, 7.9, 1.6, 1.8).fill()
    oval(10.7, 7.9, 1.6, 1.8).fill()
    oval(5.4, 9.9, 1.1, 0.8).fill()
    oval(10.6, 9.9, 1.1, 0.8).fill()

    // Nose and mouth sit on the faded muzzle at full strength.
    context.compositingOperation = .sourceOver
    NSColor.black.setFill()
    oval(8, 5.6, 2.2, 1.6).fill()
    let mouth = NSBezierPath()
    mouth.move(to: NSPoint(x: 8, y: 5.0))
    mouth.line(to: NSPoint(x: 8, y: 4.1))
    mouth.move(to: NSPoint(x: 6.6, y: 3.7))
    mouth.curve(to: NSPoint(x: 8, y: 4.1), controlPoint1: NSPoint(x: 7.1, y: 3.3), controlPoint2: NSPoint(x: 7.7, y: 3.5))
    mouth.curve(to: NSPoint(x: 9.4, y: 3.7), controlPoint1: NSPoint(x: 8.3, y: 3.5), controlPoint2: NSPoint(x: 8.9, y: 3.3))
    mouth.lineWidth = 0.7
    mouth.lineCapStyle = .round
    mouth.stroke()
}

/// Rounded badge with the letter cut out, centred on the glyph's own outline.
func drawLetterBadge(_ letter: String) -> (NSGraphicsContext) -> Void {
    { context in
        let bounds = NSRect(x: 0, y: 0, width: points, height: points)
        NSColor.black.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5).fill()

        let font = NSFont.systemFont(ofSize: 11, weight: .medium) as CTFont
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: letter, attributes: [.font: font]))
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let cg = context.cgContext
        cg.setBlendMode(.destinationOut)
        cg.textPosition = CGPoint(x: (points - glyphBounds.width) / 2 - glyphBounds.minX,
                                  y: (points - glyphBounds.height) / 2 - glyphBounds.minY)
        CTLineDraw(line, cg)
    }
}

let icons: [(String, (NSGraphicsContext) -> Void)] = [("Japanese", drawShiba), ("Roman", drawLetterBadge("A"))]
for (name, draw) in icons {
    let reps = [1, 2].map { render(scale: $0, draw) }
    guard let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0) else {
        fatalError("TIFFを作れませんでした: \(name)")
    }
    try data.write(to: resources.appendingPathComponent("\(name).tiff"))
    if let previewDirectory {
        let preview = render(scale: 8, draw)
        try preview.representation(using: .png, properties: [:])!
            .write(to: previewDirectory.appendingPathComponent("\(name).png"))
    }
    print("\(name).tiff")
}
