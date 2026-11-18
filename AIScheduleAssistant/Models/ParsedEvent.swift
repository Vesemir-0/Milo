import Foundation

struct ParsedEvent: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var description: String?
    var startDate: Date?
    var endDate: Date?
    var isAllDay = false
    var dueDate: Date?
    var priority = 0
    var suggestedCalendar = ""
    var suggestedReminderList = ""
    var confidence = 1.0
    var location: String?
    var url: String?
    var notes: [String] = []

    var readableBody: String {
        let body = description ?? ""
        let bullets = notes.filter { !$0.isEmpty }.joined(separator: "\n\n")
        return [body, bullets].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    mutating func setBody(_ value: String) { description = value; notes = [] }
    var needsTwoReminders: Bool {
        guard let start = startDate, let end = endDate else { return false }
        return !Calendar.current.isDate(start, inSameDayAs: end)
    }
}

struct EventDraft: Codable, Identifiable, Equatable {
    var id = UUID()
    var event: ParsedEvent
    var selected = true
    var target: SaveTarget
    var calendarID: String?
    var reminderListID: String?
    var savedCalendarID: String?
    var savedStartReminderID: String?
    var savedEndReminderID: String?
    var saveError: String?

    var calendarComplete: Bool { !target.includesCalendar || savedCalendarID != nil }
    var remindersComplete: Bool { !target.includesReminders || (savedStartReminderID != nil && (!event.needsTwoReminders || savedEndReminderID != nil)) }
    var isComplete: Bool { calendarComplete && remindersComplete }
    var hasSavedTargets: Bool { savedCalendarID != nil || savedStartReminderID != nil || savedEndReminderID != nil }
    var validationMessage: String? {
        if event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "请填写标题。" }
        if target.includesCalendar && !calendarComplete && event.startDate == nil { return "添加到日历前，请设置开始日期。" }
        if let start = event.startDate, let end = event.endDate, end < start { return "结束时间不能早于开始时间。" }
        return nil
    }
}
