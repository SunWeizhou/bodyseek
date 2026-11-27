import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 今日页（UI v4 §2）：恢复主卡（不用环）→ 今日建议入口（sheet）→ 四项指标格（各自专属迷你图）→ 关键体征列表 → 今日记录。
public struct TodayView: View {
    @Bindable var store: StoreOf<TodayFeature>
    @State private var showAdvice = false
    private let zoomNamespace: Namespace.ID?

    public init(store: StoreOf<TodayFeature>, zoomNamespace: Namespace.ID? = nil) {
        self.store = store
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        BSPage("今日") {
            heroSection
        } note: {
            adviceEntry
        } sections: {
            sectionsContent
        } links: {
            EmptyView()
        }
        .oneLineHeader(subtitle: dateSubtitle) {
            recordMenu
        }
        .refreshable {
            store.send(.refreshTapped)
        }
        .sheet(isPresented: $showAdvice) {
            TodayAdviceSheet(store: store)
                .presentationDetents([.medium, .large])
        }
    }

    private var dateSubtitle: String {
        Self.subtitleFormatter.string(from: store.snapshot.referenceDate)
    }

    // MARK: - 标题栏按钮

    private var recordMenu: some View {
        BSHeaderMenu(systemImage: "square.and.pencil", label: "记录", identifier: "bodyseek-menu") {
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
        }
    }

    // MARK: - L0 恢复主卡与四项指标

    private var heroSection: some View {
        VStack(spacing: BSSpace.s) {
            stateBanner
            recoveryCard
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("today-score-instrument")
        }
    }

    private var recoveryCard: some View {
        let recovery = store.today.recovery
        return BSRecoveryHeroCard(
            value: recovery.value,
            availability: recovery.availability,
            statusText: recovery.badge,
            caption: recovery.subtitle,
            weekValues: weekValues { $0.recovery.value.map(Double.init) },
            startLabel: shortDate(daysAgo: Self.weekSpan),
            endLabel: "今天",
            identifier: "today-score-recovery",
            zoom: zoomSource
        ) {
            store.send(.metricTapped(.recovery))
        }
    }

    private var zoomSource: BSZoomSource? {
        guard let zoomNamespace else { return nil }
        return BSZoomSource(namespace: zoomNamespace, prefix: "today-metric-")
    }

    /// 近 7 天（前 6 天 + 今天）某项分数；今天取当日计算结果，前几天取历史。
    private func weekValues(_ pick: (DailyComputedDay) -> Double?) -> [Double?] {
        let today = store.today
        let prior = store.snapshot.historyDays
            .filter { $0.dayKey != today.dayKey }
            .suffix(Self.weekSpan)
            .map(pick)
        return prior + [pick(today)]
    }

    private static let weekSpan = 6

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

    // MARK: - L1 今日建议入口

    private var adviceEntry: some View {
        BSCoachEntryRow(
            title: "今日建议",
            meta: adviceMeta,
            summary: adviceSummary,
            tag: adviceTag,
            identifier: "today-advice-entry"
        ) {
            showAdvice = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-quick-verdict")
    }

    private var adviceMeta: String? {
        guard let brief = store.dailyBrief else { return nil }
        return Self.timeFormatter.string(from: brief.generatedAt) + " 生成"
    }

    private var adviceTag: String? {
        let count = TodayAdviceSheet.actionCount(store: store)
        return count > 0 ? "\(count) 条行动" : nil
    }

    private var adviceSummary: String {
        if let brief = store.dailyBrief { return brief.headline }
        if !store.snapshot.isAuthorized { return "授权 Apple 健康后即可生成今日结论。" }
        if let advice = store.postWorkoutAdvice { return advice }
        let summary = store.today.factualSummary
        return summary.isEmpty ? "同步 HRV、静息心率与睡眠样本后将给出今日结论。" : summary
    }

    // MARK: - L2

    @ViewBuilder
    private var sectionsContent: some View {
        metricTiles
        if store.snapshot.isAuthorized {
            vitalsSection
        }
        recordsSection
    }

    // 四项指标：睡眠 / 负荷 / 压力 / 能量，各自专属迷你图

    private var metricTiles: some View {
        BSMetricGrid {
            sleepTile
            strainTile
            stressTile
            energyTile
        }
    }

    private func tileScore(_ score: MetricScore) -> (value: Int?, availability: MetricAvailability) {
        (score.value, score.availability)
    }

    private var sleepTile: some View {
        let score = store.today.sleep
        return BSDomainTile(
            kind: .sleep,
            value: score.value,
            availability: score.availability,
            caption: sleepCaption,
            startLabel: sleepStartLabel,
            endLabel: sleepEndLabel,
            identifier: "today-score-sleep",
            zoom: zoomSource,
            action: { store.send(.metricTapped(.sleep)) }
        ) {
            SleepLanesMini(segments: store.today.raw.sleepSegments, tint: BSColor.sleep)
        }
    }

    private var sleepCaption: String {
        if let text = sleepDurationText { return "实睡 \(text)" }
        return store.today.sleep.subtitle
    }

    private var sleepStartLabel: String {
        guard let start = store.today.raw.sleepStart else { return "入睡" }
        return "入睡 " + Self.timeFormatter.string(from: start)
    }

    private var sleepEndLabel: String {
        guard let end = store.today.raw.sleepEnd else { return "醒来" }
        return "醒来 " + Self.timeFormatter.string(from: end)
    }

    private var sleepDurationText: String? {
        guard let minutes = store.today.raw.sleepAsleepMinutes else { return nil }
        let hours = minutes / 60
        let remainder = minutes % 60
        return hours > 0 ? "\(hours) 小时 \(remainder) 分" : "\(remainder) 分钟"
    }

    private var strainTile: some View {
        let score = store.today.strain
        return BSDomainTile(
            kind: .strain,
            value: score.value,
            availability: score.availability,
            caption: score.badge,
            startLabel: shortDate(daysAgo: Self.weekSpan),
            endLabel: "今天",
            identifier: "today-score-strain",
            zoom: zoomSource,
            action: { store.send(.metricTapped(.strain)) }
        ) {
            LoadWeekBarsMini(values: weekValues { $0.strain.value.map(Double.init) }, tint: BSColor.strain)
        }
    }

    private var stressTile: some View {
        let score = store.today.stress
        return BSDomainTile(
            kind: .stress,
            value: score.value,
            availability: score.availability,
            caption: score.badge,
            startLabel: "00:00",
            endLabel: "现在",
            identifier: "today-card-stress",
            zoom: zoomSource,
            action: { store.send(.metricTapped(.stress)) }
        ) {
            StressHoursMini(
                bins: store.today.stressTimeline,
                excludedHours: workoutHours,
                currentHour: currentHour,
                tint: BSColor.stress
            )
        }
    }

    private var energyTile: some View {
        let score = store.today.energy
        return BSDomainTile(
            kind: .energy,
            value: score.value,
            availability: score.availability,
            caption: score.badge,
            startLabel: "今早",
            endLabel: "现在",
            identifier: "today-card-energy",
            zoom: zoomSource,
            action: { store.send(.metricTapped(.energy)) }
        ) {
            EnergyCurveMini(points: store.today.energyCurve, tint: BSColor.energy)
        }
    }

    private var currentHour: Int {
        Calendar.current.component(.hour, from: store.snapshot.referenceDate)
    }

    /// 训练覆盖的小时：压力在这些时段被屏蔽，画中性灰块。
    private var workoutHours: Set<Int> {
        var hours: Set<Int> = []
        let calendar = Calendar.current
        for workout in store.today.raw.workouts {
            let first = calendar.component(.hour, from: workout.startDate)
            let last = calendar.component(.hour, from: workout.endDate)
            if last >= first {
                hours.formUnion(first...last)
            } else {
                hours.formUnion(first...(Self.lastHour))
            }
        }
        return hours
    }

    private static let lastHour = 23

    private func shortDate(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: store.snapshot.referenceDate)
            ?? store.snapshot.referenceDate
        return Self.shortDateFormatter.string(from: date)
    }

    // MARK: - 关键体征

    private var vitalsSection: some View {
        BSSection("关键体征") {
            BSCard {
                VStack(spacing: BSSpace.xs) {
                    vitalRow(
                        title: "HRV", systemImage: "waveform.path.ecg", tint: BSColor.recovery,
                        value: store.today.raw.hrvMs, unit: "ms", digits: 0, points: store.recentHRVSeries
                    )
                    Divider()
                    vitalRow(
                        title: "静息心率", systemImage: "heart.fill", tint: BSColor.heart,
                        value: store.today.raw.restingHeartRateBpm, unit: "bpm", digits: 0,
                        points: store.recentRHRSeries
                    )
                    Divider()
                    vitalRow(
                        title: "呼吸率", systemImage: "lungs.fill", tint: BSColor.respiration,
                        value: store.today.raw.respiratoryRateBrpm, unit: "次/分", digits: 1,
                        points: store.recentRespiratorySeries
                    )
                    Divider()
                    vitalRow(
                        title: "血氧", systemImage: "drop.fill", tint: BSColor.oxygen,
                        value: store.today.raw.oxygenSaturationPct, unit: "%", digits: 0,
                        points: store.recentSpO2Series
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-vitals-card")
        }
    }

    private func vitalRow(
        title: String,
        systemImage: String,
        tint: Color,
        value: Double?,
        unit: String,
        digits: Int,
        points: [VitalSparkPoint]
    ) -> some View {
        let series = points.compactMap(\.value)
        let average = series.isEmpty ? nil : series.reduce(0, +) / Double(series.count)
        return BSVitalRow(
            title: title,
            systemImage: systemImage,
            tint: tint,
            value: value.map { $0.formatted(.number.precision(.fractionLength(digits))) },
            unit: unit,
            comparison: BSVitalRow.comparison(value: value, average: average, unit: unit, digits: digits),
            trend: series
        )
    }

    // MARK: - 今日记录

    private var recordsSection: some View {
        BSSection("今日记录") {
            VStack(spacing: BSSpace.s) {
                if store.snapshot.isAuthorized, let workout = store.today.raw.workouts.first {
                    summaryRow(
                        title: "今日训练",
                        value: workoutSummaryText(workout),
                        systemImage: "figure.run",
                        identifier: "today-workouts-card"
                    ) {
                        store.send(.openWorkoutTapped)
                    }
                }
                summaryRow(
                    title: "今日饮食",
                    value: nutritionSummaryText,
                    systemImage: "fork.knife",
                    identifier: "today-nutrition-card"
                ) {
                    store.send(.openNutritionTapped)
                }
            }
        }
    }

    private func workoutSummaryText(_ workout: WorkoutSummary) -> String {
        let extra = store.today.raw.workouts.count - 1
        let time = Self.timeFormatter.string(from: workout.startDate)
        let more = extra > 0 ? " 等 \(extra + 1) 次" : ""
        return "\(workout.activityName)\(more) · \(time) · \(workout.durationMinutes) 分钟"
    }

    private var nutritionSummaryText: String {
        guard let log = store.todayNutritionLog, !log.entries.isEmpty else { return "今天还没记录" }
        let meals = Set(log.entries.map(\.mealType)).count
        let hasEstimate = log.entries.contains { $0.isEstimated }
        let prefix = hasEstimate ? "≈" : ""
        let kcal = log.dietKcal.map { "\(prefix)\(Int($0.rounded())) kcal" } ?? "待补热量"
        return "已记录 \(meals) 餐 · \(kcal)"
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
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .bsText(.caption)
                }
            }
        }
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - 格式

    private static let subtitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M/d"
        return formatter
    }()
}
