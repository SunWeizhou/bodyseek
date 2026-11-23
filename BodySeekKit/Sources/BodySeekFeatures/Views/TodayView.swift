import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 今日页：按设计系统 §3 / §5 分层。
/// L0 五项分数环；L1 今日简报；L2 行动、昨夜睡眠、关键体征、训练与营养摘要。
public struct TodayView: View {
    @Bindable var store: StoreOf<TodayFeature>
    private let zoomNamespace: Namespace.ID?

    public init(store: StoreOf<TodayFeature>, zoomNamespace: Namespace.ID? = nil) {
        self.store = store
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        BSPage("今日") {
            heroSection
        } note: {
            noteSection
        } sections: {
            sectionsContent
        } links: {
            EmptyView()
        }
        .refreshable {
            store.send(.refreshTapped)
        }
        .toolbar {
            toolbarContent
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .bodyseekTrailing) {
            Menu {
                Button {
                    store.send(.refreshTapped)
                } label: {
                    Label("刷新健康数据", systemImage: "arrow.clockwise")
                }
                Button {
                    store.send(.openCheckInTapped)
                } label: {
                    Label("记录今日状态", systemImage: "square.and.pencil")
                }
                Button {
                    store.send(.openNutritionTapped)
                } label: {
                    Label("记录饮食与营养", systemImage: "fork.knife")
                }
                Button {
                    store.send(.askCoachTapped("请解读我今天的身体恢复与睡眠状态"))
                } label: {
                    Label("询问 Coach", systemImage: "sparkles")
                }
                if !store.snapshot.isAuthorized {
                    Button {
                        store.send(.authorizationTapped)
                    } label: {
                        Label("授权 Apple 健康", systemImage: "heart.text.square")
                    }
                }
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("记录")
            .accessibilityIdentifier("bodyseek-menu")

            Button {
                store.send(.openSettingsTapped)
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .accessibilityLabel("设置")
            .accessibilityIdentifier("settings-button")
        }
    }

    // MARK: - L0 五项分数

    private var heroSection: some View {
        VStack(spacing: BSSpace.s) {
            stateBanner
            Text(headerLine)
                .bsText(.caption)
            scoreGroup
        }
    }

    private var scoreGroup: some View {
        BSScoreRing.group(scoreItems, zoom: zoomSource) { kind in
            store.send(.metricTapped(kind))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-score-instrument")
    }

    private var zoomSource: BSZoomSource? {
        guard let zoomNamespace else { return nil }
        return BSZoomSource(namespace: zoomNamespace, prefix: "today-metric-")
    }

    private var scoreItems: [BSScoreItem] {
        let today = store.today
        return [
            scoreItem(today.recovery, identifier: "today-score-recovery"),
            scoreItem(today.sleep, identifier: "today-score-sleep"),
            scoreItem(today.strain, identifier: "today-score-strain"),
            scoreItem(today.stress, identifier: "today-card-stress"),
            scoreItem(today.energy, identifier: "today-card-energy"),
        ]
    }

    private func scoreItem(_ score: MetricScore, identifier: String) -> BSScoreItem {
        BSScoreItem(
            kind: score.kind,
            value: score.value,
            availability: score.availability,
            statusText: score.badge,
            identifier: identifier
        )
    }

    private var headerLine: String {
        let base = "\(formattedEditorialDate(store.today.date)) · \(store.snapshot.sourceLabel)"
        return store.isLoading ? base + " · 正在更新" : base
    }

    /// 页面级提示只在 L0 上方出现，最多一条。
    @ViewBuilder
    private var stateBanner: some View {
        if let error = store.lastError {
            BSStateView(.error, message: error)
        } else if !store.snapshot.isAuthorized {
            BSStateView(
                .unauthorized,
                message: "连接后可查看睡眠、恢复和训练数据。",
                actionTitle: "立即授权",
                action: { store.send(.authorizationTapped) },
                actionIdentifier: "today-authorize-button"
            )
        }
    }

    // MARK: - L1 今日简报

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: BSSpace.xs) {
            BSCoachNote(
                noteText,
                engine: noteEngine,
                evidence: noteEvidence,
                onAsk: askCoachAction,
                askIdentifier: "today-ask-coach-button"
            )
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-quick-verdict")
            if store.dailyBrief != nil {
                BriefFeedbackBar(selected: store.briefFeedback) { rating in
                    store.send(.briefFeedbackTapped(rating))
                }
            }
        }
    }

    private var askCoachAction: () -> Void {
        { store.send(.askCoachTapped("结合我今天的恢复、睡眠、训练负荷和近期饮食，给一个具体安排")) }
    }

    private var noteText: String {
        if let brief = store.dailyBrief { return brief.headline }
        if !store.snapshot.isAuthorized { return "授权 Apple 健康后即可生成今日结论。" }
        if let advice = store.postWorkoutAdvice { return advice }
        let summary = store.today.factualSummary
        return summary.isEmpty ? "同步 HRV、静息心率与睡眠样本后将给出今日结论。" : summary
    }

    private var noteEngine: BSBriefEngine {
        switch store.dailyBrief?.engine {
        case .cloud: .cloud
        case .onDevice: .onDevice
        case .localTemplate, .none: .localTemplate
        }
    }

    private var noteEvidence: [String] {
        guard let brief = store.dailyBrief else { return [] }
        return brief.evidence.prefix(3).map(\.summary)
    }

    // MARK: - L2 展开

    @ViewBuilder
    private var sectionsContent: some View {
        actionSection
        if store.snapshot.isAuthorized {
            sleepSection
            vitalsSection
        }
        summarySection
    }

    // ① 今天要不要行动

    private var actionSection: some View {
        BSSection("今天要不要行动") {
            VStack(spacing: BSSpace.s) {
                actionRows
                checkInRow
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-action-card")
        }
    }

    @ViewBuilder
    private var actionRows: some View {
        if let advice = store.postWorkoutAdvice {
            postWorkoutCard(advice)
        } else if !visiblePlanItems.isEmpty {
            ForEach(visiblePlanItems) { record in
                planRow(record)
            }
        } else {
            ForEach(briefActions) { action in
                briefActionRow(action)
            }
        }
    }

    private var visiblePlanItems: [PlanItemRecord] {
        let items = store.planItems.filter { $0.state != .dismissed }
        let focus = items.filter { $0.kind == .trainingFocus }
        let rest = items.filter { $0.kind != .trainingFocus }
        return Array((focus + rest).prefix(3))
    }

    private var briefActions: [BriefAction] {
        Array((store.dailyBrief?.actions ?? []).prefix(3))
    }

    private func postWorkoutCard(_ advice: String) -> some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.xxs) {
                Label("今天已完成训练", systemImage: "checkmark.circle")
                    .bsText(.cardTitle)
                Text(advice)
                    .bsText(.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func planRow(_ record: PlanItemRecord) -> some View {
        let item = record.decodedActionItem()
        let identifier = record.id.uuidString
        return BSActionRow(
            title: item?.title ?? "行动建议",
            basis: [item?.detail, item?.metricBasis].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n"),
            status: record.state == .suggested ? .idle : .done,
            actionTitle: "采纳",
            onExecute: { store.send(.adoptPlanItem(record.id)) },
            dismissTitle: "跳过",
            onDismiss: { store.send(.dismissPlanItem(record.id)) },
            executeIdentifier: "today-action-adopt-\(identifier)",
            statusIdentifier: "today-action-status-\(identifier)",
            dismissIdentifier: "today-action-dismiss-\(identifier)"
        )
    }

    private func briefActionRow(_ action: BriefAction) -> some View {
        BSActionRow(
            title: action.title,
            basis: action.basis,
            actionTitle: "问 Coach",
            onExecute: { store.send(.askCoachTapped(action.coachPrompt)) }
        )
    }

    private var checkInRow: some View {
        let recorded = store.todayCheckIn != nil
        return BSActionRow(
            title: recorded ? "今日体感已记录" : "记录今日体感",
            basis: checkInBasis,
            actionTitle: recorded ? "修改" : "打卡",
            onExecute: { store.send(.openCheckInTapped) },
            executeIdentifier: "today-checkin-card"
        )
    }

    private var checkInBasis: String {
        guard let checkIn = store.todayCheckIn else {
            return "10 秒量化主观精力、情绪、压力与酸痛，持续校准个人身体模型"
        }
        let soreness = checkIn.soreness.isEmpty ? "" : " · 酸痛 \(checkIn.soreness.count) 处"
        return "精力 \(checkIn.energy)/5 · 情绪 \(checkIn.mood)/5 · 压力 \(checkIn.stress)/5\(soreness)"
    }

    // ② 昨夜睡眠

    private var sleepSection: some View {
        BSSection("昨夜睡眠") {
            Button {
                store.send(.metricTapped(.sleep))
            } label: {
                sleepChartCard
            }
            .buttonStyle(.bsPressable)
            .accessibilityIdentifier("today-sleep-card")
        }
    }

    private var sleepChartCard: some View {
        BSChartCard(
            title: "睡眠分期",
            label: "实际睡眠",
            value: sleepDurationText,
            range: formattedEditorialDate(store.today.date),
            side: store.today.sleep.subtitle,
            availability: sleepAvailability,
            height: .standard,
            caption: "Apple 健康 · 睡眠分期"
        ) {
            SleepStageChart(segments: store.today.raw.sleepSegments, height: BSSize.chartStandard, interactive: false)
        }
    }

    private var sleepAvailability: MetricAvailability {
        if store.today.raw.sleepAsleepMinutes != nil { return .available }
        return .missing(reason: store.today.sleep.availability.reasonText ?? "昨晚暂无睡眠分段数据")
    }

    private var sleepDurationText: String? {
        guard let minutes = store.today.raw.sleepAsleepMinutes else { return nil }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours) 小时 \(remainder) 分" : "\(remainder) 分钟"
    }

    // ③ 关键体征

    private var vitalsSection: some View {
        BSSection("关键体征") {
            BSMetricGrid {
                vitalTile(
                    title: "HRV",
                    value: store.today.raw.hrvMs,
                    unit: "ms",
                    digits: 0,
                    points: store.recentHRVSeries,
                    tint: BSColor.recovery
                )
                vitalTile(
                    title: "静息心率",
                    value: store.today.raw.restingHeartRateBpm,
                    unit: "bpm",
                    digits: 0,
                    points: store.recentRHRSeries,
                    tint: BSColor.recovery
                )
                vitalTile(
                    title: "呼吸率",
                    value: store.today.raw.respiratoryRateBrpm,
                    unit: "次/分",
                    digits: 1,
                    points: store.recentRespiratorySeries,
                    tint: BSColor.sleep
                )
                vitalTile(
                    title: "血氧饱和度",
                    value: store.today.raw.oxygenSaturationPct,
                    unit: "%",
                    digits: 0,
                    points: store.recentSpO2Series,
                    tint: BSColor.sleep
                )
            }
        }
    }

    private func vitalTile(
        title: String,
        value: Double?,
        unit: String,
        digits: Int,
        points: [VitalSparkPoint],
        tint: Color
    ) -> some View {
        let series = points.compactMap(\.value)
        let average = series.isEmpty ? nil : series.reduce(0, +) / Double(series.count)
        let delta: Double? = if let value, let average { value - average } else { nil }
        let valueText = value.map { $0.formatted(.number.precision(.fractionLength(digits))) }
        return BSMetricTile(
            title: title,
            value: valueText,
            unit: unit,
            availability: value == nil ? .missing(reason: "暂无数据") : .available,
            delta: delta,
            comparison: "vs 14 天",
            trend: series,
            tint: tint
        )
    }

    // ④ 今日训练与营养

    private var summarySection: some View {
        BSSection("今日训练与营养") {
            VStack(spacing: BSSpace.s) {
                if store.snapshot.isAuthorized, !store.today.raw.workouts.isEmpty {
                    summaryRow(
                        title: "今日训练",
                        value: workoutSummaryText,
                        systemImage: "figure.run",
                        identifier: "today-workouts-card"
                    ) {
                        store.send(.openWorkoutTapped)
                    }
                }
                summaryRow(
                    title: "今日营养",
                    value: nutritionSummaryText,
                    systemImage: "fork.knife",
                    identifier: "today-nutrition-card"
                ) {
                    store.send(.openNutritionTapped)
                }
            }
        }
    }

    private var workoutSummaryText: String {
        let workouts = store.today.raw.workouts
        let minutes = workouts.reduce(0) { $0 + $1.durationMinutes }
        return "\(workouts.count) 次 · \(minutes) 分钟"
    }

    private var nutritionSummaryText: String {
        let log = store.todayNutritionLog
        let kcal = log?.dietKcal.map { "\(Int($0.rounded())) kcal" } ?? "-- kcal"
        let status: String
        if log?.dietDayComplete == true {
            status = "已结账"
        } else if log == nil {
            status = "未记录"
        } else {
            status = "记录中"
        }
        return "\(kcal) · \(status)"
    }

    private func summaryRow(
        title: String,
        value: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            BSCard {
                HStack(spacing: BSSpace.s) {
                    Label(title, systemImage: systemImage)
                        .bsText(.cardTitle)
                    Spacer(minLength: BSSpace.xs)
                    Text(value)
                        .bsText(.label)
                    Image(systemName: "chevron.right")
                        .bsText(.caption)
                }
            }
        }
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - 日期

    private static let editorialDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter
    }()

    private func formattedEditorialDate(_ date: Date) -> String {
        Self.editorialDateFormatter.string(from: date)
    }
}
