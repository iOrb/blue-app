import SwiftUI
import UniformTypeIdentifiers

struct SettingsButton: View {
    @Environment(NavigationState.self) private var navigation
    @Environment(Localizer.self) private var l
    var body: some View {
        Button {
            navigation.settingsPresented = true
        } label: {
            Image(systemName: "slider.horizontal.3").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(l("settings.title")).accessibilityIdentifier("settingsButton")
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
    @AppStorage("blue.appearance") private var appearance: BlueAppearance = .system
    @Environment(NavigationState.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var assistantHighlight = 0.0
    @Environment(Localizer.self) private var l
    @Environment(LibraryStore.self) private var store
    @Environment(AssistantService.self) private var assistant
    @Environment(FolderBackupService.self) private var backup
    @Environment(GoogleDriveConnection.self) private var drive
    @Environment(DriveBackupService.self) private var driveBackup
    @State private var expandedSections: Set<String> = ["assistant", "storage", "appearance", "language"]
    @State private var exporting = false
    @State private var importing = false
    @State private var imported = false
    @State private var document = JSONExport(data: Data())
    @State private var error: String?
    @State private var provider = AssistantConnection.provider
    @State private var model = AssistantConnection.model(for: AssistantConnection.provider)
    @State private var voiceModel = AssistantConnection.voiceModel(for: AssistantConnection.provider)
    @State private var transcriptionModel = AssistantConnection.transcriptionModel(for: AssistantConnection.provider)
    @State private var apiKey = AssistantConnection.key(for: AssistantConnection.provider) ?? ""
    @State private var models: [String] = []
    @State private var connectionStatus: String?
    @State private var connected = false
    @FocusState private var editingKey: Bool

    private struct Check: Equatable {
        let provider: AssistantProvider
        let model: String
        let key: String
    }

    private var check: Check { Check(provider: provider, model: model, key: apiKey) }
    var body: some View {
        @Bindable var l = l
        ScrollViewReader { scroll in
            List {
                collapsible("assistant", title: "settings.assistant") {
                    HStack(spacing: 12) {
                        assistantTile("settings.provider", symbol: "network")
                        Spacer()
                        Picker(l("settings.provider"), selection: $provider) {
                            ForEach(AssistantProvider.allCases) { value in Text(value.title).tag(value) }
                        }
                        .labelsHidden().accessibilityLabel(l("settings.provider"))
                        .accessibilityIdentifier("assistantProvider")
                    }
                    .id("assistantSettings").listRowBackground(assistantRowBackground)
                    HStack(spacing: 12) {
                        assistantTile("settings.model", symbol: "cpu")
                        Spacer()
                        Picker(l("settings.model"), selection: $model) {
                            ForEach(
                                Array(Set((models.isEmpty ? provider.models : models) + [model])).sorted(), id: \.self
                            ) { value in Text(value).tag(value) }
                        }
                        .labelsHidden().accessibilityLabel(l("settings.model"))
                        .accessibilityIdentifier("assistantModel")
                    }.listRowBackground(assistantRowBackground)
                    HStack(spacing: 8) {
                        assistantTile("settings.voiceModel", symbol: "waveform")
                        Spacer(minLength: 0)
                        Picker(l("settings.voiceModel"), selection: $voiceModel) {
                            ForEach(provider.liveModels, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().accessibilityLabel(l("settings.voiceModel"))
                            .accessibilityIdentifier("assistantVoiceModel")
                    }.listRowBackground(assistantRowBackground)
                    HStack(spacing: 8) {
                        assistantTile("settings.transcriptionModel", symbol: "mic")
                        Spacer(minLength: 0)
                        Picker(l("settings.transcriptionModel"), selection: $transcriptionModel) {
                            ForEach(provider.transcriptionModels, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().accessibilityLabel(l("settings.transcriptionModel"))
                            .accessibilityIdentifier("assistantTranscriptionModel")
                    }.listRowBackground(assistantRowBackground)
                    HStack(spacing: 12) {
                        assistantTile("settings.keyCaption", symbol: "key")
                        SecureField(l("settings.apiKey"), text: $apiKey)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($editingKey)
                            .accessibilityIdentifier("assistantAPIKey")
                    }.listRowBackground(assistantRowBackground)
                    if let connectionStatus {
                        Label(l(connectionStatus), systemImage: connected ? "checkmark.circle.fill" : "circle.dotted")
                            .font(.footnote)
                            .foregroundStyle(connected ? Color.green : Color.secondary)
                            .accessibilityIdentifier("assistantHealth")
                    }
                    Text(l("settings.assistantPrivacy")).font(.footnote).foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                collapsible("storage", title: "backup.title") {
                    if drive.connected {
                        LabeledContent("Google Drive", value: drive.account ?? "")
                        Button(l("drive.disconnect")) { drive.disconnect() }
                    } else {
                        Button {
                            drive.connect()
                        } label: {
                            HStack {
                                Label(l("drive.connect"), systemImage: "externaldrive")
                                Spacer()
                                if drive.busy { ProgressView() }
                            }
                        }
                        .disabled(drive.busy)
                        .accessibilityIdentifier("connectGoogleDrive")
                    }
                    ErrorLine(key: drive.errorKey)
                    if drive.connected, !drive.hasBackupPermission {
                        Button(l("drive.enableBackup")) { drive.connect() }
                    }
                    if drive.hasBackupPermission {
                        Text(l("drive.accountProtection")).font(.footnote).foregroundStyle(.secondary)
                        if driveBackup.saving {
                            Label(l("backup.saving"), systemImage: "arrow.triangle.2.circlepath").font(.footnote)
                        } else if let savedAt = driveBackup.savedAt {
                            Label(l.format("backup.savedAt", l.time(savedAt)), systemImage: "checkmark.circle.fill")
                                .font(.footnote)
                        }
                        Button(l("drive.backupNow")) {
                            driveBackup.schedule(
                                AppBackupSnapshot.capture(library: store.state), connection: drive, verify: true)
                        }.disabled(driveBackup.saving)
                        if let folderID = driveBackup.folderID,
                            let url = URL(string: "https://drive.google.com/drive/folders/" + folderID)
                        {
                            Link(l("drive.openFolder"), destination: url)
                        }
                        ErrorLine(key: driveBackup.errorKey)
                    }
                    Button(l("settings.import")) { importing = true }
                    Button(l("settings.export")) {
                        do {
                            document = JSONExport(data: try store.export())
                            exporting = true
                        } catch { self.error = BlueError.saveFailed.key }
                    }

                    if imported { Text(l("settings.imported")).foregroundStyle(.secondary) }
                    ErrorLine(key: backup.errorKey ?? error)
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                collapsible("appearance", title: "settings.appearance") {
                    Picker(l("settings.appearance"), selection: $appearance) {
                        ForEach(BlueAppearance.allCases) { option in
                            Image(
                                systemName: option == .system
                                    ? "circle.lefthalf.filled" : option == .light ? "sun.max.fill" : "moon.fill"
                            )
                            .accessibilityLabel(l("settings.appearance.\(option.rawValue)"))
                            .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .accessibilityIdentifier("appearancePicker")
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                collapsible("language", title: "settings.language") {
                    Picker(l("settings.language"), selection: $l.language) {
                        Text(verbatim: "English").tag(AppLanguage.english)
                        Text(verbatim: "Español (España)").tag(AppLanguage.spanish)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .accessibilityLabel(l("settings.language"))
                    .accessibilityIdentifier("languagePicker")
                    Text(l("settings.systemLanguage")).font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 26)
                }
                .allowsHitTesting(false)
            }
            .task(id: navigation.assistantSetupRequested) {
                assistantHighlight = 0
                guard navigation.assistantSetupRequested else { return }
                expandedSections.insert("assistant")
                do {
                    try await Task.sleep(for: .milliseconds(260))
                    withAnimation(reduceMotion ? nil : .smooth(duration: 0.32)) {
                        scroll.scrollTo("assistantSettings", anchor: .top)
                    }
                    try await Task.sleep(for: .milliseconds(180))
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.50, bounce: 0.24)) {
                        assistantHighlight = 1
                    }
                    try await Task.sleep(for: .seconds(3))
                    withAnimation(.easeInOut(duration: reduceMotion ? 0.35 : 0.90)) {
                        assistantHighlight = 0
                    }
                } catch {}
            }
        }
        .navigationTitle(l("settings.title")).navigationBarTitleDisplayMode(.inline)
        .onChange(of: provider) { _, value in
            model = AssistantConnection.model(for: value)
            voiceModel = AssistantConnection.voiceModel(for: value)
            transcriptionModel = AssistantConnection.transcriptionModel(for: value)
            apiKey = AssistantConnection.key(for: value) ?? ""
            models = []
            connected = false
            connectionStatus = nil
            AssistantConnection.select(provider: value, model: model)
            assistant.clearConversation()
        }
        .onChange(of: model) { _, value in
            AssistantConnection.select(provider: provider, model: value)
            assistant.clearConversation()
        }
        .onChange(of: voiceModel) { _, value in AssistantConnection.selectVoice(value, for: provider) }
        .onChange(of: transcriptionModel) { _, value in AssistantConnection.selectTranscription(value, for: provider) }
        .task { drive.restore() }
        .task(id: check) { await validate(check) }
        .onChange(of: editingKey) { _, focused in
            if !focused, apiKey.isEmpty, AssistantConnection.key(for: provider) != nil {
                do {
                    try AssistantConnection.setKey("", for: provider)
                    assistant.clearConversation()
                } catch { connectionStatus = "settings.checkFailed" }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            imported = false
            do {
                let url = try result.get()
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                try store.importBackup(Data(contentsOf: url, options: .mappedIfSafe))
                error = nil
                imported = true
            } catch { self.error = "settings.importFailed" }
        }
        .fileExporter(
            isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Blue-export-v3"
        ) { result in
            if case .failure = result { error = BlueError.saveFailed.key }
        }
    }
    private func collapsible<Content: View>(_ id: String, title: String, @ViewBuilder content: () -> Content)
        -> some View
    {
        Section {
            if expandedSections.contains(id) { content() }
        } header: {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    if !expandedSections.insert(id).inserted { expandedSections.remove(id) }
                }
            } label: {
                HStack {
                    Text(l(title))
                    Spacer()
                    Image(systemName: expandedSections.contains(id) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                }.frame(minHeight: 38).contentShape(Rectangle())
            }.buttonStyle(BlueRowPress())
                .accessibilityIdentifier("settingsSection-\(id)")
                .accessibilityValue(l(expandedSections.contains(id) ? "settings.expanded" : "settings.collapsed"))
        }
    }

    private func assistantTile(_ key: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.footnote.weight(.medium))
                .foregroundStyle(.secondary).frame(width: 20)
            Text(l(key)).font(.subheadline).lineLimit(2)
        }
        .accessibilityHidden(true)
    }

    private var assistantRowBackground: some View {
        LinearGradient(
            colors: [.blue.opacity(0.22 * assistantHighlight), .blue.opacity(0.08 * assistantHighlight)],
            startPoint: .leading, endPoint: .trailing
        )
    }

    private func validate(_ snapshot: Check) async {
        connected = false
        let key = snapshot.key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            connectionStatus = nil
            return
        }
        connectionStatus = "settings.checking"
        do {
            try await Task.sleep(for: .milliseconds(650))
            guard key.utf8.count <= 512, !key.contains(where: \.isWhitespace) else {
                throw BlueError.invalidValue
            }
            let connection = AssistantConnection(provider: snapshot.provider, model: snapshot.model, key: key)
            let client = ConnectedAssistant(connection: connection)
            let available = try await client.modelCatalog()
            try Task.checkCancellation()
            guard snapshot == check else { return }
            models = available
            if AssistantConnection.key(for: snapshot.provider) != key {
                try AssistantConnection.setKey(key, for: snapshot.provider)
                assistant.clearConversation()
            }
            connected = assistant.recordCatalog(available, for: connection)
            connectionStatus = connected ? "settings.keyHealthy" : "settings.modelUnavailable"
        } catch is CancellationError {
            return
        } catch {
            guard snapshot == check, !Task.isCancelled else { return }
            if (error as? BlueError)?.requiresAssistantSetup == true,
                let saved = AssistantConnection.configured(), saved.provider == snapshot.provider,
                saved.model == snapshot.model, saved.key == key
            {
                assistant.recordConnection(.needsSetup, for: saved)
            }
            connectionStatus =
                (error as? BlueError) == .assistantCredentials
                ? BlueError.assistantCredentials.key : "settings.checkFailed"
        }
    }
}
