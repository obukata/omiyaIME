import AppKit
import OmiyaWalk
import OmiyaWalkCore

// Prototype viewer: shows Omiya on the desktop without installing the input method.
// Drag him to move. Right-click for 終了.

@MainActor
final class PreviewDelegate: NSObject, NSApplicationDelegate {
    private var panel: WalkPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panel = WalkPanel()
        let menu = NSMenu()
        let settings = menu.addItem(withTitle: "おみや君の設定…（準備中）", action: nil, keyEquivalent: "")
        settings.isEnabled = false
        menu.autoenablesItems = false
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        panel.walkView?.menu = menu
        panel.walkView?.gearMenu = menu
        panel.walkView?.onTreasure = { TreasureWindowController.shared.show() }
        panel.placeAtLowerRight()
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

// Development option: `--treasure-snapshot out.png` writes the treasure list as a picture and exits.
if let index = CommandLine.arguments.firstIndex(of: "--treasure-snapshot"), index + 1 < CommandLine.arguments.count {
    MainActor.assumeIsolated {
        if let data = TreasureWindowController.snapshotPNG() {
            try? data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
    }
    exit(0)
}

// Development option: `--snapshot out.png [seconds] [steps]` writes the open stage as one picture
// and exits. With `steps`, the distance shows that many steps instead of the saved total.
if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    let seconds = CommandLine.arguments.count > index + 2 ? Double(CommandLine.arguments[index + 2]) ?? 0 : 0
    MainActor.assumeIsolated {
        let args = CommandLine.arguments
        let steps = args.count > index + 3 ? Int(args[index + 3]) : nil
        let view = WalkView(progressFile: steps == nil ? WalkProgressFile() : nil)
        if let steps { view.status = .walked(WalkProgress(steps: steps)) }
        if args.contains("--closed") { view.setExpanded(false, animated: false) } else { view.setExpanded(true, animated: false) }
        // Step through time so pose changes play as they would on screen.
        var time = 0.0
        while time < seconds { view.advance(by: 1.0 / 30); time += 1.0 / 30 }
        if let data = view.snapshotPNG() { try? data.write(to: URL(fileURLWithPath: path)) }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = PreviewDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
