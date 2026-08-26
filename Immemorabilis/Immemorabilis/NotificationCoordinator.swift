import Foundation
import UserNotifications

actor NotificationCoordinator {
    static let shared = NotificationCoordinator()
    private let center = UNUserNotificationCenter.current()

    func requestAuthorization() async -> Bool {
        configureCategories()
        return (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
    }

    func reschedule(reminders: [ReminderItem]) async {
        configureCategories()
        let existing = await center.pendingNotificationRequests()
        let identifiers = existing.map(\.identifier).filter { $0.hasPrefix("immemorabilis.") }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let candidates = reminders
            .filter { !$0.isCompleted && $0.dueDate != nil }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            .prefix(20)

        let defaults = UserDefaults.standard
        let returnMinutes = defaults.object(forKey: "nudgeInterval") as? Int ?? 240
        let spacingMinutes = defaults.object(forKey: "notificationSpacing") as? Int ?? 10
        let defaultSeconds = defaults.object(forKey: "defaultNotificationSeconds") as? Int ?? 9 * 60 * 60
        let returnInterval = TimeInterval(returnMinutes * 60)
        let notificationSpacing = TimeInterval(spacingMinutes * 60)
        var occupiedSlots: [Date] = []

        for reminder in candidates {
            guard let dueDate = reminder.dueDate else { continue }
            let scheduledDate: Date
            if reminder.hasTime {
                scheduledDate = dueDate
            } else {
                scheduledDate = Calendar.autoupdatingCurrent.startOfDay(for: dueDate)
                    .addingTimeInterval(TimeInterval(defaultSeconds))
            }
            for (index, delay) in ([0, returnInterval, returnInterval * 2] as [TimeInterval]).enumerated() {
                var fireDate = scheduledDate.addingTimeInterval(delay)
                if fireDate <= .now {
                    guard index == 0, dueDate > Date.now.addingTimeInterval(-7 * 24 * 60 * 60) else { continue }
                    fireDate = .now.addingTimeInterval(3)
                }
                while notificationSpacing > 0,
                      occupiedSlots.contains(where: { abs($0.timeIntervalSince(fireDate)) < 1 }) {
                    fireDate = fireDate.addingTimeInterval(notificationSpacing)
                }
                occupiedSlots.append(fireDate)
                let content = UNMutableNotificationContent()
                content.title = dueDate <= .now ? "A task still needs attention" : (index == 0 ? "A task is due" : "Still on your list")
                content.body = reminder.title
                content.sound = .default
                content.categoryIdentifier = "IMMEMORABILIS_REMINDER"
                content.userInfo = ["reminderID": reminder.id]
                let components = Calendar.autoupdatingCurrent.dateComponents(
                    [.calendar, .timeZone, .year, .month, .day, .hour, .minute, .second],
                    from: fireDate
                )
                let request = UNNotificationRequest(
                    identifier: "immemorabilis.\(reminder.id).\(index)",
                    content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                )
                try? await center.add(request)
            }
        }
    }

    private func configureCategories() {
        let open = UNNotificationAction(
            identifier: "OPEN_REMINDER",
            title: "Open",
            options: [.foreground]
        )
        let category = UNNotificationCategory(
            identifier: "IMMEMORABILIS_REMINDER",
            actions: [open],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }
}
