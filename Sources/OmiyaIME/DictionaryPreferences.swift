import AppKit
import OmiyaInput
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DictionaryPreferences: ObservableObject {
    static let shared = DictionaryPreferences()

    @Published private(set) var entries: [UserDictionaryEntry] = []
    @Published var errorMessage: String?
    private var store: UserDictionaryFile?
    private var window: NSWindow?

    private init() {
        let location = URL.applicationSupportDirectory
            .appending(path: "omiyaIME", directoryHint: .isDirectory)
            .appending(path: "user-dictionary.json", directoryHint: .notDirectory)
        do {
            let store = try UserDictionaryFile(location: location)
            self.store = store
            entries = store.entries
        } catch {
            errorMessage = "ユーザ辞書を開けませんでした。"
        }
    }

    func show() {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: false)
            window.title = "omiyaIMEの設定"
            window.contentViewController = NSHostingController(rootView: DictionarySettings(model: self))
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.setActivationPolicy(.accessory)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @discardableResult
    func save(_ replacement: [UserDictionaryEntry]) -> Bool {
        guard var store else {
            errorMessage = "既存の辞書を確認できないため、保存できませんでした。"
            return false
        }
        do {
            try store.save(replacement)
            self.store = store
            entries = store.entries
            return true
        } catch UserDictionaryFile.ValidationError.invalidEntry {
            errorMessage = "読みと語句を入力してください。絵文字や英字だけの語句は登録できません。"
        } catch UserDictionaryFile.ValidationError.duplicateEntry {
            errorMessage = "同じ読みと語句がすでに登録されています。"
        } catch {
            errorMessage = "ユーザ辞書を保存できませんでした。"
        }
        return false
    }
}

private struct DictionarySettings: View {
    @ObservedObject var model: DictionaryPreferences
    @State private var selection: UserDictionaryEntry?
    @State private var reading = ""
    @State private var phrase = ""
    @State private var importDraft: AppleDictionaryImport?
    @State private var showsImportReview = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ユーザ辞書")
                .font(.headline)

            Table(model.entries.map(DictionaryRow.init), selection: $selection) {
                TableColumn("読み", value: \.entry.reading)
                TableColumn("語句", value: \.entry.phrase)
            }
            .onChange(of: selection) { _, entry in
                reading = entry?.reading ?? ""
                phrase = entry?.phrase ?? ""
            }

            Form {
                TextField("読み", text: $reading)
                TextField("語句", text: $phrase)
            }
            HStack {
                Button("インポート…", action: chooseImport)
                Spacer()
                if selectedIndex != nil {
                    Button("新規") { selection = nil }
                    Button("削除", action: deleteSelection)
                }
                Button(selectedIndex == nil ? "追加" : "変更", action: saveEntry)
                    .keyboardShortcut(.defaultAction)
                    .disabled(reading.isEmpty || phrase.isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 430, minHeight: 340)
        .alert("ユーザ辞書", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .sheet(isPresented: $showsImportReview) {
            if let draft = importDraft {
                let additions = draft.entries.filter { !model.entries.contains($0) }
                VStack(alignment: .leading, spacing: 14) {
                    Text("インポートの確認").font(.headline)
                    Text("追加 \(additions.count) 件、除外 \(draft.issues.count + draft.entries.count - additions.count) 件")
                    HStack {
                        Spacer()
                        Button("キャンセル") { showsImportReview = false }
                            .keyboardShortcut(.cancelAction)
                        Button("インポート") {
                            showsImportReview = false
                            model.save(model.entries + additions)
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(additions.isEmpty)
                    }
                }
                .padding(20)
                .frame(minWidth: 320)
            }
        }
    }

    private var selectedIndex: Int? {
        selection.flatMap { model.entries.firstIndex(of: $0) }
    }

    private func saveEntry() {
        let entry = UserDictionaryEntry(reading: reading, phrase: phrase)
        var replacement = model.entries
        if let index = selectedIndex {
            replacement[index] = entry
        } else {
            replacement.append(entry)
        }
        if model.save(replacement) { selection = entry }
    }

    private func deleteSelection() {
        guard let index = selectedIndex else { return }
        var replacement = model.entries
        replacement.remove(at: index)
        if model.save(replacement) { selection = nil }
    }

    private func chooseImport() {
        let picker = NSOpenPanel()
        picker.allowedContentTypes = [.propertyList]
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = false
        guard picker.runModal() == .OK, let location = picker.url else { return }
        let hasAccess = location.startAccessingSecurityScopedResource()
        defer { if hasAccess { location.stopAccessingSecurityScopedResource() } }
        do {
            importDraft = try AppleDictionaryImport(data: Data(contentsOf: location))
            showsImportReview = true
        } catch {
            model.errorMessage = "Apple標準IMEのユーザ辞書ファイルを読み込めませんでした。"
        }
    }
}

private struct DictionaryRow: Identifiable {
    let entry: UserDictionaryEntry
    var id: UserDictionaryEntry { entry }
}
