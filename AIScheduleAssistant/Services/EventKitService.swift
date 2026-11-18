import Foundation
import EventKit

@MainActor final class EventKitService: EventWriting {
    static let shared = EventKitService()
    let eventStore = EKEventStore()
    func getCalendars() -> [EKCalendar] { if RuntimeMode.isPreview { return [] }; return eventStore.calendars(for: .event).filter(\.allowsContentModifications) }
    func getReminderLists() -> [EKCalendar] { if RuntimeMode.isPreview { return [] }; return eventStore.calendars(for: .reminder).filter(\.allowsContentModifications) }
    func saveCalendar(_ parsed: ParsedEvent, calendarID: String?) async throws -> String {
        try await ensurePermission(.event)
        guard let start = parsed.startDate else { throw FailureInfo.configuration("这项日程还没有日期", suggestion: "先在纸条上设置开始日期，再添加到日历。") }
        let event = EKEvent(eventStore: eventStore)
        event.title = parsed.title; event.startDate = start
        event.endDate = parsed.endDate ?? (parsed.isAllDay ? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: start))! : start.addingTimeInterval(3600))
        event.isAllDay = parsed.isAllDay; event.notes = parsed.readableBody
        event.location = parsed.location; event.url = parsed.url.flatMap(URL.init(string:))
        event.calendar = try destination(type: .event, id: calendarID, suggested: parsed.suggestedCalendar)
        do { try eventStore.save(event, span: .thisEvent); return event.calendarItemIdentifier }
        catch { throw writeFailure("日历", error) }
    }
    func saveReminder(_ parsed: ParsedEvent, due: Date?, suffix: String?, listID: String?) async throws -> String {
        try await ensurePermission(.reminder)
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = parsed.title + (suffix ?? "")
        if let due { reminder.dueDateComponents = Calendar.current.dateComponents(parsed.isAllDay ? [.year, .month, .day] : [.year, .month, .day, .hour, .minute], from: due) }
        reminder.priority = min(9, max(0, parsed.priority))
        reminder.notes = [parsed.location.map { "地点：" + $0 }, parsed.readableBody].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        reminder.url = parsed.url.flatMap(URL.init(string:))
        reminder.calendar = try destination(type: .reminder, id: listID, suggested: parsed.suggestedReminderList)
        do { try eventStore.save(reminder, commit: true); return reminder.calendarItemIdentifier }
        catch { throw writeFailure("待办清单", error) }
    }
    private func ensurePermission(_ type: EKEntityType) async throws {
        guard !RuntimeMode.isPreview else { throw FailureInfo.configuration("界面检查模式不会写入系统内容", suggestion: "退出检查模式后使用正式入口。") }
        let status = EKEventStore.authorizationStatus(for: type)
        if status == .fullAccess || (type == .event && status == .writeOnly) { return }
        if status == .notDetermined {
            let granted = try await (type == .event ? eventStore.requestFullAccessToEvents() : eventStore.requestFullAccessToReminders())
            if granted { return }
        }
        throw FailureInfo(kind: .permission, title: type == .event ? "日历权限还没有打开" : "提醒事项权限还没有打开", message: "这一目标尚未写入，其他成功部分会保留。", suggestion: "前往系统设置授权后，只重试尚未完成的部分。")
    }
    private func destination(type: EKEntityType, id: String?, suggested: String) throws -> EKCalendar {
        let options = type == .event ? getCalendars() : getReminderLists()
        if let id {
            guard let exact = options.first(where: { $0.calendarIdentifier == id }) else { throw FailureInfo(kind: .writing, title: "保存位置已经变化", message: "选中的日历或待办清单不存在或不可写入。", suggestion: "在纸条上重新选择保存位置后重试。") }
            return exact
        }
        let name = suggested.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = options.first(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) { return match }
        if !name.isEmpty, let match = options.first(where: { $0.title.localizedCaseInsensitiveContains(name) || name.localizedCaseInsensitiveContains($0.title) }) { return match }
        let fallback = type == .event ? eventStore.defaultCalendarForNewEvents : eventStore.defaultCalendarForNewReminders()
        if name.isEmpty, let fallback, fallback.allowsContentModifications { return fallback }
        // Preserve the original category-creation path, using writable sources only.
        let calendar = EKCalendar(for: type, eventStore: eventStore)
        calendar.title = name.isEmpty ? "Milo" : name
        calendar.source = fallback?.source ?? eventStore.sources.first { $0.sourceType == .calDAV } ?? eventStore.sources.first { $0.sourceType == .local }
        guard calendar.source != nil else { throw FailureInfo(kind: .writing, title: "还没有可用的保存位置", message: "系统中没有可用于新建分类的账户。", suggestion: "先在系统日历或提醒事项中设置可写入的账户。") }
        do { try eventStore.saveCalendar(calendar, commit: true); return calendar }
        catch { throw writeFailure("目标分类", error) }
    }
    private func writeFailure(_ target: String, _ error: Error) -> FailureInfo {
        FailureInfo(kind: .writing, title: "\(target)还没有保存成功", message: "\(target)写入失败，编辑结果和其他成功目标仍然保留。", suggestion: "检查权限、账户同步与保存位置后重试。", technical: SecretRedactor.redact(String(describing: error)))
    }
}
