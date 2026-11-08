import SwiftUI

struct RecordEditor: View {
    var recordID: UUID?
    var collectionID: UUID?
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Record?
    @State private var markdown = ""
    @State private var originalMarkdown = ""
    @State private var error: String?
    @State private var preview = false
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    private var changed: Bool { draft != recordID.flatMap(store.record) || markdown != originalMarkdown }
    var body: some View {
        Group {
            if let draft, let collection = store.collection(draft.collectionID) {
                Form {
                    Section {
                        TextField(l("title"), text: recordBinding(\.title)).font(.title2.weight(.medium))
                            .accessibilityIdentifier("recordTitle")
                    }
                    if !collection.fields.isEmpty {
                        Section {
                            ForEach(collection.fields) { field in
                                FieldValueEditor(field: field, value: valueBinding(field.id))
                            }
                        }
                    }
                    Section {
                        if preview {
                            MarkdownView(text: $markdown)
                        } else {
                            TextEditor(text: $markdown).frame(minHeight: 180).accessibilityLabel(l("note.markdown"))
                                .accessibilityIdentifier("recordMarkdown")
                        }
                    } header: {
                        HStack {
                            Text(l("record.personalNote"))
                            Spacer()
                            Button(l(preview ? "edit" : "preview")) { preview.toggle() }.textCase(nil)
                        }
                    }
                    ErrorLine(key: error)
                    if recordID != nil {
                        Section { Button(l("record.delete"), role: .destructive) { confirmDelete = true } }
                    }
                }
                .modifier(KeyboardDismissToolbar()).navigationTitle(
                    l(recordID == nil ? "record.new" : "record.details"))
            } else {
                ProgressView()
            }
        }
        .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(l("cancel")) { if changed { confirmDiscard = true } else { dismiss() } }
            }
            ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("save"), action: save).fontWeight(.semibold).accessibilityIdentifier("recordSave")
            }
        }
        .confirmationDialog(l("discard.title"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(l("discard"), role: .destructive) { dismiss() }
        }
        .confirmationDialog(l("record.confirmDelete"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(l("delete"), role: .destructive) {
                do {
                    try store.update { $0.records.removeAll { $0.id == recordID } }
                    dismiss()
                } catch { self.error = BlueError.saveFailed.key }
            }
        }
        .onAppear {
            guard draft == nil else { return }
            if let recordID {
                draft = store.record(recordID)
            } else if let collectionID {
                draft = Record(collectionID: collectionID, title: "")
            }
            markdown = draft.map { l.text($0.markdown) } ?? ""
            originalMarkdown = markdown
        }
        .onChange(of: l.language) { _, _ in
            if markdown == originalMarkdown, let text = draft?.markdown, text.key != nil {
                markdown = l.text(text)
                originalMarkdown = markdown
            }
        }
    }
    private func recordBinding<T>(_ keyPath: WritableKeyPath<Record, T>) -> Binding<T> {
        Binding(get: { draft![keyPath: keyPath] }, set: { draft?[keyPath: keyPath] = $0 })
    }
    private func valueBinding(_ id: String) -> Binding<FieldValue?> {
        Binding(get: { draft?.values[id] }, set: { draft?.values[id] = $0 })
    }
    private func save() {
        guard var record = draft else { return }
        if markdown != originalMarkdown { record.markdown = .user(markdown) }
        do {
            try store.saveRecord(record, expectedRevision: recordID == nil ? nil : record.revision)
            dismiss()
        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
    }
}

struct FieldValueEditor: View {
    let field: FieldDefinition
    @Binding var value: FieldValue?
    @Environment(Localizer.self) private var l
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        switch field.kind {
        case .text:
            TextField(
                l.text(field.label),
                text: Binding(get: { value?.text ?? "" }, set: { value = $0.isEmpty ? nil : .text($0) }),
                axis: .vertical)
        case .number, .rating:
            let layout =
                textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
            layout {
                Text(l.text(field.label))
                if !textSize.isAccessibilitySize { Spacer() }
                TextField(
                    l("value.empty"),
                    value: Binding<Double?>(get: { value?.number }, set: { value = $0.map(FieldValue.number) }),
                    format: .number.locale(l.locale)
                )
                .keyboardType(.decimalPad).multilineTextAlignment(textSize.isAccessibilitySize ? .leading : .trailing)
                .frame(minWidth: 70)
                .accessibilityLabel(l.text(field.label)).accessibilityIdentifier("field-\(field.id)")
            }
        case .status:
            Picker(
                l.text(field.label),
                selection: Binding(get: { value?.text ?? "" }, set: { value = $0.isEmpty ? nil : .option($0) })
            ) {
                Text(l("value.empty")).tag("")
                ForEach(field.options) { option in Text(l.text(option.label)).tag(option.id) }
            }.accessibilityIdentifier("field-\(field.id)")
        case .checkbox, .favorite, .like:
            Toggle(l.text(field.label), isOn: Binding(get: { value?.flag ?? false }, set: { value = .flag($0) }))
        case .date:
            if case .date(let date) = value {
                DatePicker(
                    l.text(field.label), selection: Binding(get: { date }, set: { value = .date($0) }),
                    displayedComponents: .date)
                Button(l("field.clear")) { value = nil }.font(.caption)
            } else {
                Button(l.format("field.addDate", l.text(field.label))) { value = .date(Date()) }
            }
        case .tags:
            TextField(
                l.text(field.label),
                text: Binding(
                    get: { value?.text ?? "" },
                    set: {
                        value =
                            $0.isEmpty
                            ? nil : .tags($0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                    }))
        }
    }
}
