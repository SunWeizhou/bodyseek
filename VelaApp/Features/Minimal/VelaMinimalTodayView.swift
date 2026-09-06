import SwiftUI

// MARK: - VelaTodayView — evidence-first daily decision surface

struct VelaTodayView: View {
    enum TodaySheet: Identifiable {
        case calendar
        case metric(VelaMetricDetailView.MetricType)
        case evidence
        case feedback
        case livedState

        var id: String {
            switch self {
            case .calendar: return "calendar"
            case .metric(let metric): return "metric-\(metric.id)"
            case .evidence: return "evidence"
            case .feedback: return "feedback"
            case .livedState: return "lived-state"
            }
        }
    }

    @Environment(\.velaSurfaceIsActive) private var isActiveSurface
    @Binding var showCoach: Bool
    @Binding var showSettings: Bool
    @Environment(\.colorScheme) var cs
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.todayLegacyRuntime) var todayLegacyRuntime

    /// The reader and store are both supplied by the shell composition root.
    /// The surface observes their state but never constructs its own load
    /// coordinator, so SwiftUI reevaluation cannot fork TodayStore identity.
    private let legacyTodayReader: LegacyTodayReadingModule
    @ObservedObject var todayStore: TodayStore

    init(
        showCoach: Binding<Bool>,
        showSettings: Binding<Bool>,
        todayStore: TodayStore,
        todayReader: LegacyTodayReadingModule
    ) {
        self._showCoach = showCoach
        self._showSettings = showSettings
        self.legacyTodayReader = todayReader
        self._todayStore = ObservedObject(wrappedValue: todayStore)
    }
    
    /// Today renders the value snapshot published by the Store.  The shared
    /// DashboardViewModel is retained only as a composition/compatibility
    /// bridge for legacy navigation and date selection below.
    var dashboard: DashboardSummary { todayStore.state.dashboard }
    private var hrvValue: Double { dashboard.recoveryMetrics.hrvMilliseconds ?? 0 }
    private var rhrValue: Double { dashboard.recoveryMetrics.restingHeartRate ?? 0 }

    var bodyState: BodyState { todayStore.state.bodyState }
    /// Canonical Today plan read model. SwiftData records remain available
    /// only to the compatibility sheet/adapters, never as dashboard source.
    var activePlanProjection: TodayPlanProjection? { todayStore.state.activePlan }

    /// Baseline deviation changes emphasis, never score order or display
    /// grammar. The user can therefore build a stable visual memory over time.
    private var deviatedScoreIDs: Set<String> {
        Set(dashboard.personalHealthBrief?.notableChanges.compactMap { finding in
            guard finding.isNotable else { return nil }
            switch finding.metric {
            case .recovery: return "recovery"
            case .sleepDuration: return "sleep"
            case .strain: return "strain"
            case .stress: return "stress"
            case .energy: return "energy"
            default: return nil
            }
        } ?? [])
    }

    /// The score remains the conclusion. This one short line is a bridge to
    /// Coach, with a deterministic local brief available when AI is offline.
    private var todayAgentSentence: String {
        switch todayExperience.baselineFormation.phase {
        case .waitingForEvidence:
            return "连接 Apple 健康后开始形成个人基线。"
        case .learning:
            return "继续正常佩戴，Vela 正在了解你的日常波动。"
        case .ready:
            break
        }
        let localBrief = dashboard.personalHealthBrief?.subheadline
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = if let localBrief, !localBrief.isEmpty {
            localBrief
        } else if !todayExperience.hero.summary.isEmpty {
            todayExperience.hero.summary
        } else {
            "五项状态已更新，点此继续问我。"
        }
        return compactAgentSentence(candidate)
    }

    private var todayScoreFreshness: DataFreshness { todayStore.state.freshness }

    private func calendarIsToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }

    private func compactAgentSentence(_ input: String) -> String {
        let flattened = input
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
        let sentence = flattened.split(
            whereSeparator: { "。！？!?".contains($0) }
        ).first.map(String.init) ?? flattened
        let limit = 48
        return sentence.count > limit ? String(sentence.prefix(limit)) + "…" : sentence
    }

    /// 深度专项批次 4（管线 A）：AI 今日解读卡——本机结论永远优先；
    /// 冲突时整卡降级为灰色参考并标注「以本机今日决定为准」（ADR 0008）。
    private func aiInsightCard(_ insight: DailyAIInsight) -> some View {
        let conflicted = insight.conflictsWithLocal
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(
                        conflicted
                            ? VelaTheme.rhythmInkSecondary
                            : VelaTheme.rhythmDeep
                    )
                Text("AI 增强 · 今日解读")
                    .font(.system(.caption, design: .default, weight: .bold))
                    .foregroundStyle(conflicted ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmDeep)
                Spacer()
            }

            Text(insight.interpretation)
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(conflicted ? VelaTheme.rhythmInkSecondary.opacity(0.8) : VelaTheme.rhythmInk)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if conflicted {
                Label("AI 与本机判断不一致，以本机今日决定为准", systemImage: "exclamationmark.triangle")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.stressColor)
            } else if !insight.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(insight.evidence.prefix(3), id: \.self) { line in
                        HStack(alignment: .top, spacing: 7) {
                            Circle()
                                .fill(VelaTheme.rhythmDeep.opacity(0.7))
                                .frame(width: 4, height: 4)
                                .padding(.top, 6)
                            Text(line)
                                .font(.system(.caption, design: .default))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                .fill(VelaTheme.rhythmCanvasRaised)
        )
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                .stroke(VelaTheme.rhythmDeep.opacity(0.35), lineWidth: 1.0)
        }
    }

    // Real scores mapped to 0...1 for BevelScoreRing
    var strainScore: Double { max(0, min(1.0, dashboard.strain.score / 100.0)) }
    var recoveryScore: Double { max(0, min(1.0, dashboard.recovery.score / 100.0)) }
    var sleepScore: Double { max(0, min(1.0, dashboard.sleepScore.score / 100.0)) }

    // Stress & Energy
    var stressLevel: Double { dashboard.stress.stressIndex }
    var energyScore: Double { dashboard.energy.currentEnergy }

    // MARK: - G1 重设计数据

    private var vitalCards: [TodayVitalCardModel] {
        let rm = dashboard.recoveryMetrics
        let hrv = rm.hrvMilliseconds
        let rhr = rm.restingHeartRate
        let spo2 = dashboard.extendedMetrics.oxygenSaturation
        let sleepMin = dashboard.sleepSummary.stageMinutes
            .filter { $0.key != .awake }
            .reduce(0) { $0 + $1.value }
        let updatedDate = todayStore.state.lastUpdated
        let trends = todayStore.state.vitalTrendSeries

        return [
            TodayVitalCardModel(
                kind: .hrv, label: "心率变异性",
                value: hrv.map { "\(Int($0.rounded()))" } ?? "--", unit: "ms",
                status: vitalStatusText(kind: .hrv, hasData: hrv != nil, observedAt: dashboard.recoveryMetrics.hrvObservedAt, syncedAt: updatedDate),
                assessment: vitalAssessment("hrv"), trend: trends["hrv"] ?? []
            ),
            TodayVitalCardModel(
                kind: .rhr, label: "静息心率",
                value: rhr.map { "\(Int($0.rounded()))" } ?? "--", unit: "bpm",
                status: vitalStatusText(kind: .rhr, hasData: rhr != nil, observedAt: dashboard.recoveryMetrics.rhrObservedAt, syncedAt: updatedDate),
                assessment: vitalAssessment("rhr"), trend: trends["rhr"] ?? []
            ),
            TodayVitalCardModel(
                kind: .spo2, label: "血氧",
                value: spo2.map { "\(Int($0.rounded()))" } ?? "--", unit: "%",
                status: vitalStatusText(kind: .spo2, hasData: spo2 != nil, observedAt: dashboard.extendedMetrics.oxygenSaturationObservedAt, syncedAt: updatedDate),
                assessment: vitalAssessment("spo2"), trend: trends["spo2"] ?? []
            ),
            TodayVitalCardModel(
                kind: .sleep, label: "睡眠",
                value: sleepMin > 0 ? "\(sleepMin / 60):\(String(format: "%02d", sleepMin % 60))" : "--", unit: "时",
                status: vitalStatusText(kind: .sleep, hasData: sleepMin > 0, observedAt: dashboard.sleepSummary.wakeTime, syncedAt: updatedDate),
                assessment: vitalAssessment("sleep"), trend: trends["sleep"] ?? []
            )
        ]
    }

    /// 体征卡评估：来自 canonical HealthTrendFinding（7d）的 assessment，
    /// 区分 favorable / neutral / unfavorable / unknown，避免未知或中性压成好。
    private func vitalAssessment(_ metricRaw: String) -> TodayVitalAssessment {
        let finding = dashboard.healthTrends.first {
            $0.metric.rawValue == metricRaw && $0.horizon == .sevenDays
        }
        guard let finding else { return .unknown }
        switch finding.assessment {
        case .favorable: return .favorable
        case .unfavorable: return .unfavorable
        case .neutral: return .neutral
        case .insufficientData: return .unknown
        }
    }

    private static let vitalTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private func vitalStatusText(
        kind: TodayVitalKind,
        hasData: Bool,
        observedAt: Date?,
        syncedAt: Date?
    ) -> String {
        guard hasData else { return "待同步" }

        switch kind {
        case .sleep:
            if let wake = observedAt {
                return "醒于 \(Self.vitalTimeFormatter.string(from: wake))"
            }
            return "昨夜睡眠"
        case .hrv, .rhr, .spo2:
            if let obs = observedAt, obs != .distantPast, obs != .distantFuture {
                let calendar = Calendar.current
                if calendar.isDateInToday(obs) {
                    return "\(Self.vitalTimeFormatter.string(from: obs)) 观测"
                } else if calendar.isDateInYesterday(obs) {
                    return "昨夜观测"
                }
            }
            if let syncedAt {
                return "观测时间未知 · " + syncRelativeText(syncedAt)
            }
            return "观测时间未知"
        }
    }

    private func syncRelativeText(_ lastUpdated: Date) -> String {
        let now = Date()
        let interval = now.timeIntervalSince(lastUpdated)

        if interval < 60 && interval >= 0 {
            return "刚刚同步"
        } else if interval < 3600 && interval >= 60 {
            let mins = Int(interval / 60)
            return "\(mins)分钟前同步"
        }

        let calendar = Calendar.current
        if calendar.isDateInToday(lastUpdated) {
            return "\(Self.vitalTimeFormatter.string(from: lastUpdated)) 同步"
        } else if calendar.isDateInYesterday(lastUpdated) {
            return "昨天 \(Self.vitalTimeFormatter.string(from: lastUpdated))"
        } else {
            return "已同步"
        }
    }

    private var acwrText: String {
        if let acwr = dashboard.energy.components["acwr"] {
            return String(format: "ACWR %.2f", acwr)
        }
        return "本周"
    }

    var coachMessage: String {
        dashboard.dailyInsight.isEmpty
            ? "正在等待足够的 Apple 健康数据，完成同步后会生成今日指导。"
            : dashboard.dailyInsight
    }

    var todayShareText: String {
        let recoveryText = dashboard.recovery.hasData ? "\(Int(dashboard.recovery.score.rounded()))" : "--"
        let sleepText = dashboard.sleepScore.hasData ? "\(Int(dashboard.sleepScore.score.rounded()))" : "--"
        let strainText = dashboard.strain.hasData ? "\(Int(dashboard.strain.score.rounded()))" : "--"
        return "\(dateHeaderString(for: todayStore.state.selectedDay))\n恢复 \(recoveryText) · 睡眠 \(sleepText) · 负荷 \(strainText)\n\(coachMessage)"
    }

    private func signalAccentColor(_ accent: DailyPlanAccent) -> Color {
        switch accent {
        case .recovery: return VelaTheme.recoveryColor
        case .sleep:    return VelaTheme.sleepColor
        case .strain:   return VelaTheme.strainColor
        case .stress:   return VelaTheme.stressColor
        case .energy:   return VelaTheme.energyColor
        }
    }

    @ViewBuilder
    private var notableChangeCard: some View {
        if let notable = dashboard.personalHealthBrief?.notableChanges.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text("最值得关注的变化")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Spacer()
                    Button {
                        dispatchToday(.openTrends)
                    } label: {
                        HStack(spacing: 2) {
                            Text("查看趋势")
                            Image(systemName: "chevron.right")
                        }
                        .font(.system(.caption2, design: .default, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }

                Text(notable.summary)
                    .font(.system(.footnote, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineSpacing(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            )
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private var velaInterpretationSection: some View {
        if let insight = todayAIInsight {
            aiInsightCard(insight)
        } else if let brief = dashboard.personalHealthBrief, !brief.subheadline.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text("Vela 解读")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Spacer()
                }

                Text(brief.subheadline)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineSpacing(3)

                if let insightLine = dashboard.bodyModelState?.insightLine() {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(VelaTheme.rhythmDeep.opacity(0.7))
                            .frame(width: 4, height: 4)
                        Text(insightLine)
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            )
        } else {
            personalResponseInsightView
        }
    }

    @ViewBuilder
    private var personalResponseInsightView: some View {
        if calendarIsToday(todayStore.state.selectedDay), let insightLine = dashboard.bodyModelState?.insightLine() {
            NavigationLink(destination: BodyModelDetailView()) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text(insightLine)
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(2)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.6))
                }
                .padding(12)
                .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                }
            }
            .buttonStyle(.cardPress)
        }
    }

    // Dynamic Weather Sync States
    /// Weather fetching is still a compatibility effect until the reader
    /// publishes a weather projection. Rendering prefers Store state and only
    /// falls back to this adapter's transient display values.
    private var weatherTemp: String {
        guard let temperature = todayStore.state.weather.temperature else {
            return "--"
        }
        return "\(Int(temperature.rounded()))°C"
    }

    private var weatherLocation: String {
        todayStore.state.weather.locationName ?? "天气数据待同步"
    }

    var weatherStatusText: String {
        todayStore.state.weather.status == .available ? weatherLocation : "天气暂不可用"
    }

    // A single route prevents mutually exclusive Today sheets from racing.
    @State var presentedTodaySheet: TodaySheet?
    @State var experienceFeedbackTick = 0
    /// SwiftData feedback records are retained only as a downstream adapter
    /// for the editing sheet. Dashboard copy and gating use the Store's value
    /// projection instead, so persistence models do not leak into rendering.
    @State var feedbackSheetAdapter: TodayFeedbackSheetAdapter?
    @State var selectedLivedStateAlignment: LivedStateAlignment?
    @State var livedStateSaveError: String?
    @State private var lastScenePhaseSyncTime: Date?
    // F2 修复：档案修改发生在非 Today 页面时记一笔，回到 Today 立即强制重算。
    @State private var pendingLocalDataRefresh = false

    var decisionDataCoverageSummary: DataCoverageSummaryModel { todayStore.state.coverage }

    @ViewBuilder
    var errorMessageView: some View {
        if let errorMessage = todayStore.state.errorMessage ?? todayStore.state.secondaryDataErrorMessage {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(VelaTheme.stressColor)
                    Text(errorMessage)
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .stroke(VelaTheme.stressColor.opacity(0.3), lineWidth: 1)
            )
        }
    }

    /// A surface-level projection for the short cache/load gap. It keeps the
    /// score grammar conservative (no invented values) while making the
    /// reason for the empty rings explicit to both people and UI tests.
    @ViewBuilder
    private var todayDataStateView: some View {
        let hasSignal = todayExperience.signalCards.contains { $0.value != "--" }
        if case .loading = todayStore.state.phase {
            VelaStateCard(
                state: .loading,
                title: "正在同步今日数据",
                message: "先展示保守状态；Apple 健康同步完成后，五项状态会自动更新。"
            )
            .accessibilityIdentifier("today-data-state")
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.bottom, 8)
        } else if !hasSignal {
            VelaStateCard(
                state: .empty,
                title: "今日数据待同步",
                message: "连接 Apple 健康并完成同步后，这里会显示恢复、睡眠、负荷、压力和能量。"
            )
            .accessibilityIdentifier("today-data-state")
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.bottom, 8)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if todayStore.state.errorMessage != nil || todayStore.state.secondaryDataErrorMessage != nil {
                    errorMessageView
                        .padding(.horizontal, VelaTheme.pagePadding)
                        .padding(.bottom, 8)
                }

                todayDataStateView

                // ─── Block 1: Fixed five-score dashboard + one Agent sentence ───
                TodaySignalGrid(
                    model: todayExperience,
                    freshness: todayScoreFreshness,
                    deviatedScoreIDs: deviatedScoreIDs,
                    agentSentence: todayAgentSentence,
                    accentColor: signalAccentColor,
                    onInspectGuidance: {
                        dispatchToday(.openEvidence)
                        presentedTodaySheet = .evidence
                    },
                    selectedDate: todayStore.state.selectedDay,
                    dashboardSnapshot: todayStore.state.dashboard
                )
                .equatable()
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.top, 4)

                if calendarIsToday(todayStore.state.selectedDay) {
                    livedStatePrompt
                        .padding(.horizontal, VelaTheme.pagePadding)
                        .padding(.top, 12)

                    TodayDailyPlanCard(
                        model: todayExperience,
                        payload: todayStore.state.operatingPlanPayload,
                        onAction: { performExperienceAction($0) },
                        onOpenPlan: { dispatchToday(.openPlan) }
                    )
                    .equatable()
                    .padding(.horizontal, VelaTheme.pagePadding)
                    .padding(.top, 12)

                    if let activePlan = todayStore.state.activePlan,
                       let pendingProposal = todayStore.state.pendingPlan {
                        TodayPlanAdaptationProjectionCard(
                            activePlan: activePlan,
                            pendingProposal: pendingProposal,
                            onOpenPlan: { dispatchToday(.openPlan) }
                        )
                        .padding(.horizontal, VelaTheme.pagePadding)
                        .padding(.top, 12)
                    }
                }

                // ─── Block 2: Today's Most Notable Change (if present) ───
                notableChangeCard

                // ─── Block 3: Key Vital Stats (HRV / RHR / SpO₂ / Sleep 2×2 Grid) ───
                VStack(alignment: .leading, spacing: 10) {
                    Text("关键体征")
                        .font(VelaTheme.headline())
                        .foregroundStyle(VelaTheme.rhythmInk)
                    TodayVitalsGrid(cards: vitalCards) { kind in
                        switch kind {
                        case .hrv:
                            dispatchToday(.openMetric(.recovery))
                            presentedTodaySheet = .metric(.hrv)
                        case .rhr:
                            dispatchToday(.openMetric(.recovery))
                            presentedTodaySheet = .metric(.rhr)
                        case .spo2:
                            dispatchToday(.openMetric(.recovery))
                            presentedTodaySheet = .metric(.bloodOxygen)
                        case .sleep:
                            dispatchToday(.openMetric(.sleep))
                            presentedTodaySheet = .metric(.sleep)
                        }
                    }
                    .equatable()
                }
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.top, 20)

                VStack(alignment: .leading, spacing: 24) {
                    // ─── Block 4: Downstream action sequence ───
                    if !todayExperience.actions.isEmpty {
                        VelaRhythmActionSequence(
                            actions: todayExperience.actions,
                            onAction: { performExperienceAction($0) },
                            onEvidence: {
                                dispatchToday(.openEvidence)
                                presentedTodaySheet = .evidence
                            }
                        )
                    }

                    // ─── Block 5: Feedback + data coverage ───
                    if todayStore.state.activePlan != nil {
                        TodayFeedbackProjectionCard(
                            projection: todayStore.state.feedback,
                            canOpenSheet: feedbackSheetAdapter != nil,
                            onTap: {
                                guard feedbackSheetAdapter != nil else { return }
                                presentedTodaySheet = .feedback
                            }
                        )
                    }

                    DataCoverageCompactCard(
                        model: decisionDataCoverageSummary,
                        showSettings: $showSettings
                    )
                }
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.top, 24)
                .padding(.bottom, VelaTheme.bottomContentClearance)
            }
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                TodayDateAndStatusHeader(
                    selectedDate: todayStore.state.selectedDay,
                    todayShareText: todayShareText,
                    weatherTemp: weatherTemp,
                    weatherStatusText: weatherStatusText,
                    showSimulationLabel: dashboard.source == .preview,
                    onOpenCalendar: {
                        dispatchToday(.openCalendar)
                        presentedTodaySheet = .calendar
                    },
                    showSettings: $showSettings,
                    requestWeatherUpdate: { requestWeatherUpdate() },
                    settingsSynced: todayStore.state.lastUpdated != nil
                )
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.bottom, 6)
                .background(VelaTheme.rhythmCanvas.opacity(0.94))
            }
        }
        .background(VelaTheme.rhythmCanvas)
        .task(id: isActiveSurface) {
            guard isActiveSurface else { return }
            todayLegacyRuntime.bind(reader: legacyTodayReader, dashboardVM: dashboardVM)
            todayLegacyRuntime.setSelectedDay(todayStore.state.selectedDay)
            todayLegacyRuntime.startLocationUpdates()
            if pendingLocalDataRefresh {
                pendingLocalDataRefresh = false
                await todayStore.send(.refresh(force: true))
            } else {
                await todayStore.send(.appear)
            }
            await loadDataCoverageSummary()
            loadTodayLivedStateAlignment()
            trackDailyDecisionViewed()
        }
        .refreshable {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            await todayStore.send(.refresh(force: true))
            await loadDataCoverageSummary()
        }
        .onChange(of: scenePhase) {
            // Returning to foreground (e.g. after being backgrounded overnight) re-syncs
            // HealthKit and recomputes scores when data is stale. Use force: false so
            // HealthCachePolicy (15-min TTL) prevents redundant 42-day historical sync loops.
            // Introduce a scenePhase freshness check (debounce window) to prevent rapid app toggling
            // from executing redundant refreshes.
            if scenePhase == .active, isActiveSurface {
                let now = Date()
                if let lastSync = lastScenePhaseSyncTime,
                   now.timeIntervalSince(lastSync) < 60 {
                    return
                }
                lastScenePhaseSyncTime = now
                Task {
                    await todayStore.send(.refresh(force: false))
                    await loadDataCoverageSummary()
                }
            }
        }
        .onChange(of: todayLegacyRuntime.localDataRevision) {
            // F2 修复：档案（年龄/体重/身高/maxHR/性别）修改后必须重算评分，
            // 此前只 hydrateFromCache，15 分钟内分数与建议停留在旧档案口径。
            if isActiveSurface {
                Task { await todayStore.send(.refresh(force: true)) }
            } else {
                pendingLocalDataRefresh = true
            }
            Task { @MainActor in
                await todayLegacyRuntime.refreshCompatibilitySurface()
            }
        }
        .onReceive(todayLegacyRuntime.locationUpdates) { _ in
            dispatchToday(.requestWeather)
        }
        .sheet(item: $presentedTodaySheet) { sheet in
            todaySheetContent(sheet)
        }
        .alert("暂时无法记录", isPresented: Binding(
            get: { livedStateSaveError != nil },
            set: { if !$0 { livedStateSaveError = nil } }
        )) {
            Button("好", role: .cancel) { livedStateSaveError = nil }
        } message: {
            Text(livedStateSaveError ?? "请稍后重试。")
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder
    private func todaySheetContent(_ sheet: TodaySheet) -> some View {
        switch sheet {
        case .calendar:
            CalendarOverviewSheetView(selectedDay: todayStore.state.selectedDay) { selectedDay in
                selectTodayDayFromCalendar(selectedDay)
            }
                .presentationDetents([.medium, .large])
                .velaSheetSurface()
        case .metric(let metric):
            TodayMetricDetailDownstreamAdapter(
                metric: metric,
                selectedDate: todayStore.state.selectedDay,
                dashboardSnapshot: todayStore.state.dashboard,
                dashboardVM: dashboardVM
            )
                .presentationDetents([.large])
                .velaSheetSurface()
        case .evidence:
            TodayEvidenceSheet(
                state: todayCommandState,
                dashboard: dashboard,
                onAskCoach: { question in
                    presentedTodaySheet = nil
                    dispatchToday(.askCoach(question))
                }
            )
            .presentationDetents([.medium, .large])
            .velaSheetSurface()
        case .feedback:
            if let feedbackSheetAdapter {
                DailyDecisionFeedbackSheet(record: feedbackSheetAdapter.record) { values in
                    saveDailyDecisionFeedback(values)
                }
                .presentationDetents([.large])
                .velaSheetSurface()
            }
        case .livedState:
            LivedStateCheckInSheet(
                selectedDate: todayStore.state.selectedDay,
                onSaved: { loadTodayLivedStateAlignment() },
                onSubmit: { dispatchToday(.saveLivedState($0)) }
            )
            .presentationDetents([.large])
            .velaSheetSurface()
        }
    }

    /// Calendar intent enters Today through the Store action boundary first.
    /// The DashboardViewModel mirror is updated only after the Store accepts
    /// the day, through a named compatibility adapter for legacy sheets.
    private func selectTodayDayFromCalendar(_ day: Date) {
        let requestedDay = Calendar.current.startOfDay(for: day)
        Task { @MainActor in
            await todayStore.send(.selectDay(requestedDay))
            let canonicalDay = todayStore.state.selectedDay
            guard Calendar.current.isDate(canonicalDay, inSameDayAs: requestedDay) else {
                return
            }
            todayLegacyRuntime.mirrorSelectedDayToLegacySurface(canonicalDay)
            loadTodayLivedStateAlignment()
            Task { @MainActor in
                await todayLegacyRuntime.refreshCompatibilitySurface()
            }
        }
    }

    func performExperienceAction(_ action: TodayExperienceAction) {
        experienceFeedbackTick += 1
        trackDailyDecisionAction(destination: action.destination)
        switch action.destination {
        case "training":
            dispatchToday(.startTraining)
        case "journal":
            dispatchToday(.openEvidence)
            presentedTodaySheet = .livedState
        case "coach":
            dispatchToday(.askCoach(action.detail))
        case "recovery", "sync", "evidence":
            dispatchToday(.openEvidence)
            presentedTodaySheet = .evidence
        default:
            dispatchToday(.openEvidence)
            presentedTodaySheet = .evidence
        }
    }

    private var livedStatePrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("和你的感受一致吗？")
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)

                Spacer()

                Button("补充细节") {
                    VelaHaptic.selection()
                    presentedTodaySheet = .livedState
                }
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
            }

            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                    spacing: 8
                ) {
                    ForEach(LivedStateAlignment.allCases, id: \.self) { alignment in
                        livedStateAlignmentButton(alignment)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(LivedStateAlignment.allCases, id: \.self) { alignment in
                        livedStateAlignmentButton(alignment)
                    }
                }
            }
        }
        .padding(14)
        .background(
            VelaTheme.rhythmCanvasRaised,
            in: RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        }
    }

    private func livedStateLabel(_ alignment: LivedStateAlignment) -> String {
        switch alignment {
        case .aligned: return "一致"
        case .worse: return "更差"
        case .better: return "更好"
        case .uncertain: return "不确定"
        }
    }

    private func livedStateAccessibilityLabel(_ alignment: LivedStateAlignment) -> String {
        switch alignment {
        case .aligned: return "与分数一致"
        case .worse: return "比分数更差"
        case .better: return "比分数更好"
        case .uncertain: return "暂时不确定"
        }
    }

    private func livedStateAlignmentButton(_ alignment: LivedStateAlignment) -> some View {
        let selected = (todayStore.state.livedState.alignment ?? selectedLivedStateAlignment) == alignment
        return Button {
            saveLivedStateAlignment(alignment)
        } label: {
            Text(livedStateLabel(alignment))
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(selected ? VelaTheme.rhythmDeepOn : VelaTheme.rhythmInk)
                .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget)
                .background(
                    selected ? VelaTheme.rhythmDeep : VelaTheme.rhythmMist.opacity(0.48),
                    in: Capsule(style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("身体感受\(livedStateAccessibilityLabel(alignment))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    func accentColor(_ accent: DailyPlanAccent) -> Color {
        switch accent {
        case .recovery: return VelaTheme.recoveryColor
        case .sleep: return VelaTheme.sleepColor
        case .strain: return VelaTheme.strainColor
        case .energy: return VelaTheme.energyColor
        case .stress: return VelaTheme.stressColor
        }
    }
}

/// Named boundary for the legacy metric detail surface. Today owns the
/// presentation intent, while this adapter supplies the DashboardViewModel
/// required by the downstream implementation without exposing a raw
/// environment injection in the root renderer.
private struct TodayMetricDetailDownstreamAdapter: View {
    let metric: VelaMetricDetailView.MetricType
    let selectedDate: Date?
    let dashboardSnapshot: DashboardSummary?
    let dashboardVM: DashboardViewModel

    var body: some View {
        NavigationStack {
            VelaMetricDetailView(
                metric: metric,
                selectedDate: selectedDate,
                dashboardSnapshot: dashboardSnapshot,
                isPresentedInSheet: true
            )
        }
        .environmentObject(dashboardVM)
    }
}

/// Root-facing feedback card rendered entirely from the Today value model.
/// The SwiftData record is intentionally not accepted here; it is only passed
/// to `DailyDecisionFeedbackSheet` after the user opens the downstream editor.
private struct TodayFeedbackProjectionCard: View {
    let projection: TodayFeedbackProjection
    let canOpenSheet: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: projection.isSubmitted ? "checkmark.circle.fill" : "scope")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(projection.isSubmitted ? VelaTheme.success : VelaTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(VelaTheme.secondaryGroupedBackground))

                VStack(alignment: .leading, spacing: 3) {
                    Text(projection.isSubmitted ? "今日反馈已记录" : "这个建议适合你吗？")
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.fg)
                    Text(projection.isSubmitted ? "可随时更新，Vela 会用它校准后续建议" : "记录实际行动与体感，约 20 秒")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(VelaTheme.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).fill(VelaTheme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).stroke(VelaTheme.borderSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .disabled(!canOpenSheet)
        .accessibilityLabel(projection.isSubmitted ? "更新今日建议反馈" : "记录今日建议反馈")
    }
}

// MARK: - TodayDateAndStatusHeader
struct TodayDateAndStatusHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedDate: Date
    let todayShareText: String
    let weatherTemp: String
    let weatherStatusText: String
    let showSimulationLabel: Bool

    let onOpenCalendar: () -> Void
    @Binding var showSettings: Bool
    var requestWeatherUpdate: () -> Void
    let settingsSynced: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .center, spacing: 8) {
                    dateButton
                    Spacer(minLength: 8)
                    headerActions
                }

                weatherBar
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: 8) {
                    dateButton
                    weatherBar
                    Spacer()
                    headerActions
                }
            }

            if showSimulationLabel {
                HStack {
                    Text(L10n.t("Simulated", "模拟数据"))
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Spacer()
                }
            }
        }
        // This is navigation chrome, not reading content. Keep it useful at the
        // largest accessibility settings without allowing the custom header to
        // consume most of the viewport; the scroll content below still receives
        // the user's full Dynamic Type size.
        .dynamicTypeSize(headerDynamicTypeSize)
    }

    private var headerDynamicTypeSize: DynamicTypeSize {
        dynamicTypeSize.isAccessibilitySize ? .accessibility1 : dynamicTypeSize
    }

    private var dateButton: some View {
        Button {
            onOpenCalendar()
        } label: {
            HStack(spacing: 5) {
                Text(dateHeaderString(for: selectedDate))
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .frame(minHeight: VelaTheme.minimumHitTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("选择日期")
        .accessibilityValue(dateHeaderString(for: selectedDate))
        .accessibilityIdentifier("today-calendar-button")
    }

    private var weatherBar: some View {
        TodayWeatherBar(
            weatherTemp: weatherTemp,
            weatherStatusText: weatherStatusText,
            requestWeatherUpdate: requestWeatherUpdate
        )
    }

    private var headerActions: some View {
        HStack(spacing: 2) {
            ShareLink(item: todayShareText) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .frame(width: VelaTheme.circularControlSize, height: VelaTheme.circularControlSize)
            }
            .buttonStyle(.cardPress)
            .accessibilityLabel("分享今日摘要")

            Button {
                showSettings = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(VelaTheme.rhythmMist)
                        .frame(width: 30, height: 30)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmDeep)
                        }
                    Circle()
                        .fill(VelaTheme.rhythmGlow)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(VelaTheme.rhythmCanvas, lineWidth: 2))
                }
                .frame(width: VelaTheme.circularControlSize, height: VelaTheme.circularControlSize)
            }
            .buttonStyle(.cardPress)
            .accessibilityLabel(settingsSynced ? "个人设置,数据已同步" : "个人设置,数据待同步")
        }
    }

    private static let headerDateFormatterZh: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let headerDateFormatterEn: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    private func dateHeaderString(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return L10n.t("Today", "今天")
        } else if calendar.isDateInYesterday(date) {
            return L10n.t("Yesterday", "昨天")
        } else {
            let formatter = AppLanguage.stored.isChinese ? Self.headerDateFormatterZh : Self.headerDateFormatterEn
            return formatter.string(from: date)
        }
    }
}

// MARK: - DataCoverageCompactCard
struct DataCoverageCompactCard: View {
    let model: DataCoverageSummaryModel
    @Binding var showSettings: Bool

    private var needsCalibrationGuidance: Bool {
        model.status == .low || model.status == .unknown
    }
    
    var body: some View {
        let accent = dataCoverageColor(model.status)
        return Button {
            showSettings = true
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Image(systemName: model.actionSystemImage)
                        .font(VelaTheme.caption1().weight(.semibold))
                        .foregroundStyle(accent)
                    Text(model.title)
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.fg)
                    Spacer()
                    Text(model.status == .unknown ? "--" : "\(model.scorePercent)%")
                        .font(VelaTheme.subheadline().weight(.bold).monospacedDigit())
                        .foregroundStyle(accent)
                    Image(systemName: "chevron.right")
                        .font(VelaTheme.caption2().weight(.semibold))
                        .foregroundStyle(VelaTheme.muted)
                }

                if needsCalibrationGuidance {
                    Text(model.subtitle)
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.fg2)
                        .lineLimit(1)
                }

                if !needsCalibrationGuidance {
                    coverageDomains
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                    .fill(VelaTheme.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge, style: .continuous)
                    .stroke(VelaTheme.borderSoft.opacity(0.65), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.t("Data coverage", "数据覆盖")) \(model.scorePercent)%。\(model.subtitle)")
        .accessibilityHint(model.actionTitle)
    }

    @ViewBuilder
    private var coverageDomains: some View {
        let domains = Array(model.domainSummaries.prefix(3))
        if !domains.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    ForEach(domains) { domain in
                        domainLabel(domain)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    ForEach(domains) { domain in
                        domainLabel(domain)
                    }
                }
            }
        }
    }

    private func domainLabel(_ domain: DataCoverageDomainSummary) -> some View {
        Label("\(domain.title) \(domain.usableCount)/\(domain.totalCount)", systemImage: domain.icon)
            .font(VelaTheme.caption2().weight(.medium))
            .foregroundStyle(dataCoveragePercentColor(domain.scorePercent))
            .lineLimit(1)
    }
    
    private func dataCoverageColor(_ status: DataCoverageSummaryModel.Status) -> Color {
        switch status {
        case .high: return VelaTheme.energyColor
        case .moderate: return VelaTheme.accent
        case .low: return VelaTheme.strainColor
        case .unknown: return VelaTheme.muted
        }
    }

    private func dataCoveragePercentColor(_ percent: Int) -> Color {
        if percent >= 80 { return VelaTheme.energyColor }
        if percent >= 50 { return VelaTheme.accent }
        return VelaTheme.strainColor
    }
}

/// Value-only rendering of a pending plan proposal. The executable
/// TrainingPlanRecord/TrainingPlanAdaptationRecord stay behind the Plan
/// compatibility surface; Today can therefore render the proposal without
/// importing SwiftData or reading DashboardViewModel records.
struct TodayPlanAdaptationProjectionCard: View {
    let activePlan: TodayPlanProjection
    let pendingProposal: TodayPendingPlanProjection
    let onOpenPlan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("训练计划调整建议")
                .font(VelaTheme.subheadline().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
            Text(pendingProposal.adjustment)
                .font(VelaTheme.body())
                .foregroundStyle(VelaTheme.rhythmInk)
            Text(pendingProposal.reason)
                .font(VelaTheme.caption1())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let alternative = pendingProposal.suggestedAlternative,
               !alternative.isEmpty {
                Text("建议替代：\(alternative)")
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            Text("当前计划：\(activePlan.title)")
                .font(VelaTheme.caption1().weight(.medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Button("在计划页确认") {
                onOpenPlan()
            }
            .font(VelaTheme.caption1().weight(.semibold))
            .foregroundStyle(VelaTheme.rhythmDeep)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        }
    }
}
