import AppKit
import CoreText

// 入力メニュー（メニューバー）用のアイコンを生成する。素材は利用者・本プロジェクトの自作のみ。
//   Japanese.tiff: 柴犬（おみや）のドット絵 Bundle/Artwork/omiya-shiba.png から作る。
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

/// Draws Bundle/Artwork/omiya-shiba.png (the owner's AI-generated pixel art of Omiya), trimmed to its
/// visible pixels and fitted to the icon. Only its alpha matters: the icon is a template image.
func drawArtwork(_ context: NSGraphicsContext) {
    let url = resources.deletingLastPathComponent().appendingPathComponent("Artwork/omiya-shiba.png")
    guard let source = NSBitmapImageRep(data: (try? Data(contentsOf: url)) ?? Data()) else {
        fatalError("画像を読めませんでした: \(url.path)")
    }
    var minX = source.pixelsWide, minY = source.pixelsHigh, maxX = -1, maxY = -1
    for y in 0..<source.pixelsHigh {
        for x in 0..<source.pixelsWide where (source.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX else { fatalError("画像に表示部分がありません") }
    // NSBitmapImageRep rows run top-down; drawing rectangles run bottom-up.
    let crop = NSRect(x: minX, y: source.pixelsHigh - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    let width = points * 0.98
    let height = width * crop.height / crop.width
    context.imageInterpolation = .high
    let image = NSImage(size: NSSize(width: source.pixelsWide, height: source.pixelsHigh))
    image.addRepresentation(source)
    image.draw(in: NSRect(x: (points - width) / 2, y: (points - height) / 2, width: width, height: height),
               from: crop, operation: .sourceOver, fraction: 1)
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

let icons: [(String, (NSGraphicsContext) -> Void)] = [("Japanese", drawArtwork), ("Roman", drawLetterBadge("A"))]
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
