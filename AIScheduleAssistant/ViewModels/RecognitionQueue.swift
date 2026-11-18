import Foundation
import AppKit
import Combine

/// Requests run concurrently up to the configured limit. Each worker owns its own snapshot and draft.
@MainActor final class RecognitionQueue: ObservableObject {
    struct PendingSummary: Identifiable, Equatable {
        let id: UUID
        let title: String
        let model: String
    }
    private struct Job {
        let content: CapturedContent
        let settings: AppSettings
        let record: HistoryRecord
    }
    @Published private(set) var waiting: [PendingSummary] = []
    @Published private(set) var activeWorkers: [ContentProcessViewModel] = []
    var activeWorker: ContentProcessViewModel? { activeWorkers.first }
    @Published private(set) var latestWorker: ContentProcessViewModel?
    @Published private(set) var isCapturing = false
    @Published var notice: String?
    var onReady: ((ContentProcessViewModel) -> Void)?
    var onFailure: ((ContentProcessViewModel) -> Void)?
    var onWorkerCreated: ((ContentProcessViewModel) -> Void)?
    var onCaptureEnded: (() -> Void)?
    let config: ConfigService
    let history: HistoryStore
    private let ai: AIService
    private let eventWriter: EventWriting?
    private let capturer: @MainActor () async throws -> NSImage
    private var pending: [Job] = []
    private var activeTasks: [UUID: Task<Void, Never>] = [:]
    private var limitObserver: AnyCancellable?
    private var scheduling = false
    private var captureTask: Task<Void, Never>?
    private var stopping = false
    var outstandingCount: Int { waiting.count + activeWorkers.count }
    var isWorking: Bool { !activeWorkers.isEmpty || !waiting.isEmpty }
    var concurrencyLimit: Int { min(8, max(1, config.settings.maximumConcurrentRecognitions)) }

    init(config: ConfigService? = nil, history: HistoryStore? = nil, ai: AIService = .shared, eventWriter: EventWriting? = nil, capture: (@MainActor () async throws -> NSImage)? = nil) {
        self.config = config ?? .shared; self.history = history ?? .shared; self.ai = ai; self.eventWriter = eventWriter
        capturer = capture ?? { try await ContentCaptureService.shared.captureScreenshot() }
        limitObserver = self.config.$settings.map(\.maximumConcurrentRecognitions).removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor in self?.fillAvailableSlots() }
        }
    }
    @discardableResult func enqueueText(_ text: String) -> UUID? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return enqueue(CapturedContent(type: .text(text), source: "text"), settings: config.settings)
    }
    @discardableResult func enqueue(_ content: CapturedContent, settings supplied: AppSettings? = nil) -> UUID {
        let settings = supplied ?? config.settings
        let api = settings.aiConfig
        var record = HistoryRecord(createdAt: content.timestamp, source: content.source, timeZoneID: content.timeZoneID,
            apiName: api?.profileName ?? "未配置", modelName: api?.modelName ?? "未选择模型", modelID: api?.model ?? "")
        record.status = .queued
        switch content.type {
        case .text(let text): record.sourceText = text
        case .image(let image):
            if settings.keepScreenshots {
                do { record.screenshotFile = try history.saveImage(image, id: record.id) }
                catch { notice = "截图已加入队列，但这次没有保留原图。" }
            }
        }
        _ = history.upsert(record)
        pending.append(Job(content: content, settings: settings, record: record)); publishWaiting(); fillAvailableSlots()
        return record.id
    }
    func captureScreenshot(after delay: Duration = .zero) {
        guard !isCapturing, !stopping else { return }
        isCapturing = true; notice = nil
        let settings = config.settings
        let timestamp = Date(), timeZoneID = TimeZone.current.identifier
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { isCapturing = false; captureTask = nil; if !stopping { onCaptureEnded?() } }
            do {
                if delay > .zero { try await Task.sleep(for: delay) }
                let image = try await capturer(); try Task.checkCancellation()
                enqueue(CapturedContent(type: .image(image), source: "image", timestamp: timestamp, timeZoneID: timeZoneID), settings: settings)
            } catch CaptureError.screenshotCancelled { }
            catch is CancellationError { }
            catch {
                let worker = makeWorker()
                worker.failure = FailureInfo.capture(error)
                latestWorker = worker; onFailure?(worker)
            }
        }
    }
    func cancelCurrent() { if let id = activeWorker?.record?.id { cancel(id) } }
    func cancel(_ id: UUID) {
        guard let worker = activeWorkers.first(where: { $0.record?.id == id }), worker.state == .analyzing else { return }
        activeTasks[id]?.cancel(); worker.cancel()
    }
    func forgetHistory(_ ids: Set<UUID>) {
        if let id = latestWorker?.record?.id, ids.contains(id) { latestWorker?.discardRecord(); latestWorker = nil }
    }
    func shutdown() {
        stopping = true; captureTask?.cancel()
        for task in activeTasks.values { task.cancel() }
        for worker in activeWorkers { worker.cancel() }
        latestWorker?.flushEdits()
        for job in pending {
            var record = job.record; record.status = .failed
            record.failure = FailureInfo(kind: .network, title: "应用退出前尚未开始", message: "这项识别留在了队列中，原文已保留。", suggestion: "下次从历史打开后重试。")
            _ = history.upsert(record)
        }
        pending.removeAll(); publishWaiting()
    }
    private func makeWorker() -> ContentProcessViewModel {
        let worker = ContentProcessViewModel(config: config, history: history, ai: ai, eventWriter: eventWriter)
        onWorkerCreated?(worker)
        return worker
    }
    private func fillAvailableSlots() {
        guard !stopping, !scheduling else { return }
        scheduling = true
        defer { scheduling = false; publishWaiting() }
        while activeTasks.count < concurrencyLimit && !pending.isEmpty {
            let job = pending.removeFirst()
            let worker = makeWorker()
            activeWorkers.append(worker)
            activeTasks[job.record.id] = Task { [weak self, worker] in
                guard let self else { return }
                await worker.processQueuedContent(job.content, settings: job.settings, initialRecord: job.record)
                activeTasks[job.record.id] = nil
                activeWorkers.removeAll { $0 === worker }
                guard !stopping else { return }
                latestWorker = worker
                if worker.state == .failed { onFailure?(worker) }
                else if worker.state == .review, worker.record?.status != .added { onReady?(worker) }
                fillAvailableSlots()
            }
        }
    }
    private func publishWaiting() {
        waiting = pending.map { PendingSummary(id: $0.record.id, title: $0.record.title, model: $0.record.modelName) }
    }
}
