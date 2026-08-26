import EventKit
import XCTest
@testable import Immemorabilis

@MainActor
final class ImmemorabilisTests: XCTestCase {
    func testPreviewAgendaGroupsTodayAndTomorrow() {
        let store = ReminderStore.preview

        XCTAssertEqual(store.items(in: .today).count, 2)
        XCTAssertEqual(store.items(in: .tomorrow).count, 1)
        XCTAssertTrue(store.items(in: .today).allSatisfy { !$0.isCompleted })
    }

    func testReminderSnapshotRoundTripsForWidgetCache() throws {
        let original = ReminderItem(
            id: "academic-task",
            title: "Submit camera-ready paper",
            notes: "Confirm author affiliations.",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            isCompleted: false,
            completionDate: nil,
            listTitle: "Research",
            hasRecurrence: false,
            isLocationBased: false
        )

        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(ReminderItem.self, from: data), original)
    }

    func testRepeatChoicesMapToEventKitFrequencies() {
        XCTAssertNil(RepeatChoice.never.frequency)
        XCTAssertEqual(RepeatChoice.daily.frequency, EKRecurrenceFrequency.daily)
        XCTAssertEqual(RepeatChoice.weekly.frequency, EKRecurrenceFrequency.weekly)
        XCTAssertEqual(RepeatChoice.monthly.frequency, EKRecurrenceFrequency.monthly)
        XCTAssertEqual(RepeatChoice.lastDayOfMonth.frequency, EKRecurrenceFrequency.monthly)
    }

    func testAdvancedMonthlyRecurrenceRulesUseExactPositions() {
        let lastDay = RepeatChoice.lastDayOfMonth.recurrenceRule
        XCTAssertEqual(lastDay?.daysOfTheMonth, [-1])

        let firstWeekday = RepeatChoice.firstWeekdayOfMonth.recurrenceRule
        XCTAssertEqual(firstWeekday?.setPositions?.first?.intValue, 1)
        XCTAssertEqual(Set(firstWeekday?.daysOfTheWeek?.map(\.dayOfTheWeek) ?? []),
                       Set([.monday, .tuesday, .wednesday, .thursday, .friday]))

        let lastWeekendDay = RepeatChoice.lastWeekendDayOfMonth.recurrenceRule
        XCTAssertEqual(lastWeekendDay?.setPositions?.first?.intValue, -1)
        XCTAssertEqual(Set(lastWeekendDay?.daysOfTheWeek?.map(\.dayOfTheWeek) ?? []),
                       Set([.saturday, .sunday]))
    }

    func testTextInputDetectsDatesAndNoteURLs() {
        let match = NaturalLanguageDateParser.firstDate(
            in: "Submit the paper on August 30, 2026 at 9:30 AM",
            locale: Locale(identifier: "en_US")
        )
        XCTAssertNotNil(match)
        XCTAssertTrue(match?.phrase.contains("August 30") == true)

        let links = NaturalLanguageDateParser.links(in: "Sources: https://example.edu/paper and https://doi.org/10.1000/test")
        XCTAssertEqual(links.count, 2)
    }
}
