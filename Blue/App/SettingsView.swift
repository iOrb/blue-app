import SwiftUI
import UniformTypeIdentifiers

struct SettingsButton: View {
    @State private var showing = false
    @Environment(Localizer.self) private var l
    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(l("settings.title")).accessibilityIdentifier("settingsButton")
        .blueSheet(isPresented: $showing, title: l("settings.title")) { SettingsView() }
    }
}

struct JSONExport: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(Localizer.self) private var l
    @Environment(LibraryStore.self) private var store
    @Environment(AssistantService.self) private var assistant
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false
    @State private var document = JSONExport(data: Data())
    @State private var error: String?
    var body: some View {
        @Bindable var l = l
        List {
            Section(l("settings.language")) {
                Button {
                    l.language = .english
                } label: {
                    HStack {
                        Text("English")
                        Spacer()
                        if l.language == .english { Image(systemName: "checkmark") }
                    }
                }.accessibilityIdentifier("languageEnglish")
                Button {
                    l.language = .spanish
                } label: {
                    HStack {
                        Text("Español (España)")
                        Spacer()
                        if l.language == .spanish { Image(systemName: "checkmark") }
                    }
                }.accessibilityIdentifier("languageSpanish")
            }
            Section(l("settings.intelligence")) {
                Label(l(assistant.availabilityKey), systemImage: "iphone")
                Text(l("settings.privacy")).font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                Button(l("settings.export")) {
                    do {
                        document = JSONExport(data: try store.export())
                        exporting = true
                    } catch { self.error = BlueError.saveFailed.key }
                }

                ErrorLine(key: error)
            }
            Section { Text(l("settings.systemLanguage")).font(.footnote).foregroundStyle(.secondary) }
        }
        .listStyle(.plain)
        .navigationTitle(l("settings.title")).navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Blue-export-v2"
        ) { result in
            if case .failure = result { error = BlueError.saveFailed.key }
        }
    }
}
