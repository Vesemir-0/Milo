import Foundation
import Combine

@MainActor final class ConfigService: ObservableObject {
    static let shared = ConfigService(defaults: RuntimeMode.isPreview ? UserDefaults(suiteName: "Milo.UIPreview")! : .standard,
                                      keychain: RuntimeMode.isPreview ? MemorySecretStore() : KeychainService())
    @Published private(set) var settings: AppSettings
    @Published var storageWarning: String?
    private let defaults: UserDefaults
    private let keychain: SecretStoring
    private let settingsKey = "miloSettings.v1"

    init(defaults: UserDefaults, keychain: SecretStoring) {
        self.defaults = defaults; self.keychain = keychain
        let current = defaults.data(forKey: settingsKey)
        let legacyData = defaults.data(forKey: "appSettings")
        let data = current ?? legacyData
        if let data, let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) { settings = decoded }
        else {
            settings = .default
            if let data { defaults.set(data, forKey: "appSettings.recovery.\(Date().timeIntervalSince1970)"); storageWarning = "旧配置暂时无法读取，已保留副本。请重新检查 API 设置。" }
        }
        let needsMigration = current == nil && legacyData != nil
        let legacy = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["apiProfiles"] == nil && data != nil
        for index in settings.apiProfiles.indices {
            let account = legacy ? "default" : settings.apiProfiles[index].id.uuidString
            do { settings.apiProfiles[index].apiKey = try keychain.getAPIKey(for: account) }
            catch KeychainError.itemNotFound { }
            catch { storageWarning = "有一项密钥暂时无法从钥匙串读取。原密钥没有被删除，请重新打开设置检查。" }
        }
        if needsMigration && storageWarning == nil {
            do {
                for p in settings.apiProfiles where !p.apiKey.isEmpty { try keychain.saveAPIKey(p.apiKey, for: p.id.uuidString) }
                defaults.set(try JSONEncoder().encode(settings), forKey: settingsKey)
            } catch { storageWarning = "旧配置已读取，但迁移尚未保存。请在设置中重新保存；原配置仍然保留。" }
        }
    }
    func save(_ candidate: AppSettings) throws {
        var value = candidate; value.repairSelection()
        let encoded = try JSONEncoder().encode(value)
        var changed: [(UUID, String?)] = []
        do {
            for p in value.apiProfiles {
                let previous = settings.apiProfiles.first { $0.id == p.id }
                if previous?.apiKey == p.apiKey { continue }
                if p.apiKey.isEmpty { try keychain.deleteAPIKey(for: p.id.uuidString) }
                else { try keychain.saveAPIKey(p.apiKey, for: p.id.uuidString) }
                changed.append((p.id, previous?.apiKey))
            }
        } catch {
            var recoveryFailed = false
            for (id, previous) in changed.reversed() {
                do {
                    if let previous, !previous.isEmpty { try keychain.saveAPIKey(previous, for: id.uuidString) }
                    else { try keychain.deleteAPIKey(for: id.uuidString) }
                } catch { recoveryFailed = true }
            }
            throw FailureInfo(kind: .storage, title: "配置还没有保存", message: recoveryFailed ? "部分密钥可能已更新，恢复时也遇到了问题。请逐项检查密钥后重新保存。" : "钥匙串没有接受这次修改，现有配置仍然保留。", suggestion: "确认钥匙串可用后再试一次。")
        }
        let removed = settings.apiProfiles.filter { old in !value.apiProfiles.contains(where: { $0.id == old.id }) }
        defaults.set(encoded, forKey: settingsKey)
        settings = value; storageWarning = nil
        for p in removed {
            do { try keychain.deleteAPIKey(for: p.id.uuidString) }
            catch { storageWarning = "API 已移除，但钥匙串中的旧密钥未能清理。可以在“钥匙串访问”中移除对应项。" }
        }
    }
    func select(api: UUID, model: UUID) throws {
        var copy = settings; copy.selectedAPIID = api; copy.selectedModelID = model
        try save(copy)
    }
}
