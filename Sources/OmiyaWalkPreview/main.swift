import AppKit
import OmiyaWalk

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
        panel.placeAtLowerRight()
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

// Development option: `--snapshot out.png [seconds]` writes one picture and exits.
if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
    let path = CommandLine.arguments[index + 1]
    let seconds = CommandLine.arguments.count > index + 2 ? Double(CommandLine.arguments[index + 2]) ?? 0 : 0
    MainActor.assumeIsolated {
        let view = WalkView()
        view.advance(by: seconds)
        if let data = view.snapshotPNG() { try? data.write(to: URL(fileURLWithPath: path)) }
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = PreviewDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
