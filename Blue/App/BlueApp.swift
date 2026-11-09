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
            let library = try LibraryStore(seed: false)
            #if DEBUG && !targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains("--restore-local-library") {
                    let backup = URL.temporaryDirectory.appending(path: "Blue-library-import.json")
                    try library.importBackup(Data(contentsOf: backup, options: .mappedIfSafe))
                    try? FileManager.default.removeItem(at: backup)
                }
            #endif
            store = library
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
            TabView(selection: tabSelection) {
                Tab(
                    l(LibrarySection.notes.titleKey), systemImage: "text.alignleft",
                    value: LibrarySection.notes.rawValue
                ) {
                    library(.notes)
                }
                Tab(
                    l(LibrarySection.collections.titleKey), systemImage: "square.stack",
                    value: LibrarySection.collections.rawValue
                ) {
                    library(.collections)
                }
                Tab(
                    l(LibrarySection.calendar.titleKey), systemImage: "calendar",
                    value: LibrarySection.calendar.rawValue
                ) {
                    library(.calendar)
                }
                Tab(l("library.askBlue"), image: "BlueTabIcon", value: "blue", role: blueTabRole) {
                    Color.clear.accessibilityHidden(true)
                }
            }
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
        .overlay(alignment: .bottomTrailing) {
            if !navigation.path.isEmpty && showsNavigation {
                BlueButton().padding(.trailing, 18).padding(.bottom, 6)
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
        .blueSheet(isPresented: $navigation.assistantExpanded, title: "", fitsContent: true) { AssistantDock() }
        .environment(navigation).environment(assistant).environment(alarms)
        .onChange(of: navigation.section) { _, section in
            navigation.assistantFocused = false
            navigation.assistantExpanded = false
            assistant.selectSurface(section.rawValue)
        }
        .task {
            alarms.reconcile()
            await alarms.observe()
        }
        .onChange(of: phase) { _, phase in if phase == .active { alarms.reconcile() } }
        .onChange(of: navigation.path) { _, path in
            if path.isEmpty { assistant.selectSurface(navigation.section.rawValue) }
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
        .onChange(of: navigation.selectedDate) { _, date in
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            assistant.selectedDay = formatter.string(from: date)
        }
        .onChange(of: l.language) { _, _ in assistant.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in alarms.reconcile() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in alarms.reconcile() }
    }
    private var showsNavigation: Bool {
        !navigation.assistantExpanded && navigation.detail == nil && navigation.presentations.isEmpty
    }
    private var blueTabRole: TabRole {
        if #available(iOS 27.0, *) { return .prominent }
        return .search
    }
    private func library(_ section: LibrarySection) -> some View {
        LibraryView(section: section)
            .toolbar(showsNavigation ? .visible : .hidden, for: .tabBar)
    }
    private var tabSelection: Binding<String> {
        Binding(
            get: { navigation.section.rawValue },
            set: { value in
                if value == "blue" {
                    navigation.assistantFocused = true
                    navigation.assistantExpanded = true
                } else if let section = LibrarySection(rawValue: value) {
                    navigation.path = []
                    navigation.section = section
                }
            })
    }
}

struct BlueButton: View {
    var ask: (() -> Void)? = nil
    @Environment(NavigationState.self) private var navigation
    @Environment(AssistantService.self) private var assistant
    @Environment(Localizer.self) private var l
    var body: some View {
        Button {
            if let ask {
                ask()
            } else {
                navigation.assistantFocused = true
                navigation.assistantExpanded = true
            }
        } label: {
            BlueCharacter(state: assistant.state).frame(width: 58, height: 58)
                .glassEffect(.regular.tint(Color.blue.opacity(0.12)).interactive(), in: Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(l("library.askBlue")).accessibilityIdentifier("askBlue")
    }
}
