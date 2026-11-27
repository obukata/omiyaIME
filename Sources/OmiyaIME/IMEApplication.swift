import AppKit
import InputMethodKit

@main
struct IMEApplication {
    @MainActor
    static func main() {
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

        withExtendedLifetime(server) {
            NSApplication.shared.run()
        }
    }
}
