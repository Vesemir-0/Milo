import XCTest
import AppKit
@testable import MiloCore

@MainActor final class ScreenshotCaptureTests: XCTestCase {
    func testNativeSuccessfulExitWithoutAnImageIsSilentCancellation() async throws {
        // Exercise the actual Process/file pipeline, rather than mocking the cancellation error.
        let service = ContentCaptureService(executable: URL(fileURLWithPath: "/usr/bin/true"), accessCheck: { true })
        do { _ = try await service.captureScreenshot(); XCTFail("No file must mean cancelled") }
        catch CaptureError.screenshotCancelled { }
        catch { XCTFail("Unexpected capture failure: \(error)") }
    }
    func testEmptyCaptureAndPermissionFailuresAreDistinguished() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("MiloCaptureTests-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: file) }
        for status: Int32 in [0, 1, 130] {
            XCTAssertThrowsError(try ContentCaptureService.resolveCapture(status: status, file: file)) { error in
                guard case CaptureError.screenshotCancelled = error else { return XCTFail("Expected quiet cancellation") }
            }
        }
        try Data().write(to: file)
        XCTAssertThrowsError(try ContentCaptureService.resolveCapture(status: 0, file: file)) { error in
            guard case CaptureError.screenshotCancelled = error else { return XCTFail("Empty file is cancellation") }
        }
        XCTAssertThrowsError(try ContentCaptureService.resolveCapture(status: 1, file: file, diagnostic: "screen capture permission denied")) { error in
            guard case CaptureError.permissionDenied = error else { return XCTFail("Permission errors must stay actionable") }
        }
        try Data("corrupt PNG".utf8).write(to: file)
        XCTAssertThrowsError(try ContentCaptureService.resolveCapture(status: 0, file: file)) { error in
            guard case CaptureError.screenshotFailed = error else { return XCTFail("Corrupt files must not look cancelled") }
        }
    }
    func testNoOutputDoesNotPresentAnErrorOrCreateHistory() async throws {
        let name = "MiloCaptureTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let config = ConfigService(defaults: defaults, keychain: MemorySecretStore()), history = HistoryStore(directory: directory)
        let service = ContentCaptureService(executable: URL(fileURLWithPath: "/usr/bin/true"), accessCheck: { true })
        let queue = RecognitionQueue(config: config, history: history, eventWriter: MockWriter(), capture: { try await service.captureScreenshot() })
        let finished = expectation(description: "cancelled capture ended")
        queue.onCaptureEnded = { finished.fulfill() }
        queue.onFailure = { _ in XCTFail("No failure popup on Esc/no image") }
        queue.onReady = { _ in XCTFail("No AI job without an image") }
        queue.captureScreenshot()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertTrue(history.records.isEmpty); XCTAssertFalse(queue.isCapturing); XCTAssertEqual(queue.outstandingCount, 0)
        queue.shutdown()
    }
}
