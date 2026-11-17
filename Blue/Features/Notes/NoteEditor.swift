import SwiftUI

struct NoteEditor: View {
    var noteID: UUID?
    @Environment(LibraryStore.self) private var store
    @Environment(NavigationState.self) private var navigation
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Note?
    @State private var title = ""
    @State private var markdown = ""
    @State private var error: String?
    @FocusState private var focus: Field?
    private enum Field { case title, body }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                QuietButton(key: "back", symbol: "chevron.left") { dismiss() }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityIdentifier("noteBack")
                Spacer()
            }.padding(.horizontal, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(
                        "",
                        text: Binding(
                            get: { title },
                            set: {
                                title = $0
                                save()
                            })
                    )
                    .font(.title2.bold()).focused($focus, equals: .title)
                    .onSubmit { focus = .body }
                    .accessibilityLabel(l("title")).accessibilityIdentifier("noteTitle")
                    TextField(
                        "",
                        text: Binding(
                            get: { markdown },
                            set: {
                                markdown = $0
                                save()
                            }), axis: .vertical
                    )
                    .lineLimit(8...1000).font(.body).frame(maxWidth: .infinity, alignment: .topLeading)
                    .focused($focus, equals: .body)
                    .accessibilityLabel(l("note.markdown")).accessibilityIdentifier("noteBody")
                    ErrorLine(key: error)
                }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 92).frame(
                    maxWidth: 760, alignment: .leading
                ).frame(maxWidth: .infinity)
            }.accessibilityIdentifier("noteEditor").scrollDismissesKeyboard(.interactively)
        }.background(Color(uiColor: .systemBackground)).modifier(KeyboardDismissToolbar())
            .navigationBarBackButtonHidden(true).toolbar(.hidden, for: .navigationBar)
            .onAppear {
                guard draft == nil else { return }
                if let noteID {
                    draft = store.state.notes.first { $0.id == noteID }
                } else {
                    draft = Note(title: .user(navigation.unnamedNoteTitle), markdown: .user(navigation.unnamedNoteBody))
                }
                title = draft.map { l.text($0.title) } ?? ""
                markdown = draft.map { l.text($0.markdown) } ?? ""
            }
            .onDisappear {
                guard let draft, noteID == nil, !store.state.notes.contains(where: { $0.id == draft.id }) else {
                    return
                }
                navigation.unnamedNoteTitle = title
                navigation.unnamedNoteBody = markdown
            }
            .onChange(of: l.language) { oldLanguage, _ in
                guard let draft else { return }
                let previous = Localizer(language: oldLanguage)
                if title == previous.text(draft.title) { title = l.text(draft.title) }
                if markdown == previous.text(draft.markdown) { markdown = l.text(draft.markdown) }
            }
            .onChange(of: store.state.notes.first { $0.id == draft?.id }?.revision) { _, _ in
                guard error == nil, let current = draft, title == l.text(current.title),
                    markdown == l.text(current.markdown),
                    let fresh = store.state.notes.first(where: { $0.id == current.id })
                else { return }
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
            let revision = store.state.notes.contains { $0.id == next.id } ? next.revision : nil
            try store.saveNote(next, expectedRevision: noteID == nil ? revision : next.revision)
            draft = store.state.notes.first { $0.id == next.id }
            if noteID == nil {
                navigation.unnamedNoteTitle = ""
                navigation.unnamedNoteBody = ""
            }
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
