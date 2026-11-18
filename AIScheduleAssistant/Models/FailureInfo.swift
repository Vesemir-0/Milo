import Foundation

struct TokenUsage: Codable, Equatable, Sendable {
    var input: Int?
    var output: Int?
    var total: Int?
    var reasoning: Int? = nil
    var cachedInput: Int? = nil
}

struct FailureInfo: Error, LocalizedError, Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case configuration, permission, timeout, network, authentication, rateLimit, server, parameter, response, parsing, storage, writing }
    var id = UUID()
    var kind: Kind
    var title: String
    var message: String
    var suggestion: String
    var technical = ""
    var rawOutput: String?
    var elapsed: TimeInterval?
    var usage: TokenUsage?
    var footprint: RequestFootprint?
    var rawUsage: String?
    var explanation: String?
    var diagnosticUsage: TokenUsage?
    var diagnosticDuration: TimeInterval?
    var errorDescription: String? { message }
    static func configuration(_ title: String, suggestion: String) -> FailureInfo {
        FailureInfo(kind: .configuration, title: title, message: "配置尚未准备好，你的输入会保留。", suggestion: suggestion)
    }
    static func capture(_ error: Error) -> FailureInfo {
        if let captureError = error as? CaptureError, case .permissionDenied = captureError {
            return FailureInfo(kind: .permission, title: "还没有取得屏幕录制权限", message: "系统暂时不允许 Milo 截取屏幕。", suggestion: "在系统设置中允许屏幕录制，再重新圈选。", technical: String(describing: error))
        }
        return FailureInfo(kind: .response, title: "系统没有返回有效截图", message: "这次没有取得可读取的图片。", suggestion: "重新圈选一次；如果仍然失败，检查屏幕录制权限。", technical: String(describing: error))
    }
    static func from(_ error: Error) -> FailureInfo {
        if let f = error as? FailureInfo { return f }
        if let e = error as? URLError {
            if e.code == .timedOut { return FailureInfo(kind: .timeout, title: "这次等得有些久", message: "等待时间内没有收到完整响应。内容已保留。", suggestion: "延长等待上限后重试；也可以切换备用 API 或模型。", technical: "URLError.timedOut") }
            return FailureInfo(kind: .network, title: "网络暂时没有连通", message: "AI 服务的连接中断了。内容已保留。", suggestion: "检查网络与 API 端点，稍后重试或切换服务。", technical: "URLError \(e.code.rawValue): \(e.localizedDescription)")
        }
        return FailureInfo(kind: .writing, title: "有些内容还没有保存", message: "编辑结果已保留，可以继续处理未完成的部分。", suggestion: "检查系统权限与保存位置，再重试。", technical: String(describing: error))
    }
}

enum SecretRedactor {
    static func redact(_ input: String, secrets: [String] = []) -> String {
        var value = input
        for secret in secrets where !secret.isEmpty { value = value.replacingOccurrences(of: secret, with: "[已隐藏密钥]") }
        let patterns = ["(?i)Bearer\\s+[^\\s\"'<>]+", "sk-[A-Za-z0-9_\\-]{8,}", "(?i)(api[_-]?key|authorization|token|secret|password)([\\s\"']*[:=][\\s\"']*)[^\\s\"'&,}]+"]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "[已隐藏密钥]")
            }
        }
        return String(value.prefix(64_000))
    }
}
