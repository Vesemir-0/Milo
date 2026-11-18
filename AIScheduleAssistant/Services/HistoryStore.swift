import Foundation
import AppKit
import Combine

@MainActor final class HistoryStore: ObservableObject {
    static let shared: HistoryStore = {
        let directory: URL
        if RuntimeMode.isPreview { directory = FileManager.default.temporaryDirectory.appendingPathComponent("Milo-UIPreview-\(ProcessInfo.processInfo.processIdentifier)") }
        else { directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("AIScheduleAssistant", isDirectory: true) }
        return HistoryStore(directory: directory)
    }()
    @Published private(set) var records: [HistoryRecord] = []
    @Published var storageWarning: String?
    let directory: URL
    private var historyURL: URL { directory.appendingPathComponent("history-v1.json") }
    private var canWrite = true
    init(directory: URL) {
        self.directory = directory
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([HistoryRecord].self, from: Data(contentsOf: historyURL))
            for i in records.indices where records[i].status == .processing || records[i].status == .queued || records[i].status == .saving {
                records[i].status = .failed
                records[i].failure = FailureInfo(kind: .network, title: "上次整理被中断了", message: "应用退出时，这项识别尚未完成。", suggestion: "重新打开原文后继续；已经识别出的草稿仍然保留。")
            }
        } catch {
            let backup = directory.appendingPathComponent("history-recovery-\(Int(Date().timeIntervalSince1970)).json")
            do { try FileManager.default.copyItem(at: historyURL, to: backup); storageWarning = "历史文件暂时无法读取，原文件已另存副本。新记录会继续保留。" }
            catch { canWrite = false; storageWarning = "历史暂时无法读取或备份。为保护原记录，本次只在内存中保留修改，请先导出草稿。" }
        }
    }
    func record(_ id: UUID) -> HistoryRecord? { records.first { $0.id == id } }
    @discardableResult func upsert(_ record: HistoryRecord) -> Bool {
        if let i = records.firstIndex(where: { $0.id == record.id }) { records[i] = record }
        else { records.insert(record, at: 0) }
        return persist()
    }
    @discardableResult func remove(_ ids: Set<UUID>) -> Bool {
        let previous = records
        let removed = records.filter { ids.contains($0.id) }
        records.removeAll { ids.contains($0.id) }
        guard persist() else { records = previous; return false }
        let used = Set(records.compactMap(\.screenshotFile))
        for name in removed.compactMap(\.screenshotFile) where !used.contains(name) { try? FileManager.default.removeItem(at: imageURL(name)) }
        return true
    }
    @discardableResult func prune(days: Int, limit: Int, now: Date = Date(), protecting id: UUID? = nil) -> Bool {
        let cutoff = now.addingTimeInterval(-Double(max(0, days)) * 86400)
        let eligible = records.filter { $0.id != id && $0.status != .processing && $0.status != .queued && $0.status != .saving }
        let expired = days > 0 ? eligible.filter { $0.createdAt < cutoff }.map(\.id) : []
        let remaining = records.filter { !expired.contains($0.id) }.sorted { $0.createdAt > $1.createdAt }
        let overflow = limit > 0 ? remaining.dropFirst(limit).filter { $0.id != id && $0.status != .processing && $0.status != .queued && $0.status != .saving }.map(\.id) : []
        let ids = Set(expired + overflow)
        return ids.isEmpty ? true : remove(ids)
    }
    func saveImage(_ image: NSImage, id: UUID) throws -> String {
        let name = id.uuidString + ".png"
        guard let data = image.tiffRepresentation, let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { throw FailureInfo(kind: .storage, title: "原图暂时无法保留", message: "识别可以继续，但这次没有保存截图原图。", suggestion: "稍后检查本机可用空间。") }
        try createDirectory(); try png.write(to: imageURL(name), options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: imageURL(name).path)
        return name
    }
    func image(_ name: String) -> NSImage? { NSImage(contentsOf: imageURL(name)) }
    private func imageURL(_ name: String) -> URL { directory.appendingPathComponent(URL(fileURLWithPath: name).lastPathComponent) }
    private func createDirectory() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    private func persist() -> Bool {
        guard canWrite else { return false }
        do {
            try createDirectory()
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(records).write(to: historyURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: historyURL.path)
            storageWarning = nil; return true
        } catch { storageWarning = "本机历史没有保存成功。修改仍在当前窗口，请先导出草稿，再检查磁盘空间或文件权限。"; return false }
    }
}
