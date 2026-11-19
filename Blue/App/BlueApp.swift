import SwiftUI

enum BlueAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@main
struct BlueApp: App {
    @AppStorage("blue.appearance") private var appearance: BlueAppearance = .system
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
            .preferredColorScheme(appearance.colorScheme)
        }
    }
    private func start() {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--verify-voice-playback") {
                Task { await LiveVoiceAudio.verifyPlayback() }
            }
            if ProcessInfo.processInfo.arguments.contains("--verify-voice-capture") {
                Task { await LiveVoiceAudio.verifyCapture() }
            }
        #endif
        do {
            #if DEBUG || PERFORMANCE_PROBE
                if ProcessInfo.processInfo.arguments.contains("--uitest-reset") {
                    let base = URL.applicationSupportDirectory.appending(
                        path: "BlueUITests", directoryHint: .isDirectory)
                    try? FileManager.default.removeItem(at: base)
                    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
                    UserDefaults.standard.removeObject(forKey: "blue.language")
                    UserDefaults.standard.removeObject(forKey: "blue.appearance")
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
                    if ProcessInfo.processInfo.arguments.contains("--test-collection-cover"),
                        !testStore.state.collections.contains(where: { $0.title.english == "Cover preview" })
                    {
                        let id = try testStore.createCollection(title: "Cover preview", fields: [])
                        let data = UIGraphicsImageRenderer(size: CGSize(width: 384, height: 384)).pngData { context in
                            UIColor.systemIndigo.setFill()
                            context.fill(CGRect(x: 0, y: 0, width: 384, height: 384))
                            UIColor.systemCyan.setFill()
                            context.cgContext.fillEllipse(in: CGRect(x: 58, y: 58, width: 268, height: 268))
                        }
                        var collection = testStore.collection(id)!
                        collection.artwork = try CollectionArtworkService.prepare(data)
                        try testStore.saveCollection(collection)
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
    @State private var backup = FolderBackupService()
    @State private var drive = GoogleDriveConnection()
    @State private var driveBackup = DriveBackupService()
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
        #if DEBUG && targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--uitest"), arguments.contains("--test-event-scheduling") {
                let fixture = SimulatorEventScheduleFixture(alarms: store.state.alarms)
                _alarms = State(initialValue: AlarmService(store: store, scheduler: fixture, notifications: fixture))
                return
            }
        #endif
        _alarms = State(initialValue: AlarmService(store: store))
    }
    var body: some View {
        TabView(selection: tabSelection) {
            Tab(l(LibrarySection.notes.titleKey), systemImage: "text.alignleft", value: LibrarySection.notes.rawValue) {
                stack(.notes)
            }
            Tab(
                l(LibrarySection.collections.titleKey), systemImage: "square.stack",
                value: LibrarySection.collections.rawValue
            ) {
                stack(.collections)
            }
            Tab(l(LibrarySection.calendar.titleKey), systemImage: "calendar", value: LibrarySection.calendar.rawValue) {
                stack(.calendar)
            }
            Tab(
                l("library.askBlue"), image: navigation.assistantExpanded ? "BlueTabActive" : "BlueTabIcon",
                value: "blue", role: blueTabRole
            ) {
                Color.clear.accessibilityHidden(true)
            }

        }
        .blueSheet(
            isPresented: Binding(get: { navigation.detail != nil }, set: { if !$0 { navigation.detail = nil } }),
            title: "", ownHeader: true
        ) {
            switch navigation.detail {
            case .record(let id): RecordEditor(recordID: id)
            case .newRecord(let id): RecordEditor(collectionID: id)
            default: EmptyView()
            }
        }
        .blueSheet(
            isPresented: Binding(get: { navigation.settingsPresented }, set: { navigation.settingsPresented = $0 }),
            title: l("settings.title"), initialHeight: 500, onDismiss: { navigation.assistantSetupRequested = false }
        ) {
            SettingsView()
        }
        .modifier(BlueChrome())
        .blueSheet(
            isPresented: Binding(
                get: { navigation.collectionArtworkID != nil }, set: { if !$0 { navigation.collectionArtworkID = nil } }
            ), title: "", ownHeader: true,
            onDismiss: {
                if navigation.artworkRequestsSetup {
                    navigation.artworkRequestsSetup = false
                    navigation.assistantSetupRequested = true
                    navigation.settingsPresented = true
                }
            }
        ) {
            if let id = navigation.collectionArtworkID { CollectionArtworkEditor(collectionID: id) }
        }
        .background(KeyboardOutsideTapBridge(active: navigation.keyboardVisible))
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) {
            updateKeyboard(visible: true, notification: $0)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) {
            updateKeyboard(visible: false, notification: $0)
        }
        .environment(navigation).environment(assistant).environment(alarms).environment(backup)
        .environment(drive).environment(driveBackup)
        .task { drive.restore() }
        .onChange(of: store.generation) { _, _ in saveDriveCopy() }
        .onChange(of: drive.hasBackupPermission) { _, allowed in
            if allowed { saveDriveCopy(verify: true) } else { driveBackup.stop() }
        }
        .onChange(of: drive.account) { _, _ in
            driveBackup.stop()
            saveDriveCopy(verify: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in saveDriveCopy()
        }
        .onReceive(NotificationCenter.default.publisher(for: AssistantConnection.credentialsDidChange)) { _ in
            saveDriveCopy()
        }
        .onChange(of: navigation.assistantExpanded) { _, expanded in
            if !expanded { assistant.liveVoice.stop() }
        }
        .onChange(of: navigation.section) { _, section in
            assistant.selectSurface(section.rawValue)
        }
        .task {
            alarms.reconcile()
            await alarms.observe()
        }
        .onChange(of: phase) { _, phase in
            if phase == .active {
                alarms.reconcile()
                drive.restore()
                saveDriveCopy(verify: true)
            }
        }
        .onChange(of: navigation.path) { _, path in
            if let id = navigation.deletingRecordsIn,
                path.last != .collection(id), path.last != .collectionSettings(id)
            {
                navigation.deletingRecordsIn = nil
            }
            if path.isEmpty { assistant.selectSurface(navigation.section.rawValue) }
            if case .note(let id) = path.last { assistant.selectNote(id) }
            if case .record(let id) = path.last { assistant.selectRecord(id) }
            if case .collection(let id) = path.last { assistant.selectCollection(id, store: store) }
        }
        .onChange(of: assistant.result) { _, result in
            if case .collectionView(let id, let query) = result { navigation.queries[id] = query }
        }
        .onChange(of: navigation.detail) { _, route in
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
    private func updateKeyboard(visible: Bool, notification: Notification) {
        let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
        withAnimation(.easeInOut(duration: duration)) { navigation.keyboardVisible = visible }
    }

    private func stack(_ section: LibrarySection) -> some View {
        let path = Binding(
            get: { navigation.section == section ? navigation.path : [] },
            set: { if navigation.section == section { navigation.path = $0 } })
        return NavigationStack(path: path) {
            LibraryView(section: section)
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
        .overlay {
            if navigation.assistantExpanded {
                Rectangle()
                    .fill(.thinMaterial)
                    .mask { BlueEdgeFade(top: 22, bottom: 0, topOpacity: 0.65, bottomOpacity: 1) }
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(!navigation.assistantExpanded)
        .accessibilityHidden(navigation.assistantExpanded)
        .toolbar(navigation.deletingRecordsIn == nil ? .visible : .hidden, for: .tabBar)
    }
    private func saveDriveCopy(verify: Bool = false) {
        guard drive.connected, drive.hasBackupPermission else { return }
        driveBackup.schedule(AppBackupSnapshot.capture(library: store.state), connection: drive, verify: verify)
    }

    private var blueTabRole: TabRole {
        if #available(iOS 27.0, *) { return .prominent }
        return .search
    }

    private var tabSelection: Binding<String> {
        Binding(
            get: { navigation.section.rawValue },
            set: { value in
                if value == "blue" {
                    navigation.assistantExpanded.toggle()
                } else if let section = LibrarySection(rawValue: value) {
                    navigation.assistantExpanded = false
                    navigation.path = []
                    navigation.section = section
                }
            })
    }
}

struct BlueChrome: ViewModifier {
    // Leaves the native tab bar in the same place while content changes above it.
    private let tabClearance: CGFloat = 56
    @Environment(NavigationState.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let showing = navigation.assistantExpanded
        content
            .overlay {
                if showing {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            UIApplication.shared.sendAction(
                                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        }
                        .accessibilityHidden(true)
                        .padding(.bottom, navigation.keyboardVisible ? 0 : tabClearance)
                }
            }
            .overlay {
                if showing {
                    AssistantDock()
                        .padding(.bottom, navigation.keyboardVisible ? 0 : tabClearance)
                        .transition(.identity)
                }
            }
            .animation(.smooth(duration: reduceMotion ? 0.12 : 0.34), value: showing)
    }

}

private struct KeyboardOutsideTapBridge: UIViewRepresentable {
    let active: Bool
    func makeUIView(context: Context) -> KeyboardTapView { KeyboardTapView() }
    func updateUIView(_ uiView: KeyboardTapView, context: Context) {
        uiView.active = active
    }
}

private final class KeyboardTapView: UIView, UIGestureRecognizerDelegate {
    var active = false
    private weak var installedWindow: UIWindow?
    private lazy var recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

    override func didMoveToWindow() {
        super.didMoveToWindow()
        installedWindow?.removeGestureRecognizer(recognizer)
        installedWindow = window
        recognizer.cancelsTouchesInView = false
        recognizer.delegate = self
        window?.addGestureRecognizer(recognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard active else { return false }
        var target = touch.view
        while let view = target {
            if view is UITextField || view is UITextView { return false }
            target = view.superview
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool { true }

    @objc private func dismissKeyboard() {
        window?.endEditing(false)
    }
}
