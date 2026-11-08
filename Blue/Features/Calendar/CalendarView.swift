import SwiftUI

struct CalendarView: View {
    var showAdd = true
    @Environment(Localizer.self) private var l
    @Environment(NavigationState.self) private var navigation
    @Environment(LibraryStore.self) private var store
    @Environment(AlarmService.self) private var alarms
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var month = Date()
    @State private var showDay = false
    @State private var showEvent = false
    @State private var selectedEvent: CalendarEvent?
    @State private var editingAlarm: SavedAlarm?
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
    var body: some View {
        VStack(spacing: 18) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack {
                    Text(month.formatted(.dateTime.month(.wide).year().locale(l.locale))).font(.title3.weight(.medium))
                    Spacer()
                    QuietButton(key: "calendar.previous", symbol: "chevron.left") { changeMonth(-1) }
                    QuietButton(key: "calendar.next", symbol: "chevron.right") { changeMonth(1) }
                    if showAdd {
                        QuietButton(key: "event.new", symbol: "plus") {
                            selectedEvent = nil
                            showEvent = true
                        }.accessibilityIdentifier("calendarPlus")
                    }
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                DatePicker(
                    l("alarm.date"),
                    selection: Binding(get: { navigation.selectedDate }, set: { navigation.selectedDate = $0 }),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact).labelsHidden()
                .onChange(of: navigation.selectedDate) { _, _ in showDay = true }
                Button(l.date(navigation.selectedDate)) { showDay = true }.frame(minHeight: 44)
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
        }
        .blueSheet(isPresented: $showDay, title: l.date(navigation.selectedDate)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        QuietButton(key: "event.new", symbol: "plus") {
                            selectedEvent = nil
                            showEvent = true
                        }
                    }
                    ForEach(
                        (store.state.events ?? []).filter {
                            calendar.isDate($0.date, inSameDayAs: navigation.selectedDate)
                        }.sorted { $0.date < $1.date }
                    ) { event in
                        Button {
                            selectedEvent = event
                            showEvent = true
                        } label: {
                            HStack(spacing: 12) {
                                Circle().fill((IndicatorTint(rawValue: event.color) ?? .blue).color).frame(
                                    width: 7, height: 7)
                                Text(event.title).font(.title3.weight(.medium))
                                Spacer()
                                if !event.allDay {
                                    Text(l.time(event.date)).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.frame(minHeight: 54).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    ForEach(alarms.alarms(on: navigation.selectedDate, calendar: calendar)) { alarm in
                        HStack {
                            Button {
                                editingAlarm = alarm
                            } label: {
                                Label("\(l.time(alarm.date)) · \(alarm.title)", systemImage: "alarm").frame(
                                    minHeight: 44)
                            }.buttonStyle(.plain)
                            Spacer()
                            Toggle(
                                l("alarm.enabled"),
                                isOn: Binding(
                                    get: { alarm.enabled },
                                    set: { enabled in
                                        Task {
                                            var changed = alarm
                                            changed.enabled = enabled
                                            do { try await alarms.save(changed) } catch {
                                                self.error = (error as? BlueError ?? .alarmFailed).key
                                            }
                                        }
                                    })
                            ).labelsHidden()
                        }
                    }
                    ErrorLine(key: error)
                }.padding(.horizontal, 24)
            }
            .blueSheet(isPresented: $showEvent, title: l(selectedEvent == nil ? "event.new" : "event.title")) {
                EventEditor(existing: selectedEvent, date: navigation.selectedDate)
            }
            .blueSheet(
                isPresented: Binding(get: { editingAlarm != nil }, set: { if !$0 { editingAlarm = nil } }),
                title: l("alarm.edit")
            ) {
                if let editingAlarm { AlarmEditor(existing: editingAlarm, date: editingAlarm.date) }
            }
        }
        .blueSheet(isPresented: Binding(get: { showEvent && !showDay }, set: { showEvent = $0 }), title: l("event.new"))
        { EventEditor(date: navigation.selectedDate) }
        .onAppear { month = navigation.selectedDate }
    }
    private func changeMonth(_ offset: Int) {
        month = calendar.date(byAdding: .month, value: offset, to: monthStart) ?? month
    }
    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: navigation.selectedDate)
        let hasItems =
            (store.state.events ?? []).contains { calendar.isDate($0.date, inSameDayAs: date) }
            || !alarms.alarms(on: date, calendar: calendar).isEmpty
        return Button {
            navigation.selectedDate = date
            showDay = true
        } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day().locale(l.locale))).font(.body.monospacedDigit()).lineLimit(1)
                    .minimumScaleFactor(0.7)
                Circle().fill(hasItems ? (selected ? Color(.systemBackground) : .blue) : .clear).frame(
                    width: 4, height: 4)
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                .background { if selected { Circle().fill(Color.primary) } }
        }.buttonStyle(.plain).accessibilityLabel(l.date(date)).accessibilityIdentifier(
            "day-\(calendar.component(.day, from: date))"
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct EventEditor: View {
    var existing: CalendarEvent?
    var date: Date
    @Environment(LibraryStore.self) private var store
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var draft: CalendarEvent?
    @State private var saved: CalendarEvent?
    @State private var error: String?
    @State private var confirmDelete = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let draft {
                TextField(l("title"), text: binding(\.title)).font(.title2.weight(.semibold)).accessibilityIdentifier(
                    "eventTitle")
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        DatePicker(
                            l("alarm.date"), selection: binding(\.date),
                            displayedComponents: draft.allDay ? [.date] : [.date, .hourAndMinute])
                        Toggle(l("event.allDay"), isOn: binding(\.allDay))
                        HStack(spacing: 0) {
                            ForEach(IndicatorTint.allCases, id: \.self) { tint in
                                Button {
                                    self.draft?.color = tint.rawValue
                                    save()
                                } label: {
                                    Circle().fill(tint.color).frame(width: 18, height: 18).frame(width: 44, height: 44)
                                        .overlay(
                                            Circle().stroke(
                                                draft.color == tint.rawValue ? Color.primary : .clear, lineWidth: 1))
                                }.accessibilityLabel(l("color.\(tint.rawValue)"))
                            }
                        }
                        Text(l("event.noAlarm")).font(.footnote).foregroundStyle(.tertiary)
                        if saved != nil { QuietButton(key: "delete", symbol: "minus") { confirmDelete = true } }
                        ErrorLine(key: error)
                    }.padding(.top, 10)
                }
            }
        }.padding(.horizontal, 24)
            .onAppear {
                guard draft == nil else { return }
                saved = existing
                draft =
                    existing
                    ?? CalendarEvent(
                        title: "", date: Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                    )
            }
            .blueConfirmation(isPresented: $confirmDelete, title: l("event.confirmDelete")) {
                guard let saved else { return }
                do {
                    try store.confirmDeletion(PendingDeletion(kind: "event", id: saved.id, revision: saved.revision))
                    dismiss()
                } catch { self.error = (error as? BlueError ?? .saveFailed).key }
            }
    }
    private func binding<T>(_ path: WritableKeyPath<CalendarEvent, T>) -> Binding<T> {
        Binding(
            get: { draft![keyPath: path] },
            set: {
                draft?[keyPath: path] = $0
                save()
            })
    }
    private func save() {
        guard var draft, !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        draft.day = formatter.string(from: draft.date)
        do {
            try store.saveEvent(draft, expectedRevision: saved?.revision)
            saved = store.state.events?.first { $0.id == draft.id }
            self.draft = saved
            error = nil
        } catch { self.error = (error as? BlueError ?? .saveFailed).key }
    }
}

struct AlarmEditor: View {
    var existing: SavedAlarm?
    var date: Date
    @Environment(AlarmService.self) private var alarms
    @Environment(Localizer.self) private var l
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var selectedDate = Date()
    @State private var weekdays: Set<Int> = []
    @State private var enabled = true
    @State private var loaded = false
    @State private var busy = false
    @State private var saved: SavedAlarm?
    @State private var revisionTask: Task<Void, Never>?
    @State private var error: String?
    @State private var confirmDelete = false
    var body: some View {
        Form {
            TextField(l("alarm.name"), text: $title).accessibilityIdentifier("alarmTitle")
            DatePicker(l("alarm.date"), selection: $selectedDate)
            Toggle(l("alarm.enabled"), isOn: $enabled).accessibilityIdentifier("alarmEnabled")
            Section(l("alarm.repeat")) {
                let calendar = l.locale.calendar
                ForEach(1...7, id: \.self) { day in
                    Button {
                        if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                    } label: {
                        HStack {
                            Text(calendar.weekdaySymbols[day - 1])
                            Spacer()
                            if weekdays.contains(day) { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
            Section { Text(l("alarm.systemHint")).font(.footnote).foregroundStyle(.secondary) }
            ErrorLine(key: error)
            if existing != nil { Button(l("alarm.delete"), role: .destructive) { confirmDelete = true } }
        }
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: selectedDate) { _, _ in scheduleSave() }
        .onChange(of: weekdays) { _, _ in scheduleSave() }
        .onChange(of: enabled) { _, _ in scheduleSave() }
        .modifier(KeyboardDismissToolbar()).navigationTitle(l(existing == nil ? "alarm.new" : "alarm.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .blueConfirmation(isPresented: $confirmDelete, title: l("alarm.confirmDelete")) {
            Task {
                guard let saved else { return }
                revisionTask?.cancel()
                busy = true
                do {
                    try await alarms.delete(saved)
                    dismiss()
                } catch { self.error = (error as? BlueError ?? .alarmFailed).key }
                busy = false
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
                saved = existing
                title = existing.title
                selectedDate = existing.date
                weekdays = Set(existing.weekdays)
                enabled = existing.enabled
            } else {
                selectedDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
                if selectedDate < Date() { selectedDate = Date().addingTimeInterval(3600) }
            }
        }
    }
    private func scheduleSave() {
        guard loaded, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if let saved, saved.title == title, saved.date == selectedDate, Set(saved.weekdays) == weekdays,
            saved.enabled == enabled
        {
            return
        }
        revisionTask?.cancel()
        revisionTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(500))
                try Task.checkCancellation()
                revisionTask = nil
                await save()
            } catch {}
        }
    }
    private func save() async {
        guard !busy else {
            scheduleSave()
            return
        }
        busy = true
        defer { busy = false }
        let alarm = SavedAlarm(
            id: saved?.id ?? existing?.id ?? UUID(), title: title, date: selectedDate, weekdays: weekdays.sorted(),
            enabled: enabled,
            revision: saved?.revision ?? existing?.revision ?? 0)
        do {
            try await alarms.save(alarm)
            saved = alarm
            saved?.revision += 1
            error = nil
            scheduleSave()
        } catch { self.error = (error as? BlueError ?? .alarmFailed).key }
    }
}
