import XCTest
import AppKit
@testable import MiloCore

@MainActor private final class JobFixture {
    let name = "MiloQueueTests.\(UUID())"
    let directory: URL
    let defaults: UserDefaults
    let config: ConfigService
    let history: HistoryStore
    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defaults = UserDefaults(suiteName: name)!
        config = ConfigService(defaults: defaults, keychain: MemorySecretStore()); history = HistoryStore(directory: directory)
        let model = ModelProfile(name: "first", modelID: "model-first")
        var settings = AppSettings.default
        settings.apiProfiles = [APIProfile(name: "first", baseURL: "https://mock.example/v1", apiKey: "fixture-first", models: [model])]
        settings.maximumConcurrentRecognitions = 1; settings.explainComplexErrors = false; settings.repairSelection(); try config.save(settings)
    }
    func close() { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
}

@MainActor final class RecognitionQueueTests: XCTestCase {
    func testContinuousSubmissionKeepsFIFOSettingsAndSeparateEditableResults() async throws {
        let fixture = try JobFixture(); defer { fixture.close() }
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        let queue = RecognitionQueue(config: fixture.config, history: fixture.history, ai: AIService(session: session), eventWriter: MockWriter())
        let finished = expectation(description: "three independent results"); finished.expectedFulfillmentCount = 3
        var workers: [ContentProcessViewModel] = [], sentText: [String] = [], sentModels: [String] = [], sentKeys: [String] = []
        var inFlight = 0, maximumInFlight = 0
        MockHTTP.delay = 0.06
        MockHTTP.onStart = { inFlight += 1; maximumInFlight = max(maximumInFlight, inFlight) }
        MockHTTP.handler = { request in
            let body = try MockHTTP.body(request), messages = body["messages"] as! [[String: Any]]
            let text = messages.last!["content"] as! String
            sentText.append(text); sentModels.append(body["model"] as! String); sentKeys.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
            inFlight -= 1
            return (200, MockHTTP.completion(String(data: try JSONSerialization.data(withJSONObject: ["events":[["title": text]]]), encoding: .utf8)!))
        }
        queue.onReady = { worker in workers.append(worker); finished.fulfill() }
        let firstID = try XCTUnwrap(queue.enqueueText("第一份"))
        var changed = fixture.config.settings
        changed.apiProfiles[0].models[0].modelID = "model-second"; changed.apiProfiles[0].apiKey = "fixture-second"; changed.saveTarget = .reminderOnly
        try fixture.config.save(changed)
        queue.enqueueText("第二份"); queue.enqueueText("第三份")
        XCTAssertEqual(queue.outstandingCount, 3)
        await fulfillment(of: [finished], timeout: 5)
        XCTAssertEqual(sentText, ["第一份", "第二份", "第三份"]); XCTAssertEqual(sentModels, ["model-first", "model-second", "model-second"])
        XCTAssertEqual(sentKeys, ["Bearer fixture-first", "Bearer fixture-second", "Bearer fixture-second"]); XCTAssertEqual(maximumInFlight, 1)
        XCTAssertEqual(workers[0].record?.id, firstID); XCTAssertEqual(workers[0].record?.drafts[0].target, .both)
        XCTAssertEqual(workers[1].record?.drafts[0].target, .reminderOnly)
        var edit = try XCTUnwrap(workers[0].record?.drafts.first); edit.event.title = "只修改第一份"; workers[0].updateDraft(edit); workers[0].flushEdits()
        XCTAssertEqual(workers[1].record?.drafts[0].event.title, "第二份")
        XCTAssertEqual(fixture.history.records.count, 3); XCTAssertEqual(fixture.history.record(firstID)?.drafts[0].event.title, "只修改第一份")
        queue.shutdown()
    }
    func testFailedJobDoesNotBlockTheNextAndEscapeDoesNotCreateAJob() async throws {
        let fixture = try JobFixture(); defer { fixture.close() }
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        let queue = RecognitionQueue(config: fixture.config, history: fixture.history, ai: AIService(session: session), eventWriter: MockWriter(), capture: { throw CaptureError.screenshotCancelled })
        let failed = expectation(description: "first failed"), ready = expectation(description: "second ready"), captured = expectation(description: "escape")
        var requests = 0
        MockHTTP.handler = { _ in requests += 1; return requests == 1 ? (401, Data("rejected".utf8)) : (200, MockHTTP.completion(#"{"events":[{"title":"继续整理"}]}"#)) }
        queue.onFailure = { _ in failed.fulfill() }; queue.onReady = { _ in ready.fulfill() }; queue.onCaptureEnded = { captured.fulfill() }
        let first = try XCTUnwrap(queue.enqueueText("失败记录")); let second = try XCTUnwrap(queue.enqueueText("后续记录"))
        queue.captureScreenshot()
        await fulfillment(of: [failed, ready, captured], timeout: 5)
        XCTAssertEqual(requests, 2); XCTAssertFalse(queue.isCapturing)
        XCTAssertEqual(fixture.history.records.count, 2); XCTAssertEqual(fixture.history.record(first)?.status, .failed)
        XCTAssertEqual(fixture.history.record(second)?.status, .draft); queue.shutdown()
    }
    func testCancellingActiveRequestContinuesWithPendingJob() async throws {
        let fixture = try JobFixture(); defer { fixture.close() }
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        let queue = RecognitionQueue(config: fixture.config, history: fixture.history, ai: AIService(session: session), eventWriter: MockWriter())
        let started = expectation(description: "first started"), ready = expectation(description: "second ready")
        var starts = 0
        MockHTTP.onStart = { starts += 1; if starts == 1 { started.fulfill() } }; MockHTTP.delay = 0.12
        MockHTTP.handler = { _ in (200, MockHTTP.completion(#"{"events":[{"title":"下一份"}]}"#)) }
        queue.onReady = { _ in ready.fulfill() }
        let cancelledID = try XCTUnwrap(queue.enqueueText("取消这份")); queue.enqueueText("保留下一份")
        await fulfillment(of: [started], timeout: 3); queue.cancelCurrent()
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(starts, 2); XCTAssertEqual(fixture.history.record(cancelledID)?.status, .failed); queue.shutdown()
    }
    func testSelectionSpansAllPagesAndSavingClosesOnlyAfterValidationThenReportsPartialFailure() async throws {
        let fixture = try JobFixture(); defer { fixture.close() }
        let writer = MockWriter(); writer.failingReminderCalls = [1]
        let worker = ContentProcessViewModel(config: fixture.config, history: fixture.history, eventWriter: writer)
        var record = HistoryRecord(apiName: "test", modelName: "test", modelID: "test")
        record.drafts = (0..<9).map { EventDraft(event: ParsedEvent(title: "条目\($0)", startDate: Date()), target: .both) }
        record.drafts[0].target = .calendarOnly; record.drafts[0].savedCalendarID = "existing"; record.drafts[0].selected = false; record.refreshStatus()
        fixture.history.upsert(record); worker.open(record); worker.page = 6
        worker.setAllSelected(false); XCTAssertEqual(worker.selectedCount, 0)
        worker.setAllSelected(true); XCTAssertEqual(worker.selectedCount, 8); XCTAssertFalse(worker.record!.drafts[0].selected)
        var closed = false, saveSucceeded: Bool?
        worker.onSaveStarted = { closed = true; XCTAssertEqual(writer.calendarCalls, 0) }
        worker.onSaveFinished = { saveSucceeded = $0 }
        await worker.saveSelected()
        XCTAssertTrue(closed); XCTAssertEqual(saveSucceeded, false); XCTAssertEqual(writer.calendarCalls, 8)
        XCTAssertNotNil(worker.record?.drafts[1].savedCalendarID); XCTAssertNotNil(worker.record?.drafts[1].saveError)
        worker.onSaveStarted = {}; writer.failingReminderCalls = []
        await worker.saveSelected()
        XCTAssertEqual(saveSucceeded, true); XCTAssertEqual(writer.calendarCalls, 8)
        var invalid = record; invalid.id = UUID(); invalid.drafts = [EventDraft(event: ParsedEvent(title: "未定时间"), target: .calendarOnly)]
        fixture.history.upsert(invalid); worker.open(invalid); closed = false; worker.onSaveStarted = { closed = true }
        await worker.saveSelected(); XCTAssertFalse(closed); XCTAssertNotNil(worker.notice)
    }
    func testDeletingAnOpenDraftCancelsPendingEditsWithoutRecreatingHistory() async throws {
        let fixture = try JobFixture(); defer { fixture.close() }
        let worker = ContentProcessViewModel(config: fixture.config, history: fixture.history, eventWriter: MockWriter())
        var record = HistoryRecord(apiName: "test", modelName: "test", modelID: "test")
        record.drafts = [EventDraft(event: ParsedEvent(title: "保留原文"), target: .reminderOnly)]; record.status = .draft
        fixture.history.upsert(record); worker.open(record)
        var edit = record.drafts[0]; edit.event.title = "尚未落盘的编辑"; worker.updateDraft(edit)
        XCTAssertTrue(fixture.history.remove([record.id])); worker.discardRecord(); worker.flushEdits()
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertNil(worker.record); XCTAssertNil(fixture.history.record(record.id))
        XCTAssertTrue(HistoryStore(directory: fixture.directory).records.isEmpty)
    }

    func testIndependentRequestsActuallyOverlapAndPresentInCompletionOrder() async throws {
        let fixture = try JobFixture(); defer { fixture.close() }
        var settings = fixture.config.settings; settings.maximumConcurrentRecognitions = 3; try fixture.config.save(settings)
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        let queue = RecognitionQueue(config: fixture.config, history: fixture.history, ai: AIService(session: session), eventWriter: MockWriter())
        let ready = expectation(description: "all concurrent jobs finished"); ready.expectedFulfillmentCount = 4
        var inFlight = 0, maximum = 0, completions: [String] = []
        MockHTTP.onStart = { inFlight += 1; maximum = max(maximum, inFlight) }
        MockHTTP.delayForRequest = { request in
            let body = try! MockHTTP.body(request), model = body["model"] as! String
            return model == "slow" ? 0.25 : 0.04
        }
        MockHTTP.handler = { request in
            let body = try MockHTTP.body(request), model = body["model"] as! String
            inFlight -= 1
            return (200, MockHTTP.completion(String(data: try JSONSerialization.data(withJSONObject: ["events":[["title":model]]]), encoding: .utf8)!))
        }
        queue.onReady = { worker in completions.append(worker.record!.drafts[0].event.title); ready.fulfill() }
        for model in ["slow", "fast-a", "fast-b", "fast-c"] {
            var snapshot = fixture.config.settings; snapshot.apiProfiles[0].models[0].modelID = model
            queue.enqueue(CapturedContent(type: .text(model), source: "text"), settings: snapshot)
        }
        XCTAssertEqual(queue.activeWorkers.count, 3); XCTAssertEqual(queue.waiting.count, 1)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(maximum, 3); XCTAssertEqual(completions.last, "slow")
        XCTAssertEqual(Set(completions), Set(["slow", "fast-a", "fast-b", "fast-c"]))
        XCTAssertEqual(fixture.history.records.count, 4); XCTAssertEqual(queue.outstandingCount, 0)
        queue.shutdown()
    }
    func testCancellingOneConcurrentRequestDoesNotCancelTheOthers() async throws {
        let fixture = try JobFixture(); defer { fixture.close() }
        var settings = fixture.config.settings; settings.maximumConcurrentRecognitions = 3; try fixture.config.save(settings)
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        let queue = RecognitionQueue(config: fixture.config, history: fixture.history, ai: AIService(session: session), eventWriter: MockWriter())
        let started = expectation(description: "three started"); started.expectedFulfillmentCount = 3
        let ready = expectation(description: "two survived"); ready.expectedFulfillmentCount = 2
        MockHTTP.onStart = { started.fulfill() }; MockHTTP.delay = 0.18
        MockHTTP.handler = { _ in (200, MockHTTP.completion(#"{"events":[{"title":"完成"}]}"#)) }
        queue.onReady = { _ in ready.fulfill() }
        let cancelledID = queue.enqueueText("只取消这一项")!
        queue.enqueueText("保留第二项"); queue.enqueueText("保留第三项")
        await fulfillment(of: [started], timeout: 3); queue.cancel(cancelledID)
        await fulfillment(of: [ready], timeout: 5)
        XCTAssertEqual(fixture.history.record(cancelledID)?.status, .failed)
        XCTAssertEqual(fixture.history.records.filter { $0.status == .draft }.count, 2)
        queue.shutdown()
    }

}
