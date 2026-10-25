import SwiftUI
import SwiftData

struct AccountSettingsView: View {
    let dashboard: DashboardSummary
    var onRefresh: (() async -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @AppStorage("vela_user_age") private var userAge = 0
    @AppStorage("vela_user_weight") private var userWeight = 0.0
    @AppStorage("vela_user_height") private var userHeight = 0.0
    @AppStorage("vela_max_hr") private var userMaxHR = 0
    @AppStorage("vela_user_biological_sex") private var biologicalSex = ""
    @State private var ageDraft = ""
    @State private var weightDraft = ""
    @State private var heightDraft = ""
    @State private var maxHeartRateDraft = ""
    @State private var validationMessage: String?

    init(
        dashboard: DashboardSummary,
        onRefresh: (() async -> Void)? = nil
    ) {
        self.dashboard = dashboard
        self.onRefresh = onRefresh
    }

    private var storedAge: Int? {
        Int(ageDraft).flatMap { (10...100).contains($0) ? $0 : nil }
    }

    private var inferredMaxHR: Int? {
        storedAge.map { Int(UserProfileSettings.inferredMaxHeartRate(age: $0)) }
    }

    private var hasHealthProfileData: Bool {
        dashboard.extendedMetrics.age != nil
            || dashboard.bodyMetrics.weightKilograms != nil
            || dashboard.extendedMetrics.heightCm != nil
            || dashboard.extendedMetrics.biologicalSex != nil
    }

    var body: some View {
        Form {
            Section {
                Text("评分会使用这些资料；可以留空，也可以随时更新。")
                    .font(VelaTheme.callout())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            Section(header: Text("生理特征指标")) {
                if hasHealthProfileData {
                    Label("已同步的 Apple 健康资料会自动用于评分与训练建议。", systemImage: "heart.text.square")
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.muted)
                }
                profileRowLayout {
                    Text("年龄")
                        .font(VelaTheme.callout())
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: true, vertical: false)
                    TextField("年龄", text: $ageDraft)
                        .accessibilityLabel("年龄")
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    Text("岁")
                    profileSourceBadge(
                        manual: UserProfileSettings.age() != nil,
                        automatic: dashboard.extendedMetrics.age != nil
                            ? "Apple 健康"
                            : (WikiFileService.getAgeFromWiki() != nil ? "档案" : nil)
                    )
                }
                profileRowLayout {
                    Text("体重")
                        .font(VelaTheme.callout())
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: true, vertical: false)
                    TextField("体重", text: $weightDraft)
                        .accessibilityLabel("体重")
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    Text("kg")
                    profileSourceBadge(
                        manual: UserProfileSettings.weightKilograms() != nil,
                        automatic: dashboard.bodyMetrics.weightKilograms != nil ? "Apple 健康" : nil
                    )
                }
                profileRowLayout {
                    Text("身高")
                        .font(VelaTheme.callout())
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: true, vertical: false)
                    TextField("身高", text: $heightDraft)
                        .accessibilityLabel("身高")
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    Text("cm")
                    profileSourceBadge(
                        manual: UserProfileSettings.heightCentimeters() != nil,
                        automatic: dashboard.extendedMetrics.heightCm != nil ? "Apple 健康" : nil
                    )
                }
                profileRowLayout {
                    Text("最大心率（可选）")
                        .font(VelaTheme.callout())
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: true, vertical: false)
                    TextField("最大心率（可选）", text: $maxHeartRateDraft)
                        .accessibilityLabel("最大心率（可选）")
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    Text("bpm")
                    profileSourceBadge(
                        manual: UserProfileSettings.maxHeartRate() != nil,
                        automatic: UserProfileSettings.maxHeartRate() == nil && inferredMaxHR != nil ? "按年龄推断" : nil
                    )
                }

                profileRowLayout {
                    Picker("生理性别", selection: $biologicalSex) {
                        Text("未设置").tag("")
                        Text("男性").tag("male")
                        Text("女性").tag("female")
                        Text("其他").tag("other")
                    }
                    profileSourceBadge(
                        manual: !biologicalSex.isEmpty,
                        automatic: biologicalSex.isEmpty && dashboard.extendedMetrics.biologicalSex != nil ? "Apple 健康" : nil
                    )
                }

                if let inferredMaxHR {
                    Button("使用年龄推断值（\(inferredMaxHR) bpm）") {
                        maxHeartRateDraft = ""
                    }
                } else {
                    Text("填写年龄后可使用年龄推断的最大心率。")
                        .font(.footnote)
                        .foregroundStyle(VelaTheme.muted)
                }
            }

            Section {
                Button("保存个人资料") {
                    applyProfile()
                }
                .frame(maxWidth: .infinity)
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.accentOn)
                .padding(.vertical, VelaTheme.space3)
                .frame(minHeight: VelaTheme.minimumHitTarget)
                .background(VelaTheme.accent, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard))
                .buttonStyle(.plain)
            } footer: {
                Text("已填写的数值优先于 Apple 健康数据；清空字段即可恢复使用 Apple 健康。应用后会重新计算训练建议。")
            }
        }
        .navigationTitle("基本资料")
        .velaRhythmFormSurface()
        .velaRhythmDetailChrome()
        .onAppear {
            populateProfileDrafts()
        }
        .onChange(of: dashboard) {
            populateProfileDrafts()
        }
        .alert("无法应用身体模型", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("好", role: .cancel) { validationMessage = nil }
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var profileRowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: VelaTheme.space2))
            : AnyLayout(HStackLayout())
    }

    private func populateProfileDrafts() {
        let healthProfile = dashboard
        // 与 Coach 的年龄解析同源：手动 → Apple 健康 → wiki 档案。
        ageDraft = (10...100).contains(userAge)
            ? String(userAge)
            : healthProfile.extendedMetrics.age.map(String.init)
                ?? WikiFileService.getAgeFromWiki().map(String.init)
                ?? ""
        weightDraft = (25...350).contains(userWeight)
            ? String(format: "%.1f", userWeight)
            : healthProfile.bodyMetrics.weightKilograms.map { String(format: "%.1f", $0) } ?? ""
        heightDraft = (100...250).contains(userHeight)
            ? String(format: "%.0f", userHeight)
            : healthProfile.extendedMetrics.heightCm.map { String(format: "%.0f", $0) } ?? ""
        maxHeartRateDraft = (100...240).contains(userMaxHR) ? String(userMaxHR) : ""
        // 生理性别不再自动从 Apple 健康写入手填值：保持「未设置 = 跟随 Apple 健康」语义。
    }

    private func profileSourceBadge(manual: Bool, automatic: String?) -> some View {
        Group {
            if manual {
                Text("手动")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VelaTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(VelaTheme.accent.opacity(0.12), in: Capsule())
            } else if let automatic {
                Text(automatic)
                    .font(.caption2)
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(VelaTheme.rhythmMist.opacity(0.6), in: Capsule())
            }
        }
    }

    private func applyProfile() {
        let parsedAge = ageDraft.isEmpty ? nil : Int(ageDraft)
        let parsedWeight = weightDraft.isEmpty ? nil : Double(weightDraft)
        let parsedHeight = heightDraft.isEmpty ? nil : Double(heightDraft)
        let parsedMaxHeartRate = maxHeartRateDraft.isEmpty ? nil : Int(maxHeartRateDraft)

        guard parsedAge.map({ (10...100).contains($0) }) ?? true,
              parsedWeight.map({ (25...350).contains($0) }) ?? true,
              parsedHeight.map({ (100...250).contains($0) }) ?? true,
              parsedMaxHeartRate.map({ (100...240).contains($0) }) ?? true else {
            validationMessage = "请检查输入范围：年龄 10-100 岁，体重 25-350 kg，身高 100-250 cm，最大心率 100-240 bpm。"
            return
        }

        userAge = parsedAge ?? 0
        userWeight = parsedWeight ?? 0
        userHeight = parsedHeight ?? 0
        userMaxHR = parsedMaxHeartRate ?? 0
        VelaAppState.shared.markLocalDataChanged()
        VelaHaptic.success()
        // M3 修复：设置页改档案必须与 Coach 工具路径对称——同步回写 wiki 档案
        // 与 SwiftData 记录，避免「账户与特征基准」和「健康档案」两处互相矛盾。
        WikiProfileMaterializer.refreshPhysiologicalProfile(modelContext: modelContext)
        WikiSyncManager.sync(modelContext: modelContext)
        Task {
            if let onRefresh {
                await onRefresh()
            }
        }
    }
}

enum EditorMode {
    case reading
    case form
    case markdown
}

struct ParsedItem: Identifiable, Equatable {
    let id: UUID
    var key: String
    var value: String
    var isKeyValue: Bool
    
    init(id: UUID = UUID(), key: String, value: String, isKeyValue: Bool) {
        self.id = id
        self.key = key
        self.value = value
        self.isKeyValue = isKeyValue
    }
}

struct UserWikiArchiveView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var wikiDocs: [UserWikiDocumentRecord] = []
    
    @State private var selectedDoc: UserWikiDocumentRecord?
    @State private var showEditor = false
    @State private var editText = ""
    @State private var editTitle = ""
    
    @State private var editorMode: EditorMode = .reading
    @State private var parsedItems: [ParsedItem] = []
    @State private var notesText: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("你的健康画像与个人背景会作为 Coach 的本地长期记忆，用于改善训练、恢复和营养建议。")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.muted)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                
                if wikiDocs.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                        Text("正在初始化本地健康档案...")
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(VelaTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    ForEach(wikiDocs.filter { $0.filename != "baselines.md" }) { doc in
                        Button {
                            selectedDoc = doc
                            editTitle = doc.title
                            editText = doc.markdownContent
                            parseMarkdown(doc.markdownContent)
                            editorMode = .reading
                            showEditor = true
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                  HStack {
                                      Text(doc.title)
                                          .font(.system(.callout, design: .default, weight: .bold))
                                          .foregroundStyle(VelaTheme.fg)
                                      Spacer()
                                      Image(systemName: "chevron.right")
                                          .font(VelaTheme.caption1())
                                          .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                  }
                                
                                Text(archiveExcerpt(doc))
                                    .font(.system(.footnote, design: .default))
                                    .foregroundStyle(VelaTheme.muted)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                                
                                HStack {
                                    Spacer()
                                    Text("更新于: \(formatDate(doc.updatedAt))")
                                        .font(.system(.caption2, design: .default))
                                        .foregroundStyle(VelaTheme.meta)
                                }
                            }
                            .padding(16)
                            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).fill(VelaTheme.secondaryGroupedBackground))
                            .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("健康档案")
        .velaRhythmDetailChrome()
        .task {
            loadDocuments()
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack {
                VStack(spacing: 0) {
                    Picker("编辑模式", selection: $editorMode) {
                        Text("阅读").tag(EditorMode.reading)
                        Text("编辑").tag(EditorMode.form)
                        Text("源码编辑").tag(EditorMode.markdown)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    
                    if editorMode != .reading {
                        TextField("标题", text: $editTitle)
                            .font(.system(.callout, design: .default, weight: .bold))
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusSm).fill(VelaTheme.secondaryGroupedBackground))
                            .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusSm).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    
                    }

                    if editorMode == .reading {
                        ScrollView {
                            VStack(alignment: .leading, spacing: VelaTheme.space4) {
                                if isUnchangedTemplate {
                                    Text("还没有相关记录")
                                        .font(VelaTheme.headline())
                                    Text("这份档案尚未填写。选择“编辑”补充你的习惯或背景。")
                                        .font(VelaTheme.callout())
                                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                } else {
                                    MarkdownText(markdown: editText, font: VelaTheme.body(), color: VelaTheme.rhythmInk)
                                }
                                DisclosureGroup("文件信息") {
                                    Text(selectedDoc?.filename ?? "")
                                        .font(VelaTheme.caption1())
                                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                }
                            }
                            .padding(VelaTheme.pagePadding)
                        }
                    } else if editorMode == .form {
                        ScrollView {
                            VStack(spacing: 16) {
                                if parsedItems.isEmpty {
                                    VStack(spacing: 12) {
                                        Text("这份档案以文字记录。")
                                            .font(.system(.footnote, design: .default, weight: .semibold))
                                            .foregroundStyle(VelaTheme.muted)
                                        Text("可编辑下方正文，或添加一项资料。")
                                            .font(.system(.caption, design: .default))
                                            .foregroundStyle(VelaTheme.muted)
                                            .multilineTextAlignment(.center)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 30)
                                    .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).fill(VelaTheme.secondaryGroupedBackground))
                                    .padding(.horizontal, 16)
                                } else {
                                    VStack(alignment: .leading, spacing: 14) {
                                        ForEach($parsedItems) { $item in
                                            HStack(spacing: 12) {
                                                Button {
                                                    if let index = parsedItems.firstIndex(where: { $0.id == item.id }) {
                                                        withAnimation {
                                                            _ = parsedItems.remove(at: index)
                                                        }
                                                    }
                                                } label: {
                                                    Image(systemName: "minus.circle.fill")
                                                        .font(.system(size: 20))
                                                        .foregroundStyle(VelaTheme.danger)
                                                }
                                                .buttonStyle(.plain)
                                                
                                                VStack(alignment: .leading, spacing: 6) {
                                                    if item.isKeyValue {
                                                        HStack(spacing: 8) {
                                                            Image(systemName: "tag.fill")
                                                                .font(.system(size: 11))
                                                                .foregroundStyle(VelaTheme.accent)
                                                            TextField("属性名", text: $item.key)
                                                                .font(.system(.footnote, design: .default, weight: .bold))
                                                                .foregroundStyle(VelaTheme.accent)
                                                        }
                                                        
                                                        TextField("属性值", text: $item.value)
                                                            .font(.system(.footnote, design: .default))
                                                            .foregroundStyle(VelaTheme.fg)
                                                            .padding(.leading, 19)
                                                    } else {
                                                        HStack(spacing: 8) {
                                                            Image(systemName: "list.bullet")
                                                                .font(.system(size: 12))
                                                                .foregroundStyle(VelaTheme.muted)
                                                            TextField("列表内容", text: $item.value)
                                                                .font(.system(.footnote, design: .default))
                                                                .foregroundStyle(VelaTheme.fg)
                                                        }
                                                    }
                                                }
                                                .padding(12)
                                                .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous).fill(VelaTheme.cardBg))
                                                .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                }
                                
                                HStack(spacing: 16) {
                                    Button {
                                        withAnimation {
                                            parsedItems.append(ParsedItem(key: "新属性", value: "", isKeyValue: true))
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                            Text("新增属性")
                                        }
                                        .font(.system(.footnote, design: .default, weight: .semibold))
                                        .foregroundStyle(VelaTheme.accent)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(Capsule().fill(VelaTheme.accent.opacity(0.12)))
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button {
                                        withAnimation {
                                            parsedItems.append(ParsedItem(key: "", value: "新列表项", isKeyValue: false))
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus.circle.fill")
                                            Text("新增列表项")
                                        }
                                        .font(.system(.footnote, design: .default, weight: .semibold))
                                        .foregroundStyle(VelaTheme.muted)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 16)
                                        .background(Capsule().fill(VelaTheme.muted.opacity(0.12)))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 4)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("其它备注信息 (Markdown)")
                                        .font(.system(.footnote, design: .default, weight: .bold))
                                        .foregroundStyle(VelaTheme.muted)
                                    
                                    TextEditor(text: $notesText)
                                        .font(.system(.footnote, design: .default))
                                        .frame(height: 120)
                                        .padding(8)
                                        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusSm).fill(VelaTheme.cardBg))
                                        .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusSm).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                            }
                            .padding(.vertical, 8)
                        }
                    } else {
                        TextEditor(text: $editText)
                            .font(.system(.footnote, design: .default))
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).fill(VelaTheme.cardBg))
                            .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    
                    Spacer(minLength: 16)
                }
                .background(VelaTheme.rhythmCanvas)
                .navigationTitle(editorMode == .reading ? editTitle : "编辑健康档案")
                .velaRhythmDetailChrome()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(editorMode == .reading ? "关闭" : "取消") { showEditor = false }
                    }
                    if editorMode != .reading {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("保存") {
                                saveDocEdits()
                                showEditor = false
                            }
                            .bold()
                            .foregroundStyle(VelaTheme.accent)
                        }
                    }

                }
            }
        }
    }
    
    /// List preview only: retain the original Markdown for reading and editing.
    private var isUnchangedTemplate: Bool {
        guard let filename = selectedDoc?.filename else { return false }
        return editText.trimmingCharacters(in: .whitespacesAndNewlines)
            == WikiFileService.defaultContent(for: filename).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func archiveExcerpt(_ doc: UserWikiDocumentRecord) -> String {
        let markdown = doc.markdownContent
        if markdown.trimmingCharacters(in: .whitespacesAndNewlines)
            == WikiFileService.defaultContent(for: doc.filename).trimmingCharacters(in: .whitespacesAndNewlines) {
            return "还没有相关记录，打开补充。"
        }
        let lines = markdown.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let text = lines.map { line in
            line.hasPrefix("- ") || line.hasPrefix("* ") ? String(line.dropFirst(2)) : line
        }.joined(separator: " · ")
        return text.isEmpty ? "打开查看档案" : String(text.prefix(120))
    }

    private func parseMarkdown(_ text: String) {
        var items: [ParsedItem] = []
        var extraLines: [String] = []
        var hasSkippedPrimaryHeading = false
        
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("#") {
                if !hasSkippedPrimaryHeading, trimmed.hasPrefix("# "), String(trimmed.dropFirst(2)) == editTitle {
                    hasSkippedPrimaryHeading = true
                    continue
                }
                extraLines.append(line)
                continue
            }
            
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if let colonIndex = content.firstIndex(of: ":") {
                    let key = String(content[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(content[content.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    items.append(ParsedItem(key: key, value: value, isKeyValue: true))
                } else if let cnColonIndex = content.firstIndex(of: "：") {
                    let key = String(content[..<cnColonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(content[content.index(after: cnColonIndex)...]).trimmingCharacters(in: .whitespaces)
                    items.append(ParsedItem(key: key, value: value, isKeyValue: true))
                } else {
                    items.append(ParsedItem(key: "", value: content, isKeyValue: false))
                }
            } else {
                extraLines.append(trimmed)
            }
        }
        
        self.parsedItems = items
        self.notesText = extraLines.joined(separator: "\n")
    }
    
    private func reconstructMarkdown() -> String {
        var lines: [String] = []
        lines.append("# \(editTitle)")
        lines.append("")
        
        for item in parsedItems {
            if item.isKeyValue {
                lines.append("- \(item.key): \(item.value)")
            } else {
                lines.append("- \(item.value)")
            }
        }
        
        if !notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(notesText)
        }
        
        return lines.joined(separator: "\n")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
    
    private func saveDocEdits() {
        guard let doc = selectedDoc else { return }
        
        let finalContent: String
        if editorMode == .form {
            finalContent = reconstructMarkdown()
        } else {
            finalContent = editText
        }
        
        _ = try? WikiFileService.updateSection(filename: doc.filename, content: finalContent, mode: .replace)
        loadDocuments()
    }

    private func loadDocuments() {
        WikiSyncManager.sync(modelContext: modelContext)
        wikiDocs = (try? UserWikiDocumentRepository(modelContext: modelContext).fetchAllSortedByUpdatedAt()) ?? []
    }
}
