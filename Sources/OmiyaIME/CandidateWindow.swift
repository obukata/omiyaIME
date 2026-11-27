import AppKit

/// Candidate list shown below the focused segment.
/// IMKCandidates did not keep its highlight in sync with the selected candidate
/// (2026-11-27, macOS 26.5.2), so the list is drawn here from InputSession's state.
@MainActor
final class CandidateWindow {
    static let pageSize = 9

    private let panel: NSPanel
    private let listView = CandidateListView()
    /// Called with the candidate text when the user clicks a row.
    var onSelect: ((String) -> Void)?

    var isVisible: Bool { panel.isVisible }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .popUpMenu
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        background.layer?.masksToBounds = true
        background.addSubview(listView)
        panel.contentView = background
        listView.onClick = { [weak self] text in self?.onSelect?(text) }
    }

    /// `anchor` is the screen rectangle of the focused text; the list goes below it, or above near the screen bottom.
    func show(candidates: [String], selected: Int, anchor: NSRect) {
        let size = listView.update(candidates: candidates, selected: selected)
        panel.setContentSize(size)
        listView.frame = NSRect(origin: .zero, size: size)

        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var origin = NSPoint(x: anchor.minX, y: anchor.minY - size.height - 4)
        if origin.y < visible.minY { origin.y = anchor.maxY + 4 }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        panel.setFrameOrigin(origin)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

@MainActor
private final class CandidateListView: NSView {
    private static let font = NSFont.systemFont(ofSize: 15)
    private static let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private static let footerFont = NSFont.systemFont(ofSize: 11)
    private static let rowHeight: CGFloat = 24
    private static let inset: CGFloat = 5
    private static let labelWidth: CGFloat = 20

    var onClick: ((String) -> Void)?
    private var rows: [String] = []
    private var selectedRow = 0
    private var footer: String?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func update(candidates: [String], selected: Int) -> NSSize {
        let page = selected / CandidateWindow.pageSize
        let start = page * CandidateWindow.pageSize
        rows = Array(candidates[start..<min(start + CandidateWindow.pageSize, candidates.count)])
        selectedRow = selected - start
        let pages = (candidates.count + CandidateWindow.pageSize - 1) / CandidateWindow.pageSize
        footer = pages > 1 ? "\(selected + 1) / \(candidates.count)" : nil
        needsDisplay = true

        let textWidth = rows.map { ($0 as NSString).size(withAttributes: [.font: Self.font]).width }.max() ?? 0
        let width = max(110, ceil(textWidth) + Self.labelWidth + Self.inset * 2 + 18)
        let height = CGFloat(rows.count) * Self.rowHeight + Self.inset * 2 + (footer == nil ? 0 : 18)
        return NSSize(width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, text) in rows.enumerated() {
            let row = NSRect(x: Self.inset, y: Self.inset + CGFloat(index) * Self.rowHeight,
                             width: bounds.width - Self.inset * 2, height: Self.rowHeight)
            let isSelected = index == selectedRow
            if isSelected {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: row, xRadius: 4, yRadius: 4).fill()
            }
            let textColor: NSColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
            let labelColor: NSColor = isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
            let label = NSAttributedString(string: "\(index + 1)", attributes: [.font: Self.labelFont, .foregroundColor: labelColor])
            label.draw(at: NSPoint(x: row.minX + 6, y: row.midY - label.size().height / 2))
            let candidate = NSAttributedString(string: text, attributes: [.font: Self.font, .foregroundColor: textColor])
            candidate.draw(at: NSPoint(x: row.minX + Self.labelWidth + 6, y: row.midY - candidate.size().height / 2))
        }
        if let footer {
            let attributed = NSAttributedString(string: footer, attributes: [.font: Self.footerFont, .foregroundColor: NSColor.secondaryLabelColor])
            let size = attributed.size()
            attributed.draw(at: NSPoint(x: bounds.width - Self.inset - 6 - size.width,
                                        y: bounds.height - Self.inset - 16))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let index = Int((point.y - Self.inset) / Self.rowHeight)
        guard point.y >= Self.inset, rows.indices.contains(index) else { return }
        onClick?(rows[index])
    }
}
