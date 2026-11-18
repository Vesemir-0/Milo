import XCTest
import AppKit
@testable import MiloCore

@MainActor final class ViewModelTests: XCTestCase {
    func testScreenshotEscapeIsSilentAndDoesNotCreateHistoryOrCallAI() async throws {
        let name = "MiloTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: dir) }
        let history = HistoryStore(directory: dir), config = ConfigService(defaults: defaults, keychain: MemorySecretStore())
        let cancelled = expectation(description: "capture cancelled")
        let vm = ContentProcessViewModel(config: config, history: history, eventWriter: MockWriter(), capture: { cancelled.fulfill(); throw CaptureError.screenshotCancelled })
        var errorPresented = false; vm.onPresentError = { errorPresented = true }
        vm.captureScreenshot()
        await fulfillment(of: [cancelled], timeout: 2)
        await Task.yield()
        XCTAssertEqual(vm.state, .idle); XCTAssertNil(vm.failure); XCTAssertTrue(history.records.isEmpty); XCTAssertFalse(errorPresented)
    }
    func testRecognitionEditingHistoryReopenAndSavingUseOneAPIRequest() async throws {
        let name = "MiloTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: dir) }
        let history = HistoryStore(directory: dir), config = ConfigService(defaults: defaults, keychain: MemorySecretStore())
        let model = ModelProfile(name: "test", modelID: "test")
        var settings = AppSettings.default; settings.apiProfiles = [APIProfile(name: "test", baseURL: "https://mock.example/v1", models: [model])]; settings.repairSelection(); try config.save(settings)
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        var requests = 0
        MockHTTP.handler = { _ in requests += 1; return (200, MockHTTP.completion(#"{"events":[{"title":"评审","startDate":"2026-11-19T14:00:00+08:00","description":"原始说明"}]}"#)) }
        let writer = MockWriter(), vm = ContentProcessViewModel(config: config, history: history, ai: AIService(session: session), eventWriter: writer)
        let ready = expectation(description: "review")
        vm.onPresentReview = { ready.fulfill() }
        vm.startText("明天开会")
        await fulfillment(of: [ready], timeout: 5)
        var draft = try XCTUnwrap(vm.record?.drafts.first); draft.event.title = "修改后的评审"; draft.event.setBody("第一行\n第二行")
        let stale = try XCTUnwrap(vm.record)
        vm.updateDraft(draft)
        vm.onPresentReview = nil; vm.open(stale)
        XCTAssertEqual(vm.record?.drafts[0].event.title, "修改后的评审")
        let saved = try XCTUnwrap(history.record(try XCTUnwrap(vm.record?.id)))
        vm.onPresentReview = nil; vm.open(saved)
        XCTAssertEqual(requests, 1); XCTAssertEqual(vm.record?.drafts[0].event.readableBody, "第一行\n第二行")
        await vm.saveSelected()
        XCTAssertEqual(writer.calendarEvents.first?.title, "修改后的评审"); XCTAssertEqual(requests, 1)
        let reopened = HistoryStore(directory: dir).record(saved.id)
        XCTAssertTrue(reopened?.drafts[0].isComplete == true)
    }
}
