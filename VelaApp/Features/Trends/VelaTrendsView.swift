import SwiftUI
import BodySeekDomain

private struct ScoreTrendDescriptor: Identifiable {
    let metric: CoreHealthMetric
    let detail: VelaMetricDetailView.MetricType
    let title: String
    let icon: String

    var id: String { metric.rawValue }
}

/// Compatibility adapter for the first host migration. It snapshots the
/// already-loaded summary records into value-only inputs for TrendsStore;
/// persistence and the existing dashboard formulas remain unchanged.
private struct SummaryTrendsHistoryProvider: TrendsHistoryProviding {
    let snapshots: [DailyHealthSnapshot]
    let findings: [HealthTrendFinding]
    var isPreview = false

    func history(
        metric: CoreHealthMetric,
        horizon: HealthTrendHorizon,
        endingAt selectedDay: Date,
        calendar: Calendar
    ) async throws -> TrendsHistoryPayload {
        TrendsHistoryPayload(
            snapshots: snapshots,
            finding: findings.first {
                $0.metric == metric && $0.horizon == horizon
            },
            baselineBand: usualRange(metric: metric, snapshots: snapshots, horizon: horizon, endingAt: selectedDay, calendar: calendar),
            provenanceByDay: isPreview ? Dictionary(uniqueKeysWithValues: snapshots.map {
                (calendar.startOfDay(for: $0.date), TrendsPointProvenance(source: .derived, sourceLabel: "示例数据", detail: "仅用于界面预览"))
            }) : [:]
        )
    }

    /// Usual personal range is the baseline median ± one robust scale.
    /// A flat history has no scale, so the band stays absent instead of a made-up width.
    private func usualRange(
        metric: CoreHealthMetric,
        snapshots: [DailyHealthSnapshot],
        horizon: HealthTrendHorizon,
        endingAt selectedDay: Date,
        calendar: Calendar
    ) -> ClosedRange<Double>? {
        let samples = snapshots.compactMap { snapshot -> BaselineSample? in
            guard let value = scoreValue(metric, snapshot: snapshot) else { return nil }
            return BaselineSample(date: snapshot.date, value: value)
        }
        guard let estimate = BaselineEstimator.estimate(
            samples: samples,
            asOf: selectedDay,
            windowDays: horizon.windowDays,
            minimumSamples: horizon.requiredSampleCount,
            calendar: calendar
        ), let scale = estimate.robustScale, scale > 0 else {
            return nil
        }
        let half = scale * BaselineEstimator.stableZ
        return (estimate.median - half)...(estimate.median + half)
    }

    private func scoreValue(_ metric: CoreHealthMetric, snapshot: DailyHealthSnapshot) -> Double? {
        switch metric {
        case .sleepScore: return snapshot.sleepScore
        case .recovery: return snapshot.recoveryScore
        case .strain: return snapshot.strainScore
        case .stress: return snapshot.stressIndex
        case .energy: return snapshot.currentEnergy ?? snapshot.energyBank
        default: return nil
        }
    }
}

// MARK: - VelaTrendsView — five scored time series first, raw vitals second

struct VelaTrendsView: View {
    let selectedDate: Date
    let dashboard: DashboardSummary
    let localDataRevision: Int
    let loader: PersistedTrendsWindowLoader
    let onAskCoach: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedHorizon: HealthTrendHorizon = .thirtyDays
    @State private var selectedMetricForDetail: VelaMetricDetailView.MetricType?
    @State private var showAllMetricCatalog = false
    @State private var dailyRecordsLoadError: String?
    @State private var trendStates: [CoreHealthMetric: TrendsViewState] = [:]
    @State private var trendRetryNonce = 0
    @State private var selectedRecoveryTrendDate: Date?

    private var healthBrief: PersonalHealthBrief? { dashboard.personalHealthBrief }
    private var allTrends: [HealthTrendFinding] { dashboard.healthTrends }

    private var horizonFindings: [HealthTrendFinding] {
        allTrends.filter { $0.horizon == selectedHorizon }
    }

    private var availableFindings: [HealthTrendFinding] {
        horizonFindings.filter { $0.isAvailable }
    }

    private var horizonNotableShifts: [HealthTrendFinding] {
        availableFindings.filter { $0.isNotable }
    }

    private var scoreDescriptors: [ScoreTrendDescriptor] {
        [
            .init(metric: .recovery, detail: .recovery, title: "恢复", icon: "heart.circle.fill"),
            .init(metric: .sleepScore, detail: .sleep, title: "睡眠", icon: "moon.stars.fill"),
            .init(metric: .strain, detail: .strain, title: "负荷", icon: "figure.run"),
            .init(metric: .stress, detail: .stress, title: "压力", icon: "waveform.path.ecg"),
            .init(metric: .energy, detail: .energy, title: "能量", icon: "bolt.fill")
        ]
    }

    private var hasAnyScoreHistory: Bool {
        scoreDescriptors.contains { descriptor in
            scoreHistory(for: descriptor.metric).count >= 2
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: VelaTheme.sectionGap) {
                trendHistoryErrorCard
                compactAgentObservation
                fiveScoreTrendSection
                trendLegend

                if !hasAnyScoreHistory && scoreDescriptors.allSatisfy({ finding(for: $0.metric)?.isAvailable != true }) {
                    compactCalibrationCard
                }

                metricCatalogDisclosure
                    .padding(.top, 120)
                if showAllMetricCatalog {
                    groupedMetricBrowserSection
                    recoveryTrendChart
                    if selectedHorizon != .threeYears {
                        threeYearTrajectoryCard
                    }
                    if healthBrief?.subheadline.isEmpty != false {
                        askVelaTrendCard
                    }
                }
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 72)
            .padding(.bottom, VelaFloatingNavigationMetrics.contentBottomPadding + 20)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("trends-content")
        .background(VelaTheme.rhythmCanvas)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: trendLoadID) {
            await loadTrends()
        }
        .sheet(item: $selectedMetricForDetail) { metric in
            NavigationStack {
                VelaMetricDetailView(
                    metric: metric,
                    selectedDate: selectedDate,
                    dashboardSnapshot: dashboard,
                    isPresentedInSheet: true
                )
            }
            .presentationDetents([.large])
            .velaSheetSurface()
        }
    }

    // MARK: - Five scored time series

    private var fiveScoreTrendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 0) {
                ForEach(Array(scoreDescriptors.enumerated()), id: \.element.id) { index, descriptor in
                    scoreTrendRow(descriptor)
                    if index < scoreDescriptors.count - 1 {
                        Divider()
                            .overlay(VelaTheme.rhythmMist)
                            .padding(.leading, 16)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .fill(VelaTheme.rhythmCanvasRaised)
            )
            .overlay {
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            }
        }
    }

    /// First host migration slice: the existing recovery path now renders the
    /// Store-owned series while the legacy rows remain unchanged.
    @ViewBuilder
    private var recoveryTrendChart: some View {
        if let recoveryState = trendStates[.recovery],
           let series = recoveryState.series,
           recoveryState.phase == .ready {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("恢复趋势")
                        .font(VelaTheme.callout().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Spacer()
                    Text(dashboard.source == .preview ? "示例曲线 · 缺失日期保留空档" : "缺失日期保留空档")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }

                TrendsOneMetricChart(
                    series: series,
                    selectedDate: $selectedRecoveryTrendDate,
                    tint: VelaTheme.rhythmInk
                )
                .accessibilityIdentifier("trends-recovery-store-chart")
            }
            .padding(14)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            }
        }
    }

    private func scoreTrendRow(_ descriptor: ScoreTrendDescriptor) -> some View {
        let finding = finding(for: descriptor.metric)
        let trendPoints = scoreTrendPoints(for: descriptor.metric)
        let values = trendPoints.compactMap(\.value)
        let color = scoreColor(for: descriptor.metric)
        let valueText = scoreValueText(descriptor: descriptor, finding: finding, values: values)

        return Button {
            selectedMetricForDetail = descriptor.detail
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 12) {
                            scoreTrendIcon(descriptor, color: color)

                            Text(descriptor.title)
                                .font(VelaTheme.subheadline().weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            if finding?.isNotable == true {
                                BaselineDeviationMarker(
                                    directionLabel: finding.flatMap { BaselineDeviationCopy.label(for: $0) },
                                    showsLabel: false,
                                    diameter: 7
                                )
                            }

                            Spacer(minLength: 8)

                            Text(valueText)
                                .font(.system(.headline, design: .default, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(valueText == "--" ? VelaTheme.muted : VelaTheme.rhythmInk)

                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.55))
                        }

                        Text(scoreTrendCaption(finding: finding, sampleCount: values.count))
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        DateAwareSparkline(
                            points: trendPoints,
                            color: color,
                            height: 42,
                            width: 220,
                            band: scoreBand(for: descriptor.metric),
                            marksLatestPoint: true
                        )
                        .accessibilityHidden(true)
                    }
                } else {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(descriptor.title)
                                .font(VelaTheme.subheadline().weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            HStack(spacing: 4) {
                                if finding?.isNotable == true {
                                    BaselineDeviationMarker(
                                        directionLabel: finding.flatMap { BaselineDeviationCopy.label(for: $0) },
                                        showsLabel: false,
                                        diameter: 7
                                    )
                                }
                                Text(scoreTrendCaption(finding: finding, sampleCount: values.count))
                                    .font(VelaTheme.caption2())
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 108, alignment: .leading)

                        DateAwareSparkline(
                            points: trendPoints,
                            color: color,
                            height: 36,
                            width: 128,
                            band: scoreBand(for: descriptor.metric),
                            marksLatestPoint: true
                        )
                        .accessibilityHidden(true)

                        Spacer(minLength: 0)

                        Text(valueText)
                            .font(.system(.title3, design: .default, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(valueText == "--" ? VelaTheme.muted : VelaTheme.rhythmInk)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("trends-score-\(descriptor.metric.rawValue)")
        .accessibilityLabel(scoreAccessibilityLabel(descriptor: descriptor, finding: finding, values: values))
        .accessibilityHint("打开\(descriptor.title)详情")
    }

    private func scoreTrendIcon(
        _ descriptor: ScoreTrendDescriptor,
        color: Color
    ) -> some View {
        Image(systemName: descriptor.icon)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 34, height: 34)
            .background(color.opacity(0.10), in: Circle())
    }

    private var compactCalibrationCard: some View {
        NavigationLink(destination: HistoricalBackfillView()) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                Text("同步或回填健康数据，建立个人趋势")
                    .font(VelaTheme.footnote().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(14)
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.cardPress)
    }

    @ViewBuilder
    private var compactAgentObservation: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 4) {
                ForEach(HealthTrendHorizon.allCases) { horizon in
                    let selected = horizon == selectedHorizon
                    Text(horizon.title)
                        .font(VelaTheme.subheadline().weight(selected ? .semibold : .regular))
                        .foregroundStyle(selected ? VelaTheme.rhythmInk : VelaTheme.rhythmInkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(selected ? VelaTheme.segmentOn : Color.clear))
                        .contentShape(Capsule())
                        .onTapGesture {
                            selectedHorizon = horizon
                            VelaHaptic.selection()
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Spacer(minLength: 8)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trends-horizon-picker")
            .accessibilityLabel("趋势时间范围")

            if let brief = healthBrief, !brief.headline.isEmpty || !brief.subheadline.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.circle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text("BodySeek · \(selectedHorizon.title)小结")
                            .font(VelaTheme.caption1())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Spacer(minLength: 8)
                        if dashboard.source == .preview {
                            Text("示例数据")
                                .font(VelaTheme.caption2().weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .overlay(Capsule().stroke(VelaTheme.hairline, lineWidth: 1))
                        }
                    }
                    if !brief.headline.isEmpty {
                        Text(brief.headline)
                            .font(VelaTheme.briefBody().weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !brief.subheadline.isEmpty, brief.subheadline != brief.headline {
                        Text(brief.subheadline)
                            .font(VelaTheme.briefBody())
                            .foregroundStyle(VelaTheme.rhythmInk)
                            .lineSpacing(6)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var trendLegend: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(VelaTheme.rangeBand)
                    .frame(width: 18, height: 8)
                Text("常见范围")
            }
            HStack(spacing: 6) {
                Circle()
                    .stroke(VelaTheme.rhythmInk, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                Text("对你不常见（不代表不好）")
            }
        }
        .font(VelaTheme.caption2())
        .foregroundStyle(VelaTheme.rhythmInkSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metricCatalogDisclosure: some View {
        Button {
            withAnimation(reduceMotion ? .easeOut(duration: 0.16) : .snappy(duration: 0.24)) {
                showAllMetricCatalog.toggle()
            }
            VelaHaptic.selection()
        } label: {
            HStack {
                Text("更多健康指标")
                    .font(VelaTheme.callout().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Image(systemName: showAllMetricCatalog ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showAllMetricCatalog ? "已展开" : "已收起")
    }

    private func finding(for metric: CoreHealthMetric) -> HealthTrendFinding? {
        allTrends.first { $0.metric == metric && $0.horizon == selectedHorizon }
    }

    private func scoreTrendPoints(for metric: CoreHealthMetric) -> [TrendsChartPoint] {
        trendStates[metric]?.series?.points ?? []
    }

    private func scoreBand(for metric: CoreHealthMetric) -> ClosedRange<Double>? {
        trendStates[metric]?.series?.baselineBand
    }

    private func scoreHistory(for metric: CoreHealthMetric) -> [Double] {
        trendStates[metric]?.series?.points.compactMap(\.value) ?? []
    }

    private func scoreValueText(
        descriptor: ScoreTrendDescriptor,
        finding: HealthTrendFinding?,
        values: [Double]
    ) -> String {
        let value = finding?.isAvailable == true
            ? finding?.currentValue
            : currentScoreValue(for: descriptor.metric)
        guard let value else { return "--" }
        let rounded = Int(value.rounded())
        return descriptor.metric == .energy ? "\(rounded)%" : "\(rounded)"
    }

    private func scoreTrendCaption(finding: HealthTrendFinding?, sampleCount: Int) -> String {
        guard let finding, finding.isAvailable else {
            if sampleCount >= selectedHorizon.requiredSampleCount {
                return "\(sampleCount) 天记录"
            }
            return "\(sampleCount)/\(selectedHorizon.requiredSampleCount) 天"
        }
        if finding.isNotable {
            return BaselineDeviationCopy.label(for: finding) ?? BaselineDeviationCopy.unusualFallback
        }
        if let baseline = finding.baselineValue {
            return "基线 \(Int(baseline.rounded())) · \(finding.valueDirection.label)"
        }
        return "\(finding.sampleCount) 天 · \(finding.valueDirection.label)"
    }

    private func scoreAccessibilityLabel(
        descriptor: ScoreTrendDescriptor,
        finding: HealthTrendFinding?,
        values: [Double]
    ) -> String {
        let value = scoreValueText(descriptor: descriptor, finding: finding, values: values)
        let state = scoreTrendCaption(finding: finding, sampleCount: values.count)
        return "\(descriptor.title)，\(value)，\(state)"
    }

    private func currentScoreValue(for metric: CoreHealthMetric) -> Double? {
        switch metric {
        case .recovery: return dashboard.recovery.hasData ? dashboard.recovery.value : nil
        case .sleepScore: return dashboard.sleepScore.hasData ? dashboard.sleepScore.value : nil
        case .strain: return dashboard.strain.hasData ? dashboard.strain.value : nil
        case .stress: return dashboard.stress.hasData ? dashboard.stress.value : nil
        case .energy: return dashboard.energy.hasData ? dashboard.energy.value : nil
        default: return nil
        }
    }

    private func scoreColor(for metric: CoreHealthMetric) -> Color {
        switch metric {
        case .recovery: return VelaTheme.rhythmInk
        case .sleepScore: return VelaTheme.rhythmInk
        case .strain: return VelaTheme.rhythmInk
        case .stress: return VelaTheme.rhythmInk
        case .energy: return VelaTheme.rhythmInk
        default: return VelaTheme.rhythmDeep
        }
    }

    private var trendLoadID: String {
        "\(selectedHorizon.rawValue)|\(selectedDate.timeIntervalSinceReferenceDate)|\(localDataRevision)|\(trendRetryNonce)"
    }

    /// Lets the horizon control paint before the history read. Cancelling the
    /// task keeps the visible series until a newer load finishes.
    private func loadTrends() async {
        let horizon = selectedHorizon
        let selectedDate = selectedDate
        let findings = allTrends
        await Task.yield()
        guard !Task.isCancelled else { return }
        let loaded = loader.load(horizon: horizon, endingAt: selectedDate)
        guard !Task.isCancelled else { return }
        let provider = SummaryTrendsHistoryProvider(
            snapshots: loaded.snapshots,
            findings: findings,
            isPreview: loaded.isPreview
        )
        var states: [CoreHealthMetric: TrendsViewState] = [:]
        for metric in scoreDescriptors.map(\.metric) {
            guard !Task.isCancelled else { return }
            let store = TrendsStore(
                provider: provider,
                selectedDay: selectedDate,
                horizon: horizon,
                metric: metric
            )
            await store.send(.appear)
            states[metric] = store.state
        }
        guard !Task.isCancelled else { return }
        dailyRecordsLoadError = loaded.errorMessage
        trendStates = states
    }

    // MARK: - Empty State View

    @ViewBuilder
    private var trendHistoryErrorCard: some View {
        if let dailyRecordsLoadError {
            VelaStateCard(
                state: .error,
                title: "趋势历史暂时无法读取",
                message: dailyRecordsLoadError,
                actionTitle: "重试",
                action: { trendRetryNonce += 1 }
            )
            .accessibilityIdentifier("trends-history-error")
        }
    }

    private var emptyHorizonStateView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(VelaTheme.rhythmDeep.opacity(0.1))
                    .frame(width: 56, height: 56)
                Image(systemName: "waveform.path.badge.plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("\(selectedHorizon.detailedTitle) 数据积累中")
                    .font(VelaTheme.headline().weight(.bold))
                    .foregroundStyle(VelaTheme.rhythmInk)

                Text("当前周期需要至少 \(selectedHorizon.requiredSampleCount) 天有效记录。继续佩戴 Apple Watch 记录，或在设置中回填历史健康数据。")
                    .font(VelaTheme.body())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }

            NavigationLink(destination: HistoricalBackfillView()) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(VelaTheme.footnote().weight(.semibold))
                    Text("前往回填三年 Apple 健康数据")
                        .font(VelaTheme.footnote().weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(VelaTheme.rhythmDeepOn)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(VelaTheme.rhythmDeep))
            }
            .buttonStyle(.cardPress)
            .padding(.bottom, 6)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(VelaTheme.rhythmCanvasRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
        .accessibilityIdentifier("trends-empty-state")
    }

    // MARK: - Tier 2: System Narrative Section

    private var systemNarrativeSection: some View {
        Group {
            if let brief = healthBrief, !brief.possibleDrivers.isEmpty || !brief.subheadline.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                        Text("系统关联观察")
                            .font(VelaTheme.footnote().weight(.bold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                        Spacer()
                    }

                    Text(brief.subheadline)
                        .font(VelaTheme.body().weight(.medium))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !brief.possibleDrivers.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(brief.possibleDrivers, id: \.self) { driver in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle()
                                        .fill(VelaTheme.rhythmDeep.opacity(0.7))
                                        .frame(width: 4, height: 4)
                                        .padding(.top, 6)
                                    Text(driver)
                                        .font(VelaTheme.footnote())
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
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(VelaTheme.rhythmCanvasRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            }
        }
    }

    // MARK: - Tier 3: Grouped Metric Browser

    private var groupedMetricBrowserSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("生理系统指标浏览")
                .font(VelaTheme.headline())
                .foregroundStyle(VelaTheme.rhythmInk)

            // 1. 心血管与节律
            metricGroup(
                title: "心血管与自主节律",
                metrics: [
                    (.hrv, .hrv),
                    (.restingHeartRate, .rhr),
                    (.respiratoryRate, .respiratoryRate),
                    (.oxygenSaturation, .bloodOxygen)
                ]
            )

            // 2. 睡眠与恢复
            metricGroup(
                title: "睡眠与恢复",
                metrics: [
                    (.sleepDuration, .sleep),
                    (.recovery, .recovery),
                    (.energy, .energy)
                ]
            )

            // 3. 日常负荷与活动
            metricGroup(
                title: "日常负荷与活动",
                metrics: [
                    (.strain, .strain),
                    (.stress, .stress),
                    (.steps, .steps),
                    (.activeCalories, .activeCalories)
                ]
            )

            // 4. 身体组成
            metricGroup(
                title: "身体组成",
                metrics: [
                    (.bodyWeight, .weight),
                    (.bodyFat, .bodyFat)
                ]
            )
        }
    }

    private func metricGroup(
        title: String,
        metrics: [(CoreHealthMetric, VelaMetricDetailView.MetricType)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(VelaTheme.footnote().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .padding(.leading, 2)

            VStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, pair in
                    browserRow(for: pair.0, metricType: pair.1)
                    if index < metrics.count - 1 {
                        Divider()
                            .overlay(VelaTheme.rhythmMist)
                            .padding(.leading, 48)
                    }
                }
            }
            .velaNativeCard(radius: VelaTheme.radiusLg)
        }
    }

    private func browserRow(for metric: CoreHealthMetric, metricType: VelaMetricDetailView.MetricType) -> some View {
        let finding = allTrends.first { $0.metric == metric && $0.horizon == selectedHorizon }

        return Button {
            selectedMetricForDetail = metricType
        } label: {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            browserMetricIcon(metric)
                            Text(metric.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }

                        Text(finding?.isAvailable == true
                             ? (finding?.summary ?? "")
                             : "需至少 \(selectedHorizon.requiredSampleCount) 天，当前 \(finding?.sampleCount ?? 0) 天")
                            .font(VelaTheme.footnote())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(finding?.isAvailable == true ? (finding?.currentValueFormatted ?? "--") : "--")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(finding?.isAvailable == true ? VelaTheme.rhythmInk : VelaTheme.muted)
                            if let finding, finding.isAvailable {
                                Image(systemName: finding.valueDirection.icon)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(assessmentColor(for: finding.assessment))
                                    .accessibilityLabel(finding.assessment.label)
                            }
                        }
                    }
                } else {
                    HStack(alignment: .center, spacing: 12) {
                        browserMetricIcon(metric)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(metric.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(finding?.isAvailable == true
                                 ? (finding?.summary ?? "")
                                 : "需至少 \(selectedHorizon.requiredSampleCount) 天，当前 \(finding?.sampleCount ?? 0) 天")
                                .font(VelaTheme.footnote())
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer(minLength: 8)

                        VStack(alignment: .trailing, spacing: 3) {
                            Text(finding?.isAvailable == true ? (finding?.currentValueFormatted ?? "--") : "--")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(finding?.isAvailable == true ? VelaTheme.rhythmInk : VelaTheme.muted)
                            if let finding, finding.isAvailable {
                                Image(systemName: finding.valueDirection.icon)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(assessmentColor(for: finding.assessment))
                                    .accessibilityLabel(finding.assessment.label)
                            }
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.cardPress)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开指标详情")
    }

    private func browserMetricIcon(_ metric: CoreHealthMetric) -> some View {
        Image(systemName: metric.icon)
            .font(.body.weight(.semibold))
            .foregroundStyle(accentColor(for: metric))
            .frame(width: 32, height: 32)
            .background(VelaTheme.rhythmMist.opacity(0.72), in: Circle())
    }

    // MARK: - Three-Year Trajectory Card

    private var threeYearTrajectoryCard: some View {
        NavigationLink(destination: LongTermHealthTrendView()) {
            HStack(spacing: 14) {
                Image(systemName: "chart.xyaxis.line")
                    .font(VelaTheme.title3().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(VelaTheme.rhythmMist.opacity(0.8))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("三年健康轨迹与基线")
                        .font(VelaTheme.callout().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("查看长期月均演变与同比分析")
                        .font(VelaTheme.footnote())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(VelaTheme.rhythmCanvasRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ask Vela Trend Card

    private var askVelaTrendCard: some View {
        Button {
            onAskCoach(selectedHorizonCoachQuestion)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(VelaTheme.body().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)

                VStack(alignment: .leading, spacing: 2) {
                    Text("向 Vela 深入分析\(selectedHorizon.detailedTitle)变化")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("探讨心率、睡眠与压力之间的可能联系")
                        .font(VelaTheme.footnote())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: VelaTheme.minimumHitTarget, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(VelaTheme.rhythmMist.opacity(0.45))
            )
        }
        .buttonStyle(.cardPress)
        .accessibilityHint("打开 Vela，并带入当前趋势范围与显著变化")
    }

    private var selectedHorizonCoachQuestion: String {
        let notable = horizonNotableShifts.prefix(3).map {
            "\($0.metric.title)：\($0.summary)"
        }
        let evidence = notable.isEmpty
            ? "本周期没有达到显著阈值的变化。"
            : "当前显著变化：" + notable.joined(separator: "；")
        return "请综合分析我\(selectedHorizon.detailedTitle)的身体体征变化，解释值得关注的关联，并给出一个最优先行动。\(evidence)"
    }

    private func detailMetric(for metric: CoreHealthMetric) -> VelaMetricDetailView.MetricType {
        switch metric {
        case .hrv: return .hrv
        case .restingHeartRate: return .rhr
        case .sleepDuration, .sleepScore: return .sleep
        case .recovery: return .recovery
        case .strain: return .strain
        case .stress: return .stress
        case .energy: return .energy
        case .respiratoryRate: return .respiratoryRate
        case .oxygenSaturation: return .bloodOxygen
        case .bodyWeight: return .weight
        case .bodyFat: return .bodyFat
        case .steps: return .steps
        case .activeCalories: return .activeCalories
        }
    }

    // MARK: - Helper Colors

    private func accentColor(for metric: CoreHealthMetric) -> Color {
        switch metric {
        case .hrv, .recovery: return VelaTheme.rhythmInk
        case .restingHeartRate, .strain: return VelaTheme.rhythmInk
        case .sleepDuration, .sleepScore: return VelaTheme.rhythmInk
        case .stress: return VelaTheme.rhythmInk
        case .energy: return VelaTheme.rhythmInk
        case .respiratoryRate, .oxygenSaturation, .bodyWeight, .bodyFat, .steps, .activeCalories:
            return VelaTheme.rhythmDeep
        }
    }

    private func assessmentColor(for assessment: TrendAssessment) -> Color {
        switch assessment {
        case .favorable: return VelaTheme.brandLeaf
        case .unfavorable: return VelaTheme.rhythmInk
        case .neutral: return VelaTheme.rhythmInkSecondary
        case .insufficientData: return VelaTheme.muted
        }
    }
}
