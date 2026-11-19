import AVFoundation
import SwiftUI

struct AssistantDock: View {
    @Environment(AssistantService.self) private var assistant
    @Environment(LibraryStore.self) private var store
    @Environment(AlarmService.self) private var alarms
    @Environment(NavigationState.self) private var navigation
    @Environment(Localizer.self) private var l
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var dictation = DictationService()
    private var live: LiveVoiceService { assistant.liveVoice }
    @State private var chat = false
    private var voiceFixture: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("--test-live-assistant")
        #else
            false
        #endif
    }
    private var isLive: Bool { !chat && assistant.connectionStatus == .ready }
    @State private var event: CalendarEvent?
    @State private var deletionAction: (() async throws -> Void)?
    @State private var reviewingDeletion = false
    @State private var searchSubmitted = false
    @State private var matches = AssistantSelection()
    @State private var setupPulse = false
    @State private var connectionRetry = 0
    private var hasConversation: Bool {
        searchSubmitted || assistant.result != nil || !assistant.history.isEmpty || assistant.busy
    }
    var body: some View {
        let editedEvent = event
        VStack(spacing: 8) {
            if isLive {
                VStack(spacing: 12) {
                    VoiceOrb(phase: live.phase, level: live.level, muted: live.muted)
                    if !live.caption.isEmpty {
                        Text(live.caption)
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineLimit(3)
                            .padding(.horizontal, 30)
                            .accessibilityIdentifier("liveVoiceCaption")
                    }
                    if live.phase == .failed || live.phase == .idle {
                        QuietButton(key: "voice.retry", symbol: "arrow.clockwise", action: startVoice)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .accessibilityIdentifier("retryLiveVoice")
                    }
                }.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    if hasConversation { response.padding(.top, 54).padding(.bottom, 30) }
                }
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { focused = false })
                .mask { BlueEdgeFade(top: 24, bottom: 42, topOpacity: 0.27) }
            }
            switch assistant.connectionStatus {
            case .ready:
                composer
            case .needsSetup:
                setupComposer
            case .checking:
                Color.clear.frame(height: 48).accessibilityHidden(true)
            case .unavailable:
                Button {
                    connectionRetry += 1
                } label: {
                    Label(l("assistant.retryConnection"), systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.medium)).frame(minHeight: 48)
                }.buttonStyle(BlueRowPress())
            }
            if let error = isLive ? (live.errorKey ?? live.inputWarningKey) : dictation.errorKey {
                ErrorLine(key: error).padding(.horizontal, 24)
            }
            if !isLive, dictation.transcribing {
                Text(l("dictation.transcribing")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 6)
        .frame(maxWidth: 680)
        .overlay(alignment: .top) {
            if !isLive {
                HStack {
                    BlueCloseButton { navigation.assistantExpanded = false }
                        .accessibilityIdentifier("closeAssistant")
                    Spacer()
                    QuietButton(key: "assistant.clear", symbol: "arrow.counterclockwise") {
                        assistant.clearConversation()
                        matches = AssistantSelection()
                        searchSubmitted = false
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .disabled(!hasConversation)
                    .accessibilityIdentifier("clearConversation")
                }.padding(.horizontal, 18).padding(.top, 4)
            }
        }
        .accessibilityAction(.escape) { navigation.assistantExpanded = false }
        .blueConfirmation(isPresented: $reviewingDeletion, title: l("delete.confirm")) {
            let action = deletionAction
            deletionAction = nil
            Task {
                do { try await action?() } catch {
                    assistant.result = .message((error as? BlueError ?? .saveFailed).key)
                }
            }
        }
        .task(id: connectionRetry) {
            if (assistant.testMode && !voiceFixture) || assistant.usesLibrarySearch { chat = true }
            await assistant.refreshConnection()
        }
        .task(id: assistant.connectionStatus) {
            switch assistant.connectionStatus {
            case .ready:
                if chat {
                    if !reduceMotion { try? await Task.sleep(for: .milliseconds(140)) }
                    if !Task.isCancelled { focused = true }
                } else if live.phase == .idle {
                    startVoice()
                }
            case .needsSetup:
                focused = false
                dictation.stop()
                live.stop()
                guard !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.48).repeatCount(4, autoreverses: true)) { setupPulse = true }
            case .checking, .unavailable:
                focused = false
                live.stop()
            }
        }
        .onChange(of: focused) { _, value in
            if value && isLive { showChat() }
        }
        .onDisappear {
            if !navigation.assistantExpanded { stopAudio() }
        }
        .onChange(of: phase) { _, value in
            if value == .background { stopAudio() }
            if value == .active, isLive, live.phase == .idle { startVoice() }
        }
        .onChange(of: l.language) { _, _ in
            stopAudio()
            if isLive { startVoice() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                == AVAudioSession.InterruptionType.began.rawValue
            {
                stopAudio()
            } else if notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                == AVAudioSession.InterruptionType.ended.rawValue,
                phase == .active, isLive, navigation.assistantExpanded
            {
                startVoice()
            }
        }
        .blueSheet(
            isPresented: Binding(get: { event != nil }, set: { if !$0 { event = nil } }), title: "", ownHeader: true,
            allowsExpansion: false
        ) {
            if let editedEvent { EventEditor(existing: editedEvent, date: editedEvent.date) }
        }
    }
    private var composer: some View {
        @Bindable var assistant = assistant
        let searching = assistant.usesLibrarySearch
        let hasDraft = !assistant.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(alignment: .bottom, spacing: 3) {
            TextField(
                l(
                    dictation.recording
                        ? "dictation.listening" : searching ? "assistant.searchLibrary" : "assistant.placeholder"),
                text: $assistant.input, axis: .vertical
            )
            .lineLimit(1...4)
            .focused($focused).submitLabel(searching ? .search : .send).onSubmit(submit)
            .onKeyPress(.return) {
                submit()
                return .handled
            }
            .onChange(of: assistant.input) { old, value in
                if value == old + "\n" {
                    assistant.input = old
                    submit()
                }
            }
            .padding(.vertical, 11)
            .accessibilityIdentifier("assistantInput")
            .disabled(assistant.busy)
            if isLive {
                QuietButton(
                    key: live.muted ? "voice.unmute" : "voice.mute", symbol: live.muted ? "mic.slash.fill" : "mic"
                ) {
                    live.toggleMute()
                }.accessibilityIdentifier("voiceMute")
                QuietButton(key: "voice.exit", symbol: "xmark", action: showChat)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityIdentifier("exitLiveVoice")
            } else {
                QuietButton(
                    key: dictation.recording ? "dictation.stop" : "dictation.start",
                    symbol: dictation.recording ? "stop.circle.fill" : "mic", action: toggleDictation
                ).disabled(assistant.busy || dictation.transcribing).accessibilityIdentifier("assistantMicrophone")
                if assistant.busy {
                    QuietButton(key: "assistant.stop", symbol: "stop.circle.fill") { assistant.cancel() }
                        .accessibilityIdentifier("assistantStop")
                } else if hasDraft {
                    QuietButton(
                        key: searching ? "assistant.searchLibrary" : "assistant.send",
                        symbol: searching ? "magnifyingglass" : "arrow.up.circle.fill", action: submit
                    ).accessibilityIdentifier("assistantSend")
                } else if !searching {
                    QuietButton(key: "voice.start", symbol: "waveform", action: startVoice)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .accessibilityIdentifier("startLiveVoice")
                }
            }
        }.padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 4)
            .background {
                if navigation.keyboardVisible { RoundedRectangle(cornerRadius: 22).fill(.ultraThinMaterial) }
            }
            .padding(.horizontal, 18)
    }

    private func startVoice() {
        focused = false
        chat = false
        dictation.stop()
        #if DEBUG
            if voiceFixture {
                live.startFixture()
                return
            }
        #endif
        guard let connection = AssistantConnection.configured() else { return }
        live.start(
            connection: connection, model: AssistantConnection.voiceModel(for: connection.provider),
            language: l.language,
            onExchange: { assistant.appendVoiceExchange(user: $0, reply: $1) },
            perform: assistant.voiceToolHandler(store: store, alarms: alarms, language: l.language)
        )
    }

    private func showChat() {
        chat = true
        live.stop()
    }

    private func stopAudio() {
        live.stop()
        dictation.stop()
    }

    private func toggleDictation() {
        guard let connection = AssistantConnection.configured() else { return }
        let model = AssistantConnection.transcriptionModel(for: connection.provider)
        let insert: @MainActor (String) -> Void = { text in
            let draft = assistant.input
            assistant.input = draft.isEmpty ? text : draft + " " + text
        }
        if dictation.recording {
            dictation.finish(connection: connection, model: model, language: l.language, onText: insert)
        } else {
            Task { await dictation.start(connection: connection, model: model, language: l.language, onText: insert) }
        }
    }
    private var setupComposer: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            navigation.assistantExpanded = false
            navigation.assistantSetupRequested = true
            navigation.settingsPresented = true
        } label: {
            HStack(spacing: 10) {
                Text(l("assistant.setupRequired")).multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 48)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.blue.opacity(setupPulse ? 0.68 : 0.28), lineWidth: 1)
            }
            .shadow(color: .blue.opacity(setupPulse ? 0.20 : 0), radius: 12)
        }
        .buttonStyle(BlueRowPress(shape: AnyShape(RoundedRectangle(cornerRadius: 18))))
        .accessibilityIdentifier("configureBlue")
        .padding(.horizontal, 18)
    }

    private var response: some View {
        VStack(alignment: .leading, spacing: 12) {
            if assistant.usesLibrarySearch {
                if matches.records.isEmpty && matches.collections.isEmpty && matches.notes.isEmpty
                    && matches.events.isEmpty
                {
                    Text(l("assistant.noResults")).foregroundStyle(.secondary)
                }
                ForEach(matches.collections, id: \.self) { collectionLink($0) }
                records(matches.records, compact: true)
                notes(matches.notes, compact: true)
                events(matches.events)
            } else {
                ForEach(
                    Array(assistant.history.dropLast(assistant.activePrompt == nil ? 1 : 0).enumerated()),
                    id: \.offset
                ) { _, exchange in
                    if !exchange.user.isEmpty { userBubble(exchange.user) }
                    replyBubble { MarkdownView(text: .constant(exchange.reply)) }
                }
                if let question = assistant.activePrompt ?? assistant.history.last?.user, !question.isEmpty {
                    userBubble(question)
                }
                if let result = assistant.result { replyBubble { resultView(result) } }
                if !assistant.streamingText.isEmpty {
                    replyBubble { Text(assistant.streamingText).textSelection(.enabled) }
                } else if assistant.busy {
                    replyBubble {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(l(assistant.localProgressKey ?? "character.\(assistant.state.rawValue)"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 24).padding(.vertical, 6)
    }
    private func userBubble(_ text: String) -> some View {
        Text(text)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: 20))
            .padding(.leading, 32)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func replyBubble<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color.cyan.opacity(0.19), in: RoundedRectangle(cornerRadius: 20))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(.trailing, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func submit() {
        let query = assistant.input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !assistant.busy else { return }
        dictation.stop()
        if assistant.usesLibrarySearch {
            searchSubmitted = true
            func contains(_ value: String) -> Bool { value.localizedStandardContains(query) }
            matches = AssistantSelection(
                records: store.state.records.lazy.filter { contains($0.title) }.prefix(8).map(\.id),
                notes: store.state.notes.lazy.filter {
                    contains(l.text($0.title)) || contains(l.text($0.markdown))
                }
                .prefix(5).map(\.id),
                collections: store.state.collections.lazy.filter { contains(l.text($0.title)) }.prefix(5).map(
                    \.id),
                events: (store.state.events ?? []).lazy.filter { contains($0.title) }.prefix(5).map(\.id))
            assistant.input = ""
        } else {
            assistant.submit(store: store, alarms: alarms, language: l.language)
        }
        focused = false
    }
    private func open(_ route: Route) {
        navigation.assistantExpanded = false
        navigation.open(route)
    }
    @ViewBuilder private func resultView(_ result: AssistantResult) -> some View {
        switch result {
        case .answer(let text): MarkdownView(text: .constant(text))
        case .clarification(let question, let options):
            Text(question)
            ForEach(options, id: \.self) { option in
                Button(option) {
                    dictation.stop()
                    assistant.submit(message: option, store: store, alarms: alarms, language: l.language)
                }.buttonStyle(.bordered).frame(minHeight: 44).disabled(assistant.busy)
            }
        case .localProposal(let proposal):
            Text(proposal.preview(l)).textSelection(.enabled)
            Button(l("local.apply")) {
                assistant.applyLocalProposal(proposal, store: store, alarms: alarms, language: l.language)
            }
            .frame(minHeight: 44).disabled(assistant.busy).accessibilityIdentifier("applyLocalProposal")
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
                switch pending.kind {
                case "event":
                    guard let event = store.state.events?.first(where: { $0.id == pending.id }),
                        event.revision == pending.revision
                    else { throw BlueError.staleRevision }
                    try await alarms.deleteEvent(event)
                case "alarm":
                    guard let alarm = store.state.alarms.first(where: { $0.id == pending.id }),
                        alarm.revision == pending.revision
                    else { throw BlueError.staleRevision }
                    try await alarms.delete(alarm)
                default: try store.confirmDeletion(pending)
                }
                assistant.result = .message("deleted")
            }
        case .alarms(let ids):
            ForEach(ids, id: \.self) { id in
                if let alarm = store.state.alarms.first(where: { $0.id == id }) {
                    Button("\(l.time(alarm.date)) · \(alarm.title)") {
                        navigation.jump(to: alarm)
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
    @ViewBuilder private func records(_ ids: [UUID], fields: [String] = [], compact: Bool = false) -> some View {
        ForEach(ids, id: \.self) { id in
            if let record = store.record(id), let collection = store.collection(record.collectionID) {
                Button {
                    assistant.selectRecord(id)
                    open(.record(id))
                } label: {
                    Text(record.title).font(.title3.weight(.semibold)).frame(
                        maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("result-\(record.title)")
                if !compact {
                    let displayed = Collection(
                        id: collection.id, title: collection.title,
                        fields: fields.isEmpty ? collection.fields : collection.fields.filter { fields.contains($0.id) }
                    )
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
    }
    @ViewBuilder private func notes(_ ids: [UUID], compact: Bool = false) -> some View {
        ForEach(ids, id: \.self) { id in
            if let note = store.state.notes.first(where: { $0.id == id }) {
                Button {
                    assistant.selectNote(id)
                    open(.note(id))
                } label: {
                    Text(l.text(note.title)).font(.title3.weight(.semibold)).frame(minHeight: 44)
                }.buttonStyle(.plain)
                if !compact { Text(l.text(note.markdown)).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }
    @ViewBuilder private func events(_ ids: [UUID]) -> some View {
        ForEach(ids, id: \.self) { id in
            if let value = store.state.events?.first(where: { $0.id == id }) {
                Button {
                    assistant.selectEvent(value.id)
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
                BlueDeleteLabel()
            }
            .frame(minHeight: 44).accessibilityIdentifier("confirmDeletion")
        }
    }
}
