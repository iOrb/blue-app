import SwiftUI

struct CalendarView: View {
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @Environment(LibraryStore.self) private var store
    @Environment(AlarmService.self) private var alarms
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var month = Date()
    @State private var selectedEvent: CalendarEvent?
    @State private var deletingEvent: CalendarEvent?
    @State private var confirmDelete = false
    @State private var error: String?
    private var calendar: Calendar {
        var calendar = Calendar.current
        calendar.locale = l.locale
        calendar.firstWeekday = l.language == .spanish ? 2 : 1
        return calendar
    }
    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }
    private var monthHeading: String {
        let label = month.formatted(.dateTime.month(.wide).year().locale(l.locale)).lowercased(with: l.locale)
        return label.prefix(1).uppercased(with: l.locale) + label.dropFirst()
    }
    var body: some View {
        let event = selectedEvent
        List {
            VStack(spacing: 18) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack {
                        Text(monthHeading)
                            .font(.title3.weight(.medium))
                        Spacer()
                        QuietButton(key: "calendar.previous", symbol: "chevron.left") { changeMonth(-1) }
                        QuietButton(key: "calendar.next", symbol: "chevron.right") { changeMonth(1) }

                    }
                }
                if dynamicTypeSize.isAccessibilitySize {
                    DatePicker(
                        l("alarm.date"),
                        selection: Binding(get: { navigation.selectedDate }, set: { navigation.selectedDate = $0 }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact).labelsHidden()
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                        ForEach(0..<7, id: \.self) { offset in
                            Text(calendar.veryShortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7])
                                .font(.caption).foregroundStyle(.tertiary).accessibilityHidden(true)
                        }
                        let offset = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
                        let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
                        ForEach(0..<(offset + count), id: \.self) { index in
                            if index < offset {
                                Color.clear.frame(height: 44)
                            } else if let date = calendar.date(byAdding: .day, value: index - offset, to: monthStart) {
                                dayButton(date)
                            }
                        }
                    }
                }
            }.blueListRow()
            dayAgenda
        }.listStyle(.plain).scrollContentBackground(.hidden)
            .blueSheet(
                isPresented: Binding(get: { selectedEvent != nil }, set: { if !$0 { selectedEvent = nil } }),
                title: "", ownHeader: true, allowsExpansion: false
            ) {
                if let event { EventEditor(existing: event, date: event.date) }
            }
            .onAppear { month = navigation.selectedDate }
            .blueConfirmation(isPresented: $confirmDelete, title: l("event.confirmDelete")) {
                guard let deletingEvent else { return }
                Task {
                    do { try await alarms.deleteEvent(deletingEvent) } catch {
                        self.error = (error as? BlueError ?? .saveFailed).key
                    }
                }
            }
    }
    private var dayAgenda: some View {
        let selected = navigation.selectedDate
        let events = (store.state.events ?? []).filter { $0.occurs(on: selected, calendar: calendar) }
            .sorted {
                ($0.occurrence(on: selected, calendar: calendar) ?? $0.date)
                    < ($1.occurrence(on: selected, calendar: calendar) ?? $1.date)
            }
        return Group {
            Text(l.date(selected)).font(.headline).accessibilityIdentifier("calendarAgendaTitle")
            if events.isEmpty {
                Text(l("calendar.noEvents")).foregroundStyle(.secondary)
            }
            ForEach(events) { event in
                Button {
                    selectedEvent = event
                } label: {
                    HStack(spacing: 10) {
                        Circle().fill(.blue).frame(width: 6, height: 6).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(event.title)
                            if let notes = event.notes, !notes.isEmpty {
                                Text(notes).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer()
                        if !event.repeatDays.isEmpty {
                            Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary).accessibilityLabel(
                                l("alarm.repeats"))
                        }
                        Text(l.time(event.date)).foregroundStyle(.secondary)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(BlueRowPress()).accessibilityIdentifier("calendar-event-\(event.title)")
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            deletingEvent = event
                            confirmDelete = true
                        } label: {
                            Image(systemName: "trash").accessibilityLabel(l("delete"))
                        }.tint(.red)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            deletingEvent = event
                            confirmDelete = true
                        } label: {
                            BlueDeleteLabel()
                        }
                    }
            }
            ErrorLine(key: error)
        }.blueListRow()
    }

    private func changeMonth(_ offset: Int) {
        month = calendar.date(byAdding: .month, value: offset, to: monthStart) ?? month
    }
    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: navigation.selectedDate)
        let hasItems =
            (store.state.events ?? []).contains { $0.occurs(on: date, calendar: calendar) }
        return Button {
            navigation.selectedDate = date
        } label: {
            Text(date.formatted(.dateTime.day().locale(l.locale)))
                .font(.body.monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: 36, height: 36)
                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                .background { if selected { Circle().fill(Color.primary) } }
                .overlay(alignment: .bottom) {
                    if hasItems {
                        Circle().fill(selected ? Color(.systemBackground) : .blue)
                            .frame(width: 4, height: 4).padding(.bottom, 2)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(l.date(date)).accessibilityIdentifier(
            "day-\(calendar.component(.day, from: date))"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct EventEditor: View {
    var existing: CalendarEvent?
    var date: Date
    @Environment(AlarmService.self) private var alarms
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @Environment(\.blueSheetDismiss) private var sheetDismiss
    @State private var draft: CalendarEvent?
    @State private var error: String?
    @State private var finishing = false
    @State private var timeFeedback = UIImpactFeedbackGenerator(style: .light)
    @State private var openWheel: ScheduleField?
    @FocusState private var editingText: TextFieldKind?

    private enum ScheduleField { case date, time }
    private enum TextFieldKind { case name, notes }

    var body: some View {
        VStack(spacing: 0) {
            BlueSheetHeader(title: l("event.title"), close: close) {
                if existing == nil || hasChanges {
                    BlueDoneButton(action: finish)
                        .disabled(finishing || draft == nil)
                        .accessibilityIdentifier("finishEvent")
                }
            }
            if let draft {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField(l("event.name"), text: binding(\.title))
                            .font(.headline).foregroundStyle(.primary).frame(minHeight: 50)
                            .focused($editingText, equals: .name).accessibilityIdentifier("eventTitle")
                        Divider()
                        scheduleRow(.time, label: "event.time", identifier: "eventTime", value: l.time(draft.date))
                        if openWheel == .time {
                            DatePicker(
                                l("event.time"), selection: scheduleSelection(.time),
                                displayedComponents: .hourAndMinute
                            )
                            .labelsHidden().datePickerStyle(.wheel).environment(\.locale, l.twentyFourHourLocale)
                            .frame(maxWidth: .infinity)
                        }
                        Divider()
                        scheduleRow(
                            .date, label: "event.date", identifier: "eventDay",
                            value: draft.date.formatted(.dateTime.day().month(.abbreviated).year().locale(l.locale)))
                        if openWheel == .date {
                            DatePicker(l("event.date"), selection: scheduleSelection(.date), displayedComponents: .date)
                                .labelsHidden().datePickerStyle(.wheel).environment(\.locale, l.locale)
                                .frame(maxWidth: .infinity)
                        }
                        Divider()
                        repeatPicker(draft.repeatDays)
                        Divider()
                        LabeledContent(l("note.markdown")) {
                            TextField(
                                l("event.notesPlaceholder"),
                                text: Binding(
                                    get: { self.draft?.notes ?? "" },
                                    set: { self.draft?.notes = $0.isEmpty ? nil : $0 }),
                                axis: .vertical
                            )
                            .lineLimit(1...8).multilineTextAlignment(.trailing).foregroundStyle(.primary)
                            .focused($editingText, equals: .notes).accessibilityLabel(l("note.markdown"))
                            .accessibilityIdentifier("eventNotes")
                        }
                        .padding(.vertical, 10).frame(minHeight: 50)
                        ErrorLine(key: error).padding(.top, 4)
                    }
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 24).padding(.bottom, 12).blueSheetContentSize()
                }.scrollDismissesKeyboard(.interactively).disabled(finishing)
            }
        }
        .interactiveDismissDisabled(finishing)
        .onChange(of: editingText) { _, field in if field != nil { openWheel = nil } }
        .onAppear {
            guard draft == nil else { return }
            let calendar = Calendar.current
            let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            let soon = Date().addingTimeInterval(1_800)
            let defaultDate = morning <= Date() && calendar.isDateInToday(date) ? soon : morning
            draft = existing ?? CalendarEvent(title: "", date: defaultDate)
        }
    }
    private func close() {
        guard !finishing else { return }
        if let sheetDismiss { sheetDismiss() } else { dismiss() }
    }
    private var hasChanges: Bool {
        guard let existing, let draft else { return false }
        return eventTitle(draft.title) != existing.title || draft.notes != existing.notes || draft.date != existing.date
            || draft.repeatDays != existing.repeatDays
    }
    private func eventTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? l("event.title") : title
    }
    private func finish() {
        guard !finishing, var next = draft else { return }
        next.title = eventTitle(next.title)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        next.day = formatter.string(from: next.date)
        editingText = nil
        finishing = true
        Task {
            do {
                try await alarms.saveTimedEvent(next, expectedRevision: existing?.revision)
                finishing = false
                close()
            } catch {
                finishing = false
                self.error = (error as? BlueError ?? .saveFailed).key
            }
        }
    }
    private func scheduleRow(_ field: ScheduleField, label: String, identifier: String, value: String) -> some View {
        Button {
            editingText = nil
            openWheel = openWheel == field ? nil : field
        } label: {
            LabeledContent(l(label)) {
                HStack(spacing: 8) {
                    Text(value).monospacedDigit()
                    Image(systemName: openWheel == field ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.semibold)).accessibilityHidden(true)
                }.foregroundStyle(openWheel == field ? Color.accentColor : Color.secondary)
            }
            .frame(minHeight: 50).contentShape(Rectangle())
        }
        .accessibilityLabel(l(label))
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
        .buttonStyle(BlueRowPress())
    }

    private func repeatPicker(_ selected: [Int]) -> some View {
        VStack(spacing: 2) {
            LabeledContent(l("alarm.repeat")) {
                Text(l.repeatSummary(selected)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(
                    .trailing)
            }.frame(minHeight: 46).accessibilityIdentifier("eventRepeatSummary")
            HStack(spacing: 0) {
                ForEach(l.orderedWeekdays, id: \.self) { day in
                    let active = selected.contains(day)
                    Button {
                        editingText = nil
                        openWheel = nil
                        var days = Set(self.draft?.repeatDays ?? [])
                        if !days.insert(day).inserted { days.remove(day) }
                        self.draft?.repeatDays = days.sorted()
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Text(String(l.weekday(day).prefix(1)).uppercased(with: l.locale))
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 32, height: 32)
                            .foregroundStyle(active ? Color(.systemBackground) : Color.primary)
                            .background(active ? Color.primary : Color(.tertiarySystemFill), in: Circle())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(BlueRowPress(shape: AnyShape(Circle())))
                    .accessibilityLabel(l.weekday(day))
                    .accessibilityAddTraits(active ? .isSelected : [])
                    .accessibilityIdentifier("eventRepeatDay-\(day)")
                }
            }
        }.padding(.bottom, 8)
    }

    private func scheduleSelection(_ field: ScheduleField) -> Binding<Date> {
        Binding(
            get: { draft?.date ?? date },
            set: { value in
                guard let current = draft?.date else { return }
                let calendar = Calendar.current
                let day = field == .date ? value : current
                let time = calendar.dateComponents([.hour, .minute], from: field == .time ? value : current)
                guard
                    let next = calendar.date(
                        bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day),
                    next != current
                else { return }
                if field == .time {
                    timeFeedback.impactOccurred(intensity: 0.9)
                    timeFeedback.prepare()
                }
                draft?.date = next
            })
    }

    private func binding<T>(_ path: WritableKeyPath<CalendarEvent, T>) -> Binding<T> {
        Binding(
            get: { draft![keyPath: path] },
            set: { draft?[keyPath: path] = $0 })
    }
}
