import SwiftUI

struct NoteEditor: View {
    var noteID: UUID?
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Note?
    @State private var title = ""
    @State private var markdown = ""
    @State private var error: String?
    @State private var confirmDelete = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let draft {
                    IndicatorControl(field: .favoriteIndicator, selected: draft.favorite == true) {
                        self.draft?.favorite = !(draft.favorite ?? false)
                        save()
                    }.accessibilityIdentifier("noteFavorite")
                    EditableMarkdown(
                        text: Binding(
                            get: { markdown },
                            set: {
                                markdown = $0
                                save()
                            }))
                }
                ErrorLine(key: error)
            }.padding(24).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }.scrollDismissesKeyboard(.interactively).background(Color(uiColor: .systemBackground))
            .navigationBarTitleDisplayMode(.inline).modifier(KeyboardDismissToolbar())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    TextField(
                        l("title"),
                        text: Binding(
                            get: { title },
                            set: {
                                title = $0
                                save()
                            })
                    )
                    .font(.title2.weight(.semibold)).accessibilityIdentifier("noteTitle")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    QuietButton(key: "delete", symbol: "trash") { confirmDelete = true }
                }.sharedBackgroundVisibility(.hidden)
            }
            .confirmationDialog(l("note.confirmDelete"), isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(l("delete"), role: .destructive) {
                    guard let draft else { return }
                    do {
                        try store.confirmDeletion(PendingDeletion(kind: "note", id: draft.id, revision: draft.revision))
                        dismiss()
                    } catch { self.error = (error as? BlueError ?? .saveFailed).key }
                }
            }
            .onAppear {
                guard draft == nil else { return }
                draft =
                    store.state.notes.first { $0.id == noteID }
                    ?? Note(title: .user(l("untitled")), markdown: .user(""))
                title = draft.map { l.text($0.title) } ?? ""
                markdown = draft.map { l.text($0.markdown) } ?? ""
                if noteID == nil { save() }
            }
            .onChange(of: l.language) { _, _ in
                guard let draft else { return }
                title = l.text(draft.title)
                markdown = l.text(draft.markdown)
            }
            .onChange(of: store.state.notes.first { $0.id == draft?.id }?.revision) { _, _ in
                guard error == nil, let fresh = store.state.notes.first(where: { $0.id == draft?.id }) else { return }
                draft = fresh
                title = l.text(fresh.title)
                markdown = l.text(fresh.markdown)
            }
    }
    private func save() {
        guard var next = draft, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if title != l.text(next.title) { next.title = .user(title) }
        if markdown != l.text(next.markdown) { next.markdown = .user(markdown) }
        do {
            try store.saveNote(
                next, expectedRevision: store.state.notes.contains { $0.id == next.id } ? next.revision : nil)
            draft = store.state.notes.first { $0.id == next.id }
            error = nil
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
