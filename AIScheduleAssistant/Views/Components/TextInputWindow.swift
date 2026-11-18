import SwiftUI
import AppKit

@MainActor final class MenuNavigation: ObservableObject {
    @Published var composing = false
    @Published var text = ""
    @Published var feedback: String?
}

/// This composer lives inside the original status-item popover.
struct InlineTextComposer: View {
    @ObservedObject var navigation: MenuNavigation
    @ObservedObject var queue: RecognitionQueue
    var settings: () -> Void
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("把要记的事，写在这里。").font(.system(size: 17, weight: .medium))
            TextEditor(text: $navigation.text).font(.system(size: 13)).lineSpacing(5)
                .scrollContentBackground(.hidden).padding(9).frame(height: 172)
                .background(DesignSystem.Colors.surface.opacity(0.95), in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(DesignSystem.Colors.border, lineWidth: 0.8))
                .focused($focused).accessibilityLabel("待识别的文本")
            HStack {
                Text("\(navigation.text.count) 字").foregroundStyle(DesignSystem.Colors.textTertiary)
                Spacer()
                Button("粘贴剪贴板") { if let text = NSPasteboard.general.string(forType: .string) { navigation.text = text; focused = true } }.buttonStyle(MiloHoverStyle())
            }.font(.system(size: 11))
            HStack {
                Text("本次使用").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                MiloModelPicker().frame(maxWidth: 205)
            }
            HStack {
                if ConfigService.shared.settings.aiConfig == nil { Button("配置 API", action: settings).buttonStyle(MiloHoverStyle()) }
                else { Text(navigation.feedback ?? "整理期间可以继续提交。").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textSecondary).lineLimit(2) }
                Spacer(minLength: 4)
                Button("开始识别") {
                    if queue.enqueueText(navigation.text) != nil {
                        navigation.text = ""; navigation.feedback = "已加入队列，可以继续输入。"; focused = true
                    }
                }.buttonStyle(MiloPrimaryStyle()).disabled(navigation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }.padding(16).onAppear { focused = true }
    }
}
