import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct TodayView: View {
    @Bindable var store: StoreOf<TodayFeature>
    private let zoomNamespace: Namespace.ID?

    public init(store: StoreOf<TodayFeature>, zoomNamespace: Namespace.ID? = nil) {
        self.store = store
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BevelTheme.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let error = store.lastError {
                        errorBanner(error)
                    }

                    if !store.snapshot.isAuthorized {
                        unauthorizedBanner
                    }

                    healthOverviewCard

                    stressAndEnergyRow

                    if store.snapshot.isAuthorized {
                        sleepCard
                    }

                    if store.snapshot.isAuthorized || store.postWorkoutAdvice != nil {
                        todayActionCard
                    }

                    if store.snapshot.isAuthorized {
                        vitalsGrid

                        if !store.today.raw.workouts.isEmpty {
                            workoutsCard
                        }
                    }

                    todayNutritionCard

                    checkInCard

                    if !store.proactiveInsights.isEmpty {
                        proactiveInsightsSection
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .refreshable {
                store.send(.refreshTapped)
            }
        }
        .navigationTitle("今日")
        .bodyseekNavigationBarInline()
        .bodyseekTransparentNavigationBar()
        .toolbar {
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
    }

    // MARK: - Subviews

    private func errorBanner(_ message: String) -> some View {
        BevelCard(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BevelTheme.dangerColor)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.ink)
            }
        }
    }

    private var unauthorizedBanner: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("连接 Apple 健康", systemImage: "heart.text.square")
                    .font(.headline)
                    .foregroundStyle(BevelTheme.ink)
                Text("连接后可查看睡眠、恢复和训练数据。")
                    .font(.subheadline)
                    .foregroundStyle(BevelTheme.inkSecondary)
                Button("立即授权") {
                    store.send(.authorizationTapped)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("today-authorize-button")
            }
        }
    }

    private var healthOverviewCard: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Text("身体状态")
                        .font(.headline)
                        .foregroundStyle(BevelTheme.ink)

                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("正在更新数据")
                    }

                    Spacer()

                    Text("\(formattedEditorialDate(store.today.date)) · \(store.snapshot.sourceLabel)")
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    scoreButton(for: store.today.recovery, context: recoveryReadout, identifier: "today-score-recovery")
                    scoreButton(for: store.today.sleep, context: sleepReadout, identifier: "today-score-sleep")
                    scoreButton(for: store.today.strain, context: strainReadout, identifier: "today-score-strain")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-score-instrument")
    }

    private typealias MetricReadout = (label: String, value: String?)

    private var recoveryReadout: MetricReadout {
        if let hrv = store.today.raw.hrvMs {
            return ("心率变异性", "\(Int(hrv.rounded())) ms")
        }
        if let heartRate = store.today.raw.restingHeartRateBpm {
            return ("静息心率", "\(Int(heartRate.rounded())) bpm")
        }
        return ("心率变异性", nil)
    }

    private var sleepReadout: MetricReadout {
        let duration = store.today.raw.sleepAsleepMinutes.map { minutes in
            let hours = minutes / 60
            let remainder = minutes % 60
            return hours > 0 ? "\(hours) 小时 \(remainder) 分" : "\(remainder) 分钟"
        }
        return ("昨夜实睡", duration)
    }

    private var strainReadout: MetricReadout {
        let raw = store.today.raw
        if !raw.workouts.isEmpty {
            return ("今日训练", "\(raw.workouts.count) 次")
        }
        if case .knownZero = store.today.strain.availability {
            return ("今日训练", "0 次")
        }
        return ("动态消耗", raw.activeEnergyKcal.map { "\(Int($0.rounded())) kcal" })
    }

    private var proactiveInsightsSection: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("值得留意")
                    .font(.headline)
                    .foregroundStyle(BevelTheme.ink)

                ForEach(store.proactiveInsights.prefix(2)) { insight in
                    Divider()
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(insight.body)
                                .font(.subheadline)
                                .foregroundStyle(BevelTheme.inkSecondary)

                            HStack {
                                Button(insight.ctaTitle) {
                                    store.send(.proactiveInsightActionTapped(insight))
                                }
                                .accessibilityIdentifier("today-insight-cta-\(insight.kind.rawValue)")

                                Spacer()

                                Button("忽略") {
                                    store.send(.dismissProactiveInsightTapped(insight.id))
                                }
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .accessibilityIdentifier("today-insight-dismiss-\(insight.kind.rawValue)")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.top, 8)
                    } label: {
                        Text(insight.title)
                            .font(.subheadline)
                            .foregroundStyle(BevelTheme.ink)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-proactive-insights")
    }

    @ViewBuilder
    private func scoreButton(for score: MetricScore, context: MetricReadout, identifier: String) -> some View {
        let reading: String? = switch score.availability {
        case .available, .knownZero: context.value
        case .missing, .excluded: nil
        }
        let secondaryLabel = metricContext(score, detail: context.label)
        let base = Button {
            store.send(.metricTapped(score.kind))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(score.kind.title, systemImage: score.kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.color(for: score.kind))

                scoreValue(score)

                VStack(alignment: .leading, spacing: 3) {
                    Text(secondaryLabel)
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)

                    Text(reading ?? "—")
                        .font(.subheadline.weight(.medium).monospacedDigit())
                        .foregroundStyle(reading == nil ? BevelTheme.inkSecondary : BevelTheme.ink)
                        .lineLimit(1)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(score.kind.title)
        .accessibilityValue("\(score.formattedScore)，\(score.availability.reasonText ?? "\(secondaryLabel) \(reading ?? "暂无数据")")")
        .accessibilityHint("打开指标详情")
        .accessibilityIdentifier(identifier)

        if let zoomNamespace {
            base.bodyseekZoomSource(id: "today-metric-\(score.kind.rawValue)", in: zoomNamespace)
        } else {
            base
        }
    }

    private func scoreValue(_ score: MetricScore) -> some View {
        Text(score.formattedScore)
            .font(.title.weight(.semibold).monospacedDigit())
            .contentTransition(.numericText())
            .foregroundStyle(score.value == nil ? BevelTheme.inkSecondary : BevelTheme.ink)
    }

    private func metricContext(_ score: MetricScore, detail: String) -> String {
        switch score.availability {
        case .available, .knownZero: detail
        case .missing: "暂无数据"
        case .excluded: "已排除"
        }
    }

    @ViewBuilder
    private var todayActionCard: some View {
        let postWorkoutAdvice = store.postWorkoutAdvice
        let suggestions = store.planItems.filter {
            $0.state != .dismissed && (postWorkoutAdvice == nil || $0.kind != .trainingFocus)
        }
        let primary = postWorkoutAdvice == nil ? (suggestions.first(where: { $0.kind == .trainingFocus }) ?? suggestions.first) : nil
        let otherSuggestions = suggestions.filter { $0.id != primary?.id }

        if postWorkoutAdvice != nil || primary != nil || hasAISuggestion {
            BevelCard {
                VStack(alignment: .leading, spacing: 14) {
                    Text("今日建议")
                        .font(.headline)
                        .foregroundStyle(BevelTheme.ink)

                    if let postWorkoutAdvice {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("今天已完成训练", systemImage: "checkmark.circle")
                                .font(.subheadline.weight(.semibold))
                            Text(postWorkoutAdvice)
                                .font(.subheadline)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                    } else if let primary {
                        suggestionRow(primary, isPrimary: true)
                    }

                    if !otherSuggestions.isEmpty {
                        Divider()

                        DisclosureGroup("其他建议") {
                            VStack(alignment: .leading, spacing: 14) {
                                ForEach(otherSuggestions) { record in
                                    Divider()
                                    suggestionRow(record, isPrimary: false)
                                }
                            }
                            .padding(.top, 8)
                        }
                        .font(.subheadline)
                        .accessibilityIdentifier("today-other-suggestions")
                    }

                    if hasAISuggestion {
                        if primary != nil {
                            Divider()
                        }
                        aiSuggestion
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-action-card")
        }
    }

    private var hasAISuggestion: Bool {
        if case let .generated(text, _) = store.briefingStatus {
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    @ViewBuilder
    private var aiSuggestion: some View {
        if case let .generated(rawText, engine) = store.briefingStatus {
            let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            let compact = text.count <= 64 && !text.contains(where: \.isNewline)

            VStack(alignment: .leading, spacing: 8) {
                if compact {
                    Label("AI 建议", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.inkSecondary)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.ink)
                        .accessibilityIdentifier("today-ai-suggestion-text")
                }

                DisclosureGroup(
                    compact ? "AI 参考依据" : "查看 AI 建议",
                    isExpanded: Binding(
                        get: { store.showEvidenceBreakdown },
                        set: { if $0 != store.showEvidenceBreakdown { store.send(.toggleEvidenceBreakdown) } }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !compact {
                            Text(text)
                                .foregroundStyle(BevelTheme.ink)
                                .accessibilityIdentifier("today-ai-suggestion-text")
                        }
                        Text(store.today.evidenceSummary)
                        Text("由 \(engine) 生成")
                    }
                    .foregroundStyle(BevelTheme.inkSecondary)
                    .padding(.top, 8)
                    .accessibilityIdentifier("today-ai-suggestion-evidence")
                }
                .font(.subheadline)
                .accessibilityIdentifier("today-advice-evidence")
            }
        }
    }

    private func suggestionRow(_ record: PlanItemRecord, isPrimary: Bool) -> some View {
        let item = record.decodedActionItem()
        return VStack(alignment: .leading, spacing: 8) {
            Text(item?.title ?? "行动建议")
                .font(isPrimary ? .title3.weight(.semibold) : .headline)
                .foregroundStyle(BevelTheme.ink)

            if let item {
                DisclosureGroup("建议依据") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.detail)
                        Text(item.metricBasis)
                    }
                    .foregroundStyle(BevelTheme.inkSecondary)
                    .padding(.top, 6)
                }
                .font(.subheadline)
            }

            switch record.state {
            case .suggested:
                HStack(spacing: 12) {
                    if isPrimary {
                        Button("采纳") { store.send(.adoptPlanItem(record.id)) }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("today-action-adopt-\(record.id.uuidString)")
                    } else {
                        Button("采纳") { store.send(.adoptPlanItem(record.id)) }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("today-action-adopt-\(record.id.uuidString)")
                    }

                    Button("跳过") { store.send(.dismissPlanItem(record.id)) }
                        .buttonStyle(.borderless)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .accessibilityIdentifier("today-action-dismiss-\(record.id.uuidString)")
                }
            case .adopted, .completed:
                Label(record.state == .completed ? "已完成" : "已采纳", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(BevelTheme.recoveryColor)
                    .accessibilityIdentifier("today-action-status-\(record.id.uuidString)")
            case .dismissed:
                EmptyView()
            }
        }
    }

    private var todayNutritionCard: some View {
        let log = store.todayNutritionLog
        let todayKey = store.snapshot.referenceDate.physiologicalDayKey()
        let validated = NutritionTargetEvaluator.validate(plan: store.nutritionTargetPlan, on: todayKey)
        let isClosed = log?.dietDayComplete == true
        let coreIDs = ["diet_kcal", "diet_carbs_g", "diet_protein_g", "diet_fat_g"]

        return Button {
            store.send(.openNutritionTapped)
        } label: {
            BevelCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("每日营养与能量平衡", systemImage: "fork.knife.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.brand)
                        Spacer()
                        Text(isClosed ? "已结账" : (log == nil ? "未记录" : "记录中 · 未结账"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (isClosed ? BevelTheme.nutritionColor(for: .met) : BevelTheme.nutritionColor(for: .unknown)).opacity(0.16),
                                in: Capsule()
                            )
                            .foregroundStyle(BevelTheme.nutritionInkColor(for: isClosed ? .met : .unknown))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("今日已记热量")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)
                            Text(log?.dietKcal.map { "\(Int($0.rounded())) kcal" } ?? "-- kcal")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(BevelTheme.ink)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("近 7 日日均缺口")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)
                            Text(store.nutritionRollingDeficit7d.map { "\(Int($0.rounded())) kcal/日" } ?? "--")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(BevelTheme.ink)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], alignment: .leading, spacing: 6) {
                        ForEach(coreIDs, id: \.self) { id in
                            let eval = NutritionTargetEvaluator.evaluate(metricID: id, log: log, validatedPlan: validated)
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(BevelTheme.nutritionColor(for: eval.status))
                                    .frame(width: 8, height: 8)
                                Text(eval.metricName.replacingOccurrences(of: "总", with: ""))
                                    .font(.caption2)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-nutrition-card")
    }

    private var checkInCard: some View {
        Button {
            store.send(.openCheckInTapped)
        } label: {
            BevelCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: store.todayCheckIn == nil ? "heart.text.square" : "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(store.todayCheckIn == nil ? BevelTheme.brand : BevelTheme.recoveryColor)

                    VStack(alignment: .leading, spacing: 3) {
                        if let checkIn = store.todayCheckIn {
                            Text("今日体感已记录")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BevelTheme.ink)
                            let sorenessText = checkIn.soreness.isEmpty ? "" : " · 酸痛 \(checkIn.soreness.count) 处"
                            Text("精力 \(checkIn.energy)/5 · 情绪 \(checkIn.mood)/5 · 压力 \(checkIn.stress)/5\(sorenessText)")
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .lineLimit(1)
                        } else {
                            Text("今日体感尚未记录 · 10 秒打卡")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BevelTheme.ink)
                            Text("量化主观精力、情绪、压力与酸痛，持续校准个人身体模型")
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(store.todayCheckIn == nil ? "打卡" : "修改")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BevelTheme.brandSoft, in: Capsule())
                        .foregroundStyle(BevelTheme.brand)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-checkin-card")
    }

    @ViewBuilder
    private var stressAndEnergyRow: some View {
        HStack(spacing: 12) {
            stressCardButton
            energyCardButton
        }
    }

    @ViewBuilder
    private var stressCardButton: some View {
        let button = Button {
            store.send(.metricTapped(.stress))
        } label: {
            BevelCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("压力", systemImage: MetricKind.stress.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.stressColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        scoreValue(store.today.stress)
                        Text(metricContext(store.today.stress, detail: store.today.stress.badge))
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    IntradayBarChart(bins: store.today.stressTimeline, height: 34)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-card-stress")

        if let zoomNamespace {
            button.bodyseekZoomSource(id: "today-metric-stress", in: zoomNamespace)
        } else {
            button
        }
    }

    @ViewBuilder
    private var energyCardButton: some View {
        let button = Button {
            store.send(.metricTapped(.energy))
        } label: {
            BevelCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("能量", systemImage: MetricKind.energy.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.energyColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        scoreValue(store.today.energy)
                        Text(metricContext(store.today.energy, detail: store.today.energy.subtitle))
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .lineLimit(1)
                    }

                    EnergyAreaChart(curve: store.today.energyCurve, height: 34)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-card-energy")

        if let zoomNamespace {
            button.bodyseekZoomSource(id: "today-metric-energy", in: zoomNamespace)
        } else {
            button
        }
    }

    private var sleepCard: some View {
        Button {
            store.send(.metricTapped(.sleep))
        } label: {
            BevelCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("昨夜睡眠", systemImage: MetricKind.sleep.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.sleepColor)
                        Spacer()
                        Text(store.today.sleep.subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BevelTheme.ink)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    if store.today.raw.sleepAsleepMinutes != nil {
                        SleepStageChart(segments: store.today.raw.sleepSegments, height: 148, interactive: false)
                    } else {
                        Text(store.today.sleep.availability.reasonText ?? "昨晚暂无睡眠分段数据")
                            .font(.footnote)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var vitalsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("生理指标 · 近 14 天")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BevelTheme.inkSecondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                vitalCard(
                    title: "HRV",
                    valueText: store.today.raw.hrvMs.map { "\(Int($0.rounded())) ms" } ?? "-- ms",
                    points: store.recentHRVSeries,
                    tint: BevelTheme.recoveryColor
                )
                vitalCard(
                    title: "静息心率",
                    valueText: store.today.raw.restingHeartRateBpm.map { "\(Int($0.rounded())) bpm" } ?? "-- bpm",
                    points: store.recentRHRSeries,
                    tint: BevelTheme.heartRateAverage
                )
                vitalCard(
                    title: "呼吸频率",
                    valueText: store.today.raw.respiratoryRateBrpm.map { String(format: "%.1f 次/分", $0) } ?? "-- 次/分",
                    points: store.recentRespiratorySeries,
                    tint: BevelTheme.sleepColor
                )
                vitalCard(
                    title: "血氧饱和度",
                    valueText: store.today.raw.oxygenSaturationPct.map { String(format: "%.0f%%", $0) } ?? "-- %",
                    points: store.recentSpO2Series,
                    tint: BevelTheme.infoBlue
                )
            }
        }
    }

    private func vitalCard(
        title: String,
        valueText: String,
        points: [VitalSparkPoint],
        tint: Color
    ) -> some View {
        BevelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BevelTheme.inkSecondary)
                Text(valueText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .contentTransition(.numericText())
                    .foregroundStyle(valueText.contains("--") ? BevelTheme.inkSecondary : BevelTheme.ink)
                MiniSparkline(vitalPoints: points, tint: tint, height: 42)
            }
        }
    }

    private var workoutsCard: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("今日训练记录", systemImage: "figure.run.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.strainColor)

                ForEach(store.today.raw.workouts) { workout in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: workout.symbolName)
                                .font(.title3)
                                .foregroundStyle(BevelTheme.strainColor)
                                .frame(width: 36, height: 36)
                                .background(BevelTheme.strainColor.opacity(0.14), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.activityName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Text("\(workout.durationMinutes) 分钟 · \(Int(workout.activeEnergyKcal.rounded())) kcal")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Spacer()
                            if let effort = workout.effortScore {
                                Text(String(format: "努力度 %.1f", effort))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(BevelTheme.strainColor.opacity(0.14), in: Capsule())
                                    .foregroundStyle(BevelTheme.strainColor)
                            } else if let avgHR = workout.averageHeartRate {
                                Text("\(Int(avgHR.rounded())) bpm")
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }

                        if let zones = workout.heartRateZones, zones.totalZoneMinutes > 0 {
                            ZoneBar(zones: zones)
                        }
                    }
                }
            }
        }
    }

    private func formattedEditorialDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }
}
