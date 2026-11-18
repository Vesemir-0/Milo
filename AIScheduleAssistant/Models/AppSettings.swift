import Foundation

enum SaveTarget: String, Codable, CaseIterable, Identifiable {
    case both, calendarOnly = "calendar", reminderOnly = "reminder"
    var id: String { rawValue }
    var label: String { self == .both ? "日历 + 待办" : self == .calendarOnly ? "仅日历" : "仅待办" }
    var includesCalendar: Bool { self != .reminderOnly }
    var includesReminders: Bool { self != .calendarOnly }
}

struct AppSettings: Codable, Equatable {
    var autoAddMode = false
    var enableScreenshotCapture = true
    var enableTextCapture = true
    var saveTarget: SaveTarget = .both
    var apiProfiles: [APIProfile] = []
    var selectedAPIID: UUID?
    var selectedModelID: UUID?
    var maximumConcurrentRecognitions = 3
    var timeoutSeconds = 180
    var historyRetentionDays = 30
    var historyLimit = 200
    var keepScreenshots = false
    var explainComplexErrors = true
    var useGlassBackground = true
    static let `default` = AppSettings()

    var aiConfig: AIConfig? {
        guard let p = apiProfiles.first(where: { $0.id == selectedAPIID }),
              let m = p.models.first(where: { $0.id == selectedModelID }) else { return nil }
        return AIConfig(baseURL: p.baseURL, apiKey: p.apiKey, model: m.modelID, temperature: m.temperature,
                        maxTokens: m.maxTokens, outputLimitParameter: m.outputLimitParameter,
                        supportsImages: m.supportsImages, timeout: Double(timeoutSeconds), profileName: p.name, modelName: m.name)
    }
    mutating func repairSelection() {
        if let p = apiProfiles.first(where: { $0.id == selectedAPIID }), p.models.contains(where: { $0.id == selectedModelID }) { return }
        let p = apiProfiles.first(where: { !$0.models.isEmpty })
        selectedAPIID = p?.id; selectedModelID = p?.models.first?.id
    }
    enum CodingKeys: String, CodingKey {
        case autoAddMode, enableScreenshotCapture, enableTextCapture, saveTarget, apiProfiles, selectedAPIID, selectedModelID
        case maximumConcurrentRecognitions, timeoutSeconds, historyRetentionDays, historyLimit, keepScreenshots, explainComplexErrors, useGlassBackground, aiConfig
    }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoAddMode = try c.decodeIfPresent(Bool.self, forKey: .autoAddMode) ?? false
        enableScreenshotCapture = try c.decodeIfPresent(Bool.self, forKey: .enableScreenshotCapture) ?? true
        enableTextCapture = try c.decodeIfPresent(Bool.self, forKey: .enableTextCapture) ?? true
        saveTarget = try c.decodeIfPresent(SaveTarget.self, forKey: .saveTarget) ?? .both
        maximumConcurrentRecognitions = min(8, max(1, try c.decodeIfPresent(Int.self, forKey: .maximumConcurrentRecognitions) ?? 3))
        timeoutSeconds = min(3600, max(30, try c.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 180))
        historyRetentionDays = try c.decodeIfPresent(Int.self, forKey: .historyRetentionDays) ?? 30
        historyLimit = try c.decodeIfPresent(Int.self, forKey: .historyLimit) ?? 200
        keepScreenshots = try c.decodeIfPresent(Bool.self, forKey: .keepScreenshots) ?? false
        explainComplexErrors = try c.decodeIfPresent(Bool.self, forKey: .explainComplexErrors) ?? true
        useGlassBackground = try c.decodeIfPresent(Bool.self, forKey: .useGlassBackground) ?? true
        if let profiles = try c.decodeIfPresent([APIProfile].self, forKey: .apiProfiles) {
            apiProfiles = profiles
            selectedAPIID = try c.decodeIfPresent(UUID.self, forKey: .selectedAPIID)
            selectedModelID = try c.decodeIfPresent(UUID.self, forKey: .selectedModelID)
        } else if c.contains(.aiConfig) {
            struct Legacy: Decodable { var baseURL: String; var apiKey: String?; var model: String; var maxTokens: Int? }
            let old = try c.decode(Legacy.self, forKey: .aiConfig)
            let m = ModelProfile(name: old.model, modelID: old.model, maxTokens: max(1, old.maxTokens ?? 4000))
            let p = APIProfile(name: "原有 API", baseURL: old.baseURL, apiKey: old.apiKey ?? "", models: [m])
            apiProfiles = [p]; selectedAPIID = p.id; selectedModelID = m.id
        }
        repairSelection()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(autoAddMode, forKey: .autoAddMode); try c.encode(enableScreenshotCapture, forKey: .enableScreenshotCapture)
        try c.encode(enableTextCapture, forKey: .enableTextCapture); try c.encode(saveTarget, forKey: .saveTarget)
        try c.encode(apiProfiles, forKey: .apiProfiles); try c.encodeIfPresent(selectedAPIID, forKey: .selectedAPIID)
        try c.encodeIfPresent(selectedModelID, forKey: .selectedModelID); try c.encode(maximumConcurrentRecognitions, forKey: .maximumConcurrentRecognitions); try c.encode(timeoutSeconds, forKey: .timeoutSeconds)
        try c.encode(historyRetentionDays, forKey: .historyRetentionDays); try c.encode(historyLimit, forKey: .historyLimit)
        try c.encode(keepScreenshots, forKey: .keepScreenshots); try c.encode(explainComplexErrors, forKey: .explainComplexErrors)
        try c.encode(useGlassBackground, forKey: .useGlassBackground)
    }
}
