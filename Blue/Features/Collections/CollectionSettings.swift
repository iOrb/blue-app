import SwiftUI

struct CollectionCreator: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @State private var title = ""
    @State private var error: String?
    var body: some View {
        Form {
            TextField(l("title"), text: $title).accessibilityIdentifier("collectionTitle")
            Label(l("collection.growsWithYou"), systemImage: "sparkle")
                .font(.subheadline).foregroundStyle(.secondary)
            ErrorLine(key: error)
        }
        .modifier(KeyboardDismissToolbar()).navigationTitle(l("collection.new")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("create")) {
                    do {
                        let id = try store.createCollection(title: title, fields: [])
                        navigation.path.removeLast()
                        navigation.path.append(.collection(id))
                    } catch { self.error = (error as? BlueError ?? .saveFailed).key }
                }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty).accessibilityIdentifier(
                    "collectionCreate")
            }
        }
    }
}

struct CollectionSettings: View {
    let collectionID: UUID
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Collection?
    @State private var title = ""
    @State private var originalTitle = ""
    @State private var editingField: FieldDefinition?
    @State private var error: String?
    @State private var confirmSave = false
    @State private var confirmDelete = false
    var body: some View {
        Form {
            TextField(l("title"), text: $title)
            if let draft {
                TextField(l("field.icon"), text: Binding(get: { draft.symbol }, set: { self.draft?.symbol = $0 }))
                Section(l("collection.properties")) {
                    ForEach(draft.fields) { field in
                        Button {
                            editingField = field
                        } label: {
                            HStack {
                                Text(l.text(field.label))
                                Spacer()
                                Text(l(field.kind.labelKey)).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption)
                            }
                        }
                    }.onDelete { indices in self.draft?.fields.remove(atOffsets: indices) }
                    Button(l("field.new"), systemImage: "plus") {
                        editingField = FieldDefinition(id: UUID().uuidString, label: .user(""), kind: .text)
                    }.disabled(draft.fields.count >= 12)
                }
                Section { Button(l("collection.delete"), role: .destructive) { confirmDelete = true } }
            }
            ErrorLine(key: error)
        }
        .modifier(KeyboardDismissToolbar()).navigationTitle(l("collection.properties")).navigationBarTitleDisplayMode(
            .inline
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("save")) {
                    if losesValues { confirmSave = true } else { save() }
                }
            }
        }
        .sheet(item: $editingField) { field in
            NavigationStack {
                FieldEditor(field: field) { updated in
                    if let index = draft?.fields.firstIndex(where: { $0.id == updated.id }) {
                        draft?.fields[index] = updated
                    } else {
                        draft?.fields.append(updated)
                    }
                }
            }
        }
        .confirmationDialog(l("field.confirmMigration"), isPresented: $confirmSave, titleVisibility: .visible) {
            Button(l("save"), role: .destructive, action: save)
        }
        .confirmationDialog(l("collection.confirmDelete"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(l("delete"), role: .destructive) {
                do {
                    try store.update { state in
                        state.records.removeAll { $0.collectionID == collectionID }
                        state.collections.removeAll { $0.id == collectionID }
                    }
                    navigation.path = []
                } catch { self.error = BlueError.saveFailed.key }
            }
        }
        .onAppear {
            if draft == nil {
                draft = store.collection(collectionID)
                title = draft.map { l.text($0.title) } ?? ""
                originalTitle = title
            }
        }
        .onChange(of: l.language) { _, _ in
            if title == originalTitle, let label = draft?.title {
                title = l.text(label)
                originalTitle = title
            }
        }
    }
    private var losesValues: Bool {
        guard let draft else { return false }
        return store.records(in: collectionID).contains { record in
            record.values.contains { id, value in
                guard let field = draft.fields.first(where: { $0.id == id }) else { return true }
                return (try? Validation.field(field, value: value)) == nil
            }
        }
    }
    private func save() {
        guard var draft else { return }
        do {
            try Validation.title(title)
            if title != originalTitle { draft.title = .user(title) }
            try store.saveCollection(draft)
            dismiss()
        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
    }
}

struct FieldEditor: View {
    @State var field: FieldDefinition
    let onSave: (FieldDefinition) -> Void
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var en = ""
    @State private var es = ""
    @State private var optionsEn = ""
    @State private var optionsEs = ""
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        Form {
            TextField(l("field.englishLabel"), text: $en)
            TextField(l("field.spanishLabel"), text: $es)
            Picker(l("field.type"), selection: $field.kind) {
                ForEach(FieldKind.allCases, id: \.self) { kind in Text(l(kind.labelKey)).tag(kind) }
            }
            TextField(
                l("field.icon"), text: Binding(get: { field.icon ?? "" }, set: { field.icon = $0.isEmpty ? nil : $0 })
            )
            .accessibilityIdentifier("propertyIcon")
            if field.kind.isBoolean {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44, maximum: 44))], alignment: .leading) {
                    ForEach(IndicatorTint.allCases, id: \.self) { tint in
                        Button {
                            field.tint = tint
                        } label: {
                            Circle().fill(tint.color).frame(width: 24, height: 24)
                                .overlay {
                                    if field.tint == tint {
                                        Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                    }
                                }
                                .frame(width: 44, height: 44)
                        }.buttonStyle(.plain).accessibilityLabel(l("color.\(tint.rawValue)"))
                    }
                }
            }
            Toggle(l("field.showInRow"), isOn: $field.showInRow)
            if field.kind == .status {
                Section(l("field.options")) {
                    TextField(l("field.englishOptions"), text: $optionsEn)
                    TextField(l("field.spanishOptions"), text: $optionsEs)
                }
            }
            ErrorLine(key: error)
        }
        .modifier(KeyboardDismissToolbar()).navigationTitle(l("field.edit")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { QuietButton(key: "close", symbol: "xmark") { dismiss() } }
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("save")) {
                    guard !en.trimmingCharacters(in: .whitespaces).isEmpty,
                        !es.trimmingCharacters(in: .whitespaces).isEmpty
                    else {
                        error = BlueError.invalidValue.key
                        return
                    }
                    field.label = .bilingual(en, es)
                    if field.kind == .status {
                        let english = optionsEn.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        let spanish = optionsEs.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        guard !english.isEmpty, english.count == spanish.count, english.count <= 12 else {
                            error = BlueError.invalidValue.key
                            return
                        }
                        field.options = zip(english, spanish).enumerated().map { index, labels in
                            FieldOption(
                                id: index < field.options.count ? field.options[index].id : UUID().uuidString,
                                label: .bilingual(labels.0, labels.1))
                        }
                    } else {
                        field.options = []
                    }
                    onSave(field)
                    dismiss()
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let english = Localizer(language: .english)
            let spanish = Localizer(language: .spanish)
            en = english.text(field.label)
            es = spanish.text(field.label)
            optionsEn = field.options.map { english.text($0.label) }.joined(separator: ", ")
            optionsEs = field.options.map { spanish.text($0.label) }.joined(separator: ", ")
        }
    }
}
