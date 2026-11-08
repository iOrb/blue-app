import AlarmKit
import Foundation
import Observation
import SwiftUI

@MainActor
protocol AlarmScheduling {
    func authorize() async throws
    func schedule(_ alarm: SavedAlarm) async throws
    func cancel(_ id: UUID) throws
    func scheduledIDs() throws -> Set<UUID>
}

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
    private var inFlight: Set<UUID> = []
    var errorKey: String?
    init(store: LibraryStore, scheduler: any AlarmScheduling = SystemAlarmScheduler()) {
        self.store = store
        self.scheduler = scheduler
    }

    func save(_ input: SavedAlarm) async throws {
        guard !inFlight.contains(input.id) else { throw BlueError.staleRevision }
        try Validation.title(input.title)
        guard input.weekdays.allSatisfy({ (1...7).contains($0) }), Set(input.weekdays).count == input.weekdays.count,
            !input.enabled || !input.weekdays.isEmpty || input.date > Date()
        else { throw BlueError.invalidValue }
        let old = store.state.alarms.first { $0.id == input.id }
        guard old == nil || old?.revision == input.revision else { throw BlueError.staleRevision }
        inFlight.insert(input.id)
        defer { inFlight.remove(input.id) }
        do {
            try Task.checkCancellation()
            if input.enabled {
                try await scheduler.authorize()
                try Task.checkCancellation()
                try await scheduler.schedule(input)
            } else if old?.enabled == true {
                try scheduler.cancel(input.id)
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
                }
            } catch {
                // Compensate when persistence fails after a system change.
                if let old, old.enabled { try? await scheduler.schedule(old) } else { try? scheduler.cancel(input.id) }
                throw BlueError.saveFailed
            }
        } catch let error as BlueError { throw error } catch is CancellationError { throw BlueError.cancelled } catch {
            throw BlueError.alarmFailed
        }
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
