import SwiftUI

struct LibraryView: View {
    let section: LibrarySection
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @State private var newEvent = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch section {
                case .collections:
                    ForEach(store.state.collections) { collection in
                        Button {
                            navigation.open(.collection(collection.id))
                        } label: {
                            HStack(spacing: 14) {
                                ItemGlyph(symbol: collection.symbol).foregroundStyle(.secondary).frame(width: 28)
                                Text(l.text(collection.title)).font(.title3.weight(.medium))
                                Spacer()
                                Text("\(store.records(in: collection.id).count)").font(.subheadline)
                                    .foregroundStyle(.tertiary)
                            }.frame(minHeight: 54).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier(
                            "collection-\(collection.title.key ?? collection.title.english)")
                    }
                case .notes:
                    ForEach(store.state.notes.sorted { $0.updatedAt > $1.updatedAt }) { note in
                        Button {
                            navigation.open(.note(note.id))
                        } label: {
                            Text(l.text(note.title)).font(.title3.weight(.medium))
                                .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).contentShape(
                                    Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("note-\(l.text(note.title))")
                    }
                case .calendar:
                    CalendarView(showAdd: false)
                }
                ErrorLine(key: navigation.noticeKey)
            }.padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 12)
                .frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground)).scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .toolbar(.hidden, for: .navigationBar)
        .blueSheet(isPresented: $newEvent, title: l("event.new")) { EventEditor(date: navigation.selectedDate) }
    }
    private var header: some View {
        HStack(spacing: 4) {
            Text(l(section.titleKey)).font(.largeTitle.bold()).tracking(-1.3)
                .lineLimit(1).minimumScaleFactor(0.55).layoutPriority(1)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("sectionTitle")
            Spacer(minLength: 8)
            SettingsButton().buttonStyle(.plain)
            if section == .calendar {
                QuietButton(key: "event.new", symbol: "plus") { newEvent = true }
                    .accessibilityIdentifier("newEvent")
            } else {
                Menu {
                    Button {
                        navigation.open(.newNote)
                    } label: {
                        Label(l("note.new"), systemImage: "text.alignleft")
                    }
                    Button {
                        navigation.open(.newCollection)
                    } label: {
                        Label(l("collection.new"), systemImage: "square.stack")
                    }
                    Button {
                        newEvent = true
                    } label: {
                        Label(l("event.new"), systemImage: "calendar.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel(l("create")).accessibilityIdentifier("createMenu")
            }
        }
        .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 12)
        .frame(maxWidth: 760).frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
