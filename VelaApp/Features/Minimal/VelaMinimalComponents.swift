import SwiftData
import SwiftUI
import Charts

enum VelaMinimalFormatting {
    static func roundedPercentage(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    static func calendarTitle(year: Int, month: Int) -> String {
        "\(year)年\(month)月"
    }

    static func duration(minutes: Int) -> String {
        let safeMinutes = max(0, minutes)
        return "\(safeMinutes / 60)小时\(safeMinutes % 60)分钟"
    }

    static func clockTime(hour: Int, minute: Int) -> String {
        String(format: "%02d:%02d", normalizedHour(hour), normalizedMinute(minute))
    }

    static func sleepDurationMinutes(
        bedtimeHour: Int,
        bedtimeMinute: Int,
        wakeHour: Int,
        wakeMinute: Int
    ) -> Int {
        let bedtime = minutesSinceMidnight(hour: bedtimeHour, minute: bedtimeMinute)
        let wake = minutesSinceMidnight(hour: wakeHour, minute: wakeMinute)
        return (wake - bedtime + 24 * 60) % (24 * 60)
    }

    static func sleepDialAngle(hour: Int, minute: Int) -> Double {
        Double(minutesSinceMidnight(hour: hour, minute: minute)) / Double(24 * 60) * 360.0
    }

    private static func minutesSinceMidnight(hour: Int, minute: Int) -> Int {
        normalizedHour(hour) * 60 + normalizedMinute(minute)
    }

    private static func normalizedHour(_ hour: Int) -> Int {
        (hour % 24 + 24) % 24
    }

    private static func normalizedMinute(_ minute: Int) -> Int {
        min(max(minute, 0), 59)
    }
}

struct VelaDetailBackButton: View {
    @Environment(\.dismiss) private var dismiss

    var tint: Color = VelaTheme.accent
    var label: String = "返回"

    var body: some View {
        Button(action: dismiss.callAsFunction) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(VelaTheme.surface))
                .overlay(Circle().stroke(VelaTheme.borderSoft, lineWidth: 0.5))
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel(label)
    }
}

// MARK: - Rhythm detail-page contract

/// Shared chrome for every pushed Vela destination. Detail screens use the
/// system navigation model and one quiet material hierarchy, so moving between
/// evidence, training and personal context never feels like changing apps.
private struct VelaRhythmDetailChromeModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .tint(VelaTheme.rhythmDeep)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(
                reduceTransparency
                    ? VelaTheme.rhythmCanvas
                    : VelaTheme.rhythmCanvas.opacity(0.94),
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension View {
    func velaRhythmDetailChrome() -> some View {
        modifier(VelaRhythmDetailChromeModifier())
    }

    func velaRhythmFormSurface() -> some View {
        scrollContentBackground(.hidden)
            .background(VelaTheme.rhythmCanvas)
            .tint(VelaTheme.rhythmDeep)
    }
}

// MARK: - VelaMetricDetailView — calm, evidence-first metric detail



struct VelaMetricDetailView: View {
    let metric: MetricType
    var selectedDate: Date? = nil
    var dashboardSnapshot: DashboardSummary? = nil
    var isPresentedInSheet: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var cs
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @ObservedObject var appState = VelaAppState.shared
    @State var dailyRecords: [DailyHealthSummaryRecord] = []
    @AppStorage(SleepTargetSettings.hoursKey) var sleepTargetHours = SleepTargetSettings.defaultHours
    @AppStorage("agent_bedtime_hour") var targetBedtimeHour = 22
    @AppStorage("agent_bedtime_minute") var targetBedtimeMinute = 0
    @State var showMetricInfo = false
    @State var heartRateZoneSummary: HeartRateZoneSummary?
    @State var isLoadingHeartRateZones = false
    @State private var dailyRecordsLoadError: String?
    
    // Default to 7 days (.week) for immediate momentum and responsive trend viewing
    @State var selectedRange: DetailTimeRange = .week
    @State var rawSelectedDate: Date? = nil

    var effectiveDate: Date {
        selectedDate ?? dashboardVM.selectedDate
    }

    var dashboard: DashboardSummary {
        dashboardSnapshot ?? dashboardVM.dashboard
    }

    enum MetricType: String, CaseIterable, Identifiable {
        case strain, recovery, sleep, stress, energy, hrv, rhr
        case weight, bodyFat, respiratoryRate, bloodOxygen, steps, activeCalories, activeMinutes
        var id: String { rawValue }
    }

    var body: some View {
        let isSleep = (metric == .sleep)
        
        ZStack {
            VelaTheme.rhythmCanvas.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    if metric.isScoredHealthDomain {
                        coreMetricContent(isSleep: isSleep)
                    } else {
                        rawMetricContent(isSleep: isSleep)
                    }
                }
                .padding(.horizontal, VelaTheme.pagePadding)
                .padding(.bottom, 56)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(navTitle)
        .accessibilityIdentifier("metric-detail-\(metric.rawValue)")
        .velaRhythmDetailChrome()
        .toolbar {
            if isPresentedInSheet {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: dismiss.callAsFunction) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(VelaTheme.rhythmCanvasRaised))
                            .overlay(Circle().stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("metric-detail-close")
                }
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                ShareLink(item: metricShareText) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享\(navTitle)")

                Button {
                    showMetricInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("关于\(navTitle)")
            }
        }
        .alert("关于\(navTitle)", isPresented: $showMetricInfo) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(metricInfoText)
        }
        .task(id: strainWorkoutQueryKey) {
            guard metric == .strain else { return }
            await loadHeartRateZones()
        }
        .onAppear {
            loadDailyRecords()
        }
        .onChange(of: dashboardVM.selectedDate) {
            if selectedDate == nil {
                loadDailyRecords()
            }
        }
        .onChange(of: appState.localDataRevision) {
            loadDailyRecords()
        }
    }

    private func loadDailyRecords() {
        let calendar = Calendar.current
        let endDate = calendar.startOfDay(for: effectiveDate)
        let end = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate
        let start = calendar.date(
            byAdding: .day,
            value: -(HealthTrendHorizon.threeYears.windowDays + 7),
            to: end
        ) ?? end
        
        let descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate<DailyHealthSummaryRecord> { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        do {
            dailyRecords = try modelContext.fetch(descriptor)
            dailyRecordsLoadError = nil
        } catch {
            // Never keep another date's points on screen after a failed fetch.
            dailyRecords = []
            dailyRecordsLoadError = L10n.t(
                "The history could not be read. No trend is shown until a retry succeeds.",
                "历史记录暂时无法读取。重试成功前不会展示趋势。"
            )
        }
    }





    private var timeRangeSelector: some View {
        Picker("时间区间", selection: $selectedRange) {
            ForEach(DetailTimeRange.allCases) { range in
                Text(range.title).tag(range)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
    }

    private func chartHeaderSection(isSleep: Bool) -> some View {
        MetricChartSection(
            metric: metric,
            isSleep: isSleep,
            points: chartPoints,
            isBarChart: isBarChart,
            metricColor: metricColor,
            selectedRange: $selectedRange,
            rawSelectedDate: $rawSelectedDate,
            displayDateText: displayDateText,
            dynamicValueText: dynamicValueText,
            metricSubtitle: metricSubtitle,
            baselineValue: chartBaselineValue,
            targetRange: chartTargetRange,
            isSimulated: dailyRecords.contains {
                $0.configVersion == DailySummaryUseCase.debugDemoConfigVersion
            }
        )
    }

    /// A baseline line is only truthful when the trend engine has published a
    /// baseline for the same metric and horizon. The visible chart average is
    /// not a substitute for a Personal Baseline.
    private var chartBaselineValue: Double? {
        guard chartTrendFinding?.isAvailable == true else { return nil }
        return chartTrendFinding?.baselineValue
    }

    private var chartTrendFinding: HealthTrendFinding? {
        guard let coreMetric = metric.coreMetric,
              let horizon = selectedRange.trendHorizon else { return nil }
        return dashboard.healthTrends.first {
            $0.metric == coreMetric
                && $0.horizon == horizon
        }
    }

    private var personalBaselineText: String {
        guard let finding = chartTrendFinding else { return "建立中" }
        guard let baseline = finding.baselineValue else {
            return "建立中 \(finding.sampleCount)/\(finding.requiredSampleCount)"
        }
        if finding.isNotable, let deviation = finding.currentDeviationValue {
            return String(format: "偏离 %+.0f", deviation)
        }
        return String(format: "%.0f", baseline)
    }

    private var chartTargetRange: ClosedRange<Double>? {
        guard metric == .strain else { return nil }
        return dashboard.strain.explicitRecommendedRange
    }

    @ViewBuilder
    private func coreMetricContent(isSleep: Bool) -> some View {
        if metric == .recovery {
            recoveryDetailV2
        } else {
            legacyCoreMetricContent(isSleep: isSleep)
        }
    }

    private var recoveryDetailV2: some View {
        VStack(alignment: .leading, spacing: 16) {
            metricHistoryErrorCard
            RecoveryDetailV2View(
                model: RecoveryDetailV2Builder.make(
                    dashboard: dashboard,
                    snapshots: dailyRecords.map { $0.toSnapshot() },
                    range: selectedRange,
                    endingAt: effectiveDate,
                    baselineBand: nil,
                    isSimulated: dashboard.source == .preview || dailyRecords.contains {
                        $0.configVersion == DailySummaryUseCase.debugDemoConfigVersion
                    }
                ),
                selectedRange: $selectedRange,
                onAskCoach: openMetricCoach
            )
        }
    }

    @ViewBuilder
    private func legacyCoreMetricContent(isSleep: Bool) -> some View {
        // 1. 主值 + 数据质量
        CoreMetricDetailHero(
            metric: metric,
            valueText: dynamicValueText,
            score: hasMetricData ? dynamicScore : nil,
            color: metricColor,
            state: currentMetricResult?.state ?? .moderate,
            guidance: metricRecommendation.title,
            facts: coreMetricHeroFacts,
            baselineValue: chartBaselineValue,
            targetRange: chartTargetRange,
            onAskCoach: openMetricCoach
        )
        .padding(.top, 8)

        metricHistoryErrorCard

        trustSection

        // 2. 个人比较 / 趋势
        customWidgetsSection(isSleep: isSleep)
        chartHeaderSection(isSleep: isSleep)

        // 3. HRV/RHR 等依据
        supportingEvidenceSection(isSleep: isSleep)

        // 4. 方法 / 来源 / 限制
        guidanceSection(isSleep: isSleep)
        metricMethodologySection
    }

    private var metricMethodologySection: some View {
        MetricMethodologyCard(metric: metric)
    }

    @ViewBuilder
    private func rawMetricContent(isSleep: Bool) -> some View {
        metricHistoryErrorCard
        chartHeaderSection(isSleep: isSleep)
            .padding(.top, 8)
        doubleHighlightsSection(isSleep: isSleep)
        trendsSection(isSleep: isSleep)
        guidanceSection(isSleep: isSleep)
        customWidgetsSection(isSleep: isSleep)
        coreMetricCoachCard
        trustSection
        supportingEvidenceSection(isSleep: isSleep)
    }

    @ViewBuilder
    private var metricHistoryErrorCard: some View {
        if let dailyRecordsLoadError {
            VelaStateCard(
                state: .error,
                message: dailyRecordsLoadError,
                actionTitle: L10n.t("Retry", "重试"),
                action: loadDailyRecords
            )
        }
    }

    private var coreMetricHeroFacts: [CoreMetricHeroFact] {
        switch metric {
        case .recovery:
            return [
                CoreMetricHeroFact(title: "HRV", value: rightValue, systemImage: "waveform.path.ecg"),
                CoreMetricHeroFact(title: "静息心率", value: leftValue, systemImage: "heart.fill"),
                CoreMetricHeroFact(title: "个人基线", value: personalBaselineText, systemImage: "line.diagonal")
            ]
        case .sleep:
            return [
                CoreMetricHeroFact(title: "实际睡眠", value: rightValue, systemImage: "bed.double.fill"),
                CoreMetricHeroFact(
                    title: "睡眠节律",
                    value: hasCompleteSleepTimes ? "\(bedtimeText) → \(wakeTimeText)" : "--",
                    systemImage: "moon.stars.fill"
                ),
                CoreMetricHeroFact(title: "个人基线", value: personalBaselineText, systemImage: "line.diagonal")
            ]
        case .strain:
            return [
                CoreMetricHeroFact(
                    title: "参考区间",
                    value: chartTargetRange.map { "\(Int($0.lowerBound))–\(Int($0.upperBound))" } ?? "待建立",
                    systemImage: "scope"
                ),
                CoreMetricHeroFact(title: "活跃时长", value: leftValue, systemImage: "timer"),
                CoreMetricHeroFact(title: "个人基线", value: personalBaselineText, systemImage: "line.diagonal")
            ]
        case .stress:
            return [
                CoreMetricHeroFact(title: "当前状态", value: metricSubtitle, systemImage: "waveform.path.ecg"),
                CoreMetricHeroFact(title: "个人基线", value: personalBaselineText, systemImage: "line.diagonal"),
                CoreMetricHeroFact(title: "静息心率", value: rightValue, systemImage: "heart.fill")
            ]
        case .energy:
            return [
                CoreMetricHeroFact(title: "早间储备", value: leftValue, systemImage: "sun.max.fill"),
                CoreMetricHeroFact(title: "当前剩余", value: rightValue, systemImage: "bolt.fill"),
                CoreMetricHeroFact(title: "个人基线", value: personalBaselineText, systemImage: "line.diagonal")
            ]
        default:
            return []
        }
    }

    private func openMetricCoach() {
        let context = CoreMetricCoachContext.make(for: metric)
        appState.routeToCoach(question: context.suggestedQuestion, surface: .metricDetail)
    }









    // MARK: - 1. Procedural Landscape Header
    private func landscapeHeaderSection(isSleep: Bool) -> some View {
        ZStack {
            MetricLandscapeHeader(metric: metric, isSleep: isSleep)
            
            // Metric-specific hero grammar: primary score rings, stress trace,
            // energy reserve, and absolute-value raw signals.
            VStack(spacing: 8) {
                Spacer()
                
                // Metric hero container
                ZStack {
                    switch metric.heroPresentation {
                    case .stressTrace:
                        VStack(spacing: 6) {
                            Image(systemName: "waveform.path.ecg")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(metricColor)
                            Text(dynamicValueText)
                                .font(.system(.title, design: .rounded, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(VelaTheme.rhythmInk)
                            Text(stressBandLabel(dashboard.stress.band))
                                .font(VelaTheme.caption2().weight(.semibold))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }
                        .frame(width: 140, height: 104)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(isSleep ? VelaTheme.inkDark.opacity(0.85) : VelaTheme.rhythmCanvasRaised)
                                .shadow(color: isSleep ? .clear : Color.black.opacity(0.012), radius: 10, x: 0, y: 3)
                        )
                    case .energyReserve:
                        VStack(spacing: 10) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(metricColor)
                                Text(dynamicValueText)
                                    .font(.system(.title2, design: .rounded, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(VelaTheme.rhythmInk)
                            }
                            SegmentedBatteryBar(
                                percentage: min(max(dynamicScore / 100, 0), 1),
                                barCount: 16,
                                color: metricColor
                            )
                        }
                        .frame(width: 156, height: 96)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(isSleep ? VelaTheme.inkDark.opacity(0.85) : VelaTheme.rhythmCanvasRaised)
                                .shadow(color: isSleep ? .clear : Color.black.opacity(0.012), radius: 10, x: 0, y: 3)
                        )
                    case .scoreGauge:
                        BevelScoreRing(
                            score: max(0.01, dynamicScore / 100.0),
                            color: metricColor,
                            useGradient: true,
                            size: 110,
                            label: "",
                            valueText: dynamicValueText
                        )
                        .background(
                            Circle()
                                .fill(isSleep ? VelaTheme.inkDark.opacity(0.85) : VelaTheme.rhythmCanvasRaised)
                                .frame(width: 140, height: 140)
                                .shadow(color: isSleep ? .clear : Color.black.opacity(0.012), radius: 10, x: 0, y: 3)
                        )
                    case .absoluteValue:
                        ZStack {
                            Circle()
                                .fill(isSleep ? VelaTheme.inkDark.opacity(0.85) : VelaTheme.rhythmCanvasRaised)
                                .frame(width: 140, height: 140)
                                .shadow(color: isSleep ? .clear : Color.black.opacity(0.012), radius: 10, x: 0, y: 3)

                            Circle()
                                .stroke(metricColor.opacity(0.3), lineWidth: 8)
                                .frame(width: 110, height: 110)

                            VStack(spacing: 6) {
                                Image(systemName: leftIcon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(metricColor)

                                Text(dynamicValueText)
                                    .font(.system(.body, design: .default, weight: .bold))
                                    .foregroundStyle(isSleep ? VelaTheme.sleepText : VelaTheme.fg)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.58)
                                    .frame(width: 96)
                            }
                        }
                    }
                }
                .padding(.bottom, 8)

                // Subtitle/Target Text below the ring
                if metric == .strain {
                    let range = dashboard.strain.recommendedRange
                    Text("目标耗力: \(range.lowerBound) - \(range.upperBound)%")
                        .font(VelaTheme.caption1())
                        .fontWeight(.semibold)
                        .foregroundStyle(isSleep ? VelaTheme.mistGray : VelaTheme.fg2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(isSleep ? VelaTheme.inkDark.opacity(0.6) : Color.white.opacity(0.6))
                        )
                } else if metric == .sleep {
                    Text("目标睡眠: \(VelaMinimalFormatting.duration(minutes: sleepTargetMinutes))")
                        .font(VelaTheme.caption1())
                        .fontWeight(.semibold)
                        .foregroundStyle(VelaTheme.mistGray)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(VelaTheme.inkDark.opacity(0.6)))
                } else if metric == .stress {
                    Text("目标压力: 保持平静")
                        .font(VelaTheme.caption1())
                        .fontWeight(.semibold)
                        .foregroundStyle(isSleep ? VelaTheme.mistGray : VelaTheme.fg2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isSleep ? VelaTheme.inkDark.opacity(0.6) : Color.white.opacity(0.6)))
                } else {
                    Text(metricSubtitle)
                        .font(VelaTheme.caption1())
                        .fontWeight(.semibold)
                        .foregroundStyle(isSleep ? VelaTheme.mistGray : VelaTheme.fg2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(isSleep ? VelaTheme.inkDark.opacity(0.6) : Color.white.opacity(0.6)))
                }
                
                Spacer()
                    .frame(height: 16)
            }
        }
        .frame(height: 240)
    }

    // MARK: - 2. Double Highlight Cards (Duration, Calories, Sleep, HRV etc.)
    private func doubleHighlightsSection(isSleep: Bool) -> some View {
        MetricHighlightsSection(
            isSleep: isSleep,
            metricColor: metricColor,
            leftTitle: leftTitle,
            leftIcon: leftIcon,
            leftValue: leftValue,
            leftSubtitle: leftSubtitle,
            rightTitle: rightTitle,
            rightIcon: rightIcon,
            rightValue: rightValue,
            rightSubtitle: rightSubtitle
        )
    }

    // MARK: - 3. Guidance Card
    private func guidanceSection(isSleep: Bool) -> some View {
        MetricInterpretationSection(
            title: metricRecommendation.title,
            detail: metricRecommendation.detail,
            evidence: metricRecommendation.evidence,
            symbol: metricRecommendation.symbol,
            tint: metricColor
        )
    }

    private var trustSection: some View {
        MetricTrustSection(
            direction: metricDirectionLabel,
            confidence: metricConfidenceLabel,
            coverage: metricCoverageLabel,
            updatedAt: metricUpdatedAtLabel,
            missingSummary: metricMissingSummary
        )
    }

    // MARK: - 4. Supporting Evidence




    private func supportingEvidenceSection(isSleep: Bool) -> some View {
        MetricEvidenceSection(isSleep: isSleep, items: evidenceItems)
    }

    



    // MARK: - 5. Custom Widgets & Timeline based on Metric Type
    @ViewBuilder
    private func customWidgetsSection(isSleep: Bool) -> some View {
        MetricCustomWidgetsSection(
            metric: metric,
            isSleep: isSleep,
            dashboard: dashboard,
            bedtimeHour: bedtimeHour,
            bedtimeMinute: bedtimeMinute,
            wakeHour: wakeHour,
            wakeMinute: wakeMinute,
            sleepTargetMinutes: sleepTargetMinutes,
            hasCompleteSleepTimes: hasCompleteSleepTimes,
            bedtimeText: bedtimeText,
            targetBedtimeText: targetBedtimeText,
            wakeTimeText: wakeTimeText,
            primarySleepStartText: primarySleepStartText,
            selectedFullDateText: selectedFullDateText,
            isLoadingHeartRateZones: isLoadingHeartRateZones,
            heartRateZoneSummary: heartRateZoneSummary,
            heartRateZoneRowAction: { zone, total in
                AnyView(heartRateZoneRow(zone, totalMinutes: total))
            },
            limitingFactors: limitingFactors,
            metricColor: metricColor
        )
    }

    private func timelineHeaderSection(isSleep: Bool) -> some View {
        HStack {
            Text("时间线")
                .font(VelaTheme.footnote())
                .fontWeight(.bold)
                .foregroundStyle(isSleep ? VelaTheme.inkGray : VelaTheme.muted)
            Spacer()
        }
    }

    private var strainWorkoutQueryKey: [UUID] {
        dashboard.workouts.map(\.id)
    }

    private func heartRateZoneRow(_ zone: HeartRateZoneSummary.Zone, totalMinutes: Double) -> some View {
        let share = totalMinutes > 0 ? zone.minutes / totalMinutes : 0
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(zone.title)
                    .font(VelaTheme.caption1())
                    .fontWeight(.semibold)
                    .foregroundStyle(VelaTheme.fg)
                Text(zone.detail)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.muted)
            }
            .frame(width: 68, alignment: .leading)

            GeometryReader { geometry in
                Capsule()
                    .fill(VelaTheme.accent.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(VelaTheme.accent)
                            .frame(width: geometry.size.width * share)
                    }
            }
            .frame(height: 8)

            Text("\(Int(zone.minutes.rounded())) 分钟")
                .font(VelaTheme.caption2())
                .monospacedDigit()
                .foregroundStyle(VelaTheme.muted)
                .frame(width: 52, alignment: .trailing)
        }
    }

    @MainActor
    private func loadHeartRateZones() async {
        guard !dashboard.workouts.isEmpty else {
            heartRateZoneSummary = nil
            return
        }

        isLoadingHeartRateZones = true
        defer { isLoadingHeartRateZones = false }

        let queryService = HealthKitQueryService()
        var sampleGroups: [[HeartRateSample]] = []
        for workout in dashboard.workouts {
            let samples = (try? await queryService.heartRateSamples(start: workout.start, end: workout.end)) ?? []
            if !samples.isEmpty {
                sampleGroups.append(samples)
            }
        }

        // M2 修复：心率区间与引擎/展示同源——手动 → HealthKit → wiki。
        guard let age = UserProfileSettings.age()
            ?? dashboard.extendedMetrics.age
            ?? WikiFileService.getAgeFromWiki(),
              let restingHeartRate = dashboard.recoveryMetrics.restingHeartRate else {
            heartRateZoneSummary = nil
            return
        }
        let maxHeartRate = UserProfileSettings.resolvedMaxHeartRate(
            age: age,
            wiki: WikiFileService.getMaxHeartRateFromWiki()
        )
        heartRateZoneSummary = HeartRateZoneCalculator.summarize(
            sampleGroups: sampleGroups,
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate
        )
    }

    // MARK: - 5. Trend Sparkline Cards List
    private func trendsSection(isSleep: Bool) -> some View {
        MetricTrendsSection(isSleep: isSleep, items: trendItems)
    }

    // MARK: - Dynamic Dashboard Mapping Helpers













    // MARK: - Double Highlights Mapping
















    // MARK: - Sleep Clock Helpers












    // MARK: - Guidance text mapping


    // MARK: - Trend Items Grid mapping




    private var coreMetricCoachCard: some View {
        let context = CoreMetricCoachContext.make(for: metric)
        return MetricCoachCard(
            dashboard: dashboard,
            focus: context.focus,
            suggestedQuestion: context.suggestedQuestion
        )
    }

    // MARK: - Evidence / Limiting Factors Fallback Helpers











}

enum MetricHeroPresentation: Equatable {
    case scoreGauge
    case stressTrace
    case energyReserve
    case absoluteValue
}

extension VelaMetricDetailView.MetricType {
    var isScoredHealthDomain: Bool {
        switch self {
        case .strain, .recovery, .sleep, .stress, .energy:
            return true
        case .hrv, .rhr, .weight, .bodyFat, .respiratoryRate, .bloodOxygen, .steps, .activeCalories, .activeMinutes:
            return false
        }
    }

    var heroPresentation: MetricHeroPresentation {
        switch self {
        case .strain, .recovery, .sleep:
            return .scoreGauge
        case .stress:
            return .stressTrace
        case .energy:
            return .energyReserve
        case .hrv, .rhr, .weight, .bodyFat, .respiratoryRate, .bloodOxygen, .steps, .activeCalories, .activeMinutes:
            return .absoluteValue
        }
    }
}

enum DailyActivityDetailCatalog {
    static let metrics: [VelaMetricDetailView.MetricType] = [
        .steps,
        .activeCalories,
        .activeMinutes
    ]
}

// MARK: - Digital Twin Simulator Glass Card

struct DigitalTwinSimulatorCard: View {
    @Environment(\.colorScheme) private var cs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let dashboard: DashboardSummary

    @State private var plannedStrain: Double = 12.0
    @State private var plannedHour: Double = 19.0
    @State private var targetSleepHours: Double = 7.5

    var simulationResult: DigitalTwinSimulationResult {
        let scenario = SimulationScenarioInput(
            plannedWorkoutStrain: plannedStrain,
            plannedWorkoutHour: plannedHour,
            targetSleepDurationHours: targetSleepHours
        )
        return AutonomousHealthDigitalTwin().simulateNextDay(dashboard: dashboard, scenario: scenario)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles.tv")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(VelaTheme.accent)
                        Text("明日恢复预测器")
                            .font(.system(.subheadline, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.fg)
                    }
                    Spacer()
                    Text(simulationResult.scenarioTag == "optimal" ? "最佳节奏" : (simulationResult.scenarioTag == "suboptimal_timing" ? "时机风险" : "负荷偏高"))
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(simulationResult.scenarioTag == "optimal" ? VelaTheme.systemGreen.opacity(0.18) : (simulationResult.scenarioTag == "suboptimal_timing" ? VelaTheme.systemOrange.opacity(0.18) : VelaTheme.systemRed.opacity(0.18)))
                        )
                        .foregroundStyle(simulationResult.scenarioTag == "optimal" ? VelaTheme.systemGreen : (simulationResult.scenarioTag == "suboptimal_timing" ? VelaTheme.systemOrange : VelaTheme.systemRed))
                }

                Text("滑动调整计划训练与睡眠，实时推演明早的身体恢复分")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.muted)
            }

            // Results Display Grid
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("预测次日恢复")
                        .font(.caption)
                        .foregroundStyle(VelaTheme.muted)
                    Text("\(Int(simulationResult.predictedNextDayRecovery.rounded()))%")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(simulationResult.predictedNextDayRecovery >= 66 ? VelaTheme.systemGreen : (simulationResult.predictedNextDayRecovery >= 34 ? VelaTheme.systemYellow : VelaTheme.systemRed))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).fill(VelaTheme.surface))

                VStack(alignment: .leading, spacing: 4) {
                    Text("预测次日能量")
                        .font(.caption)
                        .foregroundStyle(VelaTheme.muted)
                    Text("\(Int(simulationResult.predictedEnergyScore.rounded()))%")
                        .font(.system(.title2, design: .rounded, weight: .black))
                        .foregroundStyle(VelaTheme.accent)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).fill(VelaTheme.surface))
            }

            // Sliders Controls
            VStack(spacing: 10) {
                HStack {
                    Text("计划训练负荷: \(String(format: "%.1f", plannedStrain))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VelaTheme.fg2)
                    Spacer()
                }
                Slider(value: $plannedStrain, in: 2.0...21.0, step: 0.5)
                    .tint(VelaTheme.accent)

                HStack {
                    Text("预计训练时间: \(String(format: "%02d:00", Int(plannedHour)))")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(VelaTheme.fg2)
                    Spacer()
                }
                Slider(value: $plannedHour, in: 7.0...22.0, step: 1.0)
                    .tint(VelaTheme.accent)
            }

            // Recommendation Line
            Text(simulationResult.recommendation)
                .font(.caption)
                .foregroundStyle(VelaTheme.fg2)
                .lineLimit(2)
                .padding(.top, 2)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(VelaTheme.borderSoft, lineWidth: 0.5)
        )
    }
}

// MARK: - Long-term health trend（三年健康轨迹）

/// 长期趋势纯计算：按月均值聚合 + 今年 vs 去年同期对齐比较。
enum LongTermTrendMath {
    /// 逐日值 → 逐月均值（键为当月 1 号）。
    static func monthlyAverages(
        values: [(date: Date, value: Double)],
        calendar: Calendar = .current
    ) -> [(date: Date, value: Double)] {
        var sums: [Date: Double] = [:]
        var counts: [Date: Int] = [:]
        for entry in values {
            let monthKey = monthStart(of: entry.date, calendar: calendar)
            sums[monthKey, default: 0] += entry.value
            counts[monthKey, default: 0] += 1
        }
        return sums.keys.sorted().compactMap { key in
            guard let count = counts[key], count > 0 else { return nil }
            return (date: key, value: sums[key, default: 0] / Double(count))
        }
    }

    /// 今年（1 月 1 日至今天）与去年同对齐时段的均值；不足 7 天样本返回 nil。
    static func samePeriodComparison(
        values: [(date: Date, value: Double)],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> (thisYear: Double?, lastYear: Double?) {
        let thisYearStart = yearStart(of: today, calendar: calendar)
        let lastYearStart = yearStart(
            of: calendar.date(byAdding: .year, value: -1, to: today) ?? today,
            calendar: calendar
        )
        let thisYearEnd = calendar.startOfDay(for: today)
        let lastYearEnd = calendar.date(byAdding: .year, value: -1, to: thisYearEnd) ?? thisYearEnd

        func mean(_ include: (Date) -> Bool) -> Double? {
            let vals = values.filter { include($0.date) }.map(\.value)
            guard vals.count >= 7 else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }
        return (
            thisYear: mean { $0 >= thisYearStart && $0 <= thisYearEnd },
            lastYear: mean { $0 >= lastYearStart && $0 <= lastYearEnd }
        )
    }

    private static func monthStart(of date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: date)
        return calendar.date(from: components) ?? date
    }

    private static func yearStart(of date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year], from: date)
        return calendar.date(from: components) ?? date
    }
}

/// 三年健康轨迹：月均值曲线（点按标数值/拖动查看）+ 今年 vs 去年同期。
/// 数据源 = 回填后的 DailyHealthSummaryRecord 原始字段。
struct LongTermHealthTrendView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var cs

    @State private var metric = LongTermMetric.restingHeartRate
    @State private var monthlySeries: [(date: Date, value: Double)] = []
    @State private var points: [CGPoint] = []
    @State private var values: [Double] = []
    @State private var dates: [Date] = []
    @State private var comparison: (thisYear: Double?, lastYear: Double?) = (nil, nil)
    @State private var cachedRecords: [DailyHealthSummaryRecord] = []
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("三年健康轨迹")
                        .font(.system(.title, design: .default, weight: .semibold))
                        .tracking(-0.65)
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text("来自 Apple 健康的历史原始数据，按月均值呈现")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .padding(.bottom, 4)

                metricPicker

                if let loadError {
                    VelaStateCard(
                        state: .error,
                        message: loadError,
                        actionTitle: "重试",
                        action: { Task { await load() } }
                    )
                }

                chartCard

                comparisonCard

                VStack(alignment: .leading, spacing: 6) {
                    Label("数据来自本机回填", systemImage: "lock")
                        .font(.system(.caption, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text("只写入每日原始汇总（心率/睡眠/步数/体重等），不伪造旧日评分。历史不足时，可在「设置 → 三年 Apple 健康回填」运行回填。")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(3)
                }
                .padding(14)
                .background(VelaTheme.rhythmMist.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, VelaTheme.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 44)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas)
        .navigationTitle("长期趋势")
        .velaRhythmDetailChrome()
        .task { await load() }
        .onChange(of: metric) { _, _ in rebuild(from: cachedRecords) }
    }

    private var metricPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LongTermMetric.allCases) { item in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            metric = item
                        }
                    } label: {
                        Text(item.title)
                            .font(.system(.caption, design: .default, weight: .semibold))
                            .foregroundStyle(metric == item ? VelaTheme.rhythmDeepOn : VelaTheme.rhythmInkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                metric == item ? VelaTheme.rhythmDeep : VelaTheme.rhythmMist.opacity(0.7),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(metric.title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text("近三年 · 月均值")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                Spacer()
                Text(metric.unit)
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            if points.count > 1 {
                AreaChartCurveView(points: points, values: values, dates: dates)
                    .frame(height: 150)
                    .padding(.top, 6)

                HStack {
                    Text("三年前")
                    Spacer()
                    Text("一年半前")
                    Spacer()
                    Text("现在")
                }
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .padding(.top, 6)
            } else {
                emptyState
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
            Text("历史数据不足。可在「设置 → 三年 Apple 健康回填」运行回填，再回来看轨迹。")
                .font(.system(.footnote, design: .default))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 18)
    }

    private var comparisonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("今年 vs 去年同期")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text("1 月 1 日至今 · 对齐时段")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            if let this = comparison.thisYear, let last = comparison.lastYear {
                HStack(spacing: 0) {
                    comparisonMetric(title: "今年", value: format(this))
                    Rectangle()
                        .fill(VelaTheme.rhythmMist)
                        .frame(width: 1, height: 44)
                        .padding(.horizontal, 16)
                    comparisonMetric(title: "去年", value: format(last))
                    Spacer(minLength: 10)
                    deltaChip(delta: this - last)
                }
            } else {
                Text("回填后出现；对比需要两段各至少 7 天样本。")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
    }

    private func comparisonMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(.caption2, design: .default, weight: .medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Text(value)
                .font(.system(.callout, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
        }
    }

    private func deltaChip(delta: Double) -> some View {
        let improved = metric.improvementIsPositive ? delta > 0 : delta < 0
        let text = String(format: "%+.0f", delta)
        return Text("\(text) \(metric.unit)")
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(improved ? VelaTheme.rhythmDeep : VelaTheme.rhythmWarm)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background((improved ? VelaTheme.rhythmDeep : VelaTheme.rhythmWarm).opacity(0.12), in: Capsule())
    }

    private func format(_ value: Double) -> String {
        if metric == .steps {
            return value >= 1000 ? String(format: "%.1fk", value / 1000) : "\(Int(value.rounded()))"
        }
        return value.formatted(.number.precision(.fractionLength(metric == .sleep ? 1 : 0)))
    }

    private func load() async {
        do {
            let all = try modelContext.fetch(
                FetchDescriptor<DailyHealthSummaryRecord>(
                    sortBy: [SortDescriptor(\.date, order: .forward)]
                )
            )
            cachedRecords = all
            loadError = nil
            rebuild(from: all)
        } catch {
            loadError = AppLanguage.stored.isChinese
                ? "长期健康记录暂时无法读取，已保留上次结果。"
                : "Long-term health records are temporarily unavailable. The last result is still shown."
        }
    }

    private func rebuild(from records: [DailyHealthSummaryRecord]) {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .year, value: -3, to: Date()) ?? Date()
        let pairs = records
            .filter { $0.date >= cutoff }
            .compactMap { record -> (date: Date, value: Double)? in
                guard let value = metric.value(from: record), value > 0 else { return nil }
                return (record.date, value)
            }
        let monthly = LongTermTrendMath.monthlyAverages(values: pairs, calendar: calendar)
        monthlySeries = monthly
        values = monthly.map(\.value)
        dates = monthly.map(\.date)

        let minV = values.min() ?? 0
        let maxV = values.max() ?? 1
        let diff = maxV - minV
        var built: [CGPoint] = []
        for (index, value) in values.enumerated() {
            let x = values.count > 1 ? Double(index) / Double(values.count - 1) : 0.5
            let normalized = diff > 0 ? (value - minV) / diff : 0.5
            let y = 0.9 - (normalized * 0.78)
            built.append(CGPoint(x: x, y: y))
        }
        points = built
        comparison = LongTermTrendMath.samePeriodComparison(values: pairs, calendar: calendar)
    }
}

enum LongTermMetric: String, CaseIterable, Identifiable {
    case restingHeartRate
    case hrv
    case sleep
    case weight
    case bodyFat
    case steps
    case activeCalories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restingHeartRate: return "静息心率"
        case .hrv: return "HRV"
        case .sleep: return "睡眠时长"
        case .weight: return "体重"
        case .bodyFat: return "体脂率"
        case .steps: return "步数"
        case .activeCalories: return "活动能量"
        }
    }

    var unit: String {
        switch self {
        case .restingHeartRate: return "bpm"
        case .hrv: return "ms"
        case .sleep: return "小时"
        case .weight: return "kg"
        case .bodyFat: return "%"
        case .steps: return "步"
        case .activeCalories: return "kcal"
        }
    }

    /// 数值变大是否代表变好（用于同比色）。
    var improvementIsPositive: Bool {
        switch self {
        case .restingHeartRate: return false
        case .hrv: return true
        case .sleep: return true
        case .weight: return false
        case .bodyFat: return false
        case .steps: return true
        case .activeCalories: return true
        }
    }

    func value(from record: DailyHealthSummaryRecord) -> Double? {
        switch self {
        case .restingHeartRate: return record.restingHeartRate
        case .hrv: return record.hrvAverage
        case .sleep: return record.sleepHours
        case .weight: return record.bodyWeight
        case .bodyFat: return record.bodyFatPercent
        case .steps: return record.steps
        case .activeCalories: return record.activeCalories
        }
    }
}
