import SwiftUI
import AppKit

let miloWindowTitle = "Milo — AI 日程助手"

struct MiloHeader<Trailing: View>: View {
    let context: String
    @ViewBuilder var trailing: () -> Trailing
    init(_ context: String, @ViewBuilder trailing: @escaping () -> Trailing) { self.context = context; self.trailing = trailing }
    var body: some View {
        HStack(spacing: 10) {
            Image("MiloIcon").resizable().scaledToFit().frame(width: 28, height: 28)
            Text(miloWindowTitle).font(.system(size: 12, weight: .medium))
            Rectangle().fill(DesignSystem.Colors.border).frame(width: 1, height: 17)
            Text(context).font(.system(size: 13, weight: .medium)).foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer(minLength: 10)
            trailing()
        }
        .padding(.horizontal, 16).frame(height: 54)
        .background(MiloChromeBackground())
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
}
extension MiloHeader where Trailing == EmptyView {
    init(_ context: String) { self.context = context; self.trailing = { EmptyView() } }
}
struct MiloFooter<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        HStack(spacing: 14, content: content).padding(.horizontal, 18).frame(minHeight: 53)
            .background(MiloChromeBackground())
            .overlay(alignment: .top) { Divider().opacity(0.4) }
    }
}
/// The same visible boundary is also the hit boundary, including empty row space.
private struct MiloHitFeedback: ViewModifier {
    var pressed = false
    var selected = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false
    func body(content: Content) -> some View {
        content.contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 5).fill((selected ? Color(hex: "#E2D3BC") : Color(hex: "#96724F").opacity(enabled ? (pressed ? 0.19 : hovered ? 0.105 : 0) : 0))))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color(hex: "#A68A6D").opacity(enabled && hovered ? 0.25 : 0), lineWidth: 0.7))
            .opacity(enabled ? 1 : 0.42)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovered)
            .onHover { inside in
                if inside && enabled && !hovered { NSCursor.pointingHand.push(); hovered = true }
                else if !inside && hovered { NSCursor.pop(); hovered = false }
            }
            .onChange(of: enabled) { _, value in if !value && hovered { NSCursor.pop(); hovered = false } }
            .onDisappear { if hovered { NSCursor.pop(); hovered = false } }
    }
}
struct MiloHoverStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 4).frame(minWidth: 26, minHeight: 28)
            .modifier(MiloHitFeedback(pressed: configuration.isPressed, selected: selected))
    }
}
struct MiloPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(Color.white)
            .padding(.horizontal, 15).padding(.vertical, 9).frame(minHeight: 32)
            .background(LinearGradient(colors: [Color(hex: "#BE6245"), Color(hex: "#AC4F35")], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "#96442E"), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 2)
            .modifier(MiloHitFeedback(pressed: configuration.isPressed))
    }
}
struct MiloSecondaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12)).foregroundStyle(DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 30)
            .background(DesignSystem.Colors.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(DesignSystem.Colors.border, lineWidth: 0.8))
            .modifier(MiloHitFeedback(pressed: configuration.isPressed))
    }
}
/// Uses an explicit button so sheets cannot fall back to arrow-only disclosure hit testing.
struct MiloDisclosure<Label: View, Content: View>: View {
    private var external: Binding<Bool>?
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let content: Content
    init(isExpanded: Binding<Bool>? = nil, @ViewBuilder content: () -> Content, @ViewBuilder label: () -> Label) {
        external = isExpanded; self.content = content(); self.label = label()
    }
    private var isExpanded: Bool { external?.wrappedValue ?? expanded }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                    if let external { external.wrappedValue.toggle() } else { expanded.toggle() }
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0)).frame(width: 10)
                    label
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(MiloHoverStyle()).accessibilityValue(isExpanded ? "已展开" : "已折叠")
            if isExpanded { content.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 4) }
        }
    }
}
extension MiloDisclosure where Label == Text {
    init(_ title: String, @ViewBuilder content: () -> Content) { self.init(content: content, label: { Text(title) }) }
}
struct MiloGlassBackground: View {
    var menu = false
    @ObservedObject private var config = ConfigService.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        ZStack {
            if config.settings.useGlassBackground && !reduceTransparency {
                // Keep the blur itself at full strength. Fading it reveals sharp
                // desktop text; tint density and material thickness are separate.
                // NSPopover already supplies its own blur. Adding another effect
                // there stacks neutral material fills and makes the menu cloudy.
                if !menu { MiloVisualEffect() }
                LinearGradient(
                    colors: [DesignSystem.Colors.glassTintTop.opacity(menu ? 0.34 : 0.30),
                             DesignSystem.Colors.glassTintBottom.opacity(menu ? 0.25 : 0.22)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            } else { DesignSystem.Colors.background }
        }.ignoresSafeArea().allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct MiloChromeBackground: View {
    @ObservedObject private var config = ConfigService.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    // A light local backing for controls, over the one shared window blur.
    // An opaque header/footer would hide the background and wash out its colour.
    var body: some View {
        DesignSystem.Colors.background
            .opacity(config.settings.useGlassBackground && !reduceTransparency ? 0.18 : 1)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
private struct MiloVisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { configure(view) }
    private func configure(_ view: NSVisualEffectView) {
        // The floating review window uses a lighter HUD material.
        // AppKit owns the actual backdrop filtering; no private layer manipulation.
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .aqua)
        view.alphaValue = 1
    }
}
struct MiloUsageDetails: View {
    let usage: TokenUsage?
    let footprint: RequestFootprint?
    let rawUsage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let usage {
                Text("服务报告：输入 \(usage.input.map(String.init) ?? "—") · 输出 \(usage.output.map(String.init) ?? "—") · 合计 \(usage.total.map(String.init) ?? "—") Tokens")
                if let cached = usage.cachedInput { Text("其中缓存输入 \(cached) Tokens") }
                if let reasoning = usage.reasoning { Text("输出中包含推理 \(reasoning) Tokens（已含在输出数内）") }
            } else { Text("服务未返回用量。") }
            if let footprint {
                Text("本机请求：" + footprint.summary)
                Text("字符数与请求体大小不是 Tokens。图片也会计入输入用量；中转服务的额外上下文与计费口径需要向服务方核对。")
            }
            if let rawUsage {
                Text("API 原始 usage").fontWeight(.medium)
                Text(rawUsage).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
            }
        }.font(.system(size: 11)).lineSpacing(3).foregroundStyle(DesignSystem.Colors.textSecondary).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
}
struct MiloPaper<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View { VStack(alignment: .leading, spacing: 13, content: content).padding(18).frame(maxWidth: .infinity, alignment: .leading).background(DesignSystem.Colors.surface).shadow(color: .brown.opacity(0.035), radius: 2, y: 2) }
}
struct MiloNotice: View {
    let text: String?
    var body: some View {
        if let text, !text.isEmpty {
            HStack(alignment: .top, spacing: 7) { Image(systemName: "info.circle"); Text(text).fixedSize(horizontal: false, vertical: true) }
                .font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color(hex: "#EDE2D2"))
        }
    }
}
struct MiloModelPicker: View {
    @ObservedObject var config = ConfigService.shared
    @State private var error: String?
    var body: some View {
        Picker("本次使用", selection: Binding(get: { selection }, set: select)) {
            if config.settings.apiProfiles.allSatisfy({ $0.models.isEmpty }) { Text("尚未配置模型").tag("") }
            ForEach(config.settings.apiProfiles) { profile in
                Section(profile.name) {
                    ForEach(profile.models) { model in Text(model.name).tag(profile.id.uuidString + "|" + model.id.uuidString) }
                }
            }
        }.labelsHidden().pickerStyle(.menu).font(.system(size: 11)).help(error ?? "切换下一次识别使用的 API 和模型")
    }
    private var selection: String { guard let p = config.settings.selectedAPIID, let m = config.settings.selectedModelID else { return "" }; return p.uuidString + "|" + m.uuidString }
    private func select(_ value: String) {
        let ids = value.split(separator: "|"); guard ids.count == 2, let p = UUID(uuidString: String(ids[0])), let m = UUID(uuidString: String(ids[1])) else { return }
        do { try config.select(api: p, model: m); error = nil } catch { self.error = FailureInfo.from(error).message }
    }
}
struct QuietState<Actions: View>: View {
    let title: String; let message: String
    @ViewBuilder var actions: () -> Actions
    var body: some View {
        VStack(spacing: 17) {
            Spacer(minLength: 15)
            Image("MiloScribe").resizable().scaledToFit().frame(width: 150, height: 155)
            Text(title).font(.system(size: 22, weight: .medium)).foregroundStyle(DesignSystem.Colors.textPrimary)
            Text(message).font(.system(size: 12)).lineSpacing(6).multilineTextAlignment(.center).foregroundStyle(DesignSystem.Colors.textSecondary).frame(maxWidth: 440)
            HStack(spacing: 10, content: actions).padding(.top, 10)
            Spacer(minLength: 20)
        }.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Watches only its own paper area. Text editing keeps its normal arrow keys.
struct PaperPagingEvents: NSViewRepresentable {
    var previous: () -> Void
    var next: () -> Void
    func makeNSView(context: Context) -> PagingView { let v = PagingView(); v.previous = previous; v.next = next; return v }
    func updateNSView(_ view: PagingView, context: Context) { view.previous = previous; view.next = next }
    final class PagingView: NSView {
        var previous: (() -> Void)?; var next: (() -> Void)?
        private var monitor: Any?; private var amount: CGFloat = 0; private var lastTurn: TimeInterval = 0; private var lastEvent: TimeInterval = 0
        override func viewDidMoveToWindow() {
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .keyDown]) { [weak self] event in
                guard let self, event.window === window else { return event }
                if event.type == .keyDown {
                    guard window?.firstResponder is NSTextView == false, window?.firstResponder is NSControl == false,
                          bounds.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil)), event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
                    if event.keyCode == 123 { previous?(); return nil }
                    if event.keyCode == 124 { next?(); return nil }
                    return event
                }
                guard bounds.contains(convert(event.locationInWindow, from: nil)), abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.2 else { return event }
                if event.momentumPhase != [] { return nil }
                let now = ProcessInfo.processInfo.systemUptime
                if now - lastTurn < 0.45 { return nil }
                if now - lastEvent > 0.18 { amount = 0 }; lastEvent = now
                amount += event.scrollingDeltaX
                if abs(amount) >= 30 {
                    if amount < 0 { next?() } else { previous?() }
                    amount = 0; lastTurn = now
                }
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}

struct MiloCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3).fill(configuration.isOn ? DesignSystem.Colors.primary : DesignSystem.Colors.surface)
                RoundedRectangle(cornerRadius: 3).stroke(configuration.isOn ? DesignSystem.Colors.primary : DesignSystem.Colors.border, lineWidth: 1)
                if configuration.isOn { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white) }
            }.frame(width: 15, height: 15).frame(width: 24, height: 26).contentShape(Rectangle())
        }.buttonStyle(MiloHoverStyle())
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.checkbox)
        }
    }
}

struct MiloUsageSheet: View {
    let usage: TokenUsage?
    let footprint: RequestFootprint?
    let rawUsage: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("请求与用量").font(.system(size: 18, weight: .medium)); Spacer(); Button("完成") { dismiss() }.buttonStyle(MiloSecondaryStyle()) }
            ScrollView { MiloUsageDetails(usage: usage, footprint: footprint, rawUsage: rawUsage).frame(maxWidth: .infinity, alignment: .leading) }
        }.padding(22).frame(width: 560, height: 380).background(DesignSystem.Colors.background)
    }
}

struct MiloEditableFeedback: ViewModifier {
    @State private var hovered = false
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 3).fill(DesignSystem.Colors.primary.opacity(enabled && hovered ? 0.045 : 0)))
            .overlay(alignment: .bottom) { Rectangle().fill(DesignSystem.Colors.primary.opacity(enabled && hovered ? 0.25 : 0)).frame(height: 1) }
            .onHover { hovered = $0 }
    }
}
