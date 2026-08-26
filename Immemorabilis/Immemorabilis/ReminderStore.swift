import EventKit
import Foundation
import MapKit
import Observation
import UserNotifications
import WidgetKit

@MainActor
@Observable
final class ReminderStore {
    private let eventStore = EKEventStore()
    private let defaults = UserDefaults.standard
    private let usesInMemoryDataStore: Bool
    private let selectedListsKey = "selectedReminderListIDs"
    private let configuredListsKey = "hasConfiguredReminderLists"

    var authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    var lists: [ReminderListChoice] = []
    var reminders: [ReminderItem] = []
    var selectedListIDs: Set<String> = []
    var isLoading = false
    var errorMessage: String?
    var pendingRoute: AppRoute?

    init(usesInMemoryDataStore: Bool = false) {
        self.usesInMemoryDataStore = usesInMemoryDataStore
        selectedListIDs = Set(defaults.stringArray(forKey: selectedListsKey) ?? [])
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    func requestAccess() async -> Bool {
        if usesInMemoryDataStore {
            authorizationStatus = .fullAccess
            return true
        }
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
            if granted {
                eventStore.reset()
                await refresh()
            }
            return granted
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refresh() async {
        guard !usesInMemoryDataStore else { return }
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        guard hasFullAccess else { return }
        isLoading = true

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)
        let fetched: [EKReminder] = await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { values in
                continuation.resume(returning: values ?? [])
            }
        }

        let counts = Dictionary(grouping: fetched.filter { !$0.isCompleted }, by: { $0.calendar.calendarIdentifier })
            .mapValues(\.count)
        lists = calendars
            .map {
                ReminderListChoice(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    count: counts[$0.calendarIdentifier, default: 0],
                    colorHex: $0.cgColor.map(Self.hexString) ?? "C21311"
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        if !defaults.bool(forKey: configuredListsKey), selectedListIDs.isEmpty {
            selectedListIDs = Set(calendars.map(\.calendarIdentifier))
        }

        let visible = fetched.filter { selectedListIDs.isEmpty || selectedListIDs.contains($0.calendar.calendarIdentifier) }
        reminders = visible
            .map(Self.snapshot)
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
        isLoading = false
        writeWidgetCache()
        await NotificationCoordinator.shared.reschedule(reminders: reminders)
    }

    func toggleList(_ identifier: String) {
        if selectedListIDs.contains(identifier) {
            selectedListIDs.remove(identifier)
        } else {
            selectedListIDs.insert(identifier)
        }
        defaults.set(Array(selectedListIDs), forKey: selectedListsKey)
        defaults.set(true, forKey: configuredListsKey)
        if !usesInMemoryDataStore {
            Task { await refresh() }
        }
    }

    func saveListSelection() {
        defaults.set(Array(selectedListIDs), forKey: selectedListsKey)
        defaults.set(true, forKey: configuredListsKey)
    }

    func save(_ draft: ReminderDraft) async throws {
        if usesInMemoryDataStore {
            let identifier = draft.existingIdentifier ?? UUID().uuidString
            let item = inMemoryItem(from: draft, identifier: identifier)
            if let index = reminders.firstIndex(where: { $0.id == identifier }) {
                reminders[index] = item
            } else {
                reminders.append(item)
            }
            reminders.sort { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            return
        }

        let reminder: EKReminder
        if let identifier = draft.existingIdentifier {
            guard let existing = eventStore.calendarItem(withIdentifier: identifier) as? EKReminder else {
                throw ReminderStoreError.reminderNotFound
            }
            reminder = existing
        } else {
            reminder = EKReminder(eventStore: eventStore)
        }

        reminder.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.calendar = calendar(for: draft.calendarIdentifier) ?? eventStore.defaultCalendarForNewReminders()
        guard reminder.calendar != nil else { throw ReminderStoreError.noDefaultList }
        reminder.isCompleted = draft.isCompleted
        reminder.completionDate = draft.isCompleted ? (reminder.completionDate ?? .now) : nil

        reminder.alarms?.forEach(reminder.removeAlarm)
        reminder.recurrenceRules?.forEach(reminder.removeRecurrenceRule)

        if draft.hasDueDate {
            let components: Set<Calendar.Component> = draft.hasTime
                ? [.calendar, .timeZone, .year, .month, .day, .hour, .minute]
                : [.calendar, .timeZone, .year, .month, .day]
            reminder.dueDateComponents = Calendar.autoupdatingCurrent.dateComponents(components, from: draft.dueDate)
            if draft.hasTime {
                reminder.addAlarm(EKAlarm(absoluteDate: draft.dueDate))
            }
        } else {
            reminder.dueDateComponents = nil
        }

        if let rule = draft.repeatChoice.recurrenceRule(interval: draft.repeatInterval, endDate: draft.repeatEndDate) {
            reminder.addRecurrenceRule(rule)
        }

        if !draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let location = await resolveLocation(named: draft.locationName) {
            let structured = EKStructuredLocation(title: location.name ?? draft.locationName)
            structured.geoLocation = location.location
            structured.radius = 100
            let alarm = EKAlarm()
            alarm.structuredLocation = structured
            alarm.proximity = draft.locationProximity
            reminder.addAlarm(alarm)
        }

        try eventStore.save(reminder, commit: false)
        try eventStore.commit()
        await refresh()
    }

    func draft(for item: ReminderItem) -> ReminderDraft {
        guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else {
            return ReminderDraft(
                existingIdentifier: item.id,
                title: item.title,
                notes: item.notes,
                dueDate: item.dueDate ?? .now.addingTimeInterval(15 * 60),
                hasDueDate: item.dueDate != nil,
                hasTime: item.hasTime,
                isCompleted: item.isCompleted
            )
        }

        let locationAlarm = reminder.alarms?.first { $0.structuredLocation != nil }
        return ReminderDraft(
            existingIdentifier: reminder.calendarItemIdentifier,
            title: reminder.title ?? "",
            notes: reminder.notes ?? "",
            dueDate: reminder.dueDateComponents.flatMap { Calendar.autoupdatingCurrent.date(from: $0) } ?? .now.addingTimeInterval(15 * 60),
            hasDueDate: reminder.dueDateComponents != nil,
            hasTime: reminder.dueDateComponents?.hour != nil,
            calendarIdentifier: reminder.calendar.calendarIdentifier,
            repeatChoice: RepeatChoice(rule: reminder.recurrenceRules?.first),
            repeatInterval: reminder.recurrenceRules?.first?.interval ?? 1,
            repeatEndDate: reminder.recurrenceRules?.first?.recurrenceEnd?.endDate,
            locationName: locationAlarm?.structuredLocation?.title ?? "",
            locationProximity: locationAlarm?.proximity ?? .enter,
            isCompleted: reminder.isCompleted
        )
    }

    func setCompleted(_ item: ReminderItem, completed: Bool = true) async {
        if usesInMemoryDataStore, let index = reminders.firstIndex(where: { $0.id == item.id }) {
            reminders[index] = ReminderItem(
                id: item.id,
                title: item.title,
                notes: item.notes,
                dueDate: item.dueDate,
                hasTime: item.hasTime,
                isCompleted: completed,
                completionDate: completed ? .now : nil,
                listTitle: item.listTitle,
                hasRecurrence: item.hasRecurrence,
                isLocationBased: item.isLocationBased
            )
            return
        }
        guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = completed
        reminder.completionDate = completed ? .now : nil
        do {
            try eventStore.save(reminder, commit: true)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func snooze(_ item: ReminderItem, by interval: TimeInterval) async {
        if usesInMemoryDataStore, let index = reminders.firstIndex(where: { $0.id == item.id }) {
            reminders[index] = ReminderItem(
                id: item.id,
                title: item.title,
                notes: item.notes,
                dueDate: .now.addingTimeInterval(interval),
                hasTime: true,
                isCompleted: item.isCompleted,
                completionDate: item.completionDate,
                listTitle: item.listTitle,
                hasRecurrence: item.hasRecurrence,
                isLocationBased: item.isLocationBased
            )
            return
        }
        guard let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        let newDate = Date().addingTimeInterval(interval)
        reminder.dueDateComponents = Calendar.autoupdatingCurrent.dateComponents(
            [.calendar, .timeZone, .year, .month, .day, .hour, .minute],
            from: newDate
        )
        reminder.alarms?.filter { $0.structuredLocation == nil }.forEach(reminder.removeAlarm)
        reminder.addAlarm(EKAlarm(absoluteDate: newDate))
        do {
            try eventStore.save(reminder, commit: true)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func items(in section: ReminderSection) -> [ReminderItem] {
        let calendar = Calendar.autoupdatingCurrent
        let startToday = calendar.startOfDay(for: .now)
        let startTomorrow = calendar.date(byAdding: .day, value: 1, to: startToday)!
        let afterTomorrow = calendar.date(byAdding: .day, value: 2, to: startToday)!
        let weekEnd = calendar.date(byAdding: .day, value: 8, to: startToday)!

        return reminders.filter { item in
            guard !item.isCompleted else { return section == .today && calendar.isDateInToday(item.completionDate ?? .distantPast) }
            guard let due = item.dueDate else { return section == .anytime }
            switch section {
            case .today: return due < startTomorrow
            case .tomorrow: return due >= startTomorrow && due < afterTomorrow
            case .week: return due >= afterTomorrow && due < weekEnd
            case .later: return due >= weekEnd
            case .anytime: return false
            }
        }
    }

    private func calendar(for identifier: String?) -> EKCalendar? {
        guard let identifier else { return nil }
        return eventStore.calendar(withIdentifier: identifier)
    }

    private func resolveLocation(named name: String) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        return try? await MKLocalSearch(request: request).start().mapItems.first
    }

    private func writeWidgetCache() {
        guard let defaults = UserDefaults(suiteName: "group.com.ezefranca.Immemorabilis") else { return }
        let upcoming = reminders.filter { !$0.isCompleted }.prefix(8)
        defaults.set(try? JSONEncoder().encode(Array(upcoming)), forKey: "widgetReminders")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func inMemoryItem(from draft: ReminderDraft, identifier: String) -> ReminderItem {
        let existing = reminders.first { $0.id == identifier }
        let listTitle = lists.first { $0.id == draft.calendarIdentifier }?.title ?? existing?.listTitle ?? "Reminders"
        return ReminderItem(
            id: identifier,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: draft.hasDueDate ? draft.dueDate : nil,
            hasTime: draft.hasDueDate && draft.hasTime,
            isCompleted: draft.isCompleted,
            completionDate: draft.isCompleted ? (existing?.completionDate ?? .now) : nil,
            listTitle: listTitle,
            hasRecurrence: draft.repeatChoice != .never,
            isLocationBased: !draft.locationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
    }

    private static func snapshot(_ reminder: EKReminder) -> ReminderItem {
        let date = reminder.dueDateComponents.flatMap { Calendar.autoupdatingCurrent.date(from: $0) }
        let locationBased = reminder.alarms?.contains { $0.structuredLocation != nil } ?? false
        return ReminderItem(
            id: reminder.calendarItemIdentifier,
            title: reminder.title ?? "Untitled reminder",
            notes: reminder.notes ?? "",
            dueDate: date,
            hasTime: reminder.dueDateComponents?.hour != nil,
            isCompleted: reminder.isCompleted,
            completionDate: reminder.completionDate,
            listTitle: reminder.calendar.title,
            hasRecurrence: reminder.hasRecurrenceRules,
            isLocationBased: locationBased
        )
    }

    private static func hexString(_ color: CGColor) -> String {
        guard let components = color.components, components.count >= 3 else { return "C21311" }
        return components.prefix(3).map { String(format: "%02X", Int($0 * 255)) }.joined()
    }

    static var preview: ReminderStore {
        let store = ReminderStore(usesInMemoryDataStore: true)
        store.authorizationStatus = .fullAccess
        store.lists = [
            .init(id: "research", title: "Research", count: 4, colorHex: "6A5ACD"),
            .init(id: "teaching", title: "Teaching", count: 2, colorHex: "34C759"),
            .init(id: "personal", title: "Personal", count: 3, colorHex: "FF9500")
        ]
        store.selectedListIDs = ["research"]
        store.reminders = [
            .init(id: "1", title: "Send revised methods section", notes: "Add the reviewer-requested power analysis.", dueDate: .now.addingTimeInterval(1800), isCompleted: false, completionDate: nil, listTitle: "Research", hasRecurrence: false, isLocationBased: false),
            .init(id: "2", title: "Prepare seminar discussion prompts", notes: "", dueDate: .now.addingTimeInterval(7200), isCompleted: false, completionDate: nil, listTitle: "Teaching", hasRecurrence: false, isLocationBased: false),
            .init(id: "3", title: "Return library books", notes: "", dueDate: .now.addingTimeInterval(86400), isCompleted: false, completionDate: nil, listTitle: "Personal", hasRecurrence: false, isLocationBased: true)
        ]
        return store
    }

    static var previewWithDeniedAccess: ReminderStore {
        let store = preview
        store.authorizationStatus = .denied
        return store
    }
}

enum ReminderStoreError: LocalizedError {
    case noDefaultList
    case reminderNotFound

    var errorDescription: String? {
        switch self {
        case .noDefaultList: "Create a list in Reminders before adding your first item."
        case .reminderNotFound: "This reminder is no longer available in Apple Reminders."
        }
    }
}
