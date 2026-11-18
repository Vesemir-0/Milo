import XCTest
@testable import MiloCore

@MainActor final class MockWriter: EventWriting {
    var calendarCalls = 0
    var reminderCalls: [(ParsedEvent, Date?, String?)] = []
    var failingReminderCalls: Set<Int> = []
    var calendarEvents: [ParsedEvent] = []
    func saveCalendar(_ event: ParsedEvent, calendarID: String?) async throws -> String { calendarCalls += 1; calendarEvents.append(event); return "calendar-\(calendarCalls)" }
    func saveReminder(_ event: ParsedEvent, due: Date?, suffix: String?, listID: String?) async throws -> String {
        reminderCalls.append((event,due,suffix))
        if failingReminderCalls.contains(reminderCalls.count) { throw FailureInfo(kind: .writing, title: "failed", message: "reminder failed", suggestion: "retry") }
        return "reminder-\(reminderCalls.count)"
    }
}
@MainActor final class DraftWriterTests: XCTestCase {
    func testPartialRetryUsesEditedValuesAndDoesNotDuplicateCalendar() async throws {
        let writer = MockWriter(); writer.failingReminderCalls = [1]
        let start = Date(), due = Date().addingTimeInterval(3600)
        var event = ParsedEvent(title: "原始", startDate: start, dueDate: due)
        event.title = "编辑后的标题"; event.setBody("保留\n换行")
        let saver = DraftWriter(writer: writer)
        let first = await saver.save([EventDraft(event: event, target: .both)]) { _ in true }
        XCTAssertEqual(first.drafts[0].savedCalendarID, "calendar-1"); XCTAssertNil(first.drafts[0].savedStartReminderID)
        let second = await saver.save(first.drafts) { _ in true }
        XCTAssertEqual(writer.calendarCalls, 1); XCTAssertEqual(writer.reminderCalls.count, 2)
        XCTAssertEqual(writer.calendarEvents[0].title, "编辑后的标题"); XCTAssertEqual(writer.calendarEvents[0].readableBody, "保留\n换行")
        XCTAssertEqual(writer.reminderCalls.last?.1, due); XCTAssertTrue(second.drafts[0].isComplete); XCTAssertFalse(second.drafts[0].selected)
    }
    func testMultiDayReminderRetryKeepsTheFirstReminder() async throws {
        let writer = MockWriter(); writer.failingReminderCalls = [2]
        let start = Date(), end = Date().addingTimeInterval(2*86400)
        let draft = EventDraft(event: ParsedEvent(title: "跨天", startDate: start, endDate: end), target: .reminderOnly)
        let saver = DraftWriter(writer: writer)
        let first = await saver.save([draft]) { _ in true }
        XCTAssertNotNil(first.drafts[0].savedStartReminderID); XCTAssertNil(first.drafts[0].savedEndReminderID)
        let final = await saver.save(first.drafts) { _ in true }
        XCTAssertTrue(final.drafts[0].isComplete); XCTAssertEqual(writer.reminderCalls.count, 3)
        XCTAssertEqual(writer.reminderCalls.map { $0.2 }, ["（开始）","（结束）","（结束）"])
    }
    func testReceiptFailureStopsBeforeTheNextTarget() async throws {
        let writer = MockWriter(), saver = DraftWriter(writer: writer)
        let draft = EventDraft(event: ParsedEvent(title: "save", startDate: Date()), target: .both)
        let result = await saver.save([draft]) { _ in false }
        XCTAssertTrue(result.persistenceFailed); XCTAssertNotNil(result.drafts[0].savedCalendarID); XCTAssertTrue(writer.reminderCalls.isEmpty)
        _ = await saver.save(result.drafts) { _ in true }
        XCTAssertEqual(writer.calendarCalls, 1); XCTAssertEqual(writer.reminderCalls.count, 1)
    }
    func testUndatedCalendarNeedsEditingButUndatedTodoCanBeSaved() async throws {
        let writer = MockWriter(), saver = DraftWriter(writer: writer)
        let result = await saver.save([EventDraft(event: ParsedEvent(title: "没有日期"), target: .both), EventDraft(event: ParsedEvent(title: "以后再做"), target: .reminderOnly)]) { _ in true }
        XCTAssertEqual(writer.calendarCalls, 0); XCTAssertNotNil(result.drafts[0].saveError)
        XCTAssertEqual(writer.reminderCalls.count, 1); XCTAssertNil(writer.reminderCalls[0].1)
    }
}
