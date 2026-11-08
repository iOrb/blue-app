import SwiftUI

struct AssistantDock: View {
    @Environment(AssistantService.self) private var assistant
    @Environment(LibraryStore.self) private var store
    @Environment(AlarmService.self) private var alarms
    @Environment(NavigationState.self) private var navigation
    @Environment(Localizer.self) private var l
    @FocusState private var focused: Bool
    @State private var dictation = DictationService()
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var assistant = assistant
        VStack(spacing: 0) {
            if navigation.assistantExpanded, let result = assistant.result {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        resultView(result).frame(maxWidth: .infinity, alignment: .leading)
                        QuietButton(key: "close", symbol: "xmark") {
                            navigation.assistantExpanded = false
                            navigation.assistantFocused = false
                            dictation.stop()
                        }
                    }
                }
                .padding(.leading, 20).padding(.trailing, 6).padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 6) {
                Button {
                    navigation.assistantExpanded.toggle()
                } label: {
                    BlueCharacter(
                        state: dictation.recording || focused && !assistant.busy ? .listening : assistant.state)
                }.buttonStyle(.plain).accessibilityLabel(l("assistant.showConversation"))
                    .accessibilityIdentifier("assistantCharacter")
                TextField(
                    l(dictation.recording ? "dictation.listening" : "assistant.placeholder"), text: $assistant.input
                )
                .font(.subheadline).focused($focused)
                .submitLabel(.send).onSubmit(submit)
                .accessibilityIdentifier("assistantInput")
                if !assistant.busy {
                    QuietButton(
                        key: dictation.recording ? "dictation.stop" : "dictation.start",
                        symbol: dictation.recording ? "stop.circle.fill" : "mic"
                    ) {
                        if dictation.recording {
                            dictation.stop()
                        } else {
                            focused = false
                            navigation.assistantExpanded = true
                            let prefix = assistant.input.trimmingCharacters(in: .whitespacesAndNewlines)
                            Task {
                                await dictation.start(language: l.language) { text in
                                    assistant.input = prefix.isEmpty ? text : prefix + " " + text
                                }
                            }
                        }
                    }.accessibilityIdentifier("assistantMicrophone")
                }
                if assistant.busy {
                    QuietButton(key: "cancel", symbol: "stop.circle") { assistant.cancel() }
                } else if !assistant.input.isEmpty {
                    QuietButton(key: "assistant.send", symbol: "arrow.up.circle.fill", action: submit)
                        .accessibilityIdentifier("assistantSend")
                }
            }.padding(.horizontal, 10).padding(.vertical, 2)
            if let key = dictation.errorKey, navigation.assistantExpanded {
                Text(l(key)).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 27))
        .padding(.horizontal, 14).padding(.bottom, 8)
        .onChange(of: focused) { _, value in
            navigation.assistantFocused = value
            if value { navigation.assistantExpanded = true }
        }
        .onChange(of: navigation.assistantFocused) { _, value in focused = value }
        .onChange(of: phase) { _, value in if value != .active { dictation.stop() } }
        .onChange(of: l.language) { _, _ in dictation.stop() }
        .onDisappear { dictation.stop() }
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: assistant.result)
    }
    private func submit() {
        dictation.stop()
        focused = false
        navigation.assistantExpanded = true
        assistant.submit(store: store, alarms: alarms, language: l.language)
    }
    @ViewBuilder private func resultView(_ result: AssistantResult) -> some View {
        switch result {
        case .confirmCollectionChange(let change):
            VStack(alignment: .leading, spacing: 10) {
                Text(l("field.confirmMigration")).font(.subheadline)
                let removed = change.original.fields.filter { old in
                    !change.proposed.fields.contains { $0.id == old.id }
                }
                Text(removed.map { l.text($0.label) }.joined(separator: ", ")).font(.caption).foregroundStyle(
                    .secondary)
                Button(l("save"), role: .destructive) {
                    do {
                        guard store.collection(change.original.id) == change.original,
                            Dictionary(
                                uniqueKeysWithValues: store.records(in: change.original.id).map { ($0.id, $0.revision) }
                            ) == change.revisions
                        else { throw BlueError.staleRevision }
                        try store.saveCollection(change.proposed)
                        assistant.result = .collection(change.proposed.id)
                    } catch { assistant.result = .message((error as? BlueError ?? .saveFailed).key) }
                }.accessibilityIdentifier("confirmSchemaChange")
            }.padding(.vertical, 10)
        case .answer(let text):
            Text(text).font(.subheadline).padding(.vertical, 10)
        case .message(let key):
            Text(l(key)).font(.subheadline).padding(.vertical, 10)
        case .records(let ids, let edited):
            VStack(alignment: .leading, spacing: 8) {
                if ids.count > 1 { Text(l("assistant.chooseRecord")).font(.caption).foregroundStyle(.secondary) }
                ForEach(ids.prefix(3), id: \.self) { id in
                    if let record = store.record(id), let collection = store.collection(record.collectionID) {
                        Button {
                            assistant.selectRecord(record.id)
                            navigation.jump(to: record, store: store, locale: l.locale)
                            assistant.result = nil
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.title).font(.subheadline.weight(.semibold))
                                    Text(l(edited ? "assistant.updated" : "assistant.goToRow")).font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let rating = record.values["rating"]?.number {
                                    Text(l.number(rating)).font(.title2.weight(.medium)).monospacedDigit()
                                }
                                Image(systemName: "arrow.up.right").font(.caption)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("result-\(record.title)")
                            .accessibilityHint(l.text(collection.title))
                    }
                }
            }.padding(.vertical, 8)
        case .collection(let id):
            if let collection = store.collection(id) {
                Button {
                    navigation.tab = 0
                    navigation.path = [.collection(id)]
                    assistant.result = nil
                } label: {
                    Label(l.text(collection.title), systemImage: "arrow.up.right").font(.subheadline.weight(.medium))
                }.padding(.vertical, 12).accessibilityIdentifier("resultCollection")
            }
        case .collectionView(let id, let query):
            if let collection = store.collection(id) {
                Button {
                    navigation.queries[id] = query
                    navigation.tab = 0
                    navigation.path = [.collection(id)]
                    assistant.result = nil
                } label: {
                    Label(l.text(collection.title), systemImage: "arrow.up.right").font(.subheadline.weight(.medium))
                }.padding(.vertical, 12)
            }
        case .notes(let ids):
            VStack(alignment: .leading) {
                if ids.isEmpty { Text(l("assistant.noResults")) }
                ForEach(ids.prefix(3), id: \.self) { id in
                    if let note = store.state.notes.first(where: { $0.id == id }) {
                        Button(l.text(note.title)) {
                            navigation.tab = 0
                            navigation.path = [.note(id)]
                            assistant.result = nil
                        }
                    }
                }
            }.padding(.vertical, 10)
        case .alarms(let ids):
            VStack(alignment: .leading) {
                if ids.isEmpty { Text(l("calendar.noAlarms")) }
                ForEach(ids.prefix(3), id: \.self) { id in
                    if let alarm = store.state.alarms.first(where: { $0.id == id }) {
                        Button {
                            navigation.jump(to: alarm)
                            assistant.result = nil
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(l.time(alarm.date)) · \(alarm.title)")
                                Text(l("assistant.showCalendar")).font(.caption)
                            }
                        }
                    }
                }
            }.padding(.vertical, 10)
        case .confirmAlarmDeletion(let id):
            VStack(alignment: .leading) {
                Text(l("alarm.confirmDelete")).font(.subheadline)
                Button(l("delete"), role: .destructive) {
                    Task {
                        guard let alarm = store.state.alarms.first(where: { $0.id == id }) else { return }
                        do {
                            try await alarms.delete(alarm)
                            assistant.result = .message("alarm.deleted")
                        } catch { assistant.result = .message((error as? BlueError ?? .alarmFailed).key) }
                    }
                }
            }
        }
    }
}
