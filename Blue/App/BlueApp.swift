import SwiftUI

@main
struct BlueApp: App {
    @State private var localizer = Localizer()
    @State private var store: LibraryStore?
    @State private var startupFailed = false
    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    BlueRoot(store: store).environment(store)
                } else if startupFailed {
                    ContentUnavailableView(
                        localizer("error.saveFailed"), systemImage: "externaldrive.badge.exclamationmark",
                        description: Text(localizer("startup.recovery")))
                } else {
                    ProgressView().task { start() }
                }
            }
            .environment(localizer)
            .environment(\.locale, localizer.locale)
            .tint(.primary)
        }
    }
    private func start() {
        do {
            #if DEBUG || PERFORMANCE_PROBE
                if ProcessInfo.processInfo.arguments.contains("--uitest-reset") {
                    let base = URL.applicationSupportDirectory.appending(
                        path: "BlueUITests", directoryHint: .isDirectory)
                    try? FileManager.default.removeItem(at: base)
                    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    UserDefaults.standard.removeObject(forKey: "blue.language")
                    localizer.language = .english
                }
                if ProcessInfo.processInfo.arguments.contains("--uitest") {
                    let base = URL.applicationSupportDirectory.appending(
                        path: "BlueUITests", directoryHint: .isDirectory)
                    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    let testStore = try LibraryStore(url: base.appending(path: "library.store"))
                    if ProcessInfo.processInfo.arguments.contains("--stress-data"),
                        testStore.state.records.count < 10_000,
                        let id = testStore.state.collections.first?.id
                    {
                        try testStore.update { state in
                            for index in state.records.count..<10_000 {
                                state.records.append(
                                    Record(
                                        collectionID: id, title: String(format: "Saved item %05d", index),
                                        values: ["rating": .number(Double(index % 11)), "status": .option("watched")]))
                            }
                        }
                    }
                    store = testStore
                    return
                }
            #endif
            store = try LibraryStore(seed: false)
        } catch { startupFailed = true }
    }
}

struct BlueRoot: View {
    @State private var navigation = NavigationState()
    @State private var assistant: AssistantService
    @State private var alarms: AlarmService
    @Environment(Localizer.self) private var l
    @Environment(LibraryStore.self) private var store
    @Environment(\.scenePhase) private var phase
    init(store: LibraryStore) {
        #if DEBUG
            _assistant = State(
                initialValue: AssistantService(testMode: ProcessInfo.processInfo.arguments.contains("--test-assistant"))
            )
        #else
            _assistant = State(initialValue: AssistantService())
        #endif
        _alarms = State(initialValue: AlarmService(store: store))
    }
    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.path) {
            LibraryView()
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .collection(let id): CollectionView(collectionID: id)
                    case .record(let id): RecordEditor(recordID: id)
                    case .newRecord(let id): RecordEditor(collectionID: id)
                    case .note(let id): NoteEditor(noteID: id)
                    case .newNote: NoteEditor()
                    case .newCollection: CollectionCreator()
                    case .collectionSettings(let id): CollectionSettings(collectionID: id)
                    }
                }
        }
        .overlay(alignment: .bottom) {
            if !navigation.assistantExpanded && navigation.detail == nil && navigation.presentations.isEmpty {
                BlueNavigation(showsSections: navigation.path.isEmpty)
            }
        }
        .blueSheet(
            isPresented: Binding(get: { navigation.detail != nil }, set: { if !$0 { navigation.detail = nil } }),
            title: "",
            onDismiss: {
                if navigation.pendingAssistant {
                    navigation.pendingAssistant = false
                    navigation.assistantFocused = true
                    navigation.assistantExpanded = true
                }
            }
        ) {
            switch navigation.detail {
            case .record(let id): RecordEditor(recordID: id)
            case .newRecord(let id): RecordEditor(collectionID: id)
            case .note(let id): NoteEditor(noteID: id)
            case .newNote: NoteEditor()
            default: EmptyView()
            }
        }
        .blueSheet(isPresented: $navigation.assistantExpanded, title: "") { AssistantDock() }
        .environment(navigation).environment(assistant).environment(alarms)
        .onChange(of: navigation.tab) { _, _ in
            navigation.assistantFocused = false
            navigation.assistantExpanded = false
        }
        .task {
            alarms.reconcile()
            await alarms.observe()
        }
        .onChange(of: phase) { _, phase in if phase == .active { alarms.reconcile() } }
        .onChange(of: navigation.path) { _, path in
            if path.isEmpty { assistant.selectSurface(navigation.scope) }
            if case .note(let id) = path.last { assistant.selectNote(id) }
            if case .record(let id) = path.last { assistant.selectRecord(id) }
            if case .collection(let id) = path.last { assistant.selectCollection(id, store: store) }
        }
        .onChange(of: assistant.result) { _, result in
            if case .collectionView(let id, let query) = result { navigation.queries[id] = query }
        }
        .onChange(of: navigation.detail) { _, route in
            if case .note(let id) = route { assistant.selectNote(id) }
            if case .record(let id) = route { assistant.selectRecord(id) }
        }
        .onChange(of: navigation.scope) { _, scope in assistant.selectSurface(scope) }
        .onChange(of: navigation.selectedDate) { _, date in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            assistant.selectedDay = formatter.string(from: date)
        }
        .onChange(of: l.language) { _, _ in assistant.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in alarms.reconcile() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in alarms.reconcile() }
    }

}

struct BlueNavigation: View {
    var showsSections = true
    var ask: (() -> Void)? = nil
    @Environment(NavigationState.self) private var navigation
    @Environment(AssistantService.self) private var assistant
    @Environment(Localizer.self) private var l
    var body: some View {
        HStack(spacing: 12) {
            if showsSections {
                HStack(spacing: 0) {
                    tabButton("notes", key: "tab.notes", symbol: "text.alignleft")
                    tabButton("collections", key: "library.collections", symbol: "square.stack")
                    tabButton("calendar", key: "tab.calendar", symbol: "calendar")
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule()).overlay(Capsule().stroke(.primary.opacity(0.05)))
                .shadow(color: .black.opacity(0.06), radius: 20, y: 6)
            } else {
                Spacer()
            }
            Button {
                if let ask {
                    ask()
                } else {
                    navigation.assistantExpanded = true
                    navigation.assistantFocused = true
                }
            } label: {
                BlueCharacter(state: assistant.state).frame(width: 58, height: 58)
                    .background(Color.blue.opacity(0.09), in: Circle())
                    .overlay(Circle().stroke(Color.blue.opacity(0.16)))
                    .shadow(color: .blue.opacity(0.16), radius: 12, y: 4)
            }
            .buttonStyle(.plain).accessibilityLabel(l("library.askBlue")).accessibilityIdentifier("askBlue")
        }
        .padding(.horizontal, 18).padding(.bottom, 6)
    }
    private func tabButton(_ scope: String, key: String, symbol: String) -> some View {
        Button {
            navigation.scope = scope
            navigation.tab = scope == "calendar" ? 1 : 0
            navigation.path = []
            navigation.assistantExpanded = false
        } label: {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(l(key)).font(.caption2).dynamicTypeSize(...DynamicTypeSize.xxxLarge).lineLimit(1)
                    .minimumScaleFactor(0.65)
            }.frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(navigation.scope == scope ? Color.primary : Color.secondary)
        }.buttonStyle(.plain).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle())
            .accessibilityIdentifier("scope-\(scope)")
    }
}
