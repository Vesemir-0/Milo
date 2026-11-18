import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable {
    case models = "API 与模型", behavior = "识别与保存", permissions = "系统权限"
    var id: String { rawValue }
    var icon: String { self == .models ? "network" : self == .behavior ? "slider.horizontal.3" : "lock" }
}
@MainActor final class SettingsNavigation: ObservableObject { @Published var section: SettingsSection = .models }

@MainActor struct SettingsView: View {
    @ObservedObject var navigation: SettingsNavigation
    @ObservedObject var config: ConfigService
    @ObservedObject var history: HistoryStore
    @ObservedObject private var permissions = PermissionManager.shared
    @State private var draft: AppSettings
    @State private var editingAPI: UUID?
    @State private var showNewAPI = false
    @State private var editingModel: ModelEdit?
    @State private var removeAPI = false
    @State private var notice: String?
    @State private var testModel: UUID?
    @State private var testing = false
    @State private var testFeedback: String?
    @State private var testFailure: FailureInfo?
    @State private var testResult: ConnectionResult?
    @State private var testTask: Task<Void, Never>?
    @State private var testGeneration = UUID()
    var showHistory: () -> Void
    init(navigation: SettingsNavigation, config: ConfigService? = nil, history: HistoryStore? = nil, showHistory: @escaping () -> Void) {
        let resolvedConfig = config ?? ConfigService.shared
        self.navigation = navigation; self.config = resolvedConfig; self.history = history ?? .shared; self.showHistory = showHistory
        _draft = State(initialValue: resolvedConfig.settings); _editingAPI = State(initialValue: resolvedConfig.settings.selectedAPIID ?? resolvedConfig.settings.apiProfiles.first?.id)
    }
    var body: some View {
        VStack(spacing: 0) {
            MiloHeader("设置")
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("设置").font(.system(size: 20, weight: .medium)).foregroundStyle(DesignSystem.Colors.textTertiary).padding(.horizontal, 10).padding(.bottom, 10)
                    ForEach(SettingsSection.allCases) { section in
                        Button { navigation.section = section } label: { Label(section.rawValue, systemImage: section.icon).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 11).padding(.vertical, 11) }.buttonStyle(MiloHoverStyle(selected: navigation.section == section))
                    }
                    Spacer()
                    Image("MiloScribe").resizable().scaledToFit().frame(width: 110, height: 115).frame(maxWidth: .infinity)
                }.padding(.horizontal, 9).padding(.top, 18).padding(.bottom, 18).frame(width: 154).frame(maxHeight: .infinity).background(DesignSystem.Colors.backgroundSecondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch navigation.section { case .models: modelsContent; case .behavior: behaviorContent; case .permissions: permissionsContent }
                    }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            MiloNotice(text: notice ?? config.storageWarning)
            MiloFooter {
                Text(draft == config.settings ? "配置已保留。密钥保存在系统钥匙串。" : "修改在点按“保存配置”后生效。").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                if draft != config.settings { Button("撤销修改") { draft = config.settings; notice = nil }.buttonStyle(MiloSecondaryStyle()) }
                Button("保存配置", action: save).buttonStyle(MiloPrimaryStyle()).keyboardShortcut("s", modifiers: .command)
            }
        }.background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary).frame(minWidth: 760, minHeight: 530)
        .onChange(of: config.settings) { old, value in if draft == old { draft = value } }
        .onChange(of: draft) { _, value in if value != config.settings, notice == "配置已保存。" { notice = nil } }
        .onChange(of: editingAPI) { _, _ in testTask?.cancel(); testGeneration = UUID(); testing = false; testFeedback = nil; testFailure = nil; testResult = nil; testModel = nil }
        .sheet(isPresented: $showNewAPI) { NewAPIEditor { profile in draft.apiProfiles.append(profile); editingAPI = profile.id; showNewAPI = false } }
        .sheet(item: $editingModel) { choice in
            ModelEditor(model: choice.model, canRemove: choice.existing, save: { model in
                guard let index = draft.apiProfiles.firstIndex(where: { $0.id == choice.profileID }) else { return }
                if let m = draft.apiProfiles[index].models.firstIndex(where: { $0.id == model.id }) { draft.apiProfiles[index].models[m] = model }
                else { draft.apiProfiles[index].models.append(model) }
                draft.repairSelection(); editingModel = nil
            }, remove: {
                if let index = draft.apiProfiles.firstIndex(where: { $0.id == choice.profileID }) { draft.apiProfiles[index].models.removeAll { $0.id == choice.model.id }; draft.repairSelection() }
                editingModel = nil
            })
        }
        .confirmationDialog("移除这项 API 及其模型？", isPresented: $removeAPI) {
            Button("移除 API", role: .destructive) { draft.apiProfiles.removeAll { $0.id == editingAPI }; draft.repairSelection(); editingAPI = draft.apiProfiles.first?.id }
            Button("取消", role: .cancel) {}
        } message: { Text("保存配置后生效。历史记录中的识别结果会继续保留。") }
    }
    private var profileIndex: Int? { draft.apiProfiles.firstIndex { $0.id == editingAPI } }
    @ViewBuilder private var modelsContent: some View {
        heading("API 与模型", detail: "一个 API，一组连接信息；里面可以放多个模型。", action: { Button("+ 添加 API") { showNewAPI = true }.buttonStyle(MiloSecondaryStyle()) })
        if draft.apiProfiles.isEmpty {
            MiloPaper { Text("先添加一项 AI 服务").font(.system(size: 18, weight: .medium)); Text("使用你自己的 OpenAI 兼容 API，或提供兼容接口的本地模型。Milo 不需要账户。").font(.system(size: 12)).lineSpacing(5); Button("添加 API") { showNewAPI = true }.buttonStyle(MiloPrimaryStyle()) }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 9) { ForEach(draft.apiProfiles) { profile in
                    Button { editingAPI = profile.id } label: { HStack(spacing: 8) { Text(profile.name); Text("\(profile.models.count) 个模型").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textTertiary) }.font(.system(size: 12)).padding(.horizontal, 14).padding(.vertical, 9) }.buttonStyle(MiloHoverStyle(selected: editingAPI == profile.id))
                } }
            }.scrollIndicators(.hidden)
            if let index = profileIndex {
                MiloPaper {
                    HStack { Text("连接信息").font(.system(size: 14, weight: .semibold)); Spacer(); Button("移除 API") { removeAPI = true }.font(.system(size: 10)).buttonStyle(MiloHoverStyle()).foregroundStyle(DesignSystem.Colors.error) }
                    HStack(alignment: .top, spacing: 12) {
                        labeled("名称") { TextField("例如：常用 API", text: $draft.apiProfiles[index].name).textFieldStyle(.roundedBorder).disabled(testing) }.frame(width: 150)
                        labeled("API 端点") { TextField("https://api.example.com/v1", text: $draft.apiProfiles[index].baseURL).textFieldStyle(.roundedBorder).accessibilityLabel("API 端点").disabled(testing) }
                    }
                    labeled("API Key（本地服务可留空）") { SecureField("这项 API 的密钥", text: $draft.apiProfiles[index].apiKey).textFieldStyle(.roundedBorder).accessibilityLabel("API Key").disabled(testing) }
                    HStack(spacing: 10) {
                        if draft.apiProfiles[index].models.isEmpty { Text("先在下面添加一个模型，再测试连接。").font(.system(size: 10)) }
                        else {
                            Picker("测试模型", selection: Binding(get: { modelForTest(index)?.id }, set: { testModel = $0 })) { ForEach(draft.apiProfiles[index].models) { Text($0.name).tag(Optional($0.id)) } }.font(.system(size: 11)).frame(maxWidth: 210)
                        }
                        Spacer()
                        if testing { Button("取消测试") { testTask?.cancel(); testGeneration = UUID(); testing = false; testFeedback = "测试已取消。" }.buttonStyle(MiloHoverStyle()).font(.system(size: 10)) }
                        Button { runTest(index) } label: { HStack { if testing { ProgressView().controlSize(.mini) }; Text(testing ? "正在测试" : "测试连接") } }.buttonStyle(MiloSecondaryStyle()).disabled(testing || draft.apiProfiles[index].models.isEmpty)
                    }
                    if let feedback = testFeedback { Text(feedback).font(.system(size: 11)).foregroundStyle(testFailure == nil ? DesignSystem.Colors.success : DesignSystem.Colors.error).fixedSize(horizontal: false, vertical: true) }
                    if let result = testResult {
                        MiloDisclosure("用量与请求详情") {
                            VStack(alignment: .leading, spacing: 9) {
                                MiloUsageDetails(usage: result.usage, footprint: result.footprint, rawUsage: result.rawUsage)
                                Text("测试仅发送 Reply OK.，输出上限 \(result.outputLimit)；服务端可能附加上下文或另有计费口径。").font(.system(size: 10))
                                if result.reportedLimitExceeded { Text("服务报告的输出超过测试上限，请核对中转服务是否支持长度参数。").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.warning) }
                            }.padding(.top, 5)
                        }.font(.system(size: 11))
                    }
                    if let failure = testFailure { MiloDisclosure("技术详情") { Text(failure.technical).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.font(.system(size: 10)) }
                }
                MiloPaper {
                    HStack { Text("这个 API 下的模型").font(.system(size: 14, weight: .semibold)); Spacer(); Button("+ 添加模型") { editingModel = ModelEdit(profileID: draft.apiProfiles[index].id, model: ModelProfile(), existing: false) }.buttonStyle(MiloHoverStyle()).font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.primary) }
                    if draft.apiProfiles[index].models.isEmpty { Text("填写模型 ID 和显示名称；以后可以在菜单栏直接切换。").font(.system(size: 12)).foregroundStyle(DesignSystem.Colors.textSecondary) }
                    ForEach(draft.apiProfiles[index].models) { model in
                        HStack(spacing: 8) {
                            Button { draft.selectedAPIID = draft.apiProfiles[index].id; draft.selectedModelID = model.id } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 9) {
                                        Image(systemName: draft.selectedModelID == model.id && draft.selectedAPIID == draft.apiProfiles[index].id ? "largecircle.fill.circle" : "circle").foregroundStyle(DesignSystem.Colors.primary)
                                        Text(model.name).font(.system(size: 12, weight: .medium))
                                        Text(model.modelID).font(.system(size: 10)).lineLimit(1).help(model.modelID)
                                        Spacer(minLength: 0)
                                        Text(model.supportsImages ? "图片" : "文本").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textTertiary)
                                    }
                                    Text("Temperature：\(model.temperature.map { String(format: "%.1f", $0) } ?? "不发送")    输出上限：\(model.outputLimitParameter == .omit ? "服务默认" : String(model.maxTokens))")
                                        .font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textTertiary).padding(.leading, 24)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5).contentShape(Rectangle())
                            }.buttonStyle(MiloHoverStyle()).help("设为当前模型，保存配置后生效")
                            Button { editingModel = ModelEdit(profileID: draft.apiProfiles[index].id, model: model, existing: true) } label: { Image(systemName: "pencil").font(.system(size: 12)).frame(width: 28, height: 34) }.buttonStyle(MiloHoverStyle()).accessibilityLabel("编辑\(model.name)")
                        }
                        if model.id != draft.apiProfiles[index].models.last?.id { Divider().opacity(0.3) }
                    }
                }
            }
        }
    }
    private var behaviorContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("识别与保存", detail: "常用选项留在这里，复杂参数跟着各自的模型走。") { EmptyView() }
            MiloPaper {
                Text("确认与输入").font(.system(size: 14, weight: .semibold))
                settingRow("默认保存位置", detail: "每一项在核对时仍可单独调整。") { Picker("默认保存位置", selection: $draft.saveTarget) { ForEach(SaveTarget.allCases) { Text($0.label).tag($0) } }.labelsHidden().frame(width: 140) }
                Toggle(isOn: $draft.autoAddMode) { settingsCopy("自动添加", detail: "识别后直接保存；缺日期或有错误时仍会停下来核对。") }.toggleStyle(.switch).accessibilityLabel("自动添加")
                Toggle(isOn: $draft.enableScreenshotCapture) { Text("显示截图入口").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading) }.toggleStyle(.switch)
                Toggle(isOn: $draft.enableTextCapture) { Text("显示文本入口").font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading) }.toggleStyle(.switch)
                Toggle(isOn: $draft.useGlassBackground) { settingsCopy("磨砂玻璃背景", detail: "让菜单小窗与核对窗口透出少量桌面颜色。随时可以关闭；遵循系统“减少透明度”设置。") }.toggleStyle(.switch).accessibilityLabel("磨砂玻璃背景")
            }
            MiloPaper {
                Text("等待与诊断").font(.system(size: 14, weight: .semibold))
                settingRow("同时识别", detail: "独立并发处理，哪一份先完成就先核对。服务限流时可以调低。") {
                    Picker("同时识别数量", selection: $draft.maximumConcurrentRecognitions) { ForEach(1...8, id: \.self) { Text("\($0) 个任务").tag($0) } }.labelsHidden().frame(width: 125)
                }
                settingRow("等待上限", detail: "后台继续等待，可以随时主动取消；上游服务可能另有限制。") { Picker("等待上限", selection: $draft.timeoutSeconds) { ForEach([60,180,300,600,1800,3600], id: \.self) { Text("\($0 / 60) 分钟").tag($0) } }.labelsHidden().frame(width: 125) }
                Toggle(isOn: $draft.explainComplexErrors) { settingsCopy("辅助解释复杂错误", detail: "输出结构出错时额外调用一次当前模型，会产生少量 Tokens。只发送脱敏的错误片段，不附带 Key 或截图。") }.toggleStyle(.switch).accessibilityLabel("辅助解释复杂错误")
            }
            MiloPaper {
                Text("本机历史").font(.system(size: 14, weight: .semibold))
                settingRow("保留时间", detail: "退出应用后仍可恢复，不需要重新识别。") { Picker("历史保留时间", selection: $draft.historyRetentionDays) { Text("7 天").tag(7); Text("30 天").tag(30); Text("始终保留").tag(0) }.labelsHidden().frame(width: 125) }
                settingRow("最多保留", detail: "超出后清理最早的记录，不删除系统安排。") { Picker("历史数量上限", selection: $draft.historyLimit) { Text("50 次").tag(50); Text("200 次").tag(200); Text("500 次").tag(500); Text("不限").tag(0) }.labelsHidden().frame(width: 125) }
                Toggle(isOn: $draft.keepScreenshots) { settingsCopy("同时保留截图原图", detail: "默认只保留识别结果。此设置影响之后的识别，原图随对应历史一同清理。") }.toggleStyle(.switch).accessibilityLabel("同时保留截图原图")
                settingRow("清理历史记录", detail: "可以选择删除，也可以一次清理全部。") { Button("前往历史…", action: showHistory).buttonStyle(MiloHoverStyle()).foregroundStyle(DesignSystem.Colors.primary) }
            }
        }
    }
    private var permissionsContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            heading("系统权限", detail: "只在需要的时候，请你交出相应的权限。") { Button("重新检查") { permissions.checkAllPermissions() }.buttonStyle(MiloSecondaryStyle()) }
            MiloPaper {
                ForEach(PermissionType.allCases) { permission in
                    HStack(spacing: 15) {
                        Image(systemName: permission == .screenRecording ? "viewfinder" : permission == .calendar ? "calendar" : "checklist").font(.system(size: 21, weight: .light)).frame(width: 26).foregroundStyle(DesignSystem.Colors.primary)
                        settingsCopy(permission.rawValue, detail: permission == .screenRecording ? "直接圈选屏幕上的日程信息，Esc 取消。" : permission == .calendar ? "把核对后的安排写入系统日历。" : "把待办与截止时间写入系统提醒事项。")
                        Spacer(); Text(permissions.status(permission).label).font(.system(size: 10)).foregroundStyle(permissions.status(permission) == .granted ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                        Button(permissions.status(permission) == .granted ? "查看设置" : "前往授权") {
                            Task { do { if permissions.status(permission) == .granted { permissions.openSystemPreferences(for: permission) } else { try await permissions.request(permission) } } catch { notice = "系统没有完成这次授权，请到隐私与安全性中检查。" } }
                        }.buttonStyle(MiloSecondaryStyle())
                    }.padding(.vertical, 7)
                    if permission != .reminders { Divider().opacity(0.3) }
                }
            }
            Text("从系统设置返回后会重新检查。截图不需要辅助功能权限；你可以先使用已经可用的输入方式。").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary).lineSpacing(5)
        }
    }
    private func heading<Action: View>(_ title: String, detail: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top) { VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 23, weight: .medium)); Text(detail).font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary) }; Spacer(); action() }.padding(.bottom, 2)
    }
    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary); content().font(.system(size: 12)) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func settingsCopy(_ title: String, detail: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 12, weight: .medium)); Text(detail).font(.system(size: 11)).lineSpacing(4).foregroundStyle(DesignSystem.Colors.textSecondary).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, alignment: .leading) }
    private func settingRow<Content: View>(_ title: String, detail: String, @ViewBuilder content: () -> Content) -> some View { HStack(spacing: 24) { settingsCopy(title, detail: detail); Spacer(); content().font(.system(size: 11)) } }
    private func modelForTest(_ index: Int) -> ModelProfile? { let p = draft.apiProfiles[index]; return p.models.first { $0.id == testModel } ?? p.models.first { $0.id == draft.selectedModelID } ?? p.models.first }
    private func runTest(_ index: Int) {
        guard let model = modelForTest(index) else { return }
        let p = draft.apiProfiles[index]
        let snapshot = AIConfig(baseURL: p.baseURL, apiKey: p.apiKey, model: model.modelID, temperature: model.temperature, maxTokens: model.maxTokens, outputLimitParameter: model.outputLimitParameter, supportsImages: model.supportsImages, timeout: Double(draft.timeoutSeconds), profileName: p.name, modelName: model.name)
        let generation = UUID(); testGeneration = generation
        testing = true; testFeedback = "正在向 \(model.name) 发送一条简短测试请求…"; testFailure = nil; testResult = nil
        testTask = Task {
            do {
                let result = try await AIService.shared.testConnection(snapshot)
                try Task.checkCancellation()
                guard testGeneration == generation, editingAPI == p.id else { return }
                testResult = result
                testFeedback = "\(result.returnedText ? "文本连接可用" : "服务已连接，测试在预算内结束") · \(String(format: "%.1f", result.duration)) 秒" + (result.usage.map { " · 输入 \($0.input.map(String.init) ?? "—") / 输出 \($0.output.map(String.init) ?? "—") Tokens" } ?? "") + (model.supportsImages ? "。图片输入尚未单独测试。" : "。")
            } catch is CancellationError { if testGeneration == generation { testFeedback = "测试已取消。" } }
            catch { if testGeneration == generation, editingAPI == p.id { let f = FailureInfo.from(error); testFailure = f; testFeedback = f.title + "。" + f.suggestion } }
            if testGeneration == generation { testing = false }
        }
    }
    private func save() {
        for p in draft.apiProfiles {
            var probe = AIConfig.default; probe.baseURL = p.baseURL
            if p.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || probe.endpoint == nil { notice = "请检查 API 名称与端点。地址中不要填写密钥、查询参数或用户名密码。"; navigation.section = .models; editingAPI = p.id; return }
        }
        guard draft.enableScreenshotCapture || draft.enableTextCapture else { notice = "请至少保留一种输入方式。"; navigation.section = .behavior; return }
        do { try config.save(draft); draft = config.settings; notice = "配置已保存。"; _ = history.prune(days: draft.historyRetentionDays, limit: draft.historyLimit) }
        catch { notice = FailureInfo.from(error).message }
    }
}
private struct ModelEdit: Identifiable { var id = UUID(); var profileID: UUID; var model: ModelProfile; var existing: Bool }
private struct ModelEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var model: ModelProfile
    @State private var customTemperature: Bool
    @State private var temperature: Double
    @State private var error: String?
    @State private var showRemove = false
    let canRemove: Bool
    let save: (ModelProfile) -> Void
    let remove: () -> Void
    init(model: ModelProfile, canRemove: Bool, save: @escaping (ModelProfile) -> Void, remove: @escaping () -> Void) {
        _model = State(initialValue: model); _customTemperature = State(initialValue: model.temperature != nil); _temperature = State(initialValue: model.temperature ?? 0.7)
        self.canRemove = canRemove; self.save = save; self.remove = remove
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(canRemove ? "编辑模型" : "添加模型").font(.system(size: 20, weight: .medium))
            editorField("显示名称") { TextField("例如：日常模型", text: $model.name).accessibilityLabel("模型显示名称") }
            editorField("模型 ID") { TextField("服务提供的完整模型 ID", text: $model.modelID).accessibilityLabel("模型 ID") }
            Toggle("用于识别图片", isOn: $model.supportsImages).toggleStyle(.checkbox).font(.system(size: 12))
            MiloDisclosure("高级参数") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Temperature", selection: $customTemperature) { Text("不发送（服务默认）").tag(false); Text("自定义").tag(true) }.font(.system(size: 12))
                    HStack { Text("自定义值"); TextField("0–2", value: $temperature, format: .number).frame(width: 100).textFieldStyle(.roundedBorder).disabled(!customTemperature) }.font(.system(size: 12))
                    HStack { Text("最大输出长度"); TextField("4000", value: $model.maxTokens, format: .number).frame(width: 130).textFieldStyle(.roundedBorder).disabled(model.outputLimitParameter == .omit) }.font(.system(size: 12))
                    Picker("长度参数", selection: $model.outputLimitParameter) { ForEach(OutputLimitParameter.allCases) { Text($0.label).tag($0) } }.font(.system(size: 12))
                    Text("不支持 Temperature 的模型保留“不发送”。长度参数可选择自动、具体名称或不发送。").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary).lineSpacing(4)
                }.padding(.top, 12)
            }.font(.system(size: 12))
            MiloNotice(text: error)
            HStack {
                if canRemove { Button("移除模型") { showRemove = true }.buttonStyle(MiloHoverStyle()).foregroundStyle(DesignSystem.Colors.error) }
                Spacer(); Button("取消") { dismiss() }.buttonStyle(MiloSecondaryStyle())
                Button("保存模型") {
                    var value = model; value.temperature = customTemperature ? temperature : nil
                    value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines); value.modelID = value.modelID.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.name.isEmpty, !value.modelID.isEmpty, value.maxTokens > 0, value.maxTokens <= 1_000_000, !customTemperature || temperature.isFinite && (0...2).contains(temperature) else { error = "请填写名称和模型 ID，并检查参数范围。"; return }
                    save(value)
                }.buttonStyle(MiloPrimaryStyle()).keyboardShortcut(.return, modifiers: .command)
            }.font(.system(size: 11))
        }.padding(28).frame(width: 570).background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary)
        .confirmationDialog("移除这个模型？", isPresented: $showRemove) { Button("移除模型", role: .destructive, action: remove); Button("保留", role: .cancel) {} }
    }
    private func editorField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 6) { Text(label).font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary); content().textFieldStyle(.roundedBorder).font(.system(size: 13)) } }
}
private struct NewAPIEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var profile = APIProfile()
    @State private var error: String?
    var save: (APIProfile) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("添加 API").font(.system(size: 20, weight: .medium))
            TextField("服务名称", text: $profile.name).textFieldStyle(.roundedBorder).accessibilityLabel("服务名称")
            TextField("https://api.example.com/v1", text: $profile.baseURL).textFieldStyle(.roundedBorder).accessibilityLabel("新 API 端点")
            SecureField("API Key（本地服务可留空）", text: $profile.apiKey).textFieldStyle(.roundedBorder)
            Text("先添加服务，再为这项 API 添加一个或多个模型。密钥会在保存配置时写入系统钥匙串。").font(.system(size: 11)).foregroundStyle(DesignSystem.Colors.textSecondary).lineSpacing(4)
            MiloNotice(text: error)
            HStack { Spacer(); Button("取消") { dismiss() }.buttonStyle(MiloSecondaryStyle()); Button("添加 API") {
                var probe = AIConfig.default; probe.baseURL = profile.baseURL
                guard !profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, probe.endpoint != nil else { error = "请填写名称和有效的 http / https 端点。"; return }
                save(profile)
            }.buttonStyle(MiloPrimaryStyle()) }
        }.padding(28).frame(width: 550).background(DesignSystem.Colors.background).foregroundStyle(DesignSystem.Colors.textPrimary)
    }
}
