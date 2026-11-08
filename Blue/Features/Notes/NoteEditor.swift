import SwiftUI

struct NoteEditor: View {
    var noteID: UUID?
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var markdown = ""
    @State private var initialTitle = ""
    @State private var initialMarkdown = ""
    @State private var favorite = false
    @State private var original: Note?
    @State private var loaded = false
    @State private var preview = false
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    var body: some View {
        Form {
            TextField(l("title"), text: $title).font(.title2.weight(.medium)).accessibilityIdentifier("noteTitle")
            IndicatorControl(field: .favoriteIndicator, selected: favorite, showsLabel: true) {
                favorite.toggle()
            }.accessibilityIdentifier("noteFavorite")
            Section {
                if preview {
                    MarkdownView(text: $markdown)
                } else {
                    TextEditor(text: $markdown).frame(minHeight: 280).font(.body.monospaced()).accessibilityLabel(
                        l("note.markdown")
                    ).accessibilityIdentifier("noteBody")
                }
            }
            ErrorLine(key: error)
            if noteID != nil { Button(l("note.delete"), role: .destructive) { confirmDelete = true } }
        }
        .modifier(KeyboardDismissToolbar()).navigationTitle(l("note.editor")).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(l("cancel")) {
                    if title != initialTitle || markdown != initialMarkdown || favorite != (original?.favorite ?? false)
                    {
                        confirmDiscard = true
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    preview.toggle()
                } label: {
                    Image(systemName: preview ? "pencil" : "eye")
                }.accessibilityLabel(l(preview ? "edit" : "preview")).accessibilityIdentifier("noteToggleEdit")
            }
            ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("save"), action: save).accessibilityIdentifier("noteSave")
            }
        }
        .confirmationDialog(l("discard.title"), isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button(l("discard"), role: .destructive) { dismiss() }
        }
        .confirmationDialog(l("note.confirmDelete"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(l("delete"), role: .destructive) {
                do {
                    try store.update { $0.notes.removeAll { $0.id == noteID } }
                    dismiss()
                } catch { self.error = BlueError.saveFailed.key }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            original = store.state.notes.first { $0.id == noteID }
            preview = noteID != nil
            title = original.map { l.text($0.title) } ?? ""
            markdown = original.map { l.text($0.markdown) } ?? ""
            favorite = original?.favorite ?? false
            initialTitle = title
            initialMarkdown = markdown
        }
        .onChange(of: store.state.notes.first { $0.id == noteID }?.revision) { _, _ in
            guard let fresh = store.state.notes.first(where: { $0.id == noteID }),
                title == initialTitle, markdown == initialMarkdown, favorite == (original?.favorite ?? false)
            else { return }
            original = fresh
            title = l.text(fresh.title)
            markdown = l.text(fresh.markdown)
            favorite = fresh.favorite ?? false
            initialTitle = title
            initialMarkdown = markdown
        }
        .onChange(of: l.language) { _, _ in
            if title == initialTitle, let text = original?.title {
                title = l.text(text)
                initialTitle = title
            }
            if markdown == initialMarkdown, let text = original?.markdown {
                markdown = l.text(text)
                initialMarkdown = markdown
            }
        }
    }
    private func save() {
        do {
            try Validation.title(title)
            let note = Note(
                id: noteID ?? UUID(),
                title: title == initialTitle ? original?.title ?? .user(title) : .user(title),
                markdown: markdown == initialMarkdown ? original?.markdown ?? .user(markdown) : .user(markdown),
                favorite: favorite,
                revision: original?.revision ?? 0)
            try store.saveNote(note, expectedRevision: original?.revision)
            dismiss()
        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
    }
}

struct MarkdownView: View {
    @Binding var text: String
    @Environment(Localizer.self) private var l
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(text.components(separatedBy: "\n").enumerated()), id: \.offset) { index, line in
                if line.hasPrefix("- [ ] ") || line.hasPrefix("- [x] ") {
                    Button {
                        var lines = text.components(separatedBy: "\n")
                        lines[index] = (line.hasPrefix("- [x]") ? "- [ ] " : "- [x] ") + line.dropFirst(6)
                        text = lines.joined(separator: "\n")
                    } label: {
                        HStack(alignment: .top) {
                            Image(systemName: line.hasPrefix("- [x]") ? "checkmark.circle.fill" : "circle")
                            inline(String(line.dropFirst(6)))
                        }
                    }.buttonStyle(.plain).accessibilityValue(l(line.hasPrefix("- [x]") ? "yes" : "no"))
                } else if line.hasPrefix("### ") {
                    inline(String(line.dropFirst(4))).font(.headline)
                } else if line.hasPrefix("## ") {
                    inline(String(line.dropFirst(3))).font(.title3.weight(.semibold))
                } else if line.hasPrefix("# ") {
                    inline(String(line.dropFirst(2))).font(.title2.weight(.semibold))
                } else if line.hasPrefix("> ") {
                    inline(String(line.dropFirst(2))).foregroundStyle(.secondary).padding(.leading, 14).overlay(
                        alignment: .leading
                    ) { Rectangle().fill(.tertiary).frame(width: 2) }
                } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                    HStack(alignment: .top) {
                        Text("•")
                        inline(String(line.dropFirst(2)))
                    }
                } else if line.hasPrefix("|") {
                    if !line.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "-", with: "")
                        .replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces).isEmpty
                    {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(line.split(separator: "|").enumerated()), id: \.offset) { _, cell in
                                inline(String(cell).trimmingCharacters(in: .whitespaces))
                            }
                        }.padding(.vertical, 5)
                    }
                } else if line.isEmpty {
                    Color.clear.frame(height: 4)
                } else {
                    inline(line)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled).padding(.vertical, 8)
    }
    private func inline(_ string: String) -> Text {
        Text(
            (try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(string))
    }
}
