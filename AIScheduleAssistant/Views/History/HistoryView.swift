import SwiftUI

struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    @ObservedObject var queue: RecognitionQueue
    var didDelete: (Set<UUID>) -> Void = { _ in }
    var input: () -> Void
    var open: (HistoryRecord) -> Void
    @State private var search = ""
    @State private var filter = "all"
    @State private var selected: Set<UUID> = []
    @State private var deleting: Set<UUID> = []
    @State private var showDelete = false
    var body: some View {
        VStack(spacing: 0) {
            MiloHeader("历史记录")
            VStack(alignment: .leading, spacing: 21) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) { Text("替你收好的记录").font(.system(size: 23, weight: .medium)); Text("重新打开就能继续核对，不必再识别一次。").font(.system(size: 12)).foregroundStyle(DesignSystem.Colors.textSecondary) }
                    Spacer(); Button("清理记录…") { deleting = Set(store.records.filter { ![RecordStatus.queued, .processing, .saving].contains($0.status) }.map(\.id)); showDelete = !deleting.isEmpty }.buttonStyle(MiloSecondaryStyle()).disabled(store.records.isEmpty)
                }
                HStack(spacing: 12) {
                    HStack { Image(systemName: "magnifyingglass"); TextField("搜索标题或内容", text: $search).textFieldStyle(.plain).accessibilityLabel("搜索历史记录") }.font(.system(size: 12)).padding(9).frame(width: 280).background(DesignSystem.Colors.surface, in: RoundedRectangle(cornerRadius: 5)).overlay(RoundedRectangle(cornerRadius: 5).stroke(DesignSystem.Colors.border, lineWidth: 0.8))
                    Picker("筛选", selection: $filter) { Text("全部记录").tag("all"); Text("草稿与待确认").tag("draft"); Text("已添加").tag("added"); Text("未完成").tag("failed") }.labelsHidden().frame(width: 130)
                    Spacer(); Button("删除选中") { deleting = selected; showDelete = true }.buttonStyle(MiloHoverStyle()).font(.system(size: 11)).disabled(selected.isEmpty)
                }
                if visible.isEmpty {
                    QuietState(title: search.isEmpty ? "这里还没有收好的记录" : "没有找到这条记录", message: search.isEmpty ? "下一次识别的结果会留在这里，随时回来继续修改。" : "换个关键词，再找找看。") { if search.isEmpty { Button("输入第一段文本", action: input).buttonStyle(MiloPrimaryStyle()) } }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 11) { ForEach(visible) { record in historyRow(record) } }.padding(.bottom, 24)
                    }
                }
            }.padding(.horizontal, 22).padding(.top, 20).frame(maxWidth: .infinity, maxHeight: .infinity)
            MiloNotice(text: store.storageWarning)
            MiloFooter { Text("仅保存在本机；清理记录不会删除系统日历中的安排。").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary); Spacer(); Text("\(store.records.count) 条记录").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textTertiary) }
        }.background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary).frame(minWidth: 760, minHeight: 500)
        .confirmationDialog("清理这 \(deleting.count) 条记录？", isPresented: $showDelete) {
            Button("清理 \(deleting.count) 条", role: .destructive) {
                let eligible = Set(store.records.filter { deleting.contains($0.id) && ![RecordStatus.queued, .processing, .saving].contains($0.status) }.map(\.id))
                if store.remove(eligible) { didDelete(eligible); selected.subtract(eligible) }
            }
            Button("保留记录", role: .cancel) {}
        } message: { Text("只移除本机历史与保留的截图。已经写入系统日历和待办清单的内容不会删除。") }
    }
    private var visible: [HistoryRecord] {
        store.records.filter { record in
            let stateMatches = filter == "all" || (filter == "draft" && [.draft, .partial].contains(record.status)) || record.status.rawValue == filter
            let haystack = record.title + " " + (record.sourceText ?? "") + " " + record.drafts.map { $0.event.title + " " + $0.event.readableBody }.joined(separator: " ")
            return stateMatches && (search.isEmpty || haystack.localizedCaseInsensitiveContains(search))
        }
    }
    private func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: date)
    }
    private func historyRow(_ record: HistoryRecord) -> some View {
        HStack(spacing: 16) {
            Toggle("选择记录\(record.title)", isOn: Binding(get: { selected.contains(record.id) }, set: { if $0 { selected.insert(record.id) } else { selected.remove(record.id) } })).labelsHidden().toggleStyle(.checkbox).disabled([RecordStatus.queued, .processing, .saving].contains(record.status))
            Button { open(record) } label: {
                HStack(spacing: 17) {
                    Image(systemName: record.source == "image" ? "viewfinder" : "text.alignleft").font(.system(size: 20, weight: .light)).frame(width: 25).foregroundStyle(DesignSystem.Colors.primary)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.title).font(.system(size: 14, weight: .medium)).lineLimit(2)
                        Text("\(record.drafts.count) 项安排 · " + record.drafts.prefix(2).map(\.event.title).joined(separator: "、")).font(.system(size: 11)).lineLimit(1)
                        Text(record.modelName + " · " + timestamp(record.createdAt)).font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textTertiary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 5) {
                        if let seconds = record.duration { Text(String(format: "%.1f 秒", seconds)).font(.system(size: 12)) }
                        if let usage = record.usage { Text("输入 \(usage.input.map(String.init) ?? "—") / 输出 \(usage.output.map(String.init) ?? "—")").font(.system(size: 10)) }
                        if let extra = record.failure?.diagnosticUsage?.total { Text("解释 +\(extra)").font(.system(size: 10)) }
                    }.foregroundStyle(DesignSystem.Colors.textSecondary).frame(minWidth: 72)
                    Text(record.status.label).font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textSecondary).frame(width: 48)
                    Image(systemName: "chevron.right").font(.system(size: 10))
                }.contentShape(Rectangle())
            }.buttonStyle(MiloHoverStyle()).disabled([RecordStatus.queued, .processing, .saving].contains(record.status))
        }.padding(12).background(DesignSystem.Colors.surface)
    }
}
