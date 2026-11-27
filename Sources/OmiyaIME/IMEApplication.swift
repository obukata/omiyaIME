import AppKit
import InputMethodKit

@main
struct IMEApplication {
    @MainActor
    static func main() {
        // Development aid: open only the settings window, without registering an input server.
        if let index = CommandLine.arguments.firstIndex(of: "--settings") {
            DictionaryPreferences.shared.show()
            // "--settings <file.png>" saves a picture of the window after it has drawn, then quits.
            if CommandLine.arguments.indices.contains(index + 1) {
                let output = URL(fileURLWithPath: CommandLine.arguments[index + 1])
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    DictionaryPreferences.shared.saveSnapshot(to: output)
                    exit(EXIT_SUCCESS)
                }
            }
            NSApplication.shared.run()
            return
        }

        let bundle = Bundle.main
        guard let bundleID = bundle.bundleIdentifier,
              let connection = bundle.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
              let controller = bundle.object(forInfoDictionaryKey: "InputMethodServerControllerClass") as? String,
              controller == NSStringFromClass(InputController.self),
              let server = IMKServer(name: connection, bundleIdentifier: bundleID)
        else {
            FileHandle.standardError.write(Data("omiyaIME could not start its input server.\n".utf8))
            exit(EXIT_FAILURE)
        }

        // Reapply the chosen menu icon, e.g. after a reinstall restored the default one.
        MenuIconInstaller.apply(MenuIconInstaller.current)

        withExtendedLifetime(server) {
            NSApplication.shared.run()
        }
    }
}
