import XCTest
import AppKit
@testable import MiloCore

final class MockHTTP: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    static var delay: TimeInterval = 0
    static var delayForRequest: ((URLRequest) -> TimeInterval)?
    static var onStart: (() -> Void)?
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.onStart?()
        let deliver = { [weak self] in
            guard let self, !self.stopped else { return }
            do {
                let result = try Self.handler?(self.request) ?? (200, Data())
                let response = HTTPURLResponse(url: self.request.url!, statusCode: result.0, httpVersion: "HTTP/1.1", headerFields: ["Content-Type":"application/json"] )!
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: result.1); self.client?.urlProtocolDidFinishLoading(self)
            } catch { self.client?.urlProtocol(self, didFailWithError: error) }
        }
        let delay = Self.delayForRequest?(request) ?? Self.delay
        if delay > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: deliver) } else { deliver() }
    }
    override func stopLoading() { stopped = true }
    static func session() -> URLSession {
        delay = 0; delayForRequest = nil; onStart = nil
        let options = URLSessionConfiguration.ephemeral; options.protocolClasses = [MockHTTP.self]
        return URLSession(configuration: options)
    }
    static func body(_ request: URLRequest) throws -> [String: Any] {
        if let data = request.httpBody { return try JSONSerialization.jsonObject(with: data) as! [String: Any] }
        guard let stream = request.httpBodyStream else { return [:] }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(buffer, count: count)
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
    static func completion(_ content: String, finish: String = "stop", usage: [String:Int]? = nil) -> Data {
        var object: [String:Any] = ["choices":[["message":["content":content], "finish_reason":finish]]]
        if let usage { object["usage"] = usage }
        return try! JSONSerialization.data(withJSONObject: object)
    }
}

final class AIServiceTests: XCTestCase {
    func testEndpointAndOptionalParametersUseOneRequestPath() throws {
        var config = AIConfig.default; config.model = "gpt-5"; config.baseURL = "https://example.com/v1/"; config.apiKey = "test-secret"
        let request = try AIService().makeRequest(config: config, system: "system", user: "a")
        let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String:Any]
        XCTAssertEqual(request.url?.absoluteString, "https://example.com/v1/chat/completions")
        XCTAssertNil(body["temperature"]); XCTAssertNil(body["max_tokens"])
        XCTAssertEqual(body["max_completion_tokens"] as? Int, 4000)
        XCTAssertEqual(request.timeoutInterval, 180)
        config.baseURL = "http://localhost:9000/v1/chat/completions"; config.model = "custom-model"; config.apiKey = ""; config.temperature = 0.4; config.outputLimitParameter = .omit
        let other = try AIService().makeRequest(config: config, system: "s", user: [["type":"text","text":"x"], ["type":"image_url","image_url":["url":"data:image/png;base64,AA=="]]] as [[String:Any]])
        let imageBody = try JSONSerialization.jsonObject(with: other.httpBody!) as! [String:Any]
        XCTAssertEqual(other.url?.path, "/v1/chat/completions"); XCTAssertNil(other.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(imageBody["temperature"] as? Double, 0.4); XCTAssertNil(imageBody["max_tokens"]); XCTAssertNil(imageBody["max_completion_tokens"])
        config.baseURL = "https://example.com/v1?api_key=private"; XCTAssertNil(config.endpoint)
    }
    func testParserPreservesNotesLinksFractionalDatesAndMissingOptionalFields() throws {
        let data = """
        ```json
        {"events":[{"title":"详细安排","description":"保留第一行。\\n保留第二行。链接 https://example.com/a.b 不拆。","notes":["带材料","核对编号1.2"],"startDate":"2026-11-18T14:00:00.123+08:00","endDate":"2026-11-18T15:00:00+08:00","dueDate":"2026-11-19T18:00:00+08:00","location":"A301","url":"https://example.com/a.b"},{"title":"以后读书"}]}
        ```
        """
        let items = try AIService.parseResponse(data, timeZone: TimeZone(secondsFromGMT: 8 * 3600)!)
        XCTAssertEqual(items.count, 2); XCTAssertTrue(items[0].readableBody.contains("\n保留第二行")); XCTAssertTrue(items[0].readableBody.contains("带材料\n\n核对编号1.2"))
        XCTAssertNotEqual(items[0].startDate, items[0].dueDate); XCTAssertEqual(items[0].url, "https://example.com/a.b")
        XCTAssertNil(items[1].startDate); XCTAssertNil(items[1].dueDate)
        XCTAssertEqual(try AIService.parseResponse("{\"events\":[]}").count, 0)
        XCTAssertThrowsError(try AIService.parseResponse("{\"events\":[{\"title\":\"坏日期\",\"startDate\":\"no date\"}]}"))
    }
    @MainActor func testTruncationRetainsUsageAndRawOutput() async throws {
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        MockHTTP.handler = { _ in (200, MockHTTP.completion("{\"events\":[", finish: "length", usage: ["prompt_tokens":100,"completion_tokens":40,"total_tokens":140])) }
        var config = AIConfig.default; config.model = "test"
        do { _ = try await AIService(session: session).analyzeContent(CapturedContent(type: .text("hello"), source: "text"), using: config); XCTFail("Expected truncation error") }
        catch let f as FailureInfo { XCTAssertEqual(f.kind, .parsing); XCTAssertEqual(f.usage?.total, 140); XCTAssertEqual(f.rawOutput, "{\"events\":["); XCTAssertTrue(f.suggestion.contains("输出上限")) }
    }
    @MainActor func testImageRecognitionUsesPNGDataURLAndSameOptionalParameters() async throws {
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        var body: [String:Any] = [:]
        MockHTTP.handler = { request in
            var data = request.httpBody
            if data == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var collected = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; collected.append(buffer, count: n) }
                data = collected
            }
            body = (try JSONSerialization.jsonObject(with: data ?? Data())) as! [String:Any]
            return (200, MockHTTP.completion("{\"events\":[]}"))
        }
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus(); NSColor.white.setFill(); NSRect(x: 0,y: 0,width: 16,height: 16).fill(); image.unlockFocus()
        var config = AIConfig.default; config.model = "image-test"
        let result = try await AIService(session: session).analyzeContent(CapturedContent(type: .image(image), source: "image"), using: config)
        let messages = try XCTUnwrap(body["messages"] as? [[String:Any]])
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String:Any]])
        let url = try XCTUnwrap((parts.last?["image_url"] as? [String:String])?["url"])
        XCTAssertTrue(url.hasPrefix("data:image/png;base64,")); XCTAssertNil(body["temperature"]); XCTAssertTrue(result.events.isEmpty)
    }
    @MainActor func testClientTimeoutIsDistinctFromOutputParsing() async throws {
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        MockHTTP.handler = { _ in throw URLError(.timedOut) }
        var config = AIConfig.default; config.model = "test"; config.timeout = 300
        do { _ = try await AIService(session: session).analyzeContent(CapturedContent(type: .text("test"), source: "text"), using: config); XCTFail("Expected timeout") }
        catch let failure as FailureInfo { XCTAssertEqual(failure.kind, .timeout); XCTAssertNil(failure.rawOutput); XCTAssertNotNil(failure.elapsed); XCTAssertTrue(failure.technical.contains("300 秒")) }
    }
    @MainActor func testLongValidOutputIsNotTruncatedBeforeParsing() async throws {
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        let body = String(repeating: "完整正文", count: 20000)
        let content = String(data: try JSONSerialization.data(withJSONObject: ["events":[["title":"长文","description":body]]]), encoding: .utf8)!
        MockHTTP.handler = { _ in (200, MockHTTP.completion(content)) }
        var config = AIConfig.default; config.model = "test"
        let result = try await AIService(session: session).analyzeContent(CapturedContent(type: .text("test"), source: "text"), using: config)
        XCTAssertEqual(result.events[0].description, body)
        XCTAssertLessThanOrEqual(result.rawOutput.count, 64000)
    }
    func testHTTPFailuresAreActionableAndDoNotLeakKeys() {
        let f = AIService.httpFailure(status: 400, body: "{\"error\":\"unsupported temperature test-secret Bearer sk-abcdefghijklmnop\"}", requestID: "req-1", secret: "test-secret")
        XCTAssertEqual(f.kind, .parameter); XCTAssertTrue(f.suggestion.contains("不发送")); XCTAssertFalse(f.technical.contains("test-secret")); XCTAssertFalse(f.technical.contains("sk-abcdefghijklmnop"))
        XCTAssertEqual(AIService.httpFailure(status: 401, body: "auth", requestID: nil, secret: "").kind, .authentication)
        XCTAssertEqual(AIService.httpFailure(status: 504, body: "timeout", requestID: nil, secret: "").kind, .timeout)
        XCTAssertNil(AIService.usage(nil))
    }
    func testCancellationStopsInsteadOfBecomingAnErrorPopup() async throws {
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        let started = expectation(description: "request started")
        MockHTTP.onStart = { started.fulfill() }; MockHTTP.delay = 20
        MockHTTP.handler = { _ in (200, MockHTTP.completion("OK")) }
        var config = AIConfig.default; config.model = "test"
        let task = Task { try await AIService(session: session).testConnection(config) }
        await fulfillment(of: [started], timeout: 3); task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch is CancellationError { } catch { XCTFail("Cancellation should remain cancellation") }
    }
    func testConnectionIsASingleTinyBudgetedRequestEvenWhenRecognitionOmitsLimit() async throws {
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        var calls = 0
        MockHTTP.handler = { request in
            calls += 1
            let body = try MockHTTP.body(request)
            let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
            XCTAssertEqual(messages.count, 1); XCTAssertEqual(messages[0]["role"] as? String, "user")
            XCTAssertEqual(messages[0]["content"] as? String, "Reply OK.")
            XCTAssertEqual(body["max_completion_tokens"] as? Int, 64)
            return (200, MockHTTP.completion("OK", usage: ["prompt_tokens":18000, "completion_tokens":5, "total_tokens":18005]))
        }
        var config = AIConfig.default; config.model = "gpt-5"; config.outputLimitParameter = .omit
        let report = try await AIService(session: session).testConnection(config)
        XCTAssertEqual(calls, 1); XCTAssertEqual(report.usage?.input, 18000)
        XCTAssertNotNil(report.rawUsage); XCTAssertTrue(report.returnedText)
        XCTAssertEqual(report.footprint?.systemCharacters, 0); XCTAssertEqual(report.footprint?.inputCharacters, 9)
        XCTAssertEqual(report.footprint?.imageCount, 0)
        XCTAssertEqual(config.outputLimitParameter, .omit)
    }
    func testBudgetLimitedReasoningProbeNeverRetriesWithABiggerBudget() async throws {
        let session = MockHTTP.session(); defer { session.invalidateAndCancel() }
        var calls = 0
        MockHTTP.handler = { _ in calls += 1; return (200, MockHTTP.completion("", finish: "length", usage: ["prompt_tokens":10, "completion_tokens":64])) }
        var config = AIConfig.default; config.model = "gpt-5"
        let report = try await AIService(session: session).testConnection(config)
        XCTAssertFalse(report.returnedText); XCTAssertEqual(calls, 1)
    }
    func testHiddenAndCachedTokensAreSubtotalsAndCategoryContextIsBounded() throws {
        let usage = try XCTUnwrap(AIService.usage(["prompt_tokens":18000, "completion_tokens":5,
            "completion_tokens_details":["reasoning_tokens":3], "prompt_tokens_details":["cached_tokens":16000]]))
        XCTAssertEqual(usage.total, 18005); XCTAssertEqual(usage.reasoning, 3); XCTAssertEqual(usage.cachedInput, 16000)
        let names = (0..<1000).map { "分类\($0)" + String(repeating: "长", count: 100) }
        let prompt = AIService.systemPrompt(at: Date(), timeZone: .current, calendars: names, reminderLists: names)
        XCTAssertLessThan(prompt.count, 7000); XCTAssertFalse(prompt.contains("分类999"))
    }

    func testTypingBodyThroughBindingPreservesReturnBlankLinesAndIndentation() {
        var event = ParsedEvent(title: "多行正文", description: "第一段")
        // A binding reads the model again after every keystroke, including Return.
        for input in ["\n", "\n", "  第二段", "\n"] { event.setBody(event.readableBody + input) }
        XCTAssertEqual(event.readableBody, "第一段\n\n  第二段\n")
        event.setBody("\n\t缩进\n\n")
        XCTAssertEqual(event.readableBody, "\n\t缩进\n\n")
    }

}
