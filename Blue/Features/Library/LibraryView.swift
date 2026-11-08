import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @State private var newEvent = false
    private var scope: String { navigation.scope }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                if scope == "all" || scope == "collections" {
                    VStack(alignment: .leading, spacing: 8) {
                        heading("library.collections")
                        ForEach(store.state.collections) { collection in
                            Button {
                                navigation.path.append(.collection(collection.id))
                            } label: {
                                HStack(spacing: 14) {
                                    ItemGlyph(symbol: collection.symbol).foregroundStyle(.secondary).frame(width: 28)
                                    Text(l.text(collection.title)).font(.title3.weight(.medium))
                                    Spacer()
                                    Text("\(store.records(in: collection.id).count)").font(.subheadline)
                                        .foregroundStyle(.tertiary)
                                }.frame(minHeight: 64).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier(
                                "collection-\(collection.title.key ?? collection.title.english)")
                            Divider().overlay(Color.primary.opacity(0.02))
                        }
                    }
                }
                if scope == "all" || scope == "notes" {
                    VStack(alignment: .leading, spacing: 8) {
                        heading("tab.notes")
                        ForEach(store.state.notes.sorted { $0.updatedAt > $1.updatedAt }) { note in
                            Button {
                                navigation.path.append(.note(note.id))
                            } label: {
                                Text(l.text(note.title)).font(.title3.weight(.medium))
                                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).contentShape(
                                        Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("note-\(l.text(note.title))")
                            Divider()
                        }
                    }
                }
                if scope == "all" || scope == "calendar" {
                    VStack(alignment: .leading, spacing: 20) {
                        heading("tab.calendar")
                        CalendarView(showAdd: scope != "calendar")
                    }
                }
                ErrorLine(key: navigation.noticeKey)
            }.padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 28)
                .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground)).scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(l("app.name")) {
                    navigation.scope = "all"
                    navigation.tab = 0
                }
                .font(.title3.weight(.bold)).accessibilityIdentifier("homeBlue")
            }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) { SettingsButton() }.sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                if scope == "calendar" {
                    QuietButton(key: "event.new", symbol: "plus") { newEvent = true }.accessibilityIdentifier(
                        "newEvent")
                } else {
                    Menu {
                        NavigationLink(value: Route.newNote) { Label(l("note.new"), systemImage: "text.alignleft") }
                        NavigationLink(value: Route.newCollection) {
                            Label(l("collection.new"), systemImage: "square.stack")
                        }
                        Button {
                            newEvent = true
                        } label: {
                            Label(l("event.new"), systemImage: "calendar.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel(l("create")).accessibilityIdentifier("createMenu")
                }
            }.sharedBackgroundVisibility(.hidden)
        }
        .blueSheet(isPresented: $newEvent, title: l("event.new")) { EventEditor(date: navigation.selectedDate) }
    }
    private func heading(_ key: String) -> some View {
        Text(l(key)).font(.system(.largeTitle).weight(.bold)).tracking(-1.3)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
    }
}
