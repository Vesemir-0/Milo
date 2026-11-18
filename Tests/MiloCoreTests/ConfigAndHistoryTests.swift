import XCTest
@testable import MiloCore

@MainActor final class ConfigAndHistoryTests: XCTestCase {
    func testLegacyMigrationKeepsSelectionAndKeyOutOfPlaintext() async throws {
        let name = "MiloTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let raw = #"{"autoAddMode":false,"enableScreenshotCapture":true,"enableTextCapture":true,"saveTarget":"both","aiConfig":{"baseURL":"https://legacy.example/v1","apiKey":"","model":"custom-model","temperature":0.7,"maxTokens":9000}}"#
        defaults.set(raw.data(using: .utf8), forKey: "appSettings")
        let secrets = MemorySecretStore(); secrets.values["default"] = "old-private-key"
        let config = ConfigService(defaults: defaults, keychain: secrets)
        let p = try XCTUnwrap(config.settings.apiProfiles.first)
        XCTAssertEqual(p.models.first?.modelID, "custom-model"); XCTAssertEqual(p.models.first?.maxTokens, 9000)
        XCTAssertNil(p.models.first?.temperature); XCTAssertEqual(config.settings.selectedAPIID, p.id)
        XCTAssertEqual(secrets.values[p.id.uuidString], "old-private-key")
        let encoded = try XCTUnwrap(defaults.data(forKey: "miloSettings.v1"))
        XCTAssertEqual(defaults.data(forKey: "appSettings"), raw.data(using: .utf8))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("old-private-key"))
        let reload = ConfigService(defaults: defaults, keychain: secrets)
        XCTAssertEqual(reload.settings.apiProfiles[0].apiKey, "old-private-key"); XCTAssertEqual(reload.settings.selectedModelID, config.settings.selectedModelID)
    }
    func testKeychainFailureLeavesPreviousSettingsAndKeyIntact() async throws {
        final class FlakyStore: SecretStoring {
            var values: [String:String] = [:]; var fail = false
            func saveAPIKey(_ value: String, for account: String) throws { if fail { throw KeychainError.invalidData }; values[account] = value }
            func getAPIKey(for account: String) throws -> String { guard let v = values[account] else { throw KeychainError.itemNotFound }; return v }
            func deleteAPIKey(for account: String) throws { if fail { throw KeychainError.invalidData }; values.removeValue(forKey: account) }
        }
        let name = "MiloTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let store = FlakyStore(), config = ConfigService(defaults: defaults, keychain: store)
        var value = AppSettings.default
        let m = ModelProfile(name: "test", modelID: "one")
        let p = APIProfile(name: "test", apiKey: "old-secret", models: [m]); value.apiProfiles = [p]; value.repairSelection()
        try config.save(value); let prior = defaults.data(forKey: "miloSettings.v1")
        store.fail = true; value.apiProfiles[0].apiKey = "replacement-secret"
        XCTAssertThrowsError(try config.save(value)); XCTAssertEqual(config.settings.apiProfiles[0].apiKey, "old-secret"); XCTAssertEqual(store.values[p.id.uuidString], "old-secret"); XCTAssertEqual(defaults.data(forKey: "miloSettings.v1"), prior)
    }
    func testMultipleProvidersKeepKeysModelsAndSelectionIndependent() async throws {
        let name = "MiloTests.\(UUID())", defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let secrets = MemorySecretStore(), config = ConfigService(defaults: defaults, keychain: secrets)
        let modelA = ModelProfile(name: "日常", modelID: "provider-a-model"), modelB = ModelProfile(name: "日常", modelID: "provider-b-model")
        let a = APIProfile(name: "A", baseURL: "https://a.example/v1", apiKey: "secret-a", models: [modelA])
        let b = APIProfile(name: "B", baseURL: "https://b.example/v1", apiKey: "secret-b", models: [modelB])
        var settings = AppSettings.default; settings.apiProfiles = [a,b]; settings.selectedAPIID = b.id; settings.selectedModelID = modelB.id
        try config.save(settings)
        let reload = ConfigService(defaults: defaults, keychain: secrets)
        XCTAssertEqual(reload.settings.aiConfig?.baseURL, b.baseURL); XCTAssertEqual(reload.settings.aiConfig?.apiKey, "secret-b")
        try reload.select(api: a.id, model: modelA.id)
        XCTAssertEqual(reload.settings.aiConfig?.apiKey, "secret-a"); XCTAssertEqual(reload.settings.aiConfig?.model, "provider-a-model")
        XCTAssertNil(defaults.data(forKey: "appSettings"))
    }
    func testHistoryPersistsEditsAndPartialReceiptsThenCleansOnlySelected() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MiloTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        var record = HistoryRecord(apiName: "test", modelName: "model", modelID: "id")
        record.drafts = [EventDraft(event: ParsedEvent(title: "原标题"), target: .both)]
        record.drafts[0].event.title = "修改后的标题"; record.drafts[0].event.setBody("第一行\n第二行")
        record.drafts[0].savedCalendarID = "calendar-1"; record.refreshStatus()
        XCTAssertTrue(store.upsert(record))
        let reload = HistoryStore(directory: dir), saved = try XCTUnwrap(reload.record(record.id))
        XCTAssertEqual(saved.drafts[0].event.title, "修改后的标题"); XCTAssertEqual(saved.drafts[0].event.readableBody, "第一行\n第二行")
        XCTAssertEqual(saved.drafts[0].savedCalendarID, "calendar-1"); XCTAssertEqual(saved.status, .partial)
        var second = record; second.id = UUID(); second.createdAt = Date().addingTimeInterval(-40*86400)
        XCTAssertTrue(reload.upsert(second)); XCTAssertTrue(reload.prune(days: 30, limit: 200))
        XCTAssertEqual(reload.records.map(\.id), [record.id]); XCTAssertTrue(reload.remove([record.id])); XCTAssertTrue(HistoryStore(directory: dir).records.isEmpty)
    }
    func testInterruptedJobsRecoverAndCorruptHistoryIsBackedUp() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("MiloTests-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = HistoryStore(directory: dir)
        let record = HistoryRecord(apiName: "a", modelName: "m", modelID: "x")
        XCTAssertTrue(store.upsert(record)); XCTAssertEqual(HistoryStore(directory: dir).record(record.id)?.status, .failed)
        try Data("broken".utf8).write(to: dir.appendingPathComponent("history-v1.json"))
        let damaged = HistoryStore(directory: dir)
        XCTAssertNotNil(damaged.storageWarning)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).contains(where: { $0.hasPrefix("history-recovery") }))
    }
}
