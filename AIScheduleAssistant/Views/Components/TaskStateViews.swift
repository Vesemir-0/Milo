import SwiftUI
import AppKit

struct ProcessingView: View {
    @ObservedObject var viewModel: ContentProcessViewModel
    var background: () -> Void
    var cancel: () -> Void = {}
    var body: some View {
        VStack(spacing: 0) {
            MiloHeader("正在识别")
            VStack(spacing: 17) {
                Spacer()
                Image("MiloScribe").resizable().scaledToFit().frame(width: 150, height: 150)
                HStack(spacing: 12) { ProgressView().controlSize(.small); Text("正在整理你的信息").font(.system(size: 21, weight: .medium)) }
                Text("你可以继续做其他事。整理好了，再回来核对。").font(.system(size: 12)).foregroundStyle(DesignSystem.Colors.textSecondary)
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text("已用 \(Int(Date().timeIntervalSince(viewModel.startedAt ?? Date()))) 秒 · 等待上限 \(viewModel.waitingLimit) 秒").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textTertiary) }
                Spacer()
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            MiloFooter { Text("原始内容已保留。").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary); Spacer(); Button("取消识别") { cancel(); background() }.buttonStyle(MiloSecondaryStyle()); Button("后台继续", action: background).buttonStyle(MiloPrimaryStyle()) }
        }.background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary).frame(minWidth: 610, minHeight: 440)
    }
}
struct ErrorStateView: View {
    @ObservedObject var viewModel: ContentProcessViewModel
    var settings: (SettingsSection) -> Void
    var retry: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            MiloHeader("需要你看一下")
            ScrollView {
                if let failure = viewModel.failure {
                    VStack(alignment: .leading, spacing: 15) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 23, weight: .light)).foregroundStyle(DesignSystem.Colors.primary)
                        Text(failure.title).font(.system(size: 23, weight: .medium))
                        Text(failure.message).font(.system(size: 13)).lineSpacing(6)
                        MiloPaper {
                            Text(failure.explanation == nil ? "可以这样调整" : "可能原因与建议").font(.system(size: 11, weight: .semibold)).foregroundStyle(DesignSystem.Colors.primary)
                            Text(failure.explanation ?? failure.suggestion).font(.system(size: 13)).lineSpacing(6)
                        }
                        if viewModel.diagnosing { HStack { ProgressView().controlSize(.small); Text("正在补充一个简短解释…") }.font(.system(size: 11)) }
                        MiloDisclosure("技术详情") {
                            VStack(alignment: .leading, spacing: 12) {
                                if let count = failure.diagnosticUsage?.total { Text("辅助解释消耗 \(count) tokens").font(.system(size: 10)) }
                                if let duration = failure.diagnosticDuration { Text(String(format: "辅助解释耗时 %.1f 秒", duration)).font(.system(size: 10)) }
                                MiloUsageDetails(usage: failure.usage, footprint: failure.footprint, rawUsage: failure.rawUsage)
                                Text(failure.technical).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                if let raw = failure.rawOutput { Text("原始输出片段").font(.system(size: 11, weight: .semibold)); Text(raw).font(.system(size: 11, design: .monospaced)).textSelection(.enabled) }
                                Button("复制技术详情") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(failure.technical + "\n" + (failure.rawOutput ?? ""), forType: .string) }.buttonStyle(MiloHoverStyle())
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(13).background(DesignSystem.Colors.backgroundSecondary)
                        }.font(.system(size: 11))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(34)
                }
            }.foregroundStyle(DesignSystem.Colors.textSecondary)
            MiloNotice(text: viewModel.notice)
            MiloFooter {
                Text("内容与修改会保留。").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Button(settingsLabel) { settings(section) }.buttonStyle(MiloSecondaryStyle())
                Button("保留内容并重试", action: retry).buttonStyle(MiloPrimaryStyle()).disabled(viewModel.isBusy)
            }
        }.background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary).frame(minWidth: 620, minHeight: 480)
    }
    private var section: SettingsSection { switch viewModel.failure?.kind { case .timeout: return .behavior; case .permission, .writing: return .permissions; default: return .models } }
    private var settingsLabel: String { section == .behavior ? "调整等待设置" : section == .permissions ? "检查系统权限" : "检查模型设置" }
}
struct AboutMiloView: View {
    var body: some View {
        VStack(spacing: 0) {
            MiloHeader("关于 Milo")
            VStack(spacing: 13) {
                Image("MiloIcon").resizable().scaledToFit().frame(width: 100, height: 100)
                Text("Milo").font(.system(size: 25, weight: .medium))
                Text("AI 日程助手").font(.system(size: 13)).foregroundStyle(DesignSystem.Colors.textSecondary)
                Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0")").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("把截图和文本里的安排，\n妥帖地记进日历与待办清单。").font(.system(size: 13)).lineSpacing(6).multilineTextAlignment(.center).padding(.top, 10)
                Text("你的日程抄写员").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textTertiary).padding(.top, 15)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(35)
        }.background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary).frame(width: 540, height: 480)
    }
}

struct ConcurrentProcessingView: View {
    @ObservedObject var queue: RecognitionQueue
    var background: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            MiloHeader("识别进度")
            if queue.isWorking {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("\(queue.activeWorkers.count) 份正在同时整理").font(.system(size: 20, weight: .medium))
                        Text("每份完成后独立打开核对窗口，可以继续输入或截图。").font(.system(size: 12)).foregroundStyle(DesignSystem.Colors.textSecondary)
                        ForEach(queue.activeWorkers, id: \.identity) { worker in ActiveRecognitionRow(worker: worker, cancel: { if let id = worker.record?.id { queue.cancel(id) } }) }
                        if !queue.waiting.isEmpty {
                            Text("等待空位 · \(queue.waiting.count) 份").font(.system(size: 12, weight: .medium)).padding(.top, 8)
                            ForEach(queue.waiting) { item in HStack { Text(item.title).lineLimit(1); Spacer(); Text(item.model).foregroundStyle(DesignSystem.Colors.textSecondary) }.font(.system(size: 11)).padding(.vertical, 5) }
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                QuietState(title: "这批信息整理好了", message: "每份结果都已独立保留，可以从历史记录继续核对。") { EmptyView() }
            }
            MiloFooter { Text("最多同时处理 \(queue.concurrencyLimit) 份").font(.system(size: 11)); Spacer(); Button("后台继续", action: background).buttonStyle(MiloPrimaryStyle()) }
        }.background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary)
    }
}
private struct ActiveRecognitionRow: View {
    @ObservedObject var worker: ContentProcessViewModel
    var cancel: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)
            VStack(alignment: .leading, spacing: 5) {
                Text(worker.record?.title ?? "正在准备").font(.system(size: 13, weight: .medium)).lineLimit(2)
                TimelineView(.periodic(from: .now, by: 1)) { _ in Text((worker.record?.modelName ?? "") + " · 已用 \(Int(Date().timeIntervalSince(worker.startedAt ?? Date()))) 秒").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textSecondary) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("取消", action: cancel).buttonStyle(MiloSecondaryStyle()).disabled(worker.state != .analyzing)
        }.padding(14).background(DesignSystem.Colors.surface)
    }
}
