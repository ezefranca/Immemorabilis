import AppIntents
import EventKit
import SwiftUI
import WidgetKit

private let appGroup = "group.com.ezefranca.Immemorabilis"
private var accent: Color {
    switch UserDefaults(suiteName: appGroup)?.string(forKey: "accentColorChoice") {
    case "blue": Color(red: 0.03, green: 0.43, blue: 0.70)
    default: Color(red: 0.79, green: 0.04, blue: 0.03)
    }
}

struct WidgetReminder: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let notes: String
    let dueDate: Date?
    let isCompleted: Bool
    let completionDate: Date?
    let listTitle: String
    let hasRecurrence: Bool
    let isLocationBased: Bool

    var detail: String {
        guard let dueDate else { return listTitle }
        if Calendar.autoupdatingCurrent.isDateInToday(dueDate) {
            return dueDate.formatted(date: .omitted, time: .shortened)
        }
        return dueDate.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

struct ImmemorabilisEntry: TimelineEntry {
    let date: Date
    let reminders: [WidgetReminder]
}

struct ImmemorabilisProvider: TimelineProvider {
    func placeholder(in context: Context) -> ImmemorabilisEntry {
        .init(date: .now, reminders: Self.samples)
    }

    func getSnapshot(in context: Context, completion: @escaping (ImmemorabilisEntry) -> Void) {
        completion(.init(date: .now, reminders: context.isPreview ? Self.samples : load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ImmemorabilisEntry>) -> Void) {
        let entry = ImmemorabilisEntry(date: .now, reminders: load())
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    private func load() -> [WidgetReminder] {
        guard
            let data = UserDefaults(suiteName: appGroup)?.data(forKey: "widgetReminders"),
            let reminders = try? JSONDecoder().decode([WidgetReminder].self, from: data)
        else { return [] }
        return reminders.filter { !$0.isCompleted }
    }

    static let samples: [WidgetReminder] = [
        .init(id: "one", title: "Send revised methods section", notes: "", dueDate: .now.addingTimeInterval(1800), isCompleted: false, completionDate: nil, listTitle: "Research", hasRecurrence: false, isLocationBased: false),
        .init(id: "two", title: "Prepare seminar prompts", notes: "", dueDate: .now.addingTimeInterval(7200), isCompleted: false, completionDate: nil, listTitle: "Teaching", hasRecurrence: false, isLocationBased: false),
        .init(id: "three", title: "Return library books", notes: "", dueDate: .now.addingTimeInterval(86400), isCompleted: false, completionDate: nil, listTitle: "Personal", hasRecurrence: false, isLocationBased: true)
    ]
}

struct ImmemorabilisWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ImmemorabilisEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryInline:
            accessoryInline
        case .accessoryRectangular:
            accessoryRectangular
        case .systemSmall:
            homeWidget(limit: 2, compact: true)
        case .systemMedium:
            homeWidget(limit: 3, compact: false)
        default:
            homeWidget(limit: 6, compact: false)
        }
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(entry.reminders.count, format: .number)
                    .font(.title2.bold())
                    .monospacedDigit()
                Image(systemName: "checklist")
                    .font(.caption)
            }
        }
        .widgetLabel { Text("tasks in view") }
    }

    private var accessoryInline: some View {
        Label(entry.reminders.first?.title ?? "All clear", systemImage: "checklist")
    }

    private var accessoryRectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Immemorabilis").font(.headline)
            if let first = entry.reminders.first {
                Text(first.title).font(.caption).lineLimit(1)
                Text(first.detail).font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No upcoming tasks").font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func homeWidget(limit: Int, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 9) {
            HStack {
                Text("Today")
                    .font(.headline)
                Spacer()
                Link(destination: URL(string: "immemorabilis://dictate")!) {
                    Image(systemName: "waveform")
                        .font(.headline)
                        .foregroundStyle(accent)
                }
                .accessibilityLabel("Dictate reminder")
                Link(destination: URL(string: "immemorabilis://new")!) {
                    Image(systemName: "plus")
                        .font(.headline)
                        .foregroundStyle(accent)
                }
                .accessibilityLabel("New reminder")
            }

            if entry.reminders.isEmpty {
                Spacer()
                Label("No upcoming tasks", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(Array(entry.reminders.prefix(limit))) { reminder in
                    HStack(spacing: 8) {
                        Button(intent: CompleteReminderIntent(reminderID: reminder.id)) {
                            Image(systemName: "circle")
                                .foregroundStyle(accent)
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reminder.title)
                                .font(compact ? .caption : .subheadline)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(reminder.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if reminder.id != entry.reminders.prefix(limit).last?.id {
                        Divider()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 0.83, green: 0.95, blue: 0.99), Color(uiColor: .systemBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .widgetURL(URL(string: "immemorabilis://today"))
    }
}

struct CompleteReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete reminder"
    static let description = IntentDescription("Marks an Apple Reminder as complete from a widget.")
    static let openAppWhenRun = false

    @Parameter(title: "Reminder identifier")
    var reminderID: String

    init() { reminderID = "" }
    init(reminderID: String) { self.reminderID = reminderID }

    func perform() async throws -> some IntentResult {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            return .result()
        }
        let store = EKEventStore()
        if let reminder = store.calendarItem(withIdentifier: reminderID) as? EKReminder {
            reminder.isCompleted = true
            reminder.completionDate = .now
            try store.save(reminder, commit: true)
        }

        if let defaults = UserDefaults(suiteName: "group.com.ezefranca.Immemorabilis"),
           let data = defaults.data(forKey: "widgetReminders"),
           var reminders = try? JSONDecoder().decode([WidgetReminder].self, from: data) {
            reminders.removeAll { $0.id == reminderID }
            defaults.set(try? JSONEncoder().encode(reminders), forKey: "widgetReminders")
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ImmemorabilisWidget: Widget {
    let kind = "ImmemorabilisAgenda"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ImmemorabilisProvider()) { entry in
            ImmemorabilisWidgetView(entry: entry)
        }
        .configurationDisplayName("Tasks in view")
        .description("View and complete your next reminders.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular, .accessoryInline
        ])
    }
}

struct QuickCaptureControl: ControlWidget {
    static let kind = "com.ezefranca.Immemorabilis.QuickCapture"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "immemorabilis://new")!)) {
                Label("New reminder", systemImage: "plus")
            }
        }
        .displayName("Quick Capture")
        .description("Open Immemorabilis ready to capture a task.")
    }
}

struct DictationControl: ControlWidget {
    static let kind = "com.ezefranca.Immemorabilis.Dictation"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: OpenURLIntent(URL(string: "immemorabilis://dictate")!)) {
                Label("Dictate reminder", systemImage: "waveform")
            }
        }
        .displayName("Dictate Reminder")
        .description("Open Immemorabilis and begin dictating a task.")
    }
}

@main
struct ImmemorabilisWidgets: WidgetBundle {
    var body: some Widget {
        ImmemorabilisWidget()
        QuickCaptureControl()
        DictationControl()
    }
}

#Preview(as: .systemMedium) {
    ImmemorabilisWidget()
} timeline: {
    ImmemorabilisEntry(date: .now, reminders: ImmemorabilisProvider.samples)
}

#Preview(as: .systemSmall) {
    ImmemorabilisWidget()
} timeline: {
    ImmemorabilisEntry(date: .now, reminders: ImmemorabilisProvider.samples)
}
