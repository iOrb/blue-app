import SwiftUI

struct AssistantDock: View {
    @Environment(AssistantService.self) private var assistant
    @Environment(LibraryStore.self) private var store
    @Environment(AlarmService.self) private var alarms
    @Environment(NavigationState.self) private var navigation
    @Environment(Localizer.self) private var l
    @Environment(\.scenePhase) private var phase
    @FocusState private var focused: Bool
    @State private var dictation = DictationService()
    @State private var event: CalendarEvent?
    @State private var deletionAction: (() async throws -> Void)?
    @State private var reviewingDeletion = false
    var body: some View {
        @Bindable var assistant = assistant
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BlueCharacter(state: assistant.state).frame(width: 46, height: 46).accessibilityHidden(true)
                HStack(spacing: 4) {
                    TextField(
                        l(dictation.recording ? "dictation.listening" : "assistant.placeholder"), text: $assistant.input
                    )
                    .focused($focused).submitLabel(.send).onSubmit(submit).accessibilityIdentifier("assistantInput")
                    QuietButton(
                        key: dictation.recording ? "dictation.stop" : "dictation.start",
                        symbol: dictation.recording ? "stop.circle.fill" : "mic"
                    ) {
                        if dictation.recording {
                            dictation.stop()
                        } else {
                            focused = false
                            let prefix = assistant.input
                            Task {
                                await dictation.start(language: l.language) {
                                    assistant.input = prefix.isEmpty ? $0 : prefix + " " + $0
                                }
                            }
                        }
                    }.accessibilityIdentifier("assistantMicrophone")
                    if assistant.busy {
                        QuietButton(key: "cancel", symbol: "stop.circle") { assistant.cancel() }
                    } else {
                        QuietButton(key: "assistant.send", symbol: "arrow.up.circle.fill", action: submit).disabled(
                            assistant.input.isEmpty
                        ).accessibilityIdentifier("assistantSend")
                    }
                }.padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6).background(
                    .regularMaterial, in: Capsule())
            }.padding(.horizontal, 18).padding(.bottom, 20)
            ErrorLine(key: dictation.errorKey).padding(.horizontal, 24)
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(
                            Array(assistant.history.dropLast(assistant.activePrompt == nil ? 1 : 0).enumerated()),
                            id: \.offset
                        ) { _, exchange in
                            Text(exchange.user).foregroundStyle(.secondary).frame(
                                maxWidth: .infinity, alignment: .trailing)
                            MarkdownView(text: .constant(exchange.reply))
                        }
                        if let question = assistant.activePrompt ?? assistant.history.last?.user {
                            Text(question).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if let result = assistant.result { resultView(result) }
                        if assistant.busy { ProgressView().frame(maxWidth: .infinity, alignment: .leading) }
                        Color.clear.frame(height: 1).id("latest")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 30)
                }.scrollDismissesKeyboard(.interactively)
                    .onChange(of: assistant.history) { _, _ in scroll.scrollTo("latest", anchor: .bottom) }
            }
        }

        .blueConfirmation(isPresented: $reviewingDeletion, title: l("delete.confirm")) {
            let action = deletionAction
            deletionAction = nil
            Task {
                do { try await action?() } catch {
                    assistant.result = .message((error as? BlueError ?? .saveFailed).key)
                }
            }
        }
        .onAppear { focused = navigation.assistantFocused }
        .onDisappear {
            dictation.stop()
            navigation.assistantFocused = false
        }
        .onChange(of: phase) { _, value in if value != .active { dictation.stop() } }
        .onChange(of: l.language) { _, _ in dictation.stop() }
        .blueSheet(
            isPresented: Binding(get: { event != nil }, set: { if !$0 { event = nil } }), title: l("event.title")
        ) {
            if let event { EventEditor(existing: event, date: event.date) }
        }
    }
    private func submit() {
        dictation.stop()
        focused = false
        assistant.submit(store: store, alarms: alarms, language: l.language)
    }
    private func open(_ route: Route) {
        navigation.open(route)
        navigation.assistantExpanded = false
    }
    @ViewBuilder private func resultView(_ result: AssistantResult) -> some View {
        switch result {
        case .answer(let text): MarkdownView(text: .constant(text))
        case .message(let key): Text(l(key))
        case .records(let ids, _): records(ids)
        case .notes(let ids): notes(ids)
        case .events(let ids): events(ids)
        case .selection(let selection):
            if !selection.answer.isEmpty { Text(selection.answer) }
            records(selection.records, fields: selection.fields)
            notes(selection.notes)
            events(selection.events)
            ForEach(selection.collections, id: \.self) { collectionLink($0) }
        case .collection(let id): collectionLink(id)
        case .collectionView(let id, let query):
            if let collection = store.collection(id) {
                Text(l.text(collection.title)).font(.title2.weight(.semibold))
                records(query.apply(to: store.records(in: id), fields: collection.fields, locale: l.locale).map(\.id))
            }
        case .confirmCollectionChange(let change):
            Text(l("field.confirmMigration"))
            Text(
                change.original.fields.filter { old in !change.proposed.fields.contains { $0.id == old.id } }.map {
                    l.text($0.label)
                }.joined(separator: ", ")
            )
            .foregroundStyle(.secondary)
            confirmation {
                guard store.collection(change.original.id) == change.original,
                    Dictionary(uniqueKeysWithValues: store.records(in: change.original.id).map { ($0.id, $0.revision) })
                        == change.revisions
                else { throw BlueError.staleRevision }
                try store.saveCollection(change.proposed)
                assistant.result = .collection(change.proposed.id)
            }
        case .confirmDeletion(let pending):
            Text(l("delete.confirm"))
            confirmation {
                try store.confirmDeletion(pending)
                assistant.result = .message("deleted")
            }
        case .alarms(let ids):
            ForEach(ids, id: \.self) { id in
                if let alarm = store.state.alarms.first(where: { $0.id == id }) {
                    Button("\(l.time(alarm.date)) · \(alarm.title)") {
                        navigation.jump(to: alarm)
                        navigation.scope = "calendar"
                        navigation.path = []
                        navigation.assistantExpanded = false
                    }.frame(minHeight: 44)
                }
            }
        case .confirmAlarmDeletion(let id):
            Text(l("alarm.confirmDelete"))
            confirmation {
                guard let alarm = store.state.alarms.first(where: { $0.id == id }) else { throw BlueError.missing }
                try await alarms.delete(alarm)
                assistant.result = .message("alarm.deleted")
            }
        }
    }
    @ViewBuilder private func records(_ ids: [UUID], fields: [String] = []) -> some View {
        ForEach(ids, id: \.self) { id in
            if let record = store.record(id), let collection = store.collection(record.collectionID) {
                Button {
                    assistant.selectRecord(id)
                    open(.record(id))
                } label: {
                    Text(record.title).font(.title3.weight(.semibold)).frame(
                        maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("result-\(record.title)")
                let displayed = Collection(
                    id: collection.id, title: collection.title,
                    fields: fields.isEmpty ? collection.fields : collection.fields.filter { fields.contains($0.id) })
                RecordIndicators(
                    record: record, collection: displayed, interactive: true,
                    includeFavorite: fields.isEmpty || fields.contains("__favorite")
                        || collection.fields.contains { $0.kind == .favorite && fields.contains($0.id) })
                if (fields.isEmpty || fields.contains("markdown")) && !l.text(record.markdown).isEmpty {
                    MarkdownView(text: .constant(l.text(record.markdown)))
                }

            }
        }
    }
    @ViewBuilder private func notes(_ ids: [UUID]) -> some View {
        ForEach(ids, id: \.self) { id in
            if let note = store.state.notes.first(where: { $0.id == id }) {
                Button {
                    assistant.selectNote(id)
                    open(.note(id))
                } label: {
                    Text(l.text(note.title)).font(.title3.weight(.semibold)).frame(minHeight: 44)
                }.buttonStyle(.plain)
                Text(l.text(note.markdown)).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    @ViewBuilder private func events(_ ids: [UUID]) -> some View {
        ForEach(ids, id: \.self) { id in
            if let value = store.state.events?.first(where: { $0.id == id }) {
                Button {
                    event = value
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(value.title).font(.title3.weight(.medium))
                        Text(l.date(value.date) + (value.allDay ? "" : " · " + l.time(value.date))).foregroundStyle(
                            .secondary)
                    }.frame(minHeight: 54)
                }.buttonStyle(.plain)
            }
        }
    }
    @ViewBuilder private func collectionLink(_ id: UUID) -> some View {
        if let collection = store.collection(id) {
            Button {
                open(.collection(id))
            } label: {
                Label(l.text(collection.title), systemImage: "square.stack").font(.title3).frame(minHeight: 50)
            }.buttonStyle(.plain)
        }
    }
    private func confirmation(_ action: @escaping () async throws -> Void) -> some View {
        HStack {
            Button(l("cancel")) { assistant.result = nil }.frame(minHeight: 44)
            Spacer()
            Button(role: .destructive) {
                deletionAction = action
                reviewingDeletion = true
            } label: {
                Label(l("delete"), systemImage: "minus")
            }
            .frame(minHeight: 44).accessibilityIdentifier("confirmDeletion")
        }
    }
}
