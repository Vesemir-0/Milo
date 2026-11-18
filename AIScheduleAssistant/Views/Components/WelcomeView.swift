import SwiftUI

struct WelcomeView: View {
    var configure: () -> Void
    var tryInput: () -> Void
    var body: some View {
        VStack(spacing: 0) {
            MiloHeader("欢迎使用")
            HStack(spacing: 40) {
                Image("MiloScribe").resizable().scaledToFit().frame(width: 235, height: 270)
                VStack(alignment: .leading, spacing: 18) {
                    Text("你的日程抄写员 Milo").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.primary)
                    Text("零散的信息，\n替你记得妥帖。").font(.system(size: 29, weight: .medium)).lineSpacing(7)
                    Text("截一张图，或粘贴一段文本。\n核对和修改后，交给系统日历与提醒事项。").font(.system(size: 13)).foregroundStyle(DesignSystem.Colors.textSecondary).lineSpacing(7)
                    VStack(alignment: .leading, spacing: 12) { Text("01    配置你自己的 API 和模型"); Text("02    按需要授予日历、待办与截图权限"); Text("03    把第一份信息交给 Milo") }.font(.system(size: 12)).foregroundStyle(DesignSystem.Colors.textSecondary).padding(.vertical, 8)
                    HStack { Button("先写一段文本", action: tryInput).buttonStyle(MiloSecondaryStyle()); Button("配置 AI 服务", action: configure).buttonStyle(MiloPrimaryStyle()) }
                }
            }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
        }.background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary).frame(minWidth: 800, minHeight: 530)
    }
}
