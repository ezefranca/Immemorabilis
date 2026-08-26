import Foundation
import EventKit

struct ReminderListChoice: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let count: Int
    let colorHex: String
}

struct ReminderItem: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let notes: String
    let dueDate: Date?
    var hasTime = true
    let isCompleted: Bool
    let completionDate: Date?
    let listTitle: String
    let hasRecurrence: Bool
    let isLocationBased: Bool

    var detailText: String {
        guard let dueDate else { return listTitle }
        if Calendar.autoupdatingCurrent.isDateInToday(dueDate) {
            return hasTime ? "Today, \(dueDate.formatted(date: .omitted, time: .shortened))" : "Today"
        }
        if Calendar.autoupdatingCurrent.isDateInTomorrow(dueDate) {
            return hasTime ? "Tomorrow, \(dueDate.formatted(date: .omitted, time: .shortened))" : "Tomorrow"
        }
        return hasTime
            ? dueDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute())
            : dueDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

enum ReminderSection: String, CaseIterable, Identifiable {
    case today = "Today"
    case tomorrow = "Tomorrow"
    case week = "Next 7 Days"
    case later = "Later"
    case anytime = "Anytime"

    var id: String { rawValue }
}

enum RepeatChoice: String, CaseIterable, Identifiable {
    case never = "Never"
    case daily = "Daily"
    case weekly = "Weekly"
    case monthly = "Monthly"
    case lastDayOfMonth = "Last day of the month"
    case firstWeekdayOfMonth = "First weekday of the month"
    case lastWeekdayOfMonth = "Last weekday of the month"
    case firstWeekendDayOfMonth = "First non-weekday of the month"
    case lastWeekendDayOfMonth = "Last non-weekday of the month"

    var id: String { rawValue }

    var frequency: EKRecurrenceFrequency? {
        switch self {
        case .never: nil
        case .daily: .daily
        case .weekly: .weekly
        case .monthly: .monthly
        case .lastDayOfMonth, .firstWeekdayOfMonth, .lastWeekdayOfMonth,
             .firstWeekendDayOfMonth, .lastWeekendDayOfMonth: .monthly
        }
    }

    var recurrenceRule: EKRecurrenceRule? {
        recurrenceRule(interval: 1, endDate: nil)
    }

    func recurrenceRule(interval: Int, endDate: Date?) -> EKRecurrenceRule? {
        guard let frequency else { return nil }
        let end = endDate.map(EKRecurrenceEnd.init(end:))
        let safeInterval = max(1, interval)
        let weekdays: [EKRecurrenceDayOfWeek] = [.monday, .tuesday, .wednesday, .thursday, .friday]
            .map { EKRecurrenceDayOfWeek($0) }
        let weekendDays: [EKRecurrenceDayOfWeek] = [.saturday, .sunday]
            .map { EKRecurrenceDayOfWeek($0) }

        switch self {
        case .never:
            return nil
        case .daily, .weekly, .monthly:
            return EKRecurrenceRule(recurrenceWith: frequency, interval: safeInterval, end: end)
        case .lastDayOfMonth:
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: safeInterval,
                daysOfTheWeek: nil,
                daysOfTheMonth: [-1],
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )
        case .firstWeekdayOfMonth, .lastWeekdayOfMonth,
             .firstWeekendDayOfMonth, .lastWeekendDayOfMonth:
            let days = self == .firstWeekdayOfMonth || self == .lastWeekdayOfMonth ? weekdays : weekendDays
            let position = self == .firstWeekdayOfMonth || self == .firstWeekendDayOfMonth ? 1 : -1
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: safeInterval,
                daysOfTheWeek: days,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: [position as NSNumber],
                end: end
            )
        }
    }

    var intervalUnit: String {
        switch self {
        case .daily: "day"
        case .weekly: "week"
        case .never: "day"
        default: "month"
        }
    }

    init(rule: EKRecurrenceRule?) {
        guard let rule else { self = .never; return }
        guard rule.frequency == .monthly else {
            self = rule.frequency == .daily ? .daily : .weekly
            return
        }
        if rule.daysOfTheMonth?.contains(-1) == true {
            self = .lastDayOfMonth
            return
        }
        let position = rule.setPositions?.first?.intValue
        let days = Set(rule.daysOfTheWeek?.map(\.dayOfTheWeek) ?? [])
        let weekdays: Set<EKWeekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        let isWeekday = !days.isEmpty && days.isSubset(of: weekdays)
        if position == 1 { self = isWeekday ? .firstWeekdayOfMonth : .firstWeekendDayOfMonth }
        else if position == -1 { self = isWeekday ? .lastWeekdayOfMonth : .lastWeekendDayOfMonth }
        else { self = .monthly }
    }
}

struct ReminderDraft {
    var existingIdentifier: String?
    var title = ""
    var notes = ""
    var dueDate = Date().addingTimeInterval(15 * 60)
    var hasDueDate = true
    var hasTime = true
    var calendarIdentifier: String?
    var repeatChoice: RepeatChoice = .never
    var repeatInterval = 1
    var repeatEndDate: Date?
    var locationName = ""
    var locationProximity: EKAlarmProximity = .enter
    var locationDelayMinutes = 0
    var isCompleted = false
}

enum AppRoute: Equatable {
    case newReminder
    case dictateReminder
}
