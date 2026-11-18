import SwiftUI

private struct MenuSizeKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
struct MenuBarView: View {
    weak var appDelegate: AppDelegate?
    @ObservedObject var queue: RecognitionQueue
    @ObservedObject var navigation: MenuNavigation
    let presentationID: UUID
    @ObservedObject private var config = ConfigService.shared
    @ObservedObject private var history = HistoryStore.shared
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if navigation.composing {
                    Button { navigation.composing = false } label: { Label("返回", systemImage: "chevron.left").font(.system(size: 11)) }.buttonStyle(MiloHoverStyle())
                    Spacer()
                    Text("文本输入").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Button { appDelegate?.beginScreenshot() } label: { Image(systemName: "viewfinder") }.buttonStyle(MiloHoverStyle()).help("直接截图").disabled(queue.isCapturing || !config.settings.enableScreenshotCapture)
                } else {
                    Image("MiloScribe").resizable().scaledToFit().frame(width: 38, height: 40)
                    VStack(alignment: .leading, spacing: 4) { Text(miloWindowTitle).font(.system(size: 12, weight: .semibold)); Text("把零散信息，妥帖地记下来。").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textSecondary) }
                    Spacer(minLength: 0)
                }
            }.padding(.horizontal, 16).frame(height: navigation.composing ? 50 : 67)
            Divider().padding(.horizontal, 12).opacity(0.4)
            if navigation.composing {
                InlineTextComposer(navigation: navigation, queue: queue, settings: { appDelegate?.showSettingsWindow() })
            } else {
                VStack(spacing: 3) {
                    menuAction("截图获取", subtitle: "直接圈选屏幕，Esc 取消", icon: "viewfinder") { appDelegate?.beginScreenshot() }.disabled(queue.isCapturing || !config.settings.enableScreenshotCapture)
                    menuAction("文本输入", subtitle: "粘贴消息，或直接写下来", icon: "text.alignleft") { navigation.composing = true }.disabled(!config.settings.enableTextCapture)
                }.padding(.horizontal, 10).padding(.vertical, 7)
                Divider().padding(.horizontal, 12).opacity(0.4)
                HStack { Text("本次使用").font(.system(size: 10)); Spacer(); MiloModelPicker().frame(maxWidth: 200) }.foregroundStyle(DesignSystem.Colors.textSecondary).padding(.horizontal, 18).padding(.vertical, 10)
            }
            if queue.isWorking {
                Button { appDelegate?.showProcessingWindow() } label: {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small).allowsHitTesting(false).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("同时整理 \(queue.activeWorkers.count) 项 · 等待 \(queue.waiting.count) 项")
                            Text("最多 \(queue.concurrencyLimit) 项并发，可以继续提交").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textSecondary)
                        }
                        Spacer(); Image(systemName: "chevron.right").font(.system(size: 9))
                    }.font(.system(size: 11)).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(MiloHoverStyle()).accessibilityElement(children: .ignore).accessibilityLabel("查看识别进度，同时整理 \(queue.activeWorkers.count) 项，等待 \(queue.waiting.count) 项").padding(.horizontal, 10).padding(.bottom, 7)
            } else if let record = queue.latestWorker?.record, !record.drafts.isEmpty {
                Button { appDelegate?.openRecord(record) } label: { HStack { Image(systemName: "checkmark"); Text("\(record.drafts.count) 项安排已整理好"); Spacer(); Image(systemName: "chevron.right").font(.system(size: 9)) }.font(.system(size: 11)).padding(10).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(MiloHoverStyle()).padding(.horizontal, 10).padding(.bottom, 7)
            }
            Divider().padding(.horizontal, 12).opacity(0.4)
            VStack(spacing: 1) {
                HStack(spacing: 4) {
                    Button { appDelegate?.showHistoryWindow() } label: { HStack { Label("历史记录", systemImage: "clock.arrow.circlepath"); Spacer(); Text("\(history.records.count)") }.frame(maxWidth: .infinity).padding(.horizontal, 7).padding(.vertical, 4) }
                    Button { appDelegate?.showSettingsWindow() } label: { Label("设置", systemImage: "slider.horizontal.3").padding(.horizontal, 7).padding(.vertical, 4) }
                }.font(.system(size: 11))
                HStack {
                    Button("关于 Milo") { appDelegate?.showAboutWindow() }
                    Spacer(); Button("退出  ⌘ Q") { appDelegate?.quit() }
                }.font(.system(size: 10))
            }.buttonStyle(MiloHoverStyle()).foregroundStyle(DesignSystem.Colors.textSecondary).padding(.horizontal, 12).padding(.vertical, 7)
            if let warning = queue.notice ?? config.storageWarning { Text(warning).font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.error).padding(10) }
        }.frame(width: 352).fixedSize(horizontal: false, vertical: true)
            .background(MiloGlassBackground(menu: true)).foregroundStyle(DesignSystem.Colors.textPrimary)

            .background(GeometryReader { proxy in Color.clear.preference(key: MenuSizeKey.self, value: proxy.size) })
            .onPreferenceChange(MenuSizeKey.self) { size in appDelegate?.resizePopover(size, session: presentationID) }
    }
    private func menuAction(_ title: String, subtitle: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: icon).font(.system(size: 19, weight: .light)).foregroundStyle(DesignSystem.Colors.primary).frame(width: 24)
                VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 13, weight: .medium)); Text(subtitle).font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textSecondary) }
                Spacer(); Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(DesignSystem.Colors.textSecondary)
            }.padding(.horizontal, 10).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(MiloHoverStyle())
    }
}
