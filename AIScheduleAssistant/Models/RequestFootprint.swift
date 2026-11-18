import Foundation

/// Only sizes and counts are retained; this never stores credentials or image data.
struct RequestFootprint: Codable, Equatable, Sendable {
    var messageCount: Int
    var systemCharacters: Int
    var inputCharacters: Int
    var imageCount: Int
    var bodyBytes: Int
    var summary: String { "发送 \(messageCount) 条消息 · 提示词 \(systemCharacters) 字符 · 原文 \(inputCharacters) 字符 · 图片 \(imageCount) 张 · 请求体 \(bodyBytes) 字节" }
    static func measure(_ request: URLRequest) -> RequestFootprint? {
        guard let data = request.httpBody, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let messages = json["messages"] as? [[String: Any]] else { return nil }
        var system = 0, input = 0, images = 0
        for message in messages {
            let systemRole = ["system", "developer"].contains(message["role"] as? String ?? "")
            var count = 0
            if let text = message["content"] as? String { count = text.count }
            if let parts = message["content"] as? [[String: Any]] {
                for part in parts {
                    count += (part["text"] as? String)?.count ?? 0
                    if part["type"] as? String == "image_url" { images += 1 }
                }
            }
            if systemRole { system += count } else { input += count }
        }
        return RequestFootprint(messageCount: messages.count, systemCharacters: system, inputCharacters: input, imageCount: images, bodyBytes: data.count)
    }
}
