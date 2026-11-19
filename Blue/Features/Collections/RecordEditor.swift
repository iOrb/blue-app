import SwiftUI

struct RecordEditor: View {
    var recordID: UUID?
    var collectionID: UUID?
    @Environment(LibraryStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    @Environment(\.blueSheetSurface) private var sheetSurface
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blueSheetDismiss) private var sheetDismiss
    @State private var draft: Record?
    @State private var initial: Record?
    @State private var title = ""
    @State private var markdown = ""
    @State private var error: String?
    var body: some View {
        VStack(spacing: 0) {
            BlueSheetHeader(title: "", close: close) {
                if hasChanges {
                    BlueDoneButton {
                        if error != nil { save() }
                        if error == nil { close() }
                    }.accessibilityIdentifier("finishRecord")
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
                    .font(.largeTitle.weight(.bold)).lineLimit(1...3)
                    .accessibilityIdentifier("recordTitle")
                    if let draft, let collection = store.collection(draft.collectionID) {
                        PropertyFlow(centered: true, spacing: 10) {
                            ForEach(
                                [collection.fields.first { $0.kind == .favorite } ?? .favoriteIndicator]
                                    + collection.fields.filter { $0.kind != .favorite }
                            ) { field in
                                if field.kind == .status {
                                    ForEach(field.options.filter { $0.id != field.inactiveStatus }) { option in
                                        property(field, record: draft, option: option)
                                    }
                                } else {
                                    property(field, record: draft)
                                }
                            }
                        }.padding(.vertical, 10)
                        PlainNoteBody(
                            text: Binding(
                                get: { markdown },
                                set: {
                                    markdown = $0
                                    save()
                                }), identifier: "recordBody", minimumLines: 2)
                        ForEach(draft.sources ?? [], id: \.url) { source in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(source.summary).font(.subheadline).foregroundStyle(.secondary)
                                Link(source.title, destination: source.url).font(.footnote)
                            }
                        }
                    }
                    ErrorLine(key: error)
                }.padding(.horizontal, 22).padding(.top, 10).padding(.bottom, 16).frame(
                    maxWidth: 760, alignment: .leading
                ).frame(maxWidth: .infinity).blueSheetContentSize()
            }.accessibilityIdentifier("recordEditor").scrollDismissesKeyboard(.interactively)
        }.background(sheetSurface).modifier(KeyboardDismissToolbar())
            .onAppear {
                guard draft == nil else { return }
                if let recordID {
                    draft = store.record(recordID)
                } else if let collectionID {
                    draft = navigation.unnamedRecords[collectionID] ?? Record(collectionID: collectionID, title: "")
                }
                title = draft?.title ?? ""
                markdown = draft.map { l.text($0.markdown) } ?? ""
                initial = draft
            }
            .onDisappear {
                guard var draft, collectionID != nil, store.record(draft.id) == nil else { return }
                draft.markdown = .user(markdown)
                let hasContent = !markdown.isEmpty || !draft.values.isEmpty || draft.isFavorite
                navigation.unnamedRecords[draft.collectionID] = hasContent ? draft : nil
            }
            .onChange(of: l.language) { _, _ in if let draft { markdown = l.text(draft.markdown) } }
            .onChange(of: store.record(draft?.id ?? UUID())?.revision) { _, _ in
                guard error == nil, let id = draft?.id, let fresh = store.record(id) else { return }
                draft = fresh
                title = fresh.title
                markdown = l.text(fresh.markdown)
            }
    }

    private var hasChanges: Bool {
        guard let initial, let draft, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return title != initial.title || markdown != l.text(initial.markdown)
            || draft.values != initial.values || draft.isFavorite != initial.isFavorite
    }
    private func close() {
        if let sheetDismiss { sheetDismiss() } else { dismiss() }
    }

    private func property(_ field: FieldDefinition, record: Record, option: FieldOption? = nil) -> some View {
        PropertyControl(
            field: field, value: field.kind == .favorite ? .flag(record.isFavorite) : record.values[field.id],
            labeled: true, statusOption: option
        ) { value in
            if field.kind == .favorite { draft?.favorite = value?.flag ?? false }
            if field.id != "__favorite" { draft?.values[field.id] = value }
            save()
        }
    }

    private func save() {
        guard var next = draft, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        next.title = title
        if markdown != l.text(next.markdown) { next.markdown = .user(markdown) }
        do {
            try store.saveRecord(next, expectedRevision: store.record(next.id) == nil ? nil : next.revision)
            draft = store.record(next.id)
            if collectionID != nil { navigation.unnamedRecords.removeValue(forKey: next.collectionID) }
            error = nil
        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
    }
}
