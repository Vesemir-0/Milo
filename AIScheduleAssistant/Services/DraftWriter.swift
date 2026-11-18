import Foundation

@MainActor protocol EventWriting {
    func saveCalendar(_ event: ParsedEvent, calendarID: String?) async throws -> String
    func saveReminder(_ event: ParsedEvent, due: Date?, suffix: String?, listID: String?) async throws -> String
}
struct WriteBatchResult {
    var drafts: [EventDraft]
    var persistenceFailed = false
    var savedCount: Int { drafts.filter(\.isComplete).count }
}
@MainActor final class DraftWriter {
    let writer: EventWriting
    init(writer: EventWriting) { self.writer = writer }
    func save(_ initial: [EventDraft], receipt: ([EventDraft]) -> Bool) async -> WriteBatchResult {
        var drafts = initial
        for index in drafts.indices where drafts[index].selected && !drafts[index].isComplete {
            if Task.isCancelled { break }
            if let validation = drafts[index].validationMessage { drafts[index].saveError = validation; continue }
            drafts[index].saveError = nil
            let event = drafts[index].event
            // Each successful target is recorded before starting the next one.
            if drafts[index].target.includesCalendar && drafts[index].savedCalendarID == nil {
                do {
                    drafts[index].savedCalendarID = try await writer.saveCalendar(event, calendarID: drafts[index].calendarID)
                    guard receipt(drafts) else { return WriteBatchResult(drafts: drafts, persistenceFailed: true) }
                } catch { drafts[index].saveError = FailureInfo.from(error).message }
            }
            if drafts[index].target.includesReminders {
                if drafts[index].savedStartReminderID == nil {
                    do {
                        drafts[index].savedStartReminderID = try await writer.saveReminder(event, due: event.needsTwoReminders ? event.startDate : event.dueDate ?? event.startDate, suffix: event.needsTwoReminders ? "（开始）" : nil, listID: drafts[index].reminderListID)
                        guard receipt(drafts) else { return WriteBatchResult(drafts: drafts, persistenceFailed: true) }
                    } catch { drafts[index].saveError = FailureInfo.from(error).message }
                }
                if event.needsTwoReminders && drafts[index].savedEndReminderID == nil {
                    do {
                        drafts[index].savedEndReminderID = try await writer.saveReminder(event, due: event.endDate, suffix: "（结束）", listID: drafts[index].reminderListID)
                        guard receipt(drafts) else { return WriteBatchResult(drafts: drafts, persistenceFailed: true) }
                    } catch { drafts[index].saveError = FailureInfo.from(error).message }
                }
            }
            if drafts[index].isComplete { drafts[index].saveError = nil; drafts[index].selected = false }
            guard receipt(drafts) else { return WriteBatchResult(drafts: drafts, persistenceFailed: true) }
        }
        _ = receipt(drafts)
        return WriteBatchResult(drafts: drafts)
    }
}
