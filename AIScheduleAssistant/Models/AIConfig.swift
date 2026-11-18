import Foundation

enum OutputLimitParameter: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, maxTokens = "max_tokens", maxCompletionTokens = "max_completion_tokens", omit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .automatic: return "自动选择"
        case .maxTokens: return "max_tokens"
        case .maxCompletionTokens: return "max_completion_tokens"
        case .omit: return "不发送长度参数"
        }
    }
    func key(for model: String) -> String? {
        switch self {
        case .omit: return nil
        case .maxTokens, .maxCompletionTokens: return rawValue
        case .automatic:
            let name = model.lowercased().split(separator: "/").last.map(String.init) ?? model.lowercased()
            return ["gpt-5", "o1", "o3", "o4"].contains(where: name.hasPrefix) ? "max_completion_tokens" : "max_tokens"
        }
    }
}

struct ModelProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新模型"
    var modelID = ""
    var supportsImages = true
    var temperature: Double? = nil
    var maxTokens = 4000
    var outputLimitParameter: OutputLimitParameter = .automatic
}

struct APIProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "新 API"
    var baseURL = "https://api.openai.com/v1"
    var apiKey = ""
    var models: [ModelProfile] = []

    // Credentials only exist in memory and Keychain, never in settings exports.
    enum CodingKeys: String, CodingKey { case id, name, baseURL, models }
    init(id: UUID = UUID(), name: String = "新 API", baseURL: String = "https://api.openai.com/v1", apiKey: String = "", models: [ModelProfile] = []) {
        self.id = id; self.name = name; self.baseURL = baseURL; self.apiKey = apiKey; self.models = models
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        models = try c.decode([ModelProfile].self, forKey: .models)
        apiKey = ""
    }
}

/// Immutable request snapshot. A model switch cannot change an in-flight job.
struct AIConfig: Equatable, Sendable {
    var baseURL: String
    var apiKey: String
    var model: String
    var temperature: Double?
    var maxTokens: Int
    var outputLimitParameter: OutputLimitParameter = .automatic
    var supportsImages = true
    var timeout: TimeInterval = 180
    var profileName = "AI 服务"
    var modelName = "模型"

    static let `default` = AIConfig(baseURL: "https://api.openai.com/v1", apiKey: "", model: "", temperature: nil, maxTokens: 4000)
    var endpoint: URL? {
        guard var parts = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        var path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !path.hasSuffix("chat/completions") { path += (path.isEmpty ? "" : "/") + "chat/completions" }
        parts.path = "/" + path
        return parts.url
    }
    func validated() throws -> AIConfig {
        guard endpoint != nil else { throw FailureInfo.configuration("API 端点格式不正确", suggestion: "填写 http 或 https 的兼容接口地址，例如 https://api.example.com/v1。") }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw FailureInfo.configuration("还没有选择模型", suggestion: "在 API 设置中添加模型 ID，再选择它。") }
        guard temperature.map({ $0.isFinite && (0...2).contains($0) }) ?? true,
              maxTokens > 0, maxTokens <= 1_000_000, (30...3600).contains(timeout) else {
            throw FailureInfo.configuration("模型参数超出有效范围", suggestion: "检查 Temperature、输出长度和等待上限。")
        }
        return self
    }
}
