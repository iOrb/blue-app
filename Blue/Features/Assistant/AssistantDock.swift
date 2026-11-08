import SwiftUI

struct AssistantDock: View {
    @Environment(AssistantService.self) private var assistant
    @Environment(LibraryStore.self) private var store
    @Environment(AlarmService.self) private var alarms
    @Environment(NavigationState.self) private var navigation
    @Environment(Localizer.self) private var l
    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        @Bindable var assistant = assistant
        VStack(spacing: 0) {
            if let result = assistant.result {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top) {
                        resultView(result).frame(maxWidth: .infinity, alignment: .leading)
                        QuietButton(key: "close", symbol: "xmark") {
                            assistant.result = nil
                            assistant.state = .idle
                        }
                    }
                }
                .padding(.leading, 20).padding(.trailing, 6).padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            HStack(spacing: 6) {
                BlueCharacter(state: focused && !assistant.busy ? .listening : assistant.state)
                TextField(l("assistant.placeholder"), text: $assistant.input, axis: .vertical)
                    .font(.subheadline).lineLimit(1...3).focused($focused)
                    .submitLabel(.send).onSubmit(submit)
                    .accessibilityIdentifier("assistantInput")
                if assistant.busy {
                    QuietButton(key: "cancel", symbol: "stop.circle") { assistant.cancel() }
                } else if !assistant.input.isEmpty {
                    QuietButton(key: "assistant.send", symbol: "arrow.up.circle.fill", action: submit)
                        .accessibilityIdentifier("assistantSend")
                }
            }.padding(.horizontal, 10).padding(.vertical, 2)
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 27))
        .padding(.horizontal, 14).padding(.bottom, 8)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86), value: assistant.result)
    }
    private func submit() {
        focused = false
        assistant.submit(store: store, alarms: alarms, language: l.language)
    }
    @ViewBuilder private func resultView(_ result: AssistantResult) -> some View {
        switch result {
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
