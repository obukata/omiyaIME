import Carbon
import Foundation

// 使い方:
//   swift Scripts/register-input-source.swift [--install-path PATH] [--enable] [--check] [--remove]
//   --install-path  登録するアプリの場所（既定: ~/Library/Input Methods/omiyaIME.app）
//   --enable        入力ソースを有効化リストへ追加する
//   --check         登録・有効化の状態を表示するだけ（変更しない）
//   --remove        有効化リストから omiyaIME を取り除く（アプリ自体は削除しない）

let bundleID = "jp.omiyaime.inputmethod.omiyaIME"
let modes = ["com.apple.inputmethod.Japanese", "com.apple.inputmethod.Roman"]
let prefsDomain = "com.apple.HIToolbox" as CFString
let enabledKey = "AppleEnabledInputSources" as CFString

var arguments = Array(CommandLine.arguments.dropFirst())
var location = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Input Methods/omiyaIME.app", isDirectory: true)
var enable = false
var checkOnly = false
var remove = false
while !arguments.isEmpty {
    let argument = arguments.removeFirst()
    switch argument {
    case "--install-path":
        guard !arguments.isEmpty else { fail("--install-path にパスを指定してください") }
        location = URL(fileURLWithPath: arguments.removeFirst(), isDirectory: true)
    case "--enable": enable = true
    case "--check": checkOnly = true
    case "--remove": remove = true
    default: fail("使い方: swift Scripts/register-input-source.swift [--install-path PATH] [--enable] [--check] [--remove]")
    }
}

func fail(_ message: String) -> Never {
    print(message)
    exit(EXIT_FAILURE)
}

func enabledEntries() -> [[String: Any]] {
    CFPreferencesAppSynchronize(prefsDomain)
    return CFPreferencesCopyAppValue(enabledKey, prefsDomain) as? [[String: Any]] ?? []
}

func isOurs(_ entry: [String: Any]) -> Bool {
    entry["Bundle ID"] as? String == bundleID
}

func writeEntries(_ entries: [[String: Any]]) {
    CFPreferencesSetAppValue(enabledKey, entries as CFArray, prefsDomain)
    guard CFPreferencesAppSynchronize(prefsDomain) else { fail("入力ソース設定を保存できませんでした") }
}

func registeredSources() -> [String] {
    guard let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }
    return sources.compactMap { source in
        guard let bundle = TISGetInputSourceProperty(source, kTISPropertyBundleID),
              (Unmanaged<CFString>.fromOpaque(bundle).takeUnretainedValue() as String) == bundleID,
              let id = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(id).takeUnretainedValue() as String
    }
}

if remove {
    writeEntries(enabledEntries().filter { !isOurs($0) })
    print("omiyaIME を入力ソースの有効化リストから外しました")
    exit(EXIT_SUCCESS)
}

if !checkOnly {
    guard Bundle(url: location)?.bundleIdentifier == bundleID else {
        fail("omiyaIME.app が見つかりません: \(location.path)")
    }
    let status = TISRegisterInputSource(location as CFURL)
    guard status == noErr else { fail("omiyaIME の登録に失敗しました（\(status)）") }
}

if enable {
    var entries = enabledEntries()
    var wanted: [[String: Any]] = [["Bundle ID": bundleID, "InputSourceKind": "Keyboard Input Method"]]
    wanted += modes.map { ["Bundle ID": bundleID, "Input Mode": $0, "InputSourceKind": "Input Mode"] }
    for item in wanted where !entries.contains(where: {
        isOurs($0) && ($0["Input Mode"] as? String) == (item["Input Mode"] as? String)
            && ($0["InputSourceKind"] as? String) == (item["InputSourceKind"] as? String)
    }) {
        entries.append(item)
    }
    writeEntries(entries)
}

let found = registeredSources()
let enabledCount = enabledEntries().filter(isOurs).count
print("omiyaIME 登録: \(found.isEmpty ? "なし" : found.sorted().joined(separator: ", "))")
print("omiyaIME 有効化リスト: \(enabledCount) 件")
if found.isEmpty {
    print("macOS がまだ omiyaIME を認識していません。ログアウトしてログインし直してください")
    exit(checkOnly ? EXIT_FAILURE : EXIT_SUCCESS)
}
