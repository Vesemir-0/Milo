import Foundation

enum RecordStatus: String, Codable, CaseIterable { case queued, processing, saving, draft, added, partial, failed
    var label: String {
        switch self { case .queued: return "排队中"; case .processing: return "整理中"; case .saving: return "写入中"; case .draft: return "草稿"; case .added: return "已添加"; case .partial: return "部分完成"; case .failed: return "未完成" }
    }
}
struct HistoryRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var source = "text"
    var sourceText: String?
    var screenshotFile: String?
    var timeZoneID = TimeZone.current.identifier
    var apiName: String
    var modelName: String
    var modelID: String
    var duration: TimeInterval?
    var usage: TokenUsage?
    var rawOutput: String?
    var footprint: RequestFootprint?
    var rawUsage: String?
    var originalEvents: [ParsedEvent] = []
    var drafts: [EventDraft] = []
    var failure: FailureInfo?
    var status: RecordStatus = .processing
    var title: String { drafts.first?.event.title.isEmpty == false ? drafts[0].event.title : source == "image" ? "截图识别" : String((sourceText ?? "识别记录").prefix(32)).components(separatedBy: .newlines).first ?? "识别记录" }
    mutating func refreshStatus() {
        if drafts.isEmpty { status = failure == nil ? .draft : .failed; return }
        let complete = drafts.filter(\.isComplete).count
        if complete == drafts.count { status = .added }
        else if drafts.contains(where: \.hasSavedTargets) { status = .partial }
        else { status = .draft }
    }
}
