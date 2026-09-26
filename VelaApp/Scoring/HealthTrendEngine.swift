import Foundation

/// Pure value input for `HealthTrendEngine`.
///
/// Adapters own loading and persistence. They should pass the widest history
/// available (up to `HealthTrendHorizon.threeYears.windowDays`) when a three-
/// year finding is desired. Missing values remain `nil`; the engine never
/// coerces them to zero or silently substitutes a shorter horizon.
struct HealthTrendInput: Sendable {
    var snapshots: [DailyHealthSnapshot]
    var longTermBaselines: LongTermBaselineReport?

    init(
        snapshots: [DailyHealthSnapshot] = [],
        longTermBaselines: LongTermBaselineReport? = nil
    ) {
        self.snapshots = snapshots
        self.longTermBaselines = longTermBaselines
    }
}

/// Adapter-owned seam for supplying historical trend evidence.
///
/// This protocol intentionally has no persistence or HealthKit requirements:
/// a caller can implement it over SwiftData, a test fixture, or a remote
/// cache, then hand the resulting value to the pure scoring engine.
protocol HealthTrendHistoryProvider: Sendable {
    func history(
        endingAt selectedDay: Date,
        calendar: Calendar
    ) -> HealthTrendInput
}

/// Small convenience provider for previews and deterministic tests.
struct StaticHealthTrendHistoryProvider: HealthTrendHistoryProvider {
    let input: HealthTrendInput

    init(input: HealthTrendInput) {
        self.input = input
    }

    func history(
        endingAt selectedDay: Date,
        calendar: Calendar
    ) -> HealthTrendInput {
        input
    }
}

/// Compatibility spelling for adapters that model the seam as a history
/// input rather than a generic trend input.
typealias HealthTrendHistoryInput = HealthTrendInput

// MARK: - Health Trend Engine

struct HealthTrendEngine: Sendable {

    init() {}

    /// Analyze a caller-provided history value.
    ///
    /// The scoring module deliberately accepts value-typed history rather
    /// than fetching persistence itself. Adapters can therefore provide a
    /// full three-year snapshot window (or a pre-computed long-term report)
    /// without coupling this engine to SwiftData or HealthKit.
    func analyze(
        dashboard: DashboardSummary,
        input: HealthTrendInput,
        selectedDay: Date = Date(),
        calendar: Calendar = .current
    ) -> (brief: PersonalHealthBrief, findings: [HealthTrendFinding]) {
        analyze(
            dashboard: dashboard,
            snapshots: input.snapshots,
            longTermBaselines: input.longTermBaselines,
            today: selectedDay,
            calendar: calendar
        )
    }

    /// Analyze history obtained through an adapter-owned provider seam.
    ///
    /// `history(endingAt:calendar:)` is synchronous and pure from the
    /// engine's perspective; a persistence adapter may load and construct its
    /// `HealthTrendInput` before calling this method.
    func analyze(
        dashboard: DashboardSummary,
        historyProvider: any HealthTrendHistoryProvider,
        selectedDay: Date = Date(),
        calendar: Calendar = .current
    ) -> (brief: PersonalHealthBrief, findings: [HealthTrendFinding]) {
        let input = historyProvider.history(endingAt: selectedDay, calendar: calendar)
        return analyze(
            dashboard: dashboard,
            input: input,
            selectedDay: selectedDay,
            calendar: calendar
        )
    }

    /// Short label alias for call sites that already use `provider` as their
    /// dependency name. Both entry points share the same deterministic core.
    func analyze(
        dashboard: DashboardSummary,
        provider: any HealthTrendHistoryProvider,
        selectedDay: Date = Date(),
        calendar: Calendar = .current
    ) -> (brief: PersonalHealthBrief, findings: [HealthTrendFinding]) {
        analyze(
            dashboard: dashboard,
            historyProvider: provider,
            selectedDay: selectedDay,
            calendar: calendar
        )
    }

    func analyze(
        dashboard: DashboardSummary,
        snapshots: [DailyHealthSnapshot],
        longTermBaselines: LongTermBaselineReport?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> (brief: PersonalHealthBrief, findings: [HealthTrendFinding]) {
        let hasCoreData = dashboard.recovery.hasData || dashboard.sleepScore.hasData || dashboard.recoveryMetrics.hrvMilliseconds != nil || dashboard.recoveryMetrics.restingHeartRate != nil
        guard hasCoreData else {
            let emptyBrief = PersonalHealthBrief.empty(date: today)
            return (emptyBrief, [])
        }

        let sortedSnapshots = Self.deterministicallySortedSnapshots(snapshots)

        // Perf: build the four horizon windows in one linear pass so metric
        // computation never re-scans the full snapshot array. Windows preserve
        // the sorted order of `sortedSnapshots`.
        let horizonWindows: [HealthTrendHorizon: [DailyHealthSnapshot]] = Self.makeHorizonWindows(
            snapshots: sortedSnapshots,
            today: today,
            calendar: calendar
        )

        var allFindings: [HealthTrendFinding] = []

        // Compute findings for each core metric across all 4 horizons
        let metrics: [CoreHealthMetric] = [
            .hrv, .restingHeartRate, .sleepDuration, .sleepScore, .recovery,
            .strain, .stress, .energy, .respiratoryRate,
            .oxygenSaturation, .bodyWeight, .bodyFat, .steps, .activeCalories
        ]

        for metric in metrics {
            let findingsForMetric = computeFindings(
                for: metric,
                dashboard: dashboard,
                horizonWindows: horizonWindows,
                longTermBaselines: longTermBaselines,
                today: today,
                calendar: calendar
            )
            allFindings.append(contentsOf: findingsForMetric)
        }

        let notableChanges = rankedNotableChanges(from: allFindings)
        let stableSignals = allFindings.filter { !$0.isNotable && $0.isAvailable && $0.horizon == .thirtyDays && $0.currentValue != nil }

        let overallState = determineOverallState(
            dashboard: dashboard,
            notableChanges: notableChanges,
            snapshots: sortedSnapshots
        )

        let headline = generateHeadline(
            state: overallState,
            dashboard: dashboard,
            notableChanges: notableChanges
        )

        let subheadline = generateSubheadline(
            state: overallState,
            dashboard: dashboard,
            notableChanges: notableChanges,
            stableSignals: stableSignals
        )

        let possibleDrivers = inferDrivers(
            dashboard: dashboard,
            notableChanges: notableChanges
        )

        let actionEvaluation = evaluateAction(
            state: overallState,
            dashboard: dashboard,
            notableChanges: notableChanges
        )

        let brief = PersonalHealthBrief(
            date: today,
            overallState: overallState,
            headline: headline,
            subheadline: subheadline,
            notableChanges: notableChanges,
            stableSignals: stableSignals,
            multiscaleTrends: allFindings,
            possibleDrivers: possibleDrivers,
            confidence: dashboard.bodyState.confidence,
            confidenceLabel: confidenceText(for: dashboard.bodyState.confidence),
            needsAction: actionEvaluation.needsAction,
            suggestedActionCategory: actionEvaluation.category,
            actionHeadline: actionEvaluation.headline,
            actionDetail: actionEvaluation.detail,
            lifestyleSuggestions: actionEvaluation.lifestyleSuggestions,
            generatedAt: today
        )

        return (brief, allFindings)
    }

    // MARK: - Metric Findings Computation

    /// Swift's `sorted(by:)` is not stable. Snapshot dates are normally
    /// unique, but import/reconciliation can temporarily expose duplicate
    /// dates. Tie-break on creation time and metric payload so the temporal
    /// half-window calculation is independent of fetch order.
    private static func deterministicallySortedSnapshots(
        _ snapshots: [DailyHealthSnapshot]
    ) -> [DailyHealthSnapshot] {
        snapshots.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
            let lhsValues = Self.snapshotTieBreakKey(lhs)
            let rhsValues = Self.snapshotTieBreakKey(rhs)
            if lhsValues != rhsValues { return lhsValues < rhsValues }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Compare duplicate-date snapshots by their metric payload before using
    /// UUID as a final tie-break. This keeps semantically equivalent fixture
    /// arrays deterministic even when each fixture is reconstructed afresh.
    private static func snapshotTieBreakKey(_ snapshot: DailyHealthSnapshot) -> String {
        [
            snapshot.hrvAverage,
            snapshot.restingHeartRate,
            snapshot.sleepHours,
            snapshot.sleepScore,
            snapshot.recoveryScore,
            snapshot.strainScore,
            snapshot.stressIndex,
            snapshot.currentEnergy ?? snapshot.energyBank,
            snapshot.respiratoryRate,
            snapshot.oxygenSaturation,
            snapshot.bodyWeight,
            snapshot.bodyFatPercent,
            snapshot.steps,
            snapshot.activeCalories
        ]
        .map { value in value.map { String($0.bitPattern) } ?? "_" }
        .joined(separator: "|")
    }

    /// Builds the four horizon windows (7d / 30d / 180d / 1095d) from the
    /// already-sorted snapshot array in a single linear pass.
    private static func makeHorizonWindows(
        snapshots: [DailyHealthSnapshot],
        today: Date,
        calendar: Calendar
    ) -> [HealthTrendHorizon: [DailyHealthSnapshot]] {
        let horizons: [(HealthTrendHorizon, Int)] = [
            (.sevenDays, 7),
            (.thirtyDays, 30),
            (.sixMonths, 180),
            (.threeYears, HealthTrendHorizon.threeYears.windowDays)
        ]
        let starts = horizons.map { (horizon, days) in
            (horizon, calendar.date(byAdding: .day, value: -days, to: today) ?? today)
        }
        var result: [HealthTrendHorizon: [DailyHealthSnapshot]] = [:]
        for snap in snapshots where snap.date <= today {
            for (horizon, start) in starts where snap.date >= start {
                result[horizon, default: []].append(snap)
            }
        }
        return result
    }

    private func computeFindings(
        for metric: CoreHealthMetric,
        dashboard: DashboardSummary,
        horizonWindows: [HealthTrendHorizon: [DailyHealthSnapshot]],
        longTermBaselines: LongTermBaselineReport?,
        today: Date,
        calendar: Calendar
    ) -> [HealthTrendFinding] {
        var results: [HealthTrendFinding] = []

        let currentValue = currentValue(for: metric, dashboard: dashboard)
        let formattedCurrent = formatValue(currentValue, metric: metric)

        // 7-day Horizon (requires >= 4 samples)
        let finding7d = computeHorizonFinding(
            metric: metric,
            horizon: .sevenDays,
            days: 7,
            currentValue: currentValue,
            currentFormatted: formattedCurrent,
            windowSnapshots: horizonWindows[.sevenDays] ?? [],
            today: today,
            calendar: calendar
        )
        results.append(finding7d)

        // 30-day Horizon (requires >= 14 samples)
        let finding30d = computeHorizonFinding(
            metric: metric,
            horizon: .thirtyDays,
            days: 30,
            currentValue: currentValue,
            currentFormatted: formattedCurrent,
            windowSnapshots: horizonWindows[.thirtyDays] ?? [],
            today: today,
            calendar: calendar
        )
        results.append(finding30d)

        // 6-month Horizon (requires >= 60 samples, ~180 days)
        let finding6m = computeHorizonFinding(
            metric: metric,
            horizon: .sixMonths,
            days: 180,
            currentValue: currentValue,
            currentFormatted: formattedCurrent,
            windowSnapshots: horizonWindows[.sixMonths] ?? [],
            today: today,
            calendar: calendar
        )
        results.append(finding6m)

        // 3-Year Horizon (from longTermBaselines)
        if let ltMetric = longTermMetric(for: metric),
           let ltBaseline = longTermBaselines?.baselines[ltMetric],
           ltBaseline.sampleCount >= 60,
           let pMedian = ltBaseline.threeYearMedian,
           let cur = currentValue {
            let deviation = pMedian > 0 ? (cur - pMedian) / pMedian * 100 : 0
            let direction: HealthTrendDirection = {
                if abs(deviation) < 3.5 { return .stable }
                switch metric.polarity {
                case .higherIsBetter:
                    return deviation > 0 ? .improving : .declining
                case .lowerIsBetter:
                    return deviation > 0 ? .declining : .improving
                case .contextual:
                    return deviation > 0 ? .elevated : .suppressed
                }
            }()

            let percentile = calculatePercentilePosition(value: cur, baseline: ltBaseline)
            let devSummary = abs(deviation) < 3.5 ? "与三年基线基本持平" : (deviation > 0 ? String(format: "较三年基线偏高 %.1f%%", deviation) : String(format: "较三年基线偏低 %.1f%%", abs(deviation)))
            let trendSummary = generate3YSummary(
                metric: metric,
                cur: cur,
                median: pMedian,
                percentile: percentile,
                trendLabel: ltBaseline.trendLabel
            )
            let summary = "\(devSummary)，\(trendSummary)"
            let isNotable = abs(deviation) >= 12.0

            let valueDirection: TrendValueDirection
            if abs(deviation) < 3.5 {
                valueDirection = .stable
            } else if deviation > 0 {
                valueDirection = .rising
            } else {
                valueDirection = .falling
            }

            let assessment: TrendAssessment
            switch metric.polarity {
            case .higherIsBetter:
                assessment = valueDirection == .stable
                    ? .neutral
                    : (valueDirection == .rising ? .favorable : .unfavorable)
            case .lowerIsBetter:
                assessment = valueDirection == .stable
                    ? .neutral
                    : (valueDirection == .rising ? .unfavorable : .favorable)
            case .contextual:
                assessment = .neutral
            }

            results.append(HealthTrendFinding(
                metric: metric,
                horizon: .threeYears,
                direction: direction,
                valueDirection: valueDirection,
                assessment: assessment,
                currentValue: cur,
                currentValueFormatted: formattedCurrent,
                baselineValue: pMedian,
                baselineValueFormatted: formatValue(pMedian, metric: metric),
                currentDeviationValue: cur - pMedian,
                currentDeviationPercent: deviation,
                temporalTrendDelta: nil,
                temporalTrendDeltaPercent: nil,
                historicalPercentile: percentile,
                sampleCount: ltBaseline.sampleCount,
                requiredSampleCount: 60,
                isAvailable: true,
                confidence: .high,
                deviationSummary: devSummary,
                temporalTrendSummary: trendSummary,
                summary: summary,
                isNotable: isNotable
            ))
        } else {
            // Derived scores do not have a LongTermBaselineMetric entry. Their
            // persisted daily series is still valid evidence for a three-year
            // personal baseline, so compute from snapshots instead of silently
            // making Recovery / Sleep Score / Strain / Stress / Energy absent.
            results.append(computeHorizonFinding(
                metric: metric,
                horizon: .threeYears,
                days: HealthTrendHorizon.threeYears.windowDays,
                currentValue: currentValue,
                currentFormatted: formattedCurrent,
                windowSnapshots: horizonWindows[.threeYears] ?? [],
                today: today,
                calendar: calendar
            ))
        }

        return results
    }

    /// Briefs expose one finding per metric. The ranking is deliberately
    /// deterministic: shorter horizons are more actionable, then larger
    /// percentage movement wins, then the canonical metric order breaks ties.
    /// This prevents the same metric from occupying the brief once per horizon
    /// while keeping the headline stable across fetch/order changes.
    private func rankedNotableChanges(from findings: [HealthTrendFinding]) -> [HealthTrendFinding] {
        let horizonRank: [HealthTrendHorizon: Int] = [
            .sevenDays: 0,
            .thirtyDays: 1,
            .sixMonths: 2,
            .threeYears: 3
        ]
        let metricRank = Dictionary(uniqueKeysWithValues: CoreHealthMetric.allCases.enumerated().map { ($1, $0) })

        let ranked = findings
            .filter { $0.isNotable && $0.isAvailable }
            .sorted { lhs, rhs in
                let lhsHorizon = horizonRank[lhs.horizon, default: Int.max]
                let rhsHorizon = horizonRank[rhs.horizon, default: Int.max]
                if lhsHorizon != rhsHorizon { return lhsHorizon < rhsHorizon }

                let lhsMagnitude = max(abs(lhs.currentDeviationPercent ?? 0), abs(lhs.temporalTrendDeltaPercent ?? 0))
                let rhsMagnitude = max(abs(rhs.currentDeviationPercent ?? 0), abs(rhs.temporalTrendDeltaPercent ?? 0))
                if lhsMagnitude != rhsMagnitude { return lhsMagnitude > rhsMagnitude }

                return metricRank[lhs.metric, default: Int.max] < metricRank[rhs.metric, default: Int.max]
            }

        var seenMetrics = Set<CoreHealthMetric>()
        return ranked.filter { seenMetrics.insert($0.metric).inserted }
    }

    private func computeHorizonFinding(
        metric: CoreHealthMetric,
        horizon: HealthTrendHorizon,
        days: Int,
        currentValue: Double?,
        currentFormatted: String,
        windowSnapshots: [DailyHealthSnapshot],
        today: Date,
        calendar: Calendar
    ) -> HealthTrendFinding {
        // `windowSnapshots` arrives pre-filtered for this horizon and keeps the
        // sorted order of the source snapshot array, so no re-filter or sort is
        // needed here.
        let windowValuesWithDate: [(date: Date, value: Double)] = windowSnapshots.compactMap { snap in
            guard let val = value(for: metric, snapshot: snap) else { return nil }
            return (date: snap.date, value: val)
        }

        let sampleCount = windowValuesWithDate.count
        guard sampleCount >= horizon.requiredSampleCount else {
            return HealthTrendFinding.unavailable(metric: metric, horizon: horizon, sampleCount: sampleCount)
        }

        // Span & recency verification for multi-month / multi-year horizons
        if horizon == .sixMonths {
            guard let earliest = windowValuesWithDate.first?.date,
                  let latest = windowValuesWithDate.last?.date else {
                return HealthTrendFinding.unavailable(metric: metric, horizon: horizon, sampleCount: sampleCount)
            }
            let spanDays = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: latest)).day ?? 0)
            let daysFromToday = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: latest), to: calendar.startOfDay(for: today)).day ?? 0)
            guard spanDays >= 90, daysFromToday <= 14 else {
                return HealthTrendFinding.unavailable(metric: metric, horizon: horizon, sampleCount: sampleCount)
            }
        } else if horizon == .threeYears {
            guard let earliest = windowValuesWithDate.first?.date,
                  let latest = windowValuesWithDate.last?.date else {
                return HealthTrendFinding.unavailable(metric: metric, horizon: horizon, sampleCount: sampleCount)
            }
            let spanDays = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: earliest), to: calendar.startOfDay(for: latest)).day ?? 0)
            let daysFromToday = abs(calendar.dateComponents([.day], from: calendar.startOfDay(for: latest), to: calendar.startOfDay(for: today)).day ?? 0)
            guard spanDays >= 365, daysFromToday <= 30 else {
                return HealthTrendFinding.unavailable(metric: metric, horizon: horizon, sampleCount: sampleCount)
            }
        }

        let rawValues = windowValuesWithDate.map(\.value)
        guard let baselineMedian = median(of: rawValues) else {
            return HealthTrendFinding.unavailable(metric: metric, horizon: horizon, sampleCount: sampleCount)
        }

        // Temporal Trend: Half-window median comparison
        let halfCount = sampleCount / 2
        let firstHalfValues = Array(rawValues.prefix(halfCount))
        let secondHalfValues = Array(rawValues.suffix(sampleCount - halfCount))

        if horizon == .sixMonths && (firstHalfValues.count < 15 || secondHalfValues.count < 15) {
            return HealthTrendFinding.unavailable(metric: metric, horizon: horizon, sampleCount: sampleCount)
        }

        let m1 = median(of: firstHalfValues) ?? baselineMedian
        let m2 = median(of: secondHalfValues) ?? baselineMedian
        let trendDelta = m2 - m1
        let trendDeltaPercent = m1 > 0 ? (trendDelta / m1) * 100 : 0

        // Current Baseline Deviation
        let curDev: Double? = currentValue.map { $0 - baselineMedian }
        let curDevPercent: Double? = currentValue.flatMap { baselineMedian > 0 ? (($0 - baselineMedian) / baselineMedian) * 100 : 0 }

        // Decouple value direction (numerical) from assessment (health meaning)
        let trendThresholdPercent: Double = 3.5
        let valueDirection: TrendValueDirection
        if abs(trendDeltaPercent) < trendThresholdPercent {
            valueDirection = .stable
        } else if trendDeltaPercent > 0 {
            valueDirection = .rising
        } else {
            valueDirection = .falling
        }

        let assessment: TrendAssessment
        let direction: HealthTrendDirection
        if abs(trendDeltaPercent) < trendThresholdPercent {
            assessment = .neutral
            direction = .stable
        } else if trendDeltaPercent > 0 {
            switch metric.polarity {
            case .higherIsBetter:
                assessment = .favorable
                direction = .improving
            case .lowerIsBetter:
                assessment = .unfavorable
                direction = .declining
            case .contextual:
                assessment = .neutral
                direction = .elevated
            }
        } else {
            switch metric.polarity {
            case .higherIsBetter:
                assessment = .unfavorable
                direction = .declining
            case .lowerIsBetter:
                assessment = .favorable
                direction = .improving
            case .contextual:
                assessment = .neutral
                direction = .suppressed
            }
        }

        // Deviation Summary
        let devSummary: String
        if let devPct = curDevPercent {
            if abs(devPct) < 3.5 {
                devSummary = "较基线基本持平"
            } else if devPct > 0 {
                devSummary = String(format: "较基线偏高 %.1f%%", devPct)
            } else {
                devSummary = String(format: "较基线偏低 %.1f%%", abs(devPct))
            }
        } else {
            devSummary = "基线中位数 \(formatValue(baselineMedian, metric: metric))"
        }

        // Temporal Trend Summary
        let temporalSummary: String
        if abs(trendDeltaPercent) < trendThresholdPercent {
            temporalSummary = "\(horizon.detailedTitle)整体平稳"
        } else if trendDeltaPercent > 0 {
            temporalSummary = String(format: "\(horizon.detailedTitle)中位数上升 +%.1f%%", trendDeltaPercent)
        } else {
            temporalSummary = String(format: "\(horizon.detailedTitle)中位数下降 -%.1f%%", abs(trendDeltaPercent))
        }

        let isNotable = (curDevPercent.map { abs($0) >= 12.0 } ?? false) || abs(trendDeltaPercent) >= 10.0

        let summaryText: String
        if let devPct = curDevPercent, abs(devPct) >= 5.0 {
            summaryText = "\(devSummary)，\(temporalSummary)"
        } else {
            summaryText = temporalSummary
        }

        return HealthTrendFinding(
            metric: metric,
            horizon: horizon,
            direction: direction,
            valueDirection: valueDirection,
            assessment: assessment,
            currentValue: currentValue,
            currentValueFormatted: formatValue(currentValue, metric: metric),
            baselineValue: baselineMedian,
            baselineValueFormatted: formatValue(baselineMedian, metric: metric),
            currentDeviationValue: curDev,
            currentDeviationPercent: curDevPercent,
            temporalTrendDelta: trendDelta,
            temporalTrendDeltaPercent: trendDeltaPercent,
            historicalPercentile: nil,
            sampleCount: sampleCount,
            requiredSampleCount: horizon.requiredSampleCount,
            isAvailable: true,
            confidence: sampleCount >= horizon.requiredSampleCount * 2 ? .high : .medium,
            deviationSummary: devSummary,
            temporalTrendSummary: temporalSummary,
            summary: summaryText,
            isNotable: isNotable
        )
    }

    // MARK: - State & Narrative Synthesizers

    private func determineOverallState(
        dashboard: DashboardSummary,
        notableChanges: [HealthTrendFinding],
        snapshots: [DailyHealthSnapshot]
    ) -> BodyGeneralState {
        guard let recoveryScore = dashboard.recovery.value else {
            // Recovery score is absent: check sleep and stress without assuming 0
            if let sleepScore = dashboard.sleepScore.value {
                if sleepScore >= 75 { return .stable }
                if sleepScore < 50 { return .recovering }
            }
            return .insufficientData
        }

        let hrvFinding = notableChanges.first { $0.metric == .hrv }
        let rhrFinding = notableChanges.first { $0.metric == .restingHeartRate }
        let sleepFinding = notableChanges.first { $0.metric == .sleepScore }
            ?? notableChanges.first { $0.metric == .sleepDuration }

        if recoveryScore < 35 || (hrvFinding?.direction == .declining && rhrFinding?.direction == .declining) {
            return .recovering
        }

        // Strain is 0-100 scale: high strain is >= 70
        if let strainScore = dashboard.strain.value, strainScore >= 70 {
            return .strained
        }

        if recoveryScore >= 67 && hrvFinding?.direction != .declining && rhrFinding?.direction != .declining {
            return .optimal
        }
        if sleepFinding?.direction == .declining && recoveryScore < 50 {
            return .strained
        }

        return .stable
    }

    private func generateHeadline(
        state: BodyGeneralState,
        dashboard: DashboardSummary,
        notableChanges: [HealthTrendFinding]
    ) -> String {
        switch state {
        case .optimal:
            return "身体机能处于良好水平"
        case .stable:
            if notableChanges.isEmpty {
                return "身体状态总体稳定"
            } else if let notable = notableChanges.first {
                return "\(notable.metric.shortTitle)出现短期波动，整体可控"
            } else {
                return "身体状态总体稳定"
            }
        case .strained:
            return "生理负荷有所累积，建议关注恢复"
        case .recovering:
            return "身体处于恢复调节状态"
        case .insufficientData:
            return "正在建立个人健康基线"
        }
    }

    private func generateSubheadline(
        state: BodyGeneralState,
        dashboard: DashboardSummary,
        notableChanges: [HealthTrendFinding],
        stableSignals: [HealthTrendFinding]
    ) -> String {
        var parts: [String] = []

        if let rec = dashboard.recovery.value {
            parts.append("恢复 \(Int(rec.rounded()))")
        }

        if let clause = notableDeviationClause(notableChanges) {
            parts.append(clause)
        }

        if parts.isEmpty {
            return "各项核心体征平稳运行在个人基线范围内。"
        }
        return parts.joined(separator: "，") + "。"
    }

    /// One already-computed deviation. Sleep duration may be named when the
    /// sleep score itself is not notable; it never replaces that score.
    private func notableDeviationClause(_ notableChanges: [HealthTrendFinding]) -> String? {
        if let sleep = notableChanges.first(where: { $0.metric == .sleepScore }),
           sleep.direction == .declining {
            return "近两周睡眠得分较个人基线有所下降"
        }
        if let duration = notableChanges.first(where: { $0.metric == .sleepDuration }),
           duration.direction == .declining {
            return "近两周睡眠时长较平时基线略有减少"
        }
        if let hrv = notableChanges.first(where: { $0.metric == .hrv }) {
            if hrv.direction == .improving {
                return "HRV 呈现向上改善走势"
            }
            if hrv.direction == .declining {
                return "HRV 较近期基线偏低"
            }
        }
        if let rhr = notableChanges.first(where: { $0.metric == .restingHeartRate }),
           rhr.direction == .declining {
            return "静息心率较基线略有升高"
        }
        return nil
    }

    private func inferDrivers(
        dashboard: DashboardSummary,
        notableChanges: [HealthTrendFinding]
    ) -> [String] {
        var drivers: [String] = []

        let hrvLow = notableChanges.contains { $0.metric == .hrv && $0.direction == .declining }
        let rhrHigh = notableChanges.contains { $0.metric == .restingHeartRate && $0.direction == .declining }
        let sleepScoreLow = notableChanges.contains {
            $0.metric == .sleepScore && $0.direction == .declining
        }
        let sleepDurationLow = notableChanges.contains {
            $0.metric == .sleepDuration && $0.direction == .declining
        }
        let strainHigh = dashboard.strain.value.map { $0 >= 70 } ?? false

        if hrvLow && rhrHigh {
            drivers.append("观察到 HRV 偏低与静息心率升高在近期协同出现，提示生理恢复负荷有所累积")
        }
        if sleepScoreLow {
            drivers.append("近期睡眠得分偏离个人基线，可能与恢复感受变化相关")
        } else if sleepDurationLow {
            drivers.append("近期睡眠时长偏离个人基线，可能与恢复感受变化相关")
        }
        if strainHigh {
            drivers.append("近期日常活动与训练负荷相对较高，构成当前体征波动的潜在背景")
        }

        return drivers
    }

    private struct ActionEval {
        var needsAction: Bool
        var category: HealthActionCategory
        var headline: String?
        var detail: String?
        var lifestyleSuggestions: [String]
    }

    private func evaluateAction(
        state: BodyGeneralState,
        dashboard: DashboardSummary,
        notableChanges: [HealthTrendFinding]
    ) -> ActionEval {
        switch state {
        case .optimal:
            return ActionEval(
                needsAction: false,
                category: .training,
                headline: "机能充沛",
                detail: "体征处于基线良好区间，可按个人节奏正常开展日常工作与训练活动。",
                lifestyleSuggestions: ["保持规律作息与水分摄入"]
            )
        case .stable:
            return ActionEval(
                needsAction: false,
                category: .none,
                headline: "节奏良好",
                detail: "各项身体指标平稳，无须大幅调整日常计划。",
                lifestyleSuggestions: []
            )
        case .strained:
            return ActionEval(
                needsAction: true,
                category: .recovery,
                headline: "建议关注恢复",
                detail: "近期生理负荷有所累积，建议今晚提前准备休息或安排轻度放松活动。",
                lifestyleSuggestions: ["建议今晚提前 20-30 分钟准备睡眠", "注意水分与电解质补充"]
            )
        case .recovering:
            return ActionEval(
                needsAction: true,
                category: .sleep,
                headline: "休整调节优先",
                detail: "身体处于恢复调节窗口，建议优先保障睡眠时长与放松减压。",
                lifestyleSuggestions: ["保持充足睡眠与舒适作息", "避免高强度疲劳刺激"]
            )
        case .insufficientData:
            return ActionEval(
                needsAction: false,
                category: .none,
                headline: "持续记录中",
                detail: "继续佩戴 Apple Watch 记录睡眠与日常活动，以积累个人基线。",
                lifestyleSuggestions: []
            )
        }
    }

    // MARK: - Helper Methods

    private func currentValue(for metric: CoreHealthMetric, dashboard: DashboardSummary) -> Double? {
        switch metric {
        case .hrv: return dashboard.recoveryMetrics.hrvMilliseconds
        case .restingHeartRate: return dashboard.recoveryMetrics.restingHeartRate
        case .sleepDuration:
            if dashboard.sleepSummary.totalSleepMinutes > 0 { return Double(dashboard.sleepSummary.totalSleepMinutes) / 60.0 }
            return nil
        case .sleepScore: return dashboard.sleepScore.value
        case .recovery: return dashboard.recovery.value
        case .strain: return dashboard.strain.value
        case .stress: return dashboard.stress.value
        case .energy: return dashboard.energy.value
        case .respiratoryRate: return dashboard.recoveryMetrics.respiratoryRate
        case .oxygenSaturation: return dashboard.extendedMetrics.oxygenSaturation
        case .bodyWeight: return dashboard.bodyMetrics.weightKilograms ?? dashboard.extendedMetrics.bodyWeightKg
        case .bodyFat: return dashboard.bodyMetrics.bodyFatPercentage ?? dashboard.extendedMetrics.bodyFatPercent
        case .steps:
            return dashboard.strain.metrics["steps_raw"]
        case .activeCalories:
            return dashboard.strain.metrics["active_energy_raw"] ?? dashboard.strain.metrics["active_calories_raw"]
        }
    }

    private func value(for metric: CoreHealthMetric, snapshot: DailyHealthSnapshot) -> Double? {
        switch metric {
        case .hrv: return snapshot.hrvAverage
        case .restingHeartRate: return snapshot.restingHeartRate
        case .sleepDuration: return snapshot.sleepHours
        case .sleepScore: return snapshot.sleepScore
        case .recovery: return snapshot.recoveryScore
        case .strain: return snapshot.strainScore
        case .stress: return snapshot.stressIndex
        case .energy: return snapshot.currentEnergy ?? snapshot.energyBank
        case .respiratoryRate: return snapshot.respiratoryRate
        case .oxygenSaturation: return snapshot.oxygenSaturation
        case .bodyWeight: return snapshot.bodyWeight
        case .bodyFat: return snapshot.bodyFatPercent
        case .steps: return snapshot.steps
        case .activeCalories: return snapshot.activeCalories
        }
    }

    private func formatValue(_ value: Double?, metric: CoreHealthMetric) -> String {
        guard let val = value else { return "--" }
        switch metric {
        case .hrv:
            return "\(Int(val.rounded())) ms"
        case .restingHeartRate:
            return "\(Int(val.rounded())) bpm"
        case .sleepDuration:
            return String(format: "%.1f h", val)
        case .sleepScore:
            return "\(Int(val.rounded()))"
        case .recovery, .energy, .oxygenSaturation, .bodyFat:
            return "\(Int(val.rounded()))%"
        case .strain, .stress:
            return "\(Int(val.rounded()))"
        case .respiratoryRate:
            return String(format: "%.1f 次/分", val)
        case .bodyWeight:
            return String(format: "%.1f kg", val)
        case .steps:
            return "\(Int(val.rounded())) 步"
        case .activeCalories:
            return "\(Int(val.rounded())) kcal"
        }
    }

    private func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 1 {
            return sorted[count / 2]
        } else {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        }
    }

    private func longTermMetric(for metric: CoreHealthMetric) -> LongTermBaselineMetric? {
        switch metric {
        case .hrv: return .hrv
        case .restingHeartRate: return .restingHeartRate
        case .sleepDuration: return .sleepHours
        case .sleepScore: return nil
        case .bodyWeight: return .bodyWeight
        case .bodyFat: return .bodyFatPercent
        case .steps: return .steps
        case .activeCalories: return .activeCalories
        default: return nil
        }
    }

    private func calculatePercentilePosition(value: Double, baseline: LongTermMetricBaseline) -> Double {
        if let p10 = baseline.percentile10, value <= p10 { return 0.10 }
        if let p25 = baseline.percentile25, value <= p25 { return 0.25 }
        if let med = baseline.threeYearMedian, value <= med { return 0.50 }
        if let p75 = baseline.percentile75, value <= p75 { return 0.75 }
        if let p90 = baseline.percentile90, value <= p90 { return 0.90 }
        return 0.95
    }

    private func generate3YSummary(
        metric: CoreHealthMetric,
        cur: Double,
        median: Double?,
        percentile: Double,
        trendLabel: String?
    ) -> String {
        let pText = "处于三年历史 P\(Int(percentile * 100))"
        if let trend = trendLabel, !trend.isEmpty {
            return "\(trend)，\(pText)"
        }
        return pText
    }

    private func confidenceText(for confidence: DataConfidence) -> String {
        switch confidence {
        case .high: return "数据充足"
        case .medium: return "数据部分"
        case .low: return "数据较少"
        case .unavailable: return "数据不足"
        }
    }
}
