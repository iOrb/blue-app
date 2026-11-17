import AlarmKit
import Foundation
import Observation
import SwiftUI
import UserNotifications

@MainActor
protocol AlarmScheduling {
    func authorize() async throws
    func schedule(_ alarm: SavedAlarm) async throws
    func cancel(_ id: UUID) throws
    func scheduledIDs() throws -> Set<UUID>
}

@MainActor
protocol EventNotificationScheduling {
    func schedule(_ event: CalendarEvent) async throws
    func cancelNotification(for id: UUID)
}

@MainActor
struct SystemEventNotifications: EventNotificationScheduling {
    func schedule(_ event: CalendarEvent) async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        if status == .notDetermined {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                throw BlueError.notificationPermissionDenied
            }
        } else if status == .denied {
            throw BlueError.notificationPermissionDenied
        }
        try Task.checkCancellation()
        guard event.nextOccurrence(after: .now) != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.notes ?? ""
        content.sound = .default
        let requests = Self.requests(for: event, content: content)
        do {
            for request in requests { try await center.add(request) }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier))
            throw error
        }
        let retained = Set(requests.map(\.identifier))
        center.removePendingNotificationRequests(
            withIdentifiers: Self.notificationIDs(event.id).filter { !retained.contains($0) })
    }

    func cancelNotification(for id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: Self.notificationIDs(id))
    }

    static func requests(for event: CalendarEvent, content: UNNotificationContent) -> [UNNotificationRequest] {
        let base = "blue-event-" + event.id.uuidString
        if event.repeatDays.isEmpty {
            return [
                UNNotificationRequest(
                    identifier: base, content: content,
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: max(1, event.date.timeIntervalSinceNow), repeats: false))
            ]
        }
        let time = Calendar.current.dateComponents([.hour, .minute], from: event.date)
        return event.repeatDays.map { day in
            UNNotificationRequest(
                identifier: base + "-\(day)", content: content,
                trigger: UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: time.hour, minute: time.minute, weekday: day), repeats: true))
        }
    }

    private static func notificationIDs(_ id: UUID) -> [String] {
        let base = "blue-event-" + id.uuidString
        return [base] + (1...7).map { base + "-\($0)" }
    }
}

#if DEBUG && targetEnvironment(simulator)
    @MainActor
    final class SimulatorEventScheduleFixture: AlarmScheduling, EventNotificationScheduling {
        private var alarms: Set<UUID>
        init(alarms: [SavedAlarm]) { self.alarms = Set(alarms.filter(\.enabled).map(\.id)) }
        func authorize() async throws {}
        func schedule(_ alarm: SavedAlarm) async throws { alarms.insert(alarm.id) }
        func schedule(_ event: CalendarEvent) async throws {}
        func cancelNotification(for id: UUID) {}
        func cancel(_ id: UUID) { alarms.remove(id) }
        func scheduledIDs() throws -> Set<UUID> { alarms }
    }
#endif

private struct BlueAlarmMetadata: AlarmMetadata {}

@MainActor
final class SystemAlarmScheduler: AlarmScheduling {
    func authorize() async throws {
        guard try await AlarmManager.shared.requestAuthorization() == .authorized else {
            throw BlueError.permissionDenied
        }
    }
    func schedule(_ alarm: SavedAlarm) async throws {
        let schedule: Alarm.Schedule
        if alarm.weekdays.isEmpty {
            schedule = .fixed(alarm.date)
        } else {
            let components = Calendar.current.dateComponents([.hour, .minute], from: alarm.date)
            let weekdays: [Locale.Weekday] = [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
            schedule = .relative(
                .init(
                    time: .init(hour: components.hour ?? 0, minute: components.minute ?? 0),
                    repeats: .weekly(alarm.weekdays.map { weekdays[$0 - 1] })))
        }
        let title = LocalizedStringResource(stringLiteral: alarm.title)
        let alert: AlarmPresentation.Alert
        if #available(iOS 26.1, *) {
            alert = AlarmPresentation.Alert(title: title)
        } else {
            alert = AlarmPresentation.Alert(
                title: title, stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
        }
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert), metadata: BlueAlarmMetadata(), tintColor: Color.primary)
        _ = try await AlarmManager.shared.schedule(
            id: alarm.id, configuration: .alarm(schedule: schedule, attributes: attributes))
    }
    func cancel(_ id: UUID) throws { try AlarmManager.shared.cancel(id: id) }
    func scheduledIDs() throws -> Set<UUID> {
        guard AlarmManager.shared.authorizationState == .authorized else { return [] }
        return Set(try AlarmManager.shared.alarms.map(\.id))
    }
}

@MainActor
@Observable
final class AlarmService {
    private let store: LibraryStore
    private let scheduler: any AlarmScheduling
    private let notifications: any EventNotificationScheduling
    private var inFlight: Set<UUID> = []
    private var eventsInFlight: Set<UUID> = []
    var errorKey: String?
    init(
        store: LibraryStore, scheduler: any AlarmScheduling = SystemAlarmScheduler(),
        notifications: (any EventNotificationScheduling)? = nil
    ) {
        self.store = store
        self.scheduler = scheduler
        self.notifications = notifications ?? SystemEventNotifications()
    }

    func save(_ input: SavedAlarm) async throws {
        try await save(input, committing: { _ in })
    }

    private func save(_ input: SavedAlarm, committing change: (inout LibraryState) throws -> Void) async throws {
        guard !inFlight.contains(input.id) else { throw BlueError.staleRevision }
        try Validation.title(input.title)
        guard input.weekdays.allSatisfy({ (1...7).contains($0) }), Set(input.weekdays).count == input.weekdays.count,
            !input.enabled || !input.weekdays.isEmpty || input.date > Date()
        else { throw BlueError.invalidValue }
        let old = store.state.alarms.first { $0.id == input.id }
        guard old == nil || old?.revision == input.revision else { throw BlueError.staleRevision }
        inFlight.insert(input.id)
        defer { inFlight.remove(input.id) }
        var removed = false
        var scheduled = false
        do {
            try Task.checkCancellation()
            if input.enabled {
                try await scheduler.authorize()
                try Task.checkCancellation()
            }
            let exists = try scheduler.scheduledIDs().contains(input.id)
            let unchanged =
                old.map {
                    $0.title == input.title && $0.date == input.date && $0.weekdays == input.weekdays
                } ?? false
            if exists && (!input.enabled || !unchanged) {
                try scheduler.cancel(input.id)
                removed = true
            }
            if input.enabled && (!exists || removed) {
                try await scheduler.schedule(input)
                scheduled = true
            }
            var saved = input
            saved.revision += 1
            saved.timeZoneID = TimeZone.current.identifier
            do {
                try store.update { state in
                    if let index = state.alarms.firstIndex(where: { $0.id == input.id }) {
                        state.alarms[index] = saved
                    } else {
                        state.alarms.append(saved)
                    }
                    try change(&state)
                }
            } catch { throw BlueError.saveFailed }
        } catch {
            if scheduled { try? scheduler.cancel(input.id) }
            if removed, let old, old.enabled { try? await scheduler.schedule(old) }
            if let error = error as? BlueError { throw error }
            if error is CancellationError { throw BlueError.cancelled }
            throw BlueError.alarmFailed
        }
    }

    func saveEvent(_ event: CalendarEvent, expectedRevision: Int?, ringing: Bool) async throws {
        try Validation.event(event)
        guard store.state.events?.first(where: { $0.id == event.id })?.revision == expectedRevision else {
            throw BlueError.staleRevision
        }
        let existing = store.state.alarms.first { $0.id == event.id }
        guard ringing || existing != nil else {
            try store.saveEvent(event, expectedRevision: expectedRevision)
            return
        }
        guard !ringing || !event.allDay else { throw BlueError.invalidValue }
        var alarm = existing ?? SavedAlarm(id: event.id, title: event.title, date: event.date)
        alarm.title = event.title
        alarm.date = event.date
        alarm.weekdays = event.repeatDays
        alarm.enabled = ringing
        try await save(alarm) { state in
            try LibraryStore.stageEvent(event, expectedRevision: expectedRevision, in: &state)
            if !ringing { state.alarms.removeAll { $0.id == event.id } }
        }
    }

    func saveTimedEvent(_ input: CalendarEvent, expectedRevision: Int?) async throws {
        guard eventsInFlight.insert(input.id).inserted else { throw BlueError.staleRevision }
        defer { eventsInFlight.remove(input.id) }
        let previous = store.state.events?.first { $0.id == input.id }
        guard previous?.revision == expectedRevision else { throw BlueError.staleRevision }
        try Validation.event(input)
        var event = input
        event.allDay = false
        if !event.repeatDays.isEmpty, let next = event.nextOccurrence(after: .now) {
            event.date = next
            event.day = nil
        }
        guard event.nextOccurrence(after: .now) != nil else {
            try await savePastEvent(event, expectedRevision: expectedRevision)
            return
        }
        event.notification = true
        do {
            try await notifications.schedule(event)
            if event.nextOccurrence(after: .now) != nil {
                try await saveEvent(event, expectedRevision: expectedRevision, ringing: true)
            } else {
                try await savePastEvent(event, expectedRevision: expectedRevision)
            }
        } catch {
            notifications.cancelNotification(for: event.id)
            if event.repeatDays.isEmpty, event.date <= Date(), !Task.isCancelled {
                try await savePastEvent(event, expectedRevision: expectedRevision)
                return
            }
            if let previous, previous.notification == true, previous.nextOccurrence(after: .now) != nil {
                try? await notifications.schedule(previous)
            }
            throw error
        }
    }

    private func savePastEvent(_ input: CalendarEvent, expectedRevision: Int?) async throws {
        var event = input
        event.notification = false
        try await saveEvent(event, expectedRevision: expectedRevision, ringing: false)
        notifications.cancelNotification(for: event.id)
    }

    func deleteEvent(_ event: CalendarEvent) async throws {
        guard eventsInFlight.insert(event.id).inserted else { throw BlueError.staleRevision }
        defer { eventsInFlight.remove(event.id) }
        guard store.state.events?.first(where: { $0.id == event.id })?.revision == event.revision else {
            throw BlueError.staleRevision
        }
        let deletion = PendingDeletion(kind: "event", id: event.id, revision: event.revision)
        guard var alarm = store.state.alarms.first(where: { $0.id == event.id }) else {
            try store.confirmDeletion(deletion)
            notifications.cancelNotification(for: event.id)
            return
        }
        alarm.enabled = false
        try await save(alarm) { state in
            try LibraryStore.stageDeletion(deletion, in: &state)
            state.alarms.removeAll { $0.id == event.id }
        }
        notifications.cancelNotification(for: event.id)
    }

    func delete(_ alarm: SavedAlarm) async throws {
        var disabled = alarm
        disabled.enabled = false
        try await save(disabled)
        try store.update { $0.alarms.removeAll { $0.id == alarm.id } }
    }

    func reconcile(timeZone: TimeZone = .current, now: Date = Date()) {
        do {
            let ids = try scheduler.scheduledIDs()
            var updates: [UUID: SavedAlarm] = [:]
            for alarm in store.state.alarms where !inFlight.contains(alarm.id) {
                var updated = alarm
                if alarm.enabled && !ids.contains(alarm.id) { updated.enabled = false }
                if alarm.timeZoneID != timeZone.identifier {
                    if !alarm.weekdays.isEmpty {
                        var previousCalendar = Calendar.current
                        previousCalendar.timeZone = TimeZone(identifier: alarm.timeZoneID) ?? timeZone
                        let components = previousCalendar.dateComponents([.hour, .minute], from: alarm.date)
                        var currentCalendar = Calendar.current
                        currentCalendar.timeZone = timeZone
                        updated.date =
                            currentCalendar.date(
                                bySettingHour: components.hour ?? 0,
                                minute: components.minute ?? 0, second: 0, of: now) ?? alarm.date
                    }
                    updated.timeZoneID = timeZone.identifier
                }
                if updated != alarm {
                    updated.revision += 1
                    updates[alarm.id] = updated
                }
            }
            if !updates.isEmpty {
                try store.update { state in
                    for index in state.alarms.indices {
                        if let update = updates[state.alarms[index].id] { state.alarms[index] = update }
                    }
                }
            }
            errorKey = nil
        } catch { errorKey = BlueError.alarmFailed.key }
    }

    func observe() async {
        for await _ in AlarmManager.shared.alarmUpdates {
            if Task.isCancelled { return }
            reconcile()
        }
    }

    func alarms(on date: Date, calendar: Calendar = .current) -> [SavedAlarm] {
        store.state.alarms.filter {
            $0.weekdays.isEmpty
                ? calendar.isDate($0.date, inSameDayAs: date)
                : $0.weekdays.contains(calendar.component(.weekday, from: date))
        }.sorted {
            calendar.component(.hour, from: $0.date) * 60 + calendar.component(.minute, from: $0.date)
                < calendar.component(.hour, from: $1.date) * 60 + calendar.component(.minute, from: $1.date)
        }
    }
}
