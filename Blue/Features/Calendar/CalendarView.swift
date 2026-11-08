import SwiftUI

struct CalendarView: View {
    @Environment(Localizer.self) private var l
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(NavigationState.self) private var navigation
    @Environment(AlarmService.self) private var alarms
    @State private var month = Date()
    @State private var editingAlarm: SavedAlarm?
    @State private var showNewAlarm = false
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
        List {
            Section {
                if textSize.isAccessibilitySize {
                    DatePicker(
                        l("alarm.date"),
                        selection: Binding(get: { navigation.selectedDate }, set: { navigation.selectedDate = $0 }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.compact).labelsHidden().frame(minHeight: 44)
                } else {
                    VStack(spacing: 18) {
                        HStack {
                            Text(month.formatted(.dateTime.month(.wide).year().locale(l.locale))).font(
                                .title3.weight(.medium))
                            Spacer()
                            QuietButton(key: "calendar.previous", symbol: "chevron.left") { changeMonth(-1) }
                            QuietButton(key: "calendar.next", symbol: "chevron.right") { changeMonth(1) }
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 8) {
                            ForEach(0..<7, id: \.self) { offset in
                                let index = (calendar.firstWeekday - 1 + offset) % 7
                                Text(calendar.veryShortStandaloneWeekdaySymbols[index]).font(.caption).foregroundStyle(
                                    .secondary
                                ).frame(maxWidth: .infinity)
                                    .accessibilityHidden(true)
                            }
                            let offset =
                                (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
                            let count = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
                            ForEach(0..<(offset + count), id: \.self) { index in
                                if index < offset {
                                    Color.clear.frame(height: 44)
                                } else if let date = calendar.date(
                                    byAdding: .day, value: index - offset, to: monthStart)
                                {
                                    dayButton(date)
                                }
                            }
                        }
                    }.padding(.vertical, 8)
                }
            }.listRowSeparator(.hidden)
            Section {
                let selected = alarms.alarms(on: navigation.selectedDate, calendar: calendar)
                ForEach(selected) { alarm in
                    HStack(spacing: 16) {
                        Button {
                            editingAlarm = alarm
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(l.time(alarm.date)).font(.system(.largeTitle, design: .rounded).weight(.light))
                                    .monospacedDigit()
                                Text(alarm.title).font(.subheadline).foregroundStyle(.secondary)
                                if !alarm.weekdays.isEmpty {
                                    Text(l("alarm.repeats")).font(.caption).foregroundStyle(.secondary)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Toggle(
                            l("alarm.enabled"),
                            isOn: Binding(
                                get: { alarm.enabled },
                                set: { enabled in
                                    Task {
                                        var updated = alarm
                                        updated.enabled = enabled
                                        do { try await alarms.save(updated) } catch {
                                            self.error = (error as? BlueError ?? .alarmFailed).key
                                        }
                                    }
                                })
                        ).labelsHidden().tint(.primary).accessibilityLabel(alarm.title)
                    }.padding(.vertical, 12)
                        .listRowBackground(
                            navigation.highlightedAlarm == alarm.id ? Color.primary.opacity(0.07) : Color.clear)
                }
                if selected.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(l("calendar.noAlarms")).font(.body).foregroundStyle(.secondary)
                        Button(l("alarm.new"), systemImage: "plus") { showNewAlarm = true }.padding(.vertical, 6)
                    }.padding(.vertical, 20).listRowSeparator(.hidden)
                }
                ErrorLine(key: error ?? alarms.errorKey)
            } header: {
                Text(l.date(navigation.selectedDate)).textCase(nil)
            }
        }
        .listStyle(.plain).modifier(KeyboardDismissToolbar()).navigationTitle(l("tab.calendar"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { SettingsButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("calendar.today")) {
                    navigation.selectedDate = Date()
                    month = Date()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewAlarm = true
                } label: {
                    Image(systemName: "plus")
                }.accessibilityLabel(l("alarm.new")).accessibilityIdentifier("newAlarm")
            }
        }
        .navigationDestination(isPresented: $showNewAlarm) { AlarmEditor(date: navigation.selectedDate) }
        .navigationDestination(item: $editingAlarm) { alarm in AlarmEditor(existing: alarm, date: alarm.date) }
        .onChange(of: navigation.selectedDate) { _, value in month = value }
        .onAppear { month = navigation.selectedDate }
    }
    private func changeMonth(_ offset: Int) {
        month = calendar.date(byAdding: .month, value: offset, to: monthStart) ?? month
    }
    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: navigation.selectedDate)
        let hasAlarms = !alarms.alarms(on: date, calendar: calendar).isEmpty
        return Button {
            navigation.selectedDate = date
        } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day().locale(l.locale))).font(.body).lineLimit(1).minimumScaleFactor(0.7)
                    .frame(minHeight: 32)
                Circle().fill(hasAlarms ? (selected ? Color(.systemBackground) : .primary) : .clear).frame(
                    width: 3, height: 3)
            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                .foregroundStyle(selected ? Color(.systemBackground) : .primary)
                .background { if selected { RoundedRectangle(cornerRadius: 16).fill(Color.primary) } }
        }.buttonStyle(.plain).accessibilityLabel(l.date(date))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(hasAlarms ? l("calendar.hasAlarms") : "")
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
        .disabled(busy)
        .modifier(KeyboardDismissToolbar()).navigationTitle(l(existing == nil ? "alarm.new" : "alarm.edit"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { SettingsButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button(l("save")) { Task { await save() } }.disabled(
                    busy || title.trimmingCharacters(in: .whitespaces).isEmpty
                ).accessibilityIdentifier("alarmSave")
            }
        }
        .confirmationDialog(l("alarm.confirmDelete"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(l("delete"), role: .destructive) {
                Task {
                    guard let existing else { return }
                    busy = true
                    do {
                        try await alarms.delete(existing)
                        dismiss()
                    } catch { self.error = (error as? BlueError ?? .alarmFailed).key }
                    busy = false
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let existing {
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
    private func save() async {
        busy = true
        defer { busy = false }
        let alarm = SavedAlarm(
            id: existing?.id ?? UUID(), title: title, date: selectedDate, weekdays: weekdays.sorted(), enabled: enabled,
            revision: existing?.revision ?? 0)
        do {
            try await alarms.save(alarm)
            dismiss()
        } catch { self.error = (error as? BlueError ?? .alarmFailed).key }
    }
}
