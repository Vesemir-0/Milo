import Foundation
import Combine
import AppKit

@MainActor final class ContentProcessViewModel: ObservableObject {
    let identity = UUID()
    enum State { case idle, capturing, analyzing, review, saving, failed }
    @Published private(set) var state: State = .idle
    @Published var record: HistoryRecord?
    @Published var failure: FailureInfo?
    @Published var notice: String?
    @Published var diagnosing = false
    @Published var startedAt: Date?
    @Published var sourceText = ""
    @Published var page = 0
    var onPresentReview: (() -> Void)?
    var onPresentError: (() -> Void)?
    var onSaveStarted: (() -> Void)?
    var onSaveFinished: ((Bool) -> Void)?
    var isBusy: Bool { state == .capturing || state == .analyzing || state == .saving }
    var selectedCount: Int { record?.drafts.filter { $0.selected && !$0.isComplete }.count ?? 0 }
    let config: ConfigService
    let history: HistoryStore
    private let ai: AIService
    private let writer: DraftWriter
    private let capturer: @MainActor () async throws -> NSImage
    private var activeTask: Task<Void, Never>?
    private var diagnosticTask: Task<Void, Never>?
    private var pendingEditSave: Task<Void, Never>?
    private var jobID = UUID()
    private var lastContent: CapturedContent?
    private var requestSnapshot: AIConfig?

    init(config: ConfigService? = nil, history: HistoryStore? = nil, ai: AIService = .shared, eventWriter: EventWriting? = nil, capture: (@MainActor () async throws -> NSImage)? = nil) {
        self.config = config ?? .shared; self.history = history ?? .shared; self.ai = ai
        self.capturer = capture ?? { try await ContentCaptureService.shared.captureScreenshot() }
        writer = DraftWriter(writer: eventWriter ?? EventKitService.shared)
        _ = self.history.prune(days: self.config.settings.historyRetentionDays, limit: self.config.settings.historyLimit)
    }
    func captureScreenshot() {
        guard !isBusy else { return }
        flushEdits(); diagnosticTask?.cancel(); diagnosing = false; failure = nil; notice = nil; startedAt = Date()
        state = .capturing; let job = UUID(); jobID = job
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let image = try await capturer()
                guard jobID == job else { return }
                await recognize(CapturedContent(type: .image(image), source: "image"), job: job)
            } catch CaptureError.screenshotCancelled { if jobID == job { state = .idle } }
            catch is CancellationError { if jobID == job { state = .idle } }
            catch {
                guard jobID == job else { return }
                let f = FailureInfo.capture(error)
                failure = f; state = .failed; onPresentError?()
            }
        }
    }
    func startText(_ text: String) {
        guard !isBusy, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sourceText = text
        start(CapturedContent(type: .text(text), source: "text"))
    }
    private func start(_ content: CapturedContent) {
        guard !isBusy else { return }
        flushEdits(); diagnosticTask?.cancel(); diagnosing = false; let job = UUID(); jobID = job
        state = .analyzing; startedAt = Date(); failure = nil
        activeTask = Task { [weak self] in await self?.recognize(content, job: job) }
    }
    func processQueuedContent(_ content: CapturedContent, settings: AppSettings, initialRecord: HistoryRecord) async {
        let job = UUID(); jobID = job
        await recognize(content, job: job, settings: settings, initialRecord: initialRecord)
    }
    private func recognize(_ content: CapturedContent, job: UUID, settings suppliedSettings: AppSettings? = nil, initialRecord: HistoryRecord? = nil) async {
        guard jobID == job, !Task.isCancelled else { return }
        lastContent = content; state = .analyzing; failure = nil; notice = nil; startedAt = Date(); page = 0
        let settings = suppliedSettings ?? config.settings
        let snapshot = settings.aiConfig
        requestSnapshot = snapshot
        let autoAdd = settings.autoAddMode
        let defaultTarget = settings.saveTarget
        var newRecord = initialRecord ?? HistoryRecord(createdAt: content.timestamp, source: content.source, timeZoneID: content.timeZoneID, apiName: snapshot?.profileName ?? "未配置", modelName: snapshot?.modelName ?? "未选择模型", modelID: snapshot?.model ?? "")
        newRecord.status = .processing
        switch content.type {
        case .text(let text): newRecord.sourceText = text
        case .image(let image):
            if settings.keepScreenshots && newRecord.screenshotFile == nil {
                do { newRecord.screenshotFile = try history.saveImage(image, id: newRecord.id) }
                catch { notice = "这次没有保留截图原图，识别仍会继续。" }
            }
        }
        record = newRecord; _ = history.upsert(newRecord)
        do {
            guard let snapshot else { throw FailureInfo.configuration("先给 Milo 连接一项 AI 服务", suggestion: "在设置中添加 API 和模型，再继续识别。原文已经保留。") }
            let result = try await ai.analyzeContent(content, using: snapshot,
                calendars: EventKitService.shared.getCalendars().map(\.title), reminderLists: EventKitService.shared.getReminderLists().map(\.title), timeZone: TimeZone(identifier: content.timeZoneID) ?? .current)
            try Task.checkCancellation(); guard jobID == job else { return }
            newRecord.originalEvents = result.events
            newRecord.drafts = result.events.map { EventDraft(event: $0, target: defaultTarget) }
            newRecord.rawOutput = result.rawOutput; newRecord.duration = Date().timeIntervalSince(startedAt ?? Date()); newRecord.usage = result.usage; newRecord.footprint = result.footprint; newRecord.rawUsage = result.rawUsage; newRecord.status = .draft
            record = newRecord; _ = history.upsert(newRecord)
            _ = history.prune(days: config.settings.historyRetentionDays, limit: config.settings.historyLimit, protecting: newRecord.id)
            state = .review
            if autoAdd && config.settings.autoAddMode && !newRecord.drafts.isEmpty && newRecord.drafts.allSatisfy({ $0.validationMessage == nil }) { await saveSelected() }
            if record?.status != .added { onPresentReview?() }
        } catch is CancellationError { if jobID == job { state = .idle } }
        catch {
            guard jobID == job else { return }
            let f = FailureInfo.from(error)
            newRecord.failure = f; newRecord.status = .failed; newRecord.duration = Date().timeIntervalSince(startedAt ?? Date())
            newRecord.usage = f.usage; newRecord.rawOutput = f.rawOutput; newRecord.footprint = f.footprint; newRecord.rawUsage = f.rawUsage
            record = newRecord; _ = history.upsert(newRecord)
            _ = history.prune(days: config.settings.historyRetentionDays, limit: config.settings.historyLimit, protecting: newRecord.id)
            failure = f; state = .failed
            onPresentError?()
            if config.settings.explainComplexErrors, [.parsing, .response].contains(f.kind), let snapshot { diagnose(f, using: snapshot, recordID: newRecord.id) }
        }
    }
    func cancel() {
        flushEdits(); activeTask?.cancel(); diagnosticTask?.cancel(); diagnosing = false
        jobID = UUID()
        if var r = record, r.status == .processing {
            r.status = .failed; r.failure = FailureInfo(kind: .network, title: "这次整理已取消", message: "识别已主动停止，原始内容仍然保留。", suggestion: "需要时从历史重新打开。")
            record = r; _ = history.upsert(r)
        }
        state = .idle
    }
    var sourceImage: NSImage? { if case .image(let image) = lastContent?.type { return image }; return nil }
    var capturedSource: CapturedContent? { lastContent }
    var waitingLimit: Int { Int(requestSnapshot?.timeout ?? Double(config.settings.timeoutSeconds)) }
    func retry() {
        guard !isBusy else { return }
        if let lastContent { start(lastContent) }
        else if let r = record, let text = r.sourceText { start(CapturedContent(type: .text(text), source: "text", timestamp: r.createdAt, timeZoneID: r.timeZoneID)) }
        else if let r = record, let name = r.screenshotFile, let image = history.image(name) { start(CapturedContent(type: .image(image), source: "image", timestamp: r.createdAt, timeZoneID: r.timeZoneID)) }
        else { notice = "这条记录没有保留截图原图，请重新截图。" }
    }
    func open(_ requested: HistoryRecord) {
        guard !isBusy else { notice = "当前任务仍在进行，完成后再打开历史。"; return }
        flushEdits(); diagnosticTask?.cancel(); diagnosing = false; notice = nil
        let value = history.record(requested.id) ?? requested
        record = value; page = 0; failure = value.failure
        if let text = value.sourceText { sourceText = text; lastContent = CapturedContent(type: .text(text), source: "text", timestamp: value.createdAt, timeZoneID: value.timeZoneID) }
        else if let file = value.screenshotFile, let image = history.image(file) { lastContent = CapturedContent(type: .image(image), source: "image", timestamp: value.createdAt, timeZoneID: value.timeZoneID) }
        else { lastContent = nil }
        if value.drafts.isEmpty && value.failure != nil { state = .failed; onPresentError?() }
        else { state = .review; onPresentReview?() }
    }
    func updateDraft(_ value: EventDraft) {
        guard state != .saving, var r = record, let i = r.drafts.firstIndex(where: { $0.id == value.id }) else { return }
        r.drafts[i] = value; r.refreshStatus(); record = r
        pendingEditSave?.cancel()
        pendingEditSave = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)); try Task.checkCancellation() }
            catch { return }
            guard let self, record?.id == r.id else { return }
            if !history.upsert(r) { notice = history.storageWarning }
            pendingEditSave = nil
        }
    }
    func setAllSelected(_ selected: Bool) {
        guard !isBusy, var r = record else { return }
        flushEdits()
        for i in r.drafts.indices where !r.drafts[i].isComplete { r.drafts[i].selected = selected }
        record = r
        if !history.upsert(r) { notice = history.storageWarning }
    }
    func flushEdits() {
        guard pendingEditSave != nil else { return }
        pendingEditSave?.cancel(); pendingEditSave = nil
        if let record, !history.upsert(record) { notice = history.storageWarning }
    }
    func saveSelected() async {
        guard !isBusy, var r = record, selectedCount > 0 else { return }
        if let bad = r.drafts.first(where: { $0.selected && !$0.isComplete && $0.validationMessage != nil }) {
            notice = bad.validationMessage; page = r.drafts.firstIndex(where: { $0.id == bad.id }) ?? 0; return
        }
        flushEdits()
        let beforeSaving = r; r.status = .saving
        guard history.upsert(r) else {
            _ = history.upsert(beforeSaving)
            notice = "历史暂时无法保存，请先导出草稿并检查本机存储，再写入系统日历。"; return
        }
        record = r; state = .saving; failure = nil; notice = nil
        onSaveStarted?()
        let result = await writer.save(r.drafts) { [weak self] drafts in
            guard let self else { return false }
            r.drafts = drafts; r.status = .saving; record = r
            return history.upsert(r)
        }
        r.drafts = result.drafts; r.refreshStatus(); record = r
        state = .review
        if result.persistenceFailed { notice = "已有成功目标，但本机保存记录失败。为避免重复添加，已停止继续写入；请先导出当前草稿。" }
        else if r.drafts.contains(where: { $0.selected && !$0.isComplete && $0.saveError != nil }) { notice = "有些目标还没有写入。成功部分已记住，再次确认只处理未完成部分。" }
        else { notice = "已保存到你选择的日历和待办清单。" }
        PermissionManager.shared.checkAllPermissions()
        onSaveFinished?(!result.persistenceFailed && !r.drafts.contains(where: { $0.selected && !$0.isComplete }))
    }
    func discardRecord() {
        guard !isBusy else { return }
        pendingEditSave?.cancel(); pendingEditSave = nil
        diagnosticTask?.cancel(); diagnosing = false
        record = nil; failure = nil; notice = nil; lastContent = nil; state = .idle
    }
    private func diagnose(_ f: FailureInfo, using snapshot: AIConfig, recordID: UUID) {
        diagnosing = true
        diagnosticTask = Task { [weak self] in
            guard let self else { return }
            do {
                let explanation = try await ai.explain(f, using: snapshot)
                try Task.checkCancellation()
                guard record?.id == recordID else { return }
                failure?.explanation = explanation.text; failure?.diagnosticUsage = explanation.usage; failure?.diagnosticDuration = explanation.duration
                record?.failure = failure
                if let record { _ = history.upsert(record) }
            } catch {
                if !Task.isCancelled && record?.id == recordID {
                    let extra = FailureInfo.from(error)
                    failure?.diagnosticUsage = extra.usage; failure?.diagnosticDuration = extra.elapsed
                    record?.failure = failure
                    if let record { _ = history.upsert(record) }
                    notice = "辅助解释未完成，下面的本地说明仍然可用。"
                }
            }
            if record?.id == recordID { diagnosing = false }
        }
    }
}
