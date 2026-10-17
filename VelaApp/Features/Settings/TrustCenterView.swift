import SwiftUI
import SwiftData

/// A scrollable history of all agent runs (Morning Brief, Evening Sync, Coach).
/// Shows status, duration, and what was produced.
struct TrustCenterView: View {
    var dashboard: DashboardSummary = .empty()
    var onRefresh: (() async -> Void)?

    @AppStorage(CoachOutboundDataPolicy.consentVersionKey) private var outboundConsentVersion = 0
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var appState = VelaAppState.shared
    @State private var runRecords: [AgentRunRecord] = []
    @State private var selectedRun: AgentRunRecord?

    var body: some View {
        ZStack {
            VelaTheme.rhythmCanvas.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    trustOverviewCard

                    Text(AppLanguage.stored.isChinese ? "Agent 活动" : "Agent Activity")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)

                    if runRecords.isEmpty {
                        emptyAuditCard
                    } else {
                        auditSummaryCard

                        ForEach(runRecords.prefix(100)) { run in
                            runCard(run)
                        }
                    }
                }
                .padding(VelaTheme.pagePadding)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(AppLanguage.stored.isChinese ? "信任中心" : "Trust Center")
        .velaRhythmDetailChrome()
        .task { loadRuns() }
        .onChange(of: appState.localDataRevision) { _, _ in
            loadRuns()
        }
        .sheet(item: $selectedRun) { run in
            runDetailSheet(run)
        }
    }

    private func loadRuns() {
        runRecords = (try? AgentRunRepository(modelContext: modelContext).fetchAllSortedByStartedAt()) ?? []
    }

    // MARK: - Ownership overview

    private var trustOverviewCard: some View {
        VelaHeroSurface(tint: VelaTheme.recoveryColor) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "hand.raised.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(VelaTheme.recoveryColor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(VelaTheme.recoveryColor.opacity(0.12)))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLanguage.stored.isChinese ? "你的数据，你的决定" : "Your data. Your decision.")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(VelaTheme.fg)
                        Text(AppLanguage.stored.isChinese
                             ? "查看身体数据、联网 Agent、计划与记忆如何被使用。"
                             : "See how body data, network AI, plans, and memory are used.")
                            .font(.footnote)
                            .foregroundStyle(VelaTheme.fg2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 0) {
                    trustControlLink(
                        icon: "heart.text.square.fill",
                        title: AppLanguage.stored.isChinese ? "身体数据" : "Body Data",
                        detail: AppLanguage.stored.isChinese ? "Apple 健康只读；分数在本机计算" : "Read-only Apple Health; scores compute on device",
                        status: AppLanguage.stored.isChinese ? "本机" : "On Device",
                        tint: VelaTheme.recoveryColor,
                        destination: DataSourceSettingsView(
                            dashboard: dashboard,
                            onRefresh: onRefresh
                        )
                    )
                    Divider().padding(.leading, 54)
                    trustControlLink(
                        icon: "network",
                        title: AppLanguage.stored.isChinese ? "联网 Agent" : "Network Agent",
                        detail: AppLanguage.stored.isChinese ? "逐类选择允许发送的上下文" : "Choose each context category that may be sent",
                        status: outboundConsentStatus,
                        tint: VelaTheme.sleepColor,
                        destination: AIModelSettingsView()
                    )
                    Divider().padding(.leading, 54)
                    trustControlLink(
                        icon: "calendar.badge.checkmark",
                        title: AppLanguage.stored.isChinese ? "计划与长期记忆" : "Plans and Long-term Memory",
                        detail: AppLanguage.stored.isChinese ? "Agent 写入前先由你确认" : "You confirm before the Agent writes",
                        status: AppLanguage.stored.isChinese ? "需确认" : "Confirm First",
                        tint: VelaTheme.energyColor,
                        destination: UserWikiArchiveView()
                    )
                    Divider().padding(.leading, 54)
                    trustControlLink(
                        icon: "square.and.arrow.up",
                        title: AppLanguage.stored.isChinese ? "导出与删除" : "Export and Delete",
                        detail: AppLanguage.stored.isChinese ? "管理保存在 Vela 的本地资料" : "Manage local data stored by Vela",
                        status: AppLanguage.stored.isChinese ? "可管理" : "Available",
                        tint: VelaTheme.strainColor,
                        destination: PrivacyDataControlsView()
                    )
                }
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(VelaTheme.rhythmMist.opacity(0.78), lineWidth: 0.75)
                }
            }
        }
    }

    private var outboundConsentStatus: String {
        let enabled = outboundConsentVersion >= CoachOutboundDataPolicy.currentConsentVersion
        if AppLanguage.stored.isChinese {
            return enabled ? "已授权" : "未授权"
        }
        return enabled ? "Allowed" : "Not Allowed"
    }

    private func trustControlLink<Destination: View>(
        icon: String,
        title: String,
        detail: String,
        status: String,
        tint: Color,
        destination: Destination
    ) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 6)

                Text(status)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(tint)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(tint.opacity(0.1), in: Capsule())

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var emptyAuditCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(VelaTheme.accent)
                .frame(width: 42, height: 42)
                .background(Circle().fill(VelaTheme.accent.opacity(0.11)))
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLanguage.stored.isChinese ? "还没有运行记录" : "No runs yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(AppLanguage.stored.isChinese
                     ? "Agent 首次工作后，可在这里查看时间、结果与工具调用。"
                     : "After the Agent first runs, review its timing, result, and tool calls here.")
                    .font(.caption)
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VelaTheme.rhythmMist.opacity(0.78), lineWidth: 0.75)
        }
    }

    // MARK: - Run Card

    private var auditSummaryCard: some View {
        let shown = min(runRecords.count, 100)
        let failed = runRecords.filter { $0.status == "failed" }.count
        let running = runRecords.filter { $0.status == "running" }.count

        return VelaHeroSurface(tint: failed > 0 ? VelaTheme.strainColor : VelaTheme.accent) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(failed > 0 ? VelaTheme.strainColor : VelaTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill((failed > 0 ? VelaTheme.strainColor : VelaTheme.accent).opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(AppLanguage.stored.isChinese ? "Agent 审计日志" : "Agent Audit Log")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(VelaTheme.fg)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    VelaMetricPill(title: AppLanguage.stored.isChinese ? "显示" : "Shown", value: "\(shown)", systemImage: "list.bullet", tint: VelaTheme.accent)
                    VelaMetricPill(title: AppLanguage.stored.isChinese ? "失败" : "Failed", value: "\(failed)", systemImage: "exclamationmark.triangle.fill", tint: failed > 0 ? VelaTheme.strainColor : VelaTheme.recoveryColor)
                    VelaMetricPill(title: AppLanguage.stored.isChinese ? "运行中" : "Running", value: "\(running)", systemImage: "clock.fill", tint: VelaTheme.energyColor)
                }
            }
        }
    }

    private func runCard(_ run: AgentRunRecord) -> some View {
        Button {
            selectedRun = run
        } label: {
            VelaGlassCard(padding: 14, cornerRadius: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: iconFor(run.agentName))
                        .font(.title3)
                        .foregroundStyle(colorFor(run.status))
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(colorFor(run.status).opacity(0.12)))

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top) {
                            Text(labelFor(run.agentName))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(VelaTheme.fg)
                            Spacer()
                            statusBadge(run.status)
                        }

                        Text(run.startedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(VelaTheme.fg2)

                        if let summary = localizedRunSummary(run.outputSummary) {
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(VelaTheme.fg2)
                                .lineLimit(2)
                        } else if let reason = run.reason, !reason.isEmpty {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(VelaTheme.fg2)
                                .lineLimit(2)
                        }

                        HStack(spacing: 8) {
                            if let endedAt = run.endedAt {
                                VelaStatusBadge(label: durationText(start: run.startedAt, end: endedAt), systemImage: "timer", tint: VelaTheme.sleepColor)
                            }
                            if !run.inputContextHash.isEmpty {
                                VelaStatusBadge(label: String(run.inputContextHash.prefix(8)), systemImage: "number", tint: VelaTheme.fg2)
                            }
                            if hasToolCalls(run) {
                                VelaStatusBadge(label: AppLanguage.stored.isChinese ? "工具" : "Tools", systemImage: "wrench.and.screwdriver.fill", tint: VelaTheme.energyColor)
                            }
                        }
                    }
                }
            }
            .appleIntelligenceGlow(isHighlighted: run.status == "running", radius: 14)
        }
        .buttonStyle(.cardPress)
    }

    // MARK: - Detail Sheet

    private func runDetailSheet(_ run: AgentRunRecord) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VelaHeroSurface(tint: colorFor(run.status)) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label(labelFor(run.agentName), systemImage: iconFor(run.agentName))
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(VelaTheme.fg)
                                Spacer()
                                statusBadge(run.status)
                            }
                            if let reason = run.reason, !reason.isEmpty {
                                Text(reason)
                                    .font(.subheadline)
                                    .foregroundStyle(VelaTheme.fg2)
                            }
                            HStack(spacing: 8) {
                                VelaMetricPill(title: AppLanguage.stored.isChinese ? "开始" : "Started", value: run.startedAt.formatted(date: .omitted, time: .shortened), systemImage: "play.fill", tint: VelaTheme.accent)
                                if let endedAt = run.endedAt {
                                    VelaMetricPill(title: AppLanguage.stored.isChinese ? "耗时" : "Duration", value: durationText(start: run.startedAt, end: endedAt), systemImage: "timer", tint: VelaTheme.sleepColor)
                                }
                            }
                        }
                    }

                    VelaGlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(AppLanguage.stored.isChinese ? "运行上下文" : "Run Context")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(VelaTheme.fg)
                            detailRow(title: AppLanguage.stored.isChinese ? "创建/开始" : "Created / Started", value: run.startedAt.formatted())
                            if let endedAt = run.endedAt {
                                detailRow(title: AppLanguage.stored.isChinese ? "结束时间" : "Ended", value: endedAt.formatted())
                            }
                            if !run.inputContextHash.isEmpty {
                                detailRow(title: AppLanguage.stored.isChinese ? "输入上下文哈希" : "Input Context Hash", value: run.inputContextHash)
                            }
                        }
                    }

                    if let summary = localizedRunSummary(run.outputSummary) {
                        VelaGlassCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(AppLanguage.stored.isChinese ? "输出摘要" : "Output Summary")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(VelaTheme.fg)
                                Text(summary)
                                    .font(.subheadline)
                                    .foregroundStyle(VelaTheme.fg2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    VelaGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLanguage.stored.isChinese ? "工具调用" : "Tool Calls")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(VelaTheme.fg)
                            Text(toolCallsSummary(run))
                                .font(.caption.monospaced())
                                .foregroundStyle(VelaTheme.fg2)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VelaGlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(AppLanguage.stored.isChinese ? "响应与记忆扫描" : "Response and Memory Scan")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(VelaTheme.fg)
                            VelaInlineAlert(
                                title: AppLanguage.stored.isChinese ? "透明记录" : "Transparent record",
                                message: AppLanguage.stored.isChinese
                                ? "personal_response_scan、记忆提案和训练调整如果被 Agent 写入，会保留在输出摘要或工具调用记录中。"
                                : "personal_response_scan entries, memory proposals, and training adaptations are preserved here when logged through output summary or tool calls.",
                                systemImage: "doc.text.magnifyingglass",
                                tint: VelaTheme.accent
                            )
                        }
                    }

                    if let error = run.errorMessage, !error.isEmpty {
                        VelaInlineAlert(
                            title: AppLanguage.stored.isChinese ? "错误" : "Error",
                            message: error,
                            systemImage: "exclamationmark.triangle.fill",
                            tint: VelaTheme.strainColor
                        )
                    }
                }
                .padding()
            }
            .background(VelaBackground())
            .navigationTitle(AppLanguage.stored.isChinese ? "运行详情" : "Run Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppLanguage.stored.isChinese ? "完成" : "Done") { selectedRun = nil }
                }
            }
        }
    }

    // MARK: - Helpers

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(VelaTheme.muted)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(VelaTheme.fg)
        }
    }

    private func labelFor(_ agentName: String) -> String {
        switch agentName {
        case "morning_brief": return AppLanguage.stored.isChinese ? "早间简报" : "Morning Brief"
        case "evening_wiki_sync": return AppLanguage.stored.isChinese ? "晚间同步" : "Evening Sync"
        case "coach": return "Coach"
        case "health_pipeline": return AppLanguage.stored.isChinese ? "健康数据管道" : "Health Data Pipeline"
        default: return agentName
        }
    }

    private func iconFor(_ agentName: String) -> String {
        switch agentName {
        case "morning_brief": return "sunrise.fill"
        case "evening_wiki_sync": return "moon.stars.fill"
        case "coach": return "bubble.left.and.bubble.right.fill"
        case "health_pipeline": return "heart.text.square.fill"
        default: return "gear"
        }
    }

    private func colorFor(_ status: String) -> Color {
        switch status {
        case "success": return VelaTheme.energyColor
        case "failed": return VelaTheme.strainColor
        case "running": return VelaTheme.accent
        case "skipped": return VelaTheme.muted
        default: return VelaTheme.fg2
        }
    }

    private func statusBadge(_ status: String) -> some View {
        let label: String
        switch status {
        case "success": label = AppLanguage.stored.isChinese ? "成功" : "Success"
        case "failed": label = AppLanguage.stored.isChinese ? "失败" : "Failed"
        case "running": label = AppLanguage.stored.isChinese ? "运行中" : "Running"
        case "skipped": label = AppLanguage.stored.isChinese ? "已跳过" : "Skipped"
        default: label = status
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(colorFor(status))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(colorFor(status).opacity(0.12)))
    }

    private func hasToolCalls(_ run: AgentRunRecord) -> Bool {
        let trimmed = run.toolCallsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "[]"
    }

    private func toolCallsSummary(_ run: AgentRunRecord) -> String {
        let trimmed = run.toolCallsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "[]" {
            return AppLanguage.stored.isChinese ? "没有记录工具调用。" : "No tool calls recorded."
        }
        return trimmed
    }

    private func localizedRunSummary(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard AppLanguage.stored.isChinese else { return trimmed }

        if trimmed.hasPrefix("Synced and computed metrics for past") {
            let numbers = trimmed
                .split(whereSeparator: { !$0.isNumber })
                .compactMap { Int($0) }
            if numbers.count >= 2 {
                let retry = numbers[1] > 0 ? "；\(numbers[1]) 天读取失败，等待重试" : ""
                return "已同步并计算最近 \(numbers[0]) 天的身体指标\(retry)。"
            }
            return "健康数据同步与身体指标计算已完成。"
        }

        if trimmed.contains("query failures"), trimmed.contains("Marked dirty for retry") {
            return "部分健康信号读取失败，已加入自动重试。"
        }

        return trimmed
    }

    private func durationText(start: Date, end: Date) -> String {
        let seconds = Int(end.timeIntervalSince(start))
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return "\(hours)h \(remainingMinutes)m"
    }
}
