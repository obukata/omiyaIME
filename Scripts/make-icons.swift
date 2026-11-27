import AppKit

// 入力メニュー（メニューバー）用のアイコンを生成する。
// 角丸の四角から文字を抜いたテンプレート画像（16pt、1x/2x）を Bundle/Resources に書き出す。
// 使い方: swift Scripts/make-icons.swift

let resources = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Bundle/Resources", isDirectory: true)

func representation(label: String, scale: Int) -> NSBitmapImageRep {
    let points = 16
    let pixels = points * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: points, height: points)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context

    let bounds = NSRect(x: 0, y: 0, width: points, height: points)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3.5, yRadius: 3.5).fill()

    // Cut the label out of the filled square so the menu bar tints it like the system icons.
    context.compositingOperation = .destinationOut
    let font = NSFont.systemFont(ofSize: label.count > 1 ? 7.5 : 12, weight: .medium)
    let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: NSColor.black])
    let size = text.size()
    text.draw(at: NSPoint(x: (CGFloat(points) - size.width) / 2,
                          y: (CGFloat(points) - size.height) / 2 + font.descender / 2 + 0.25))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, label) in [("Hiragana", "あ"), ("Roman", "A")] {
    let reps = [1, 2].map { representation(label: label, scale: $0) }
    guard let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0) else {
        fatalError("TIFFを作れませんでした: \(name)")
    }
    try data.write(to: resources.appendingPathComponent("\(name).tiff"))
    print("\(name).tiff")
}
