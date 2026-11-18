//
//  ContentCaptureService.swift
//  AIScheduleAssistant
//
//  Created by Claude on 2026/3/9.
//

import Foundation
import AppKit
import ApplicationServices

enum CaptureError: LocalizedError {
    case screenshotCancelled
    case screenshotFailed
    case noTextSelected
    case accessibilityAPIFailed
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .screenshotCancelled:
            return "截图已取消"
        case .screenshotFailed:
            return "截图失败"
        case .noTextSelected:
            return "未选中任何文本"
        case .accessibilityAPIFailed:
            return "无法读取选中的文本"
        case .permissionDenied:
            return "权限被拒绝"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .screenshotCancelled:
            return "请重新尝试截图"
        case .screenshotFailed:
            return "请检查屏幕录制权限"
        case .noTextSelected:
            return "请先选中要识别的文本"
        case .accessibilityAPIFailed:
            return "请检查辅助功能权限"
        case .permissionDenied:
            return "请在设置中授予必要的权限"
        }
    }
}

@MainActor class ContentCaptureService {
    static let shared = ContentCaptureService()

    private let executable: URL
    private let accessCheck: @MainActor () -> Bool
    init(executable: URL = URL(fileURLWithPath: "/usr/sbin/screencapture"), accessCheck: (@MainActor () -> Bool)? = nil) {
        self.executable = executable
        self.accessCheck = accessCheck ?? { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }
    }

    // MARK: - Screenshot Capture

    func captureScreenshot() async throws -> NSImage {
        guard accessCheck() else { throw CaptureError.permissionDenied }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("milo-capture-\(UUID().uuidString).png")
        let errorURL = url.appendingPathExtension("stderr")
        FileManager.default.createFile(atPath: errorURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer { try? errorHandle.close(); try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: errorURL) }
        let box = CaptureProcessBox()
        let localEscape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { box.markEscape() }; return event
        }
        let globalEscape = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { box.markEscape() }
        }
        defer { if let localEscape { NSEvent.removeMonitor(localEscape) }; if let globalEscape { NSEvent.removeMonitor(globalEscape) } }
        let status: Int32 = try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                process.executableURL = executable
                process.standardError = errorHandle; process.standardOutput = FileHandle.nullDevice
                process.arguments = ["-i", "-s", "-x", url.path]
                process.terminationHandler = { process in continuation.resume(returning: process.terminationStatus) }
                do { try box.start(process) }
                catch { continuation.resume(throwing: error) }
            }
        }, onCancel: { box.cancel() })
        try Task.checkCancellation()
        let diagnostic = String(data: (try? Data(contentsOf: errorURL)) ?? Data(), encoding: .utf8) ?? ""
        return try Self.resolveCapture(status: status, file: url, diagnostic: diagnostic, escapePressed: box.escapePressed)
    }

    /// Interactive capture can exit successfully without writing a file after Esc.
    static func resolveCapture(status: Int32, file: URL, diagnostic: String = "", escapePressed: Bool = false) throws -> NSImage {
        if escapePressed { throw CaptureError.screenshotCancelled }
        let data = try? Data(contentsOf: file)
        let missing = data?.isEmpty != false
        let message = diagnostic.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if message.contains("permission") || message.contains("not authorized") || message.contains("denied") { throw CaptureError.permissionDenied }
        if missing && ([0, 1, 130].contains(status) || message.contains("cancel")) {
            throw CaptureError.screenshotCancelled
        }
        guard status == 0, let data, !data.isEmpty, let image = NSImage(data: data), image.isValid else { throw CaptureError.screenshotFailed }
        return image
    }

    // MARK: - Text Selection Capture

    func captureSelectedText() throws -> String {
        // Check accessibility permission first
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        guard AXIsProcessTrustedWithOptions(options) else {
            throw CaptureError.permissionDenied
        }

        // Get system-wide accessibility element
        let systemWideElement = AXUIElementCreateSystemWide()

        // Get focused element
        var focusedElement: AnyObject?
        let focusedResult = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard focusedResult == .success, let element = focusedElement else {
            throw CaptureError.accessibilityAPIFailed
        }

        // Try to get selected text
        var selectedText: AnyObject?
        let selectedResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXSelectedTextAttribute as CFString,
            &selectedText
        )

        if selectedResult == .success, let text = selectedText as? String, !text.isEmpty {
            return text
        }

        // If no selected text, try to get value (for text fields)
        var value: AnyObject?
        let valueResult = AXUIElementCopyAttributeValue(
            element as! AXUIElement,
            kAXValueAttribute as CFString,
            &value
        )

        if valueResult == .success, let text = value as? String, !text.isEmpty {
            return text
        }

        throw CaptureError.noTextSelected
    }

    // MARK: - Create CapturedContent

    func createCapturedContent(from image: NSImage) -> CapturedContent {
        return CapturedContent(
            type: .image(image),
            source: "screenshot"
        )
    }

    func createCapturedContent(from text: String) -> CapturedContent {
        return CapturedContent(
            type: .text(text),
            source: "text_selection"
        )
    }
}

private final class CaptureProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var escaped = false
    var escapePressed: Bool { lock.lock(); defer { lock.unlock() }; return escaped }
    func markEscape() { lock.lock(); escaped = true; lock.unlock() }
    func start(_ process: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        self.process = process
        try process.run()
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let process, process.isRunning { process.terminate() }
    }
}
