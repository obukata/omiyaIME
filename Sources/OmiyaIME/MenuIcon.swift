import AppKit
import Carbon
import Security

/// Icon designs for the Japanese mode in the input menu.
enum MenuIcon: String, CaseIterable, Identifiable {
    case shiba
    case filled

    var id: Self { self }
    var title: String { self == .shiba ? "柴犬" : "柴犬（塗りつぶし）" }
    fileprivate var resourceName: String { self == .shiba ? "JapaneseShiba" : "JapaneseFilled" }

    @MainActor var preview: NSImage? {
        guard let url = Bundle.main.url(forResource: "IconPreview-\(rawValue)", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}

/// macOS reads input mode icons only from the bundle's Info.plist resources, so a choice is applied by
/// replacing Japanese.tiff and asking the system to reload the input source (verified 2026-11-27, macOS 26.5.2).
@MainActor
enum MenuIconInstaller {
    private static let preferenceKey = "MenuIcon"

    static var current: MenuIcon {
        MenuIcon(rawValue: UserDefaults.standard.string(forKey: preferenceKey) ?? "") ?? .shiba
    }

    /// Saves the choice and makes the installed icon match it. Cheap when nothing changes, so it also runs at launch.
    static func apply(_ icon: MenuIcon, bundle: Bundle = .main) {
        UserDefaults.standard.set(icon.rawValue, forKey: preferenceKey)
        guard let source = bundle.url(forResource: icon.resourceName, withExtension: "tiff"),
              let target = bundle.url(forResource: "Japanese", withExtension: "tiff"),
              let data = try? Data(contentsOf: source),
              (try? Data(contentsOf: target)) != data,
              (try? data.write(to: target, options: .atomic)) != nil
        else { return }
        resignIfAdHoc(bundle.bundleURL)
        reloadInputSource(bundle.bundleURL)
    }

    /// Keeps a locally built (ad-hoc signed) bundle's signature valid after the resource change.
    /// A Developer ID signed bundle is left alone rather than downgraded.
    private static func resignIfAdHoc(_ url: URL) {
        var code: SecStaticCode?
        var information: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let flags = (information as? [String: Any])?[kSecCodeInfoFlags as String] as? UInt32,
              flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        else { return }
        run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
    }

    private static func reloadInputSource(_ url: URL) {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count) > 0 {
            let cache = URL(fileURLWithPath: String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self), isDirectory: true)
            let files = (try? FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.lastPathComponent.hasPrefix("com.apple.IntlDataCache.le") {
                try? FileManager.default.removeItem(at: file)
            }
        }
        TISRegisterInputSource(url as CFURL)
        // These system agents keep showing the old icon until restarted; macOS relaunches them on demand.
        run("/usr/bin/killall", ["TextInputMenuAgent"])
        run("/usr/bin/killall", ["-9", "CursorUIViewService", "TextInputSwitcher"])
    }

    private static func run(_ executable: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
