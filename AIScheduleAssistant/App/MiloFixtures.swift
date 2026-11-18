import Foundation
import AppKit
import SwiftUI

@MainActor enum MiloFixtures {
    static func install(viewModel: ContentProcessViewModel) {
        guard RuntimeMode.isPreview else { return }
        let m = ModelProfile(name: "日常模型", modelID: "milo-ui-fixture")
        let quick = ModelProfile(name: "快速模型", modelID: "milo-ui-fast")
        let profile = APIProfile(name: "常用 API", baseURL: "http://127.0.0.1:48764/v1", models: [m, quick])
        var settings = AppSettings.default
        let backup = APIProfile(name: "备用 API", baseURL: "http://127.0.0.1:48764/v1", models: [ModelProfile(name: "备用模型", modelID: "milo-ui-backup"), ModelProfile(name: "结构错误检查", modelID: "return-bad-json")])
        settings.apiProfiles = [profile, backup]; settings.selectedAPIID = profile.id; settings.selectedModelID = m.id
        try? viewModel.config.save(settings)
        let rows = [("团队周会", "回顾本周进展。\n确认下周的安排。", "三楼会议室"), ("周末读书会", "带上正在读的书。\n分享喜欢的一个段落。", "社区书店"), ("整理报销材料", "核对本月票据。\n补齐报销表格。", ""), ("牙齿检查", "提前十分钟到诊所。\n带上之前的检查记录。", "口腔诊所"), ("整理本周周报", "汇总本周完成的工作。\n列出下周要推进的事项。", ""), ("取洗好的外套", "取衣码放在短信里。", "洗衣店"), ("读论文并做摘记", "读完方法和结果部分。\n记下可以用于研究设计的思路。", ""), ("和朋友吃晚饭", "提前确认餐厅与人数。", "")]
        let day = Calendar.current.startOfDay(for: Date())
        let events = rows.enumerated().map { n, row in ParsedEvent(title: row.0, description: row.1, startDate: day.addingTimeInterval(Double(n + 1) * 86400 + 14 * 3600), endDate: n == 2 || n == 4 || n == 5 ? nil : day.addingTimeInterval(Double(n + 1) * 86400 + 15 * 3600), dueDate: day.addingTimeInterval(Double(n + 1) * 86400 + 18 * 3600), suggestedCalendar: "工作", suggestedReminderList: "工作", location: row.2.isEmpty ? nil : row.2) }
        var record = HistoryRecord(apiName: profile.name, modelName: m.name, modelID: m.modelID)
        record.sourceText = rows.map { $0.0 + "\n" + $0.1 }.joined(separator: "\n\n")
        record.duration = 2.4; record.usage = TokenUsage(input: 430, output: 270, total: 700)
        record.originalEvents = events; record.drafts = events.enumerated().map { n, e in EventDraft(event: e, target: [2,4,5].contains(n) ? .reminderOnly : n == 1 || n == 7 ? .calendarOnly : .both) }; record.status = .draft
        _ = viewModel.history.upsert(record); viewModel.open(record)
        #if DEBUG
        viewModel.notice = ProcessInfo.processInfo.environment["MILO_PRODUCT_SCREENSHOTS"] == "1"
            ? nil : "界面检查模式：数据为预置内容，不会写入系统日历。"
        #endif
    }
    #if DEBUG
    private static var glassBackdrop: NSWindow?
    static func installGlassBackdrop() {
        guard RuntimeMode.isPreview, ProcessInfo.processInfo.environment["MILO_GLASS_BACKDROP"] == "1" else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Glass backdrop check"; window.identifier = NSUserInterfaceItemIdentifier("glass-backdrop")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            ZStack {
                HStack(spacing: 0) { Color(red: 0.24, green: 0.48, blue: 0.65); Color(red: 0.76, green: 0.45, blue: 0.27); Color(red: 0.32, green: 0.60, blue: 0.43) }
                VStack(spacing: 22) { ForEach(0..<14, id: \.self) { _ in Text("MILO  BACKGROUND  TEXT  0123456789").font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(.white) } }
            }.frame(maxWidth: .infinity, maxHeight: .infinity))
        window.center(); window.orderFront(nil); glassBackdrop = window
    }
    private static var captureNumber = 0
    static func captureWindow() {
        guard RuntimeMode.isPreview, let path = ProcessInfo.processInfo.environment["MILO_EVIDENCE_DIRECTORY"],
              let window = NSApp.keyWindow, let view = window.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        captureNumber += 1
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = String(format: "%02d", captureNumber) + "-" + (window.identifier?.rawValue ?? "window") + ".png"
            try png.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch { NSLog("Milo UI capture could not be saved.") }
    }
    #endif

}
