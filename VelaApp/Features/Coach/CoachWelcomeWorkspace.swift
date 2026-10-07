import SwiftUI
import SwiftData

// MARK: - Coach welcome workspace

/// A compact dated context leaves room for the conversation and its next question.
struct CoachWelcomeWorkspace: View {
    @ObservedObject var vm: CoachChatVM
    let todayOperatingPlan: DailyOperatingPlanRecord?
    let pendingMemoryProposals: [MemoryEventRecord]
    let agentArtifacts: [AgentArtifactRecord]
    @Binding var showWikiProfile: Bool
    let onSendMessage: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var dashboardVM: DashboardViewModel
    @ObservedObject private var appState = VelaAppState.shared

    private var dashboard: DashboardSummary { dashboardVM.dashboard }

    private var questions: [String] {
        Array(vm.contextualQuickQuestions(
            todayPlan: todayOperatingPlan,
            dashboard: dashboard
        ).prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("今天想聊什么？")
                .font(VelaTheme.largeTitle())
                .foregroundStyle(VelaTheme.rhythmInk)
                .accessibilityIdentifier("coach-welcome-greeting")
            currentContextSection
            questionSection
            workspaceSection
        }
    }

    private var currentContextSection: some View {
        Button {
            VelaHaptic.selection()
            appState.routeToToday()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(dashboard.date, format: .dateTime.month().day())
                    Spacer()
                    Text("查看状态")
                    Image(systemName: "chevron.right")
                        .imageScale(.small)
                }
                .font(VelaTheme.subheadline())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)

                Text(contextSummary)
                    .font(VelaTheme.body())
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coach-current-context")
    }

    private var contextSummary: String {
        let metrics: [(String, MetricResult)] = [
            ("恢复", dashboard.recovery), ("睡眠", dashboard.sleepScore),
            ("负荷", dashboard.strain), ("压力", dashboard.stress), ("能量", dashboard.energy)
        ]
        return metrics.map { title, metric in
            "\(title) \(metric.value.map { String(Int($0.rounded())) } ?? "—")"
        }.joined(separator: " · ")
    }

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                ForEach(Array(questions.enumerated()), id: \.offset) { index, question in
                    Button {
                        VelaHaptic.selection()
                        onSendMessage(question)
                    } label: {
                        HStack(spacing: 12) {
                            Text(question)
                                .font(VelaTheme.body())
                                .foregroundStyle(VelaTheme.rhythmInk)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 6)
                            Image(systemName: "arrow.up.right")
                                .font(VelaTheme.caption2().weight(.bold))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 18)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < questions.count - 1 {
                        Divider()
                            .overlay(VelaTheme.rhythmMist)
                            .padding(.horizontal, 14)
                    }
                }
            }
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            }
        }
        .accessibilityIdentifier("coach-contextual-questions")
    }

    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("记录与记忆")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)

            VStack(spacing: 0) {
                if !pendingMemoryProposals.isEmpty {
                    Button {
                        onSendMessage("请展示待确认的记忆更新提案，并逐项说明来源。")
                    } label: {
                        workspaceRow(
                            icon: "brain.head.profile",
                            title: "待确认记忆",
                            badge: "\(pendingMemoryProposals.count)"
                        )
                    }
                    .buttonStyle(.plain)
                    workspaceDivider
                }

                if !agentArtifacts.isEmpty {
                    NavigationLink(destination: AgentArtifactLibraryView()) {
                        workspaceRow(
                            icon: "doc.text.magnifyingglass",
                            title: "分析生成物",
                            badge: "\(agentArtifacts.count)"
                        )
                    }
                    .buttonStyle(.plain)
                    workspaceDivider
                }

                Button {
                    showWikiProfile = true
                } label: {
                    workspaceRow(icon: "person.text.rectangle", title: "健康记忆档案")
                }
                .buttonStyle(.plain)

                workspaceDivider

                NavigationLink(destination: VelaReportsView()) {
                    workspaceRow(icon: "clock.arrow.circlepath", title: "历史分析报告")
                }
                .buttonStyle(.plain)
            }
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            }
        }
    }

    private var workspaceDivider: some View {
        Divider()
            .overlay(VelaTheme.rhythmMist)
            .padding(.leading, 52)
    }

    private func workspaceRow(icon: String, title: String, badge: String? = nil) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(VelaTheme.footnote().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 28, height: 28)
            Text(title)
                .font(VelaTheme.subheadline().weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInk)
            Spacer()
            if let badge {
                Text(badge)
                    .font(VelaTheme.caption2().weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(VelaTheme.rhythmDeep.opacity(0.09), in: Capsule())
            }
            Image(systemName: "chevron.right")
                .font(VelaTheme.caption2().weight(.bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .contentShape(Rectangle())
    }

}


struct VelaReportsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AIReportRecord.createdAt, order: .reverse)
    private var reports: [AIReportRecord]
    @Query(sort: \AgentArtifactRecord.createdAt, order: .reverse)
    private var artifacts: [AgentArtifactRecord]

    @AppStorage("agent_morning_brief_alerts") private var morningBriefOn = true
    @AppStorage("agent_bedtime_reminders") private var sleepReviewOn = true
    @AppStorage("agent_weekly_review_enabled") private var weeklyReviewOn = true
    @AppStorage("agent_post_workout_checkin_enabled") private var postWorkoutOn = true
    @State private var artifactPendingDeletion: AgentArtifactRecord?
    @State private var artifactError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                morningBriefHero

                VelaMakeSectionHeader(title: "今日")
                reportRows

                HStack {
                    VelaMakeSectionHeader(title: "生成物")
                    Spacer()
                    NavigationLink("查看全部") {
                        AgentArtifactLibraryView()
                    }
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                }
                artifactRows

                VelaMakeSectionHeader(title: "自动报告")
                automationRows

                Text("可在「设置 · 通知」中调整时间与开关。")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(VelaTheme.fg2)
                    .padding(.horizontal, 4)
            }
            .padding(16)
            .padding(.bottom, 30)
        }
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("历史报告")
        .velaRhythmDetailChrome()
        .confirmationDialog(
            "删除这个生成物？",
            isPresented: Binding(
                get: { artifactPendingDeletion != nil },
                set: { if !$0 { artifactPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除生成物", role: .destructive) {
                deletePendingArtifact()
            }
            Button("取消", role: .cancel) {
                artifactPendingDeletion = nil
            }
        } message: {
            Text("这只会删除本机保存的生成物，且无法撤销。")
        }
        .alert("无法删除", isPresented: Binding(
            get: { artifactError != nil },
            set: { if !$0 { artifactError = nil } }
        )) {
            Button("好", role: .cancel) { artifactError = nil }
        } message: {
            Text(artifactError ?? "未知错误")
        }
    }

    private var morningBriefHero: some View {
        let latest = reports.first
        return VStack(alignment: .leading, spacing: 8) {
            Label("今日 Morning Brief · 6:00", systemImage: "sun.max.fill")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
            Text(latest?.title ?? "今日身体状态简报")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(.white)
            Text(reportPreview(latest?.markdownContent) ?? "同步健康数据后，Vela 会自动生成恢复、睡眠和训练建议。")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(4)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.orange, Color(uiColor: .systemPink)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var reportRows: some View {
        if reports.isEmpty {
            VelaMakeCard {
                Text("暂无历史报告")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(VelaTheme.fg2)
            }
        } else {
            VStack(spacing: 0) {
                // PR8：报告行可点开阅读完整正文（此前周报/月报正文生成后无阅读入口）。
                ForEach(Array(reports.prefix(5).enumerated()), id: \.element.createdAt) { index, report in
                    NavigationLink {
                        AIReportDetailView(report: report)
                    } label: {
                        reportRow(
                            icon: report.type.contains("sleep") ? "moon.fill" : "sun.max.fill",
                            color: report.type.contains("sleep") ? .indigo : .orange,
                            title: report.title,
                            subtitle: report.createdAt.formatted(.dateTime.month().day().hour().minute())
                        )
                    }
                    .buttonStyle(.plain)
                    if index < min(reports.count, 5) - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(VelaTheme.rhythmCanvasRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// PR8：报告完整正文阅读页（此前只显示标题行，正文不可读）。
    private struct AIReportDetailView: View {
        let report: AIReportRecord

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(report.title)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    MarkdownText(markdown: report.markdownContent, color: VelaTheme.rhythmInk)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle("历史报告")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private var artifactRows: some View {
        if artifacts.isEmpty {
            VelaMakeCard {
                Text("暂无生成物")
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(artifacts.prefix(5).enumerated()), id: \.element.id) { index, artifact in
                    NavigationLink {
                        AgentArtifactDetailView(record: artifact)
                    } label: {
                        reportRow(
                            icon: AgentArtifactPresentation.icon(for: artifact.type),
                            color: .indigo,
                            title: artifact.title,
                            subtitle: "\(AgentArtifactPresentation.typeLabel(for: artifact.type)) · \(artifact.createdAt.formatted(.relative(presentation: .named)))"
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            artifactPendingDeletion = artifact
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    if index < min(artifacts.count, 5) - 1 {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(VelaTheme.rhythmCanvasRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var automationRows: some View {
        VStack(spacing: 0) {
            automationRow("Morning Brief", "每日 6:00", .blue, $morningBriefOn)
            Divider().padding(.leading, 60)
            automationRow("睡眠回顾", "起床后", .purple, $sleepReviewOn)
            Divider().padding(.leading, 60)
            automationRow("周报", "周日 21:00", .green, $weeklyReviewOn)
            Divider().padding(.leading, 60)
            automationRow("训练后复盘", "训练结束 15 分钟后", .orange, $postWorkoutOn)
        }
        .background(VelaTheme.rhythmCanvasRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func reportRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VelaMakeIconTile(systemName: icon, color: color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                    .foregroundStyle(VelaTheme.fg)
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(VelaTheme.fg2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(VelaTheme.meta)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func automationRow(
        _ title: String,
        _ subtitle: String,
        _ color: Color,
        _ isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VelaMakeIconTile(systemName: "sparkles", color: color, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                Text(subtitle)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(VelaTheme.fg2)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    private func reportPreview(_ markdown: String?) -> String? {
        guard let markdown else { return nil }
        return markdown
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func deletePendingArtifact() {
        guard let artifact = artifactPendingDeletion else { return }
        do {
            try PersistenceWriteGate.shared.assertWritable(
                operation: "VelaReportsView: delete agent artifact",
                modelContext: modelContext
            )
            modelContext.delete(artifact)
            try modelContext.save()
            artifactPendingDeletion = nil
            VelaAppState.shared.markLocalDataChanged()
        } catch {
            artifactError = error.localizedDescription
        }
    }
}

// MARK: - Agent artifact library

struct AgentArtifactFact: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { "\(label):\(value)" }
}

struct AgentArtifactPresentation: Equatable {
    let summary: String?
    let facts: [AgentArtifactFact]

    static func parse(payloadJSON: String) -> AgentArtifactPresentation {
        guard let data = payloadJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return AgentArtifactPresentation(summary: nil, facts: [])
        }

        let summary = nonEmptyString(root["summary"])
            ?? nonEmptyString(root["decision"])
            ?? nonEmptyString(root["description"])
        var facts: [AgentArtifactFact] = []

        appendStringFact("训练决策", key: "decision", from: root, to: &facts)
        appendStringFact("目标训练", key: "targetSessionTitle", from: root, to: &facts)
        if let value = root["volumeMultiplier"] as? NSNumber {
            facts.append(AgentArtifactFact(label: "训练量", value: "\(Int((value.doubleValue * 100).rounded()))%"))
        }
        if let value = root["intensityCap"] as? NSNumber {
            facts.append(AgentArtifactFact(label: "强度上限", value: "RPE \(value.intValue)"))
        }
        appendStringFact("结论", key: "decisionText", from: root, to: &facts)

        if let reasons = root["reasons"] as? [[String: Any]] {
            for reason in reasons.prefix(4) {
                let signal = nonEmptyString(reason["signal"]) ?? "判断依据"
                let value = nonEmptyString(reason["value"])
                let explanation = nonEmptyString(reason["explanation"])
                let detail = [value, explanation].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty {
                    facts.append(AgentArtifactFact(label: signal, value: detail))
                }
            }
        } else if let reasons = root["reasons"] as? [String] {
            for (index, reason) in reasons.prefix(4).enumerated() where !reason.isEmpty {
                facts.append(AgentArtifactFact(label: "依据 \(index + 1)", value: reason))
            }
        }

        return AgentArtifactPresentation(summary: summary, facts: Array(facts.prefix(8)))
    }

    static func typeLabel(for type: String) -> String {
        switch type {
        case "daily_plan": return "每日计划"
        case "training_adjustment": return "训练调整"
        case "weekly_report", "weekly_review": return "周度报告"
        case "correlation_chart": return "关联分析"
        case "wiki_diff", "wiki_update_proposal": return "记忆更新"
        case "nutrition_feedback": return "营养反馈"
        case "morning_brief": return "今日简报"
        case "workout_readiness": return "训练准备度"
        case "post_workout_review": return "训练后复盘"
        case "evening_review": return "晚间回顾"
        default: return "Coach 生成物"
        }
    }

    static func icon(for type: String) -> String {
        switch type {
        case "daily_plan": return "calendar.badge.checkmark"
        case "training_adjustment", "workout_readiness": return "slider.horizontal.3"
        case "weekly_report", "weekly_review": return "chart.line.uptrend.xyaxis"
        case "correlation_chart": return "point.3.connected.trianglepath.dotted"
        case "wiki_diff", "wiki_update_proposal": return "brain.head.profile"
        case "nutrition_feedback": return "fork.knife"
        case "post_workout_review": return "figure.strengthtraining.traditional"
        default: return "doc.text.fill"
        }
    }

    private static func appendStringFact(
        _ label: String,
        key: String,
        from object: [String: Any],
        to facts: inout [AgentArtifactFact]
    ) {
        guard let value = nonEmptyString(object[key]),
              !facts.contains(where: { $0.value == value }) else { return }
        facts.append(AgentArtifactFact(label: label, value: value))
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct AgentArtifactLibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \AgentArtifactRecord.createdAt, order: .reverse)
    private var artifacts: [AgentArtifactRecord]

    @State private var searchText = ""
    @State private var selectedType = "all"
    @State private var pendingDeletion: AgentArtifactRecord?
    @State private var errorMessage: String?

    private var availableTypes: [String] {
        Array(Set(artifacts.map(\.type))).sorted {
            AgentArtifactPresentation.typeLabel(for: $0) < AgentArtifactPresentation.typeLabel(for: $1)
        }
    }

    private var filteredArtifacts: [AgentArtifactRecord] {
        artifacts.filter { artifact in
            let matchesType = selectedType == "all" || artifact.type == selectedType
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let matchesSearch = query.isEmpty
                || artifact.title.localizedCaseInsensitiveContains(query)
                || AgentArtifactPresentation.typeLabel(for: artifact.type).localizedCaseInsensitiveContains(query)
            return matchesType && matchesSearch
        }
    }

    var body: some View {
        List {
            Section {
                Picker("类型", selection: $selectedType) {
                    Text("全部").tag("all")
                    ForEach(availableTypes, id: \.self) { type in
                        Text(AgentArtifactPresentation.typeLabel(for: type)).tag(type)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("本机生成物 · \(filteredArtifacts.count)") {
                if filteredArtifacts.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "暂无生成物" : "没有匹配结果",
                        systemImage: searchText.isEmpty ? "tray" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Coach 创建的计划、分析和报告会保存在这里。" : "请尝试其他关键词或类型。")
                    )
                } else {
                    ForEach(filteredArtifacts) { artifact in
                        NavigationLink {
                            AgentArtifactDetailView(record: artifact)
                        } label: {
                            AgentArtifactLibraryRow(record: artifact)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDeletion = artifact
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("生成物")
        .velaRhythmDetailChrome()
        .searchable(text: $searchText, prompt: "搜索计划、报告或分析")
        .confirmationDialog(
            "删除这个生成物？",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除生成物", role: .destructive) { deletePendingArtifact() }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("这只会删除本机保存的生成物，且无法撤销。")
        }
        .alert("无法删除", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func deletePendingArtifact() {
        guard let artifact = pendingDeletion else { return }
        do {
            try PersistenceWriteGate.shared.assertWritable(
                operation: "AgentArtifactLibraryView: delete agent artifact",
                modelContext: modelContext
            )
            modelContext.delete(artifact)
            try modelContext.save()
            pendingDeletion = nil
            VelaAppState.shared.markLocalDataChanged()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AgentArtifactLibraryRow: View {
    let record: AgentArtifactRecord

    var body: some View {
        HStack(spacing: 12) {
            VelaMakeIconTile(
                systemName: AgentArtifactPresentation.icon(for: record.type),
                color: .indigo,
                size: 36
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(record.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(VelaTheme.fg)
                    .lineLimit(2)
                Text("\(AgentArtifactPresentation.typeLabel(for: record.type)) · \(record.createdAt.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(VelaTheme.fg2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            ConfidenceBadge(score: record.confidence)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}

struct AgentArtifactDetailView: View {
    let record: AgentArtifactRecord

    private var presentation: AgentArtifactPresentation {
        AgentArtifactPresentation.parse(payloadJSON: record.payloadJSON)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VelaMakeIconTile(
                            systemName: AgentArtifactPresentation.icon(for: record.type),
                            color: .indigo,
                            size: 42
                        )
                        Spacer()
                        ConfidenceBadge(score: record.confidence)
                    }
                    Text(record.title)
                        .font(VelaTheme.title2())
                        .foregroundStyle(VelaTheme.fg)
                    Text(AgentArtifactPresentation.typeLabel(for: record.type))
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(VelaTheme.muted)
                }
                .padding(18)
                .velaNativeCard(radius: 20)

                if let summary = presentation.summary {
                    artifactSection(title: "摘要") {
                        Text(summary)
                            .font(VelaTheme.body())
                            .foregroundStyle(VelaTheme.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !presentation.facts.isEmpty {
                    artifactSection(title: "关键内容") {
                        VStack(spacing: 0) {
                            ForEach(Array(presentation.facts.enumerated()), id: \.element.id) { index, fact in
                                HStack(alignment: .top, spacing: 12) {
                                    Text(fact.label)
                                        .font(VelaTheme.subheadline().weight(.semibold))
                                        .foregroundStyle(VelaTheme.fg)
                                        .frame(width: 82, alignment: .leading)
                                    Text(fact.value)
                                        .font(VelaTheme.subheadline())
                                        .foregroundStyle(VelaTheme.fg2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 11)
                                if index < presentation.facts.count - 1 { Divider() }
                            }
                        }
                    }
                }

                artifactSection(title: "来源与安全") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(record.source.isEmpty ? "本机生成" : record.source, systemImage: "iphone")
                        Label(record.createdAt.formatted(.dateTime.year().month().day().hour().minute()), systemImage: "clock")
                        Label(record.status == "active" ? "当前有效" : record.status, systemImage: "checkmark.shield")
                        if let notice = record.safetyNotice, !notice.isEmpty {
                            Label(notice, systemImage: "cross.case")
                        }
                    }
                    .font(VelaTheme.footnote())
                    .foregroundStyle(VelaTheme.fg2)
                }
            }
            .padding(16)
            .padding(.bottom, 24)
        }
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("生成物详情")
        .velaRhythmDetailChrome()
    }

    private func artifactSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.muted)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .velaNativeCard(radius: 18)
    }
}
