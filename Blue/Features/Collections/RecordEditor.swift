import SwiftUI

struct RecordEditor: View {
    var recordID: UUID?
    var collectionID: UUID?
    @Environment(LibraryStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    @Environment(AssistantService.self) private var assistant
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Record?
    @State private var title = ""
    @State private var markdown = ""
    @State private var error: String?
    @State private var confirmDelete = false
    @FocusState private var renaming: Bool
    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(close: { dismiss() }) {
                Button(l("rename")) { renaming = true }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label(l("delete"), systemImage: "minus")
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(
                        l("title"),
                        text: Binding(
                            get: { title },
                            set: {
                                title = $0
                                save()
                            })
                    )
                    .font(.title.weight(.bold)).focused($renaming).accessibilityIdentifier("recordTitle")
                    if let draft, let collection = store.collection(draft.collectionID) {
                        PropertyFlow(centered: true) {
                            ForEach(
                                [collection.fields.first { $0.kind == .favorite } ?? .favoriteIndicator]
                                    + collection.fields.filter { $0.kind != .favorite }
                            ) { field in
                                PropertyControl(
                                    field: field,
                                    value: field.kind == .favorite ? .flag(draft.isFavorite) : draft.values[field.id]
                                ) { value in
                                    if field.kind == .favorite { self.draft?.favorite = value?.flag ?? false }
                                    if field.id != "__favorite" { self.draft?.values[field.id] = value }
                                    save()
                                }
                            }
                        }.padding(.vertical, 8)
                        PlainNoteBody(
                            text: Binding(
                                get: { markdown },
                                set: {
                                    markdown = $0
                                    save()
                                }), identifier: "recordBody")
                        ForEach(draft.sources ?? [], id: \.url) { source in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(source.summary).font(.subheadline).foregroundStyle(.secondary)
                                Link(source.title, destination: source.url).font(.footnote)
                            }
                        }
                    }
                    ErrorLine(key: error)
                }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 92).frame(
                    maxWidth: 760, alignment: .leading
                ).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("recordEditor").scrollDismissesKeyboard(.interactively)
        }.background(Color(uiColor: .systemBackground)).modifier(KeyboardDismissToolbar())
            .overlay(alignment: .bottom) {
                if !confirmDelete {
                    BlueNavigation(
                        showsSections: false,
                        ask: {
                            if let draft { assistant.selectRecord(draft.id) }
                            navigation.pendingAssistant = true
                            navigation.detail = nil
                        })
                }
            }
            .blueConfirmation(isPresented: $confirmDelete, title: l("record.confirmDelete")) {
                guard let draft else { return }
                do {
                    try store.confirmDeletion(PendingDeletion(kind: "record", id: draft.id, revision: draft.revision))
                    dismiss()
                } catch { self.error = (error as? BlueError ?? .saveFailed).key }
            }
            .onAppear {
                guard draft == nil else { return }
                if let recordID {
                    draft = store.record(recordID)
                } else if let collectionID {
                    draft = Record(collectionID: collectionID, title: l("untitled"))
                }
                title = draft?.title ?? ""
                markdown = draft.map { l.text($0.markdown) } ?? ""
                if recordID == nil { save() }
            }
            .onChange(of: l.language) { _, _ in if let draft { markdown = l.text(draft.markdown) } }
            .onChange(of: store.record(draft?.id ?? UUID())?.revision) { _, _ in
                guard error == nil, let id = draft?.id, let fresh = store.record(id) else { return }
                draft = fresh
                title = fresh.title
                markdown = l.text(fresh.markdown)
            }
    }
    private func save() {
        guard var next = draft, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        next.title = title
        if markdown != l.text(next.markdown) { next.markdown = .user(markdown) }
        do {
            try store.saveRecord(next, expectedRevision: store.record(next.id) == nil ? nil : next.revision)
            draft = store.record(next.id)
            error = nil
        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
    }
}
