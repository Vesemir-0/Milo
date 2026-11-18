import SwiftUI
import EventKit

struct PreviewWindow: View {
    @ObservedObject var viewModel: ContentProcessViewModel
    var retry: () -> Void = {}
    @ObservedObject private var config = ConfigService.shared
    @ObservedObject private var history = HistoryStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSource = false
    @State private var showUsage = false
    @State private var exportError: String?
    var body: some View {
        VStack(spacing: 0) {
            MiloHeader("核对 \(viewModel.record?.drafts.count ?? 0) 项安排") {
                Button { showUsage = true } label: { Image(systemName: "chart.bar") }.buttonStyle(MiloHoverStyle()).help("请求与用量").accessibilityLabel("请求与用量")
                Button { showSource = true } label: { Label("查看原文", systemImage: "doc.text") }.buttonStyle(MiloHoverStyle()).font(.system(size: 11))
            }
            if let record = viewModel.record, !record.drafts.isEmpty {
                HStack(spacing: 18) {
                    assistant
                    GeometryReader { geometry in
                        let columns = geometry.size.width >= 890 ? 3 : geometry.size.width >= 540 ? 2 : 1
                        let cardWidth = max(1, (geometry.size.width - 10 - CGFloat(columns - 1) * 20) / CGFloat(columns))
                        let pageCount = max(1, Int(ceil(Double(record.drafts.count) / Double(columns))))
                        let group = min(max(0, viewModel.page / columns), pageCount - 1)
                        let start = group * columns
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Text("\(record.source == "image" ? "截图" : "文本")识别 · \(record.modelName)").lineLimit(1)
                                Text("第 \(start + 1)–\(min(start + columns, record.drafts.count)) 项 · 共 \(record.drafts.count) 项").accessibilityLabel("当前显示第\(start + 1)到\(min(start + columns, record.drafts.count))项，共\(record.drafts.count)项")
                                Spacer(minLength: 4)
                                pageButton("chevron.left", disabled: group == 0) { move(-1, columns: columns, pages: pageCount) }
                                if geometry.size.width >= 690 { ForEach(pageDots(group, total: pageCount), id: \.self) { index in
                                    Button { setPage(index * columns) } label: { Circle().fill(group == index ? DesignSystem.Colors.primary : Color(hex: "#CDBCA5")).frame(width: 6, height: 6) }
                                        .buttonStyle(MiloHoverStyle()).help("查看第 \(index + 1) 组").accessibilityLabel("查看第 \(index + 1) 组")
                                }
                                }
                                pageButton("chevron.right", disabled: group == pageCount - 1) { move(1, columns: columns, pages: pageCount) }
                            }.font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary).frame(height: 34)
                            HStack(spacing: 7) {
                                Button("全选") { viewModel.setAllSelected(true) }.buttonStyle(MiloHoverStyle())
                                Button("全不选") { viewModel.setAllSelected(false) }.buttonStyle(MiloHoverStyle())
                                Text("共 \(record.drafts.count) 项，跨页生效").foregroundStyle(DesignSystem.Colors.textTertiary)
                                Spacer()
                            }.font(.system(size: 11)).padding(.bottom, 4).disabled(viewModel.isBusy || record.status == .added)
                            ScrollView(.vertical) {
                                ZStack(alignment: .top) {
                                    HangingRail().padding(.top, 8)
                                    HStack(alignment: .top, spacing: 20) {
                                        ForEach(Array(record.drafts.dropFirst(start).prefix(columns))) { draft in
                                            ScribeNote(draft: draftBinding(draft), number: (record.drafts.firstIndex(where: { $0.id == draft.id }) ?? 0) + 1)
                                                .frame(width: cardWidth, alignment: .top)
                                        }
                                        if record.drafts.count - start < columns {
                                            ForEach(0..<(columns - (record.drafts.count - start)), id: \.self) { _ in Color.clear.frame(width: cardWidth) }
                                        }
                                    }.padding(.horizontal, 5).padding(.top, 43).padding(.bottom, 28)
                                }.frame(maxWidth: .infinity)
                            }
                            .id(group)
                            .scrollIndicators(.automatic)
                            .background(PaperPagingEvents(previous: { move(-1, columns: columns, pages: pageCount) }, next: { move(1, columns: columns, pages: pageCount) }))
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    if !config.settings.useGlassBackground {
                        RadialGradient(colors: [Color(hex: "#F8F4EB"), Color(hex: "#EDE8DF")], center: .top, startRadius: 10, endRadius: 900)
                    }
                }
                MiloNotice(text: exportError ?? viewModel.notice ?? history.storageWarning)
                MiloFooter {
                    Label("已选 \(viewModel.selectedCount) 项", systemImage: "checkmark").font(.system(size: 12, weight: .medium))
                    Text(targetSummary(record)).font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textTertiary)
                    Spacer()
                    Text("标题与正文可直接编辑").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textTertiary)
                    Button { exportDraft() } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(MiloHoverStyle()).help("导出当前草稿")
                    Button { Task { await viewModel.saveSelected() } } label: {
                        if viewModel.state == .saving { HStack { ProgressView().controlSize(.small); Text("正在保存") } }
                        else { Text(viewModel.selectedCount > 0 ? "添加 \(viewModel.selectedCount) 项" : record.status == .added ? "已添加" : "请选择条目") }
                    }.buttonStyle(MiloPrimaryStyle()).disabled(viewModel.isBusy || viewModel.selectedCount == 0).keyboardShortcut(.return, modifiers: .command)
                }
            } else {
                QuietState(title: "这次没有找到明确的日程", message: "内容已经保留。可以补充日期、时间或要做的事，再交给 Milo。") {
                    Button("查看原文") { showSource = true }.buttonStyle(MiloSecondaryStyle())
                    Button("重新整理", action: retry).buttonStyle(MiloPrimaryStyle()).disabled(viewModel.isBusy)
                }
            }
        }.background(MiloGlassBackground()).foregroundStyle(DesignSystem.Colors.textPrimary)
        .sheet(isPresented: $showSource) { SourceSheet(record: viewModel.record, transientImage: viewModel.sourceImage) }
        .sheet(isPresented: $showUsage) { MiloUsageSheet(usage: viewModel.record?.usage, footprint: viewModel.record?.footprint, rawUsage: viewModel.record?.rawUsage) }
        .frame(minWidth: 740, minHeight: 500)
    }
    private var assistant: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.record?.status == .added ? "安排好了。" : "替你写好了。").font(.system(size: 17, weight: .medium)).padding(.top, 37)
            Rectangle().fill(DesignSystem.Colors.primary).frame(width: 28, height: 1)
            Text("再看一眼，\n也可以添上你的一笔。").font(.system(size: 12)).lineSpacing(6).foregroundStyle(DesignSystem.Colors.textSecondary)
            Spacer(minLength: 20)
            Image("MiloScribe").resizable().scaledToFit().frame(width: 118, height: 126)
            Text("你的日程抄写员 Milo").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textTertiary).padding(.bottom, 27)
        }.frame(width: 118, alignment: .leading).frame(maxHeight: .infinity)
    }
    private func pageDots(_ group: Int, total: Int) -> [Int] { total <= 7 ? Array(0..<total) : Array(Set([0, group - 1, group, group + 1, total - 1])).filter { $0 >= 0 && $0 < total }.sorted() }
    private func pageButton(_ icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 10)).frame(width: 26, height: 26).background(DesignSystem.Colors.background, in: RoundedRectangle(cornerRadius: 4)).overlay(RoundedRectangle(cornerRadius: 4).stroke(DesignSystem.Colors.border, lineWidth: 0.7)) }
            .buttonStyle(MiloHoverStyle()).disabled(disabled).opacity(disabled ? 0.25 : 1).accessibilityLabel(icon == "chevron.left" ? "上一组条目" : "下一组条目").help("也可以在纸条区用触控板左右滑动")
    }
    private func move(_ delta: Int, columns: Int, pages: Int) { let group = max(0, min(pages - 1, viewModel.page / columns + delta)); setPage(group * columns) }
    private func setPage(_ first: Int) { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { viewModel.page = first } }
    private func draftBinding(_ initial: EventDraft) -> Binding<EventDraft> { Binding(get: { viewModel.record?.drafts.first { $0.id == initial.id } ?? initial }, set: { viewModel.updateDraft($0) }) }
    private func targetSummary(_ record: HistoryRecord) -> String {
        let items = record.drafts.filter { $0.selected && !$0.isComplete }
        return "日历 \(items.filter { !$0.calendarComplete }.count) 条 · 待办 \(items.filter { !$0.remindersComplete }.count) 项"
    }
    private func exportDraft() {
        guard let record = viewModel.record else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Milo-日程草稿.json"; panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(record).write(to: url, options: .atomic); exportError = nil }
        catch { exportError = "草稿导出没有成功，请选择可写入的位置重试。" }
    }
}

private struct HangingRail: View {
    var body: some View {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [Color(hex: "#9F886C"), Color(hex: "#D5C2A6"), Color(hex: "#998167")], startPoint: .top, endPoint: .bottom)).frame(height: 3)
            HStack { Circle().frame(width: 8, height: 8); Spacer(); Circle().frame(width: 8, height: 8) }.foregroundStyle(Color(hex: "#C4AE8E"))
        }.frame(height: 9).shadow(color: .brown.opacity(0.1), radius: 3, y: 4)
    }
}
private struct PaperClip: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2).fill(LinearGradient(colors: [Color(hex: "#AD916F"), Color(hex: "#E4D0AE"), Color(hex: "#C3A47C"), Color(hex: "#E1C79F")], startPoint: .leading, endPoint: .trailing))
            .overlay(alignment: .top) { Rectangle().fill(Color(hex: "#A58B68")).frame(width: 8, height: 1).padding(.top, 13) }
            .frame(width: 14, height: 44).shadow(color: .brown.opacity(0.2), radius: 2, x: 1, y: 2)
    }
}
private struct ScribeNote: View {
    @Binding var draft: EventDraft
    let number: Int
    @State private var timeExpanded = false
    @State private var targetExpanded = false
    @State private var showLocationInline: Bool
    @State private var showURLInline: Bool
    init(draft: Binding<EventDraft>, number: Int) {
        _draft = draft; self.number = number
        _showLocationInline = State(initialValue: !(draft.wrappedValue.event.location ?? "").isEmpty)
        _showURLInline = State(initialValue: !(draft.wrappedValue.event.url ?? "").isEmpty)
    }
    private var locked: Bool { draft.hasSavedTargets }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Toggle("选择\(draft.event.title)", isOn: $draft.selected).labelsHidden().toggleStyle(MiloCheckboxStyle()).disabled(draft.isComplete).accessibilityLabel("选择\(draft.event.title)")
                Text(String(format: "%02d", number)).font(.system(size: 12, design: .serif))
                Spacer()
                Text(draft.isComplete ? "已添加" : draft.target == .reminderOnly ? "待办" : "日程").font(.system(size: 11))
            }.foregroundStyle(DesignSystem.Colors.textTertiary).padding(.bottom, 19)
            MiloMultilineEditor(text: $draft.event.title, placeholder: "填写标题", font: .systemFont(ofSize: 20, weight: .semibold), color: NSColor(DesignSystem.Colors.textPrimary), accessibilityLabel: "第\(number)项标题")
                .disabled(locked).modifier(MiloEditableFeedback())
            if showLocationInline {
                TextField("地点", text: optionalString(\ParsedEvent.location), axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(DesignSystem.Colors.textSecondary).padding(.top, 6).disabled(locked).accessibilityLabel("第\(number)项地点")
            }
            MiloMultilineEditor(text: Binding(get: { draft.event.readableBody }, set: { draft.event.setBody($0) }), placeholder: "补充内容", font: .systemFont(ofSize: 14), color: NSColor(DesignSystem.Colors.textSecondary), lineSpacing: 6, minimumLines: 2, accessibilityLabel: "第\(number)项正文")
                .padding(.top, 16).disabled(locked).modifier(MiloEditableFeedback())
            if showURLInline {
                TextField("完整链接", text: optionalString(\ParsedEvent.url), axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(DesignSystem.Colors.primary).padding(.top, 9).disabled(locked).accessibilityLabel("第\(number)项链接")
            }
            Spacer(minLength: 28)
            if draft.hasSavedTargets && !draft.isComplete { Text("成功部分已保存，只处理未完成目标。").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.success).padding(.bottom, 8) }
            Divider().opacity(0.35)
            MiloDisclosure(isExpanded: $timeExpanded) {
                dateFields.padding(.top, 9)
            } label: { Label(timeSummary, systemImage: "calendar").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textMetadata) }.tint(DesignSystem.Colors.textTertiary).padding(.top, 9)
            MiloDisclosure(isExpanded: $targetExpanded) {
                destinationFields.padding(.top, 9)
            } label: { Label(targetLabel, systemImage: draft.target == .reminderOnly ? "checklist" : "calendar").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textMetadata) }.tint(DesignSystem.Colors.textTertiary).padding(.top, 11)
            if let validation = draft.validationMessage, draft.selected { Text(validation).font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.warning).padding(.top, 9) }
            if let error = draft.saveError { Text(error).font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.error).padding(.top, 10) }
        }.padding(18).frame(maxWidth: .infinity, minHeight: 340, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(DesignSystem.Colors.textPrimary)
        .background(LinearGradient(colors: [Color(hex: "#FFFCF5"), Color(hex: "#FFFDF8")], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .top) { PaperClip().offset(y: -36) }
        .shadow(color: Color(hex: "#66503A").opacity(0.15), radius: 9, x: 2, y: 10)
    }
    private func optionalString(_ key: WritableKeyPath<ParsedEvent, String?>) -> Binding<String> { Binding(get: { draft.event[keyPath: key] ?? "" }, set: { draft.event[keyPath: key] = $0.isEmpty ? nil : $0 }) }
    private var timeSummary: String {
        let date = draft.target == .reminderOnly ? draft.event.dueDate ?? draft.event.startDate : draft.event.startDate
        guard let date else { return "设置日期与时间" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = draft.event.isAllDay ? "M月d日 · 全天" : "M月d日 · HH:mm"
        var text = formatter.string(from: date)
        if draft.target == .reminderOnly { text += " 截止" }
        else if let end = draft.event.endDate { formatter.dateFormat = Calendar.current.isDate(date, inSameDayAs: end) ? "HH:mm" : "M月d日 HH:mm"; text += " — " + formatter.string(from: end) }
        return text
    }
    private var targetLabel: String {
        if draft.isComplete { return "已添加到" + draft.target.label }
        let calendars = EventKitService.shared.getCalendars(), lists = EventKitService.shared.getReminderLists()
        let cal = calendars.first(where: { $0.calendarIdentifier == draft.calendarID })?.title ?? (draft.event.suggestedCalendar.isEmpty ? "默认日历" : draft.event.suggestedCalendar)
        let list = lists.first(where: { $0.calendarIdentifier == draft.reminderListID })?.title ?? (draft.event.suggestedReminderList.isEmpty ? "默认清单" : draft.event.suggestedReminderList)
        return [draft.target.includesCalendar ? "日历 · " + cal : nil, draft.target.includesReminders ? "待办 · " + list : nil].compactMap { $0 }.joined(separator: " / ")
    }
    private var dateFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("全天安排", isOn: $draft.event.isAllDay).toggleStyle(.checkbox)
            if draft.target != .reminderOnly { dateControl("开始", key: \ParsedEvent.startDate) }
            if draft.target.includesCalendar { dateControl("结束", key: \ParsedEvent.endDate) }
            if draft.target.includesReminders { dateControl("截止", key: \ParsedEvent.dueDate) }
            if draft.target.includesCalendar && draft.event.endDate == nil { Text("未设结束时间时，日历默认保留一小时；全天安排为一天。").font(.system(size: 10)).fixedSize(horizontal: false, vertical: true) }
        }.font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary).disabled(locked)
    }
    private func dateControl(_ label: String, key: WritableKeyPath<ParsedEvent, Date?>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Toggle(label + "日期", isOn: Binding(get: { draft.event[keyPath: key] != nil }, set: { draft.event[keyPath: key] = $0 ? draft.event.startDate ?? Date() : nil })).toggleStyle(.checkbox)
            if draft.event[keyPath: key] != nil {
                DatePicker(label, selection: Binding(get: { draft.event[keyPath: key] ?? Date() }, set: { draft.event[keyPath: key] = $0 }), displayedComponents: draft.event.isAllDay ? [.date] : [.date, .hourAndMinute]).labelsHidden().datePickerStyle(.field).controlSize(.small)
            }
        }
    }
    private var destinationFields: some View {
        VStack(alignment: .leading, spacing: 11) {
            Picker("保存到", selection: $draft.target) { ForEach(SaveTarget.allCases) { Text($0.label).tag($0) } }.disabled(locked)
            if draft.target.includesCalendar {
                Picker("日历", selection: $draft.calendarID) {
                    Text(draft.event.suggestedCalendar.isEmpty ? "系统默认" : "建议：\(draft.event.suggestedCalendar)").tag(String?.none)
                    ForEach(EventKitService.shared.getCalendars(), id: \.calendarIdentifier) { Text($0.title).tag(Optional($0.calendarIdentifier)) }
                }.disabled(draft.savedCalendarID != nil)
            }
            if draft.target.includesReminders {
                Picker("待办", selection: $draft.reminderListID) {
                    Text(draft.event.suggestedReminderList.isEmpty ? "系统默认" : "建议：\(draft.event.suggestedReminderList)").tag(String?.none)
                    ForEach(EventKitService.shared.getReminderLists(), id: \.calendarIdentifier) { Text($0.title).tag(Optional($0.calendarIdentifier)) }
                }.disabled(draft.savedStartReminderID != nil || draft.savedEndReminderID != nil)
                Picker("优先级", selection: $draft.event.priority) { Text("无").tag(0); Text("高").tag(1); Text("普通").tag(5); Text("低").tag(9) }.disabled(locked)
            }
            if !showLocationInline { TextField("地点（可选）", text: optionalString(\ParsedEvent.location)).textFieldStyle(.roundedBorder).disabled(locked) }
            if !showURLInline { TextField("链接（可选）", text: optionalString(\ParsedEvent.url)).textFieldStyle(.roundedBorder).disabled(locked) }
        }.font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary)
    }
}

struct SourceSheet: View {
    let record: HistoryRecord?
    var transientImage: NSImage? = nil
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("交给 Milo 的原文").font(.system(size: 18, weight: .medium)); Spacer(); Button("完成") { dismiss() } }.padding(22)
            Divider()
            ScrollView {
                if let text = record?.sourceText { Text(text).font(.system(size: 14)).lineSpacing(6).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24) }
                else if let name = record?.screenshotFile, let image = HistoryStore.shared.image(name) { Image(nsImage: image).resizable().scaledToFit().padding(20) }
                else if let transientImage { Image(nsImage: transientImage).resizable().scaledToFit().padding(20) }
                else { Text("这次没有保留截图原图，识别结果仍可继续使用。可以在设置中开启原图留存。").font(.system(size: 13)).padding(24) }
            }
        }.frame(width: 650, height: 500).background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary)
    }
}
