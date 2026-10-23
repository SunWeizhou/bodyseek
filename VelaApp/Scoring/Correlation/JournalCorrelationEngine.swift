import Foundation

struct HabitCorrelationInsight: Codable, Hashable, Identifiable {
    var id: String { "\(habit)_\(outcome)_lag\(lagDays)" }
    var habit: String
    var outcome: String
    var lagDays: Int
    var correlation: Double
    var sampleSize: Int
    var confidence: MetricConfidence
    var direction: String // "positive" / "negative" / "neutral"
    var explanation: String
}

extension JournalCorrelationEngine {
    /// T6：统一口径——Coach 工具 / Coach 上下文 / 图表工具全部消费
    /// `calculateInsights`（点二列 + BH-FDR），不再走旧 `correlateTags`（均值差、无校正）。
    func formatInsightsForAI(_ insights: [HabitCorrelationInsight], limit: Int = 6) -> String {
        guard !insights.isEmpty else { return "" }
        return insights.prefix(limit).map { insight in
            let dirText = insight.direction == "positive" ? "正相关" : "负相关"
            let lagText = insight.lagDays == 0 ? "当天" : "次日"
            return "「\(insight.habit)」与\(lagText)\(insight.outcome)呈\(dirText)（r=\(String(format: "%.2f", insight.correlation))，n=\(insight.sampleSize)，置信度 \(insight.confidence.rawValue)）"
        }.joined(separator: "\n")
    }
}

// Struct to retain old class usage compatibility if needed, but primary calculations will be returned here
struct TagCorrelation: Identifiable, Hashable, Codable {
    var id: String { tag }
    var tag: String
    var count: Int
    var avgSleepScore: Double
    var avgRecoveryScore: Double
    var avgStrainScore: Double
    var avgHRV: Double
    var avgRHR: Double
    var withoutCount: Int = 0
    var withoutAvgSleepScore: Double = 0
    var withoutAvgRecoveryScore: Double = 0
    var withoutAvgStrainScore: Double = 0
    var withoutAvgHRV: Double = 0
    var withoutAvgRHR: Double = 0

    var sleepScoreDelta: Double { avgSleepScore - withoutAvgSleepScore }
    var recoveryScoreDelta: Double { avgRecoveryScore - withoutAvgRecoveryScore }
    var strainScoreDelta: Double { avgStrainScore - withoutAvgStrainScore }
    var overallImpact: Double { (sleepScoreDelta + recoveryScoreDelta) / 2.0 }
}

struct JournalCorrelationEngine {
    init() {}

    private func ranks(for X: [Double]) -> [Double] {
        let indexed = X.enumerated().map { (index: $0.offset, value: $0.element) }
        let sorted = indexed.sorted { $0.value < $1.value }
        var ranks = [Double](repeating: 0.0, count: X.count)
        
        var i = 0
        while i < sorted.count {
            var j = i
            while j < sorted.count && sorted[j].value == sorted[i].value {
                j += 1
            }
            let rankSum = Double((i + 1 + j)) / 2.0
            for k in i..<j {
                ranks[sorted[k].index] = rankSum
            }
            i = j
        }
        return ranks
    }

    private func pearsonCorrelation(_ X: [Double], _ Y: [Double]) -> Double {
        let N = Double(X.count)
        guard N > 0 else { return 0.0 }
        let meanX = X.reduce(0, +) / N
        let meanY = Y.reduce(0, +) / N
        
        var num = 0.0
        var denX = 0.0
        var denY = 0.0
        for i in 0..<X.count {
            let dx = X[i] - meanX
            let dy = Y[i] - meanY
            num += dx * dy
            denX += dx * dx
            denY += dy * dy
        }
        guard denX > 0 && denY > 0 else { return 0.0 }
        return num / sqrt(denX * denY)
    }

    func spearmanCorrelation(_ X: [Double], _ Y: [Double]) -> Double {
        let rankX = ranks(for: X)
        let rankY = ranks(for: Y)
        return pearsonCorrelation(rankX, rankY)
    }

    private func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return [
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        ]
        .map { String(format: "%02d", $0) }
        .joined(separator: "-")
    }

    /// Calculate lagged correlations between journal tags and health outcomes
    func calculateInsights(
        journalEntries: [JournalEntryRecord],
        snapshots: [DailyHealthSnapshot],
        calendar: Calendar = .current
    ) -> [HabitCorrelationInsight] {
        let journalEntries = journalEntries.filter { !isCoachConversation($0) }
        var snapshotByDay: [String: DailyHealthSnapshot] = [:]
        for snap in snapshots {
            let key = dayKey(for: snap.date, calendar: calendar)
            snapshotByDay[key] = snap
        }

        // 预索引「某天真正发生的标签」：下方每个 tag/outcome/lag/day 不再
        // 线性扫描全量手记，避免全量 1100 天 + 大量标签时出现 O(n²)。
        var tagsByDay: [String: Set<String>] = [:]
        for entry in journalEntries where entry.value != 0 && entry.value != 1 {
            tagsByDay[dayKey(for: entry.createdAt, calendar: calendar), default: []]
                .formUnion(entry.tags)
        }

        // Get all unique tags
        let allTags = Set(journalEntries.flatMap { $0.tags })
        let allDaysSortedKeys = snapshotByDay.keys.sorted()
        
        struct Candidate {
            var habit: String
            var outcome: String
            var lag: Int
            var correlation: Double
            var sampleSize: Int
            var exposedCount: Int
            var controlCount: Int
            var pValue: Double
        }
        var candidates: [Candidate] = []
        var evaluatedTests = 0

        // Outcome key paths or mappings
        let outcomes = [
            ("HRV", { (snap: DailyHealthSnapshot) -> Double? in snap.hrvAverage }),
            ("RHR", { (snap: DailyHealthSnapshot) -> Double? in snap.restingHeartRate }),
            ("Sleep Score", { (snap: DailyHealthSnapshot) -> Double? in snap.sleepScore }),
            ("Recovery Score", { (snap: DailyHealthSnapshot) -> Double? in snap.recoveryScore })
        ]

        for tag in allTags {
            for outcome in outcomes {
                for lag in [0, 1] { // Lag 0 (same day/night), Lag 1 (next day)
                    var tagSeries: [Double] = []
                    var outcomeSeries: [Double] = []

                    for key in allDaysSortedKeys {
                        guard let targetDate = calendar.date(from: parseDateComponents(from: key)) else { continue }
                        guard let sampleDate = calendar.date(byAdding: .day, value: -lag, to: targetDate) else { continue }
                        
                        // Only treat the habit as EXPOSED when it actually occurred.
                        // value is the quick-entry state: 0 = ✕ "not done", 1 = "–"
                        // neutral, 2 = ✓ "done", nil = tagged via a journal note.
                        // Neutral (1) and not-done (0) must not be correlated as an
                        // occurrence (previously any day containing the tag counted,
                        // which let an explicit "neutral" bias the point-biserial r).
                        let isTagLogged = tagsByDay[dayKey(for: sampleDate, calendar: calendar)]?
                            .contains(tag) == true

                        if let outcomeVal = snapshotByDay[key].flatMap(outcome.1) {
                            tagSeries.append(isTagLogged ? 1.0 : 0.0)
                            outcomeSeries.append(outcomeVal)
                        }
                    }

                    let n = tagSeries.count
                    let exposedCount = tagSeries.filter { $0 == 1 }.count
                    let controlCount = n - exposedCount
                    guard n >= 28, exposedCount >= 8, controlCount >= 8 else { continue }

                    // Compute Point-Biserial Correlation (which is standard Pearson correlation between binary and continuous)
                    let r = pearsonCorrelation(tagSeries, outcomeSeries)
                    let nEff = effectiveSampleSize(outcomeSeries)
                    let pValue = correlationPValue(r: r, sampleSize: nEff)
                    evaluatedTests += 1
                    guard abs(r) >= 0.25 else { continue }
                    candidates.append(Candidate(
                        habit: tag,
                        outcome: outcome.0,
                        lag: lag,
                        correlation: r,
                        sampleSize: n,
                        exposedCount: exposedCount,
                        controlCount: controlCount,
                        pValue: pValue
                    ))
                }
            }
        }

        // Benjamini-Hochberg false-discovery control across every tag/outcome/lag
        // comparison. This prevents a large tag library from manufacturing a
        // seemingly meaningful result by chance.
        let sortedCandidates = candidates.sorted { $0.pValue < $1.pValue }
        let testCount = max(evaluatedTests, sortedCandidates.count)
        var acceptedPValue = -1.0
        for (index, candidate) in sortedCandidates.enumerated() {
            let threshold = 0.05 * Double(index + 1) / Double(max(testCount, 1))
            if candidate.pValue <= threshold {
                acceptedPValue = candidate.pValue
            }
        }

        var insights: [HabitCorrelationInsight] = []
        for candidate in sortedCandidates where candidate.pValue <= acceptedPValue {
                    let n = candidate.sampleSize
                    let r = candidate.correlation

                    let confidence: MetricConfidence
                    if n >= 90 && min(candidate.exposedCount, candidate.controlCount) >= 20 {
                        confidence = .high
                    } else if n >= 60 && min(candidate.exposedCount, candidate.controlCount) >= 14 {
                        confidence = .medium
                    } else {
                        confidence = .low
                    }

                    let strength: String
                    if abs(r) >= 0.50 {
                        strength = L10n.t("strong", "强")
                    } else if abs(r) >= 0.35 {
                        strength = L10n.t("moderate", "中等")
                    } else {
                        strength = L10n.t("weak", "弱")
                    }

                    let dir = r > 0 ? "positive" : "negative"
                    let dirText = r > 0 ? L10n.t("positive correlation", "正相关") : L10n.t("negative correlation", "负相关")
                    
                    let lagText = candidate.lag == 0 ? L10n.t("same-day", "当天") : L10n.t("next-day", "次日")
                    let explanation = L10n.t(
                        "Across \(n) days (\(candidate.exposedCount) exposed / \(candidate.controlCount) control), logging '\(candidate.habit)' has a \(strength) \(dirText) with \(lagText) \(candidate.outcome) after false-discovery screening. This is correlation, not clinical causation.",
                        "在 \(n) 天数据中（记录 \(candidate.exposedCount) 天 / 对照 \(candidate.controlCount) 天），习惯标签「\(candidate.habit)」与\(lagText)\(candidate.outcome)在多重比较校正后表现出\(strength)的\(dirText)。本提示仅代表关联，不代表因果关系。"
                    )

                    insights.append(HabitCorrelationInsight(
                        habit: candidate.habit,
                        outcome: candidate.outcome,
                        lagDays: candidate.lag,
                        correlation: r,
                        sampleSize: n,
                        confidence: confidence,
                        direction: dir,
                        explanation: explanation
                    ))
        }

        return insights.sorted { abs($0.correlation) > abs($1.correlation) }
    }

    private func parseDateComponents(from string: String) -> DateComponents {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return DateComponents() }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }

    // Preserve old correlateTags method signature for backward compatibility
    func correlateTags(
        journalEntries: [JournalEntryRecord],
        snapshots: [DailyHealthSnapshot],
        calendar: Calendar = .current
    ) -> [TagCorrelation] {
        let journalEntries = journalEntries.filter { !isCoachConversation($0) }
        var snapshotByDay: [String: DailyHealthSnapshot] = [:]
        for snap in snapshots {
            let key = dayKey(for: snap.date, calendar: calendar)
            snapshotByDay[key] = snap
        }

        var tagDays: [String: Set<String>] = [:]
        for entry in journalEntries {
            if let nextDay = calendar.date(byAdding: .day, value: 1, to: entry.createdAt) {
                let key = dayKey(for: nextDay, calendar: calendar)
                for tag in entry.tags {
                    tagDays[tag, default: []].insert(key)
                }
            }
        }

        let allDays = Set(snapshotByDay.keys)
        var results: [TagCorrelation] = []

        for (tag, daysWithTag) in tagDays {
            let daysWith = daysWithTag.intersection(allDays)
            let daysWithout = allDays.subtracting(daysWith)

            guard allDays.count >= 28, daysWith.count >= 8, daysWithout.count >= 8 else { continue }

            let withSleep = daysWith.compactMap { snapshotByDay[$0]?.sleepScore }
            let withRecovery = daysWith.compactMap { snapshotByDay[$0]?.recoveryScore }
            let withStrain = daysWith.compactMap { snapshotByDay[$0]?.strainScore }
            let withHRV = daysWith.compactMap { snapshotByDay[$0]?.hrvAverage }
            let withRHR = daysWith.compactMap { snapshotByDay[$0]?.restingHeartRate }

            let withoutSleep = daysWithout.compactMap { snapshotByDay[$0]?.sleepScore }
            let withoutRecovery = daysWithout.compactMap { snapshotByDay[$0]?.recoveryScore }
            let withoutStrain = daysWithout.compactMap { snapshotByDay[$0]?.strainScore }
            let withoutHRV = daysWithout.compactMap { snapshotByDay[$0]?.hrvAverage }
            let withoutRHR = daysWithout.compactMap { snapshotByDay[$0]?.restingHeartRate }

            results.append(TagCorrelation(
                tag: tag,
                count: daysWith.count,
                avgSleepScore: averageOf(withSleep),
                avgRecoveryScore: averageOf(withRecovery),
                avgStrainScore: averageOf(withStrain),
                avgHRV: averageOf(withHRV),
                avgRHR: averageOf(withRHR),
                withoutCount: daysWithout.count,
                withoutAvgSleepScore: averageOf(withoutSleep),
                withoutAvgRecoveryScore: averageOf(withoutRecovery),
                withoutAvgStrainScore: averageOf(withoutStrain),
                withoutAvgHRV: averageOf(withoutHRV),
                withoutAvgRHR: averageOf(withoutRHR)
            ))
        }

        return results.sorted { abs($0.overallImpact) > abs($1.overallImpact) }
    }

    private func averageOf(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func effectiveSampleSize(_ series: [Double]) -> Int {
        guard series.count > 2 else { return series.count }
        let centered = series
        let mean = centered.reduce(0, +) / Double(centered.count)
        var lag0 = 0.0
        var lag1 = 0.0
        for index in centered.indices {
            let delta = centered[index] - mean
            lag0 += delta * delta
            if index > centered.startIndex {
                lag1 += delta * (centered[centered.index(before: index)] - mean)
            }
        }
        let rho = lag0 > 0 ? min(0.8, max(0, lag1 / lag0)) : 0
        let nEff = Double(series.count) * (1 - rho) / (1 + rho)
        return max(8, Int(nEff.rounded()))
    }

    private func correlationPValue(r: Double, sampleSize: Int) -> Double {
        guard sampleSize > 3 else { return 1 }
        let bounded = min(0.999_999, max(-0.999_999, r))
        let fisherZ = abs(atanh(bounded)) * sqrt(Double(sampleSize - 3))
        return erfc(fisherZ / sqrt(2))
    }

    private func isCoachConversation(_ entry: JournalEntryRecord) -> Bool {
        entry.tags.contains { tag in
            let normalized = tag.lowercased()
            return normalized == "coach" || normalized == "coach_conversation"
        }
    }

    /// Returns the top N correlations sorted by absolute impact magnitude.
    func topCorrelations(correlations: [TagCorrelation], limit: Int = 5) -> [TagCorrelation] {
        var result = correlations
            .filter { abs($0.overallImpact) > 1.0 }
        result.sort { abs($0.overallImpact) > abs($1.overallImpact) }
        return Array(result.prefix(limit))
    }

    /// Formats correlation data as a human-readable string for AI context injection.
    func formatCorrelationsForAI(_ correlations: [TagCorrelation]) -> String {
        guard !correlations.isEmpty else { return "" }
        var lines: [String] = ["Journal tag correlations with next-day health metrics:"]
        for c in correlations {
            let direction = c.overallImpact > 0 ? "positive" : "negative"
            lines.append("- '\(c.tag)': \(direction) impact, "
                + "sleep Δ\(String(format: "%.1f", c.sleepScoreDelta)), "
                + "recovery Δ\(String(format: "%.1f", c.recoveryScoreDelta)) "
                + "(n=\(c.count))")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Cross-Lagged Time Series Correlation Engine (Functional Deep Optimization)

    struct CrossLaggedResult: Sendable, Equatable {
        var lagDays: Int
        var correlation: Double
        var isOptimalLag: Bool
    }

    /// Computes cross-lagged Spearman rank correlation between two time series (e.g. Strain on T vs HRV on T+k).
    func calculateCrossLaggedCorrelation(
        seriesA: [Double],
        seriesB: [Double],
        maxLagDays: Int = 3
    ) -> [CrossLaggedResult] {
        guard seriesA.count == seriesB.count, seriesA.count >= 7 else { return [] }

        var results: [CrossLaggedResult] = []
        var maxAbsCorr = -1.0
        var maxIdx = -1

        for lag in 0...maxLagDays {
            let count = seriesA.count - lag
            guard count >= 5 else { break }

            let subA = Array(seriesA.prefix(count))
            let subB = Array(seriesB.suffix(count))

            let corr = spearmanCorrelation(subA, subB)
            results.append(CrossLaggedResult(
                lagDays: lag,
                correlation: corr,
                isOptimalLag: false
            ))

            if abs(corr) > maxAbsCorr {
                maxAbsCorr = abs(corr)
                maxIdx = lag
            }
        }

        if maxIdx >= 0 && maxIdx < results.count {
            results[maxIdx].isOptimalLag = true
        }

        return results
    }
}


// MARK: - 三年生理行为配对（无需手记）

extension JournalCorrelationEngine {
    /// 用三年生理记录直接配对「行为」：训练日 / 高活动日 / 短睡眠夜
    /// → 次日 HRV / RHR 的点二列相关。曝光组与对照组各 ≥ 8 天才发布，
    /// |r| < 0.15 视为噪声不发布。回填后立即可用，不依赖手记。
    func physiologicalInsights(
        snapshots: [DailyHealthSnapshot],
        calendar: Calendar = .current
    ) -> [HabitCorrelationInsight] {
        let byDay = snapshots.reduce(into: [Date: DailyHealthSnapshot]()) { result, snapshot in
            result[calendar.startOfDay(for: snapshot.date)] = snapshot
        }
        let days = byDay.keys.sorted()
        guard days.count >= 30 else { return [] }

        let stepsValues = snapshots.compactMap(\.steps).filter { $0 > 0 }.sorted()
        let sleepValues = snapshots.compactMap(\.sleepHours).filter { $0 > 0 }.sorted()
        func percentile(_ sorted: [Double], _ fraction: Double) -> Double? {
            guard !sorted.isEmpty else { return nil }
            let index = Int((Double(sorted.count - 1) * fraction).rounded())
            return sorted[max(0, min(index, sorted.count - 1))]
        }
        let highStepsThreshold = percentile(stepsValues, 0.75)
        let shortSleepThreshold = percentile(sleepValues, 0.25)

        struct HabitSpec {
            var name: String
            var exposure: (DailyHealthSnapshot) -> Bool
        }
        let specs: [HabitSpec] = [
            HabitSpec(name: "训练日", exposure: { ($0.workoutCount ?? 0) > 0 || ($0.workoutDuration ?? 0) >= 15 }),
            HabitSpec(name: "高活动日", exposure: { snap in
                guard let threshold = highStepsThreshold, let steps = snap.steps, steps > 0 else { return false }
                return steps >= threshold
            }),
            HabitSpec(name: "短睡眠夜", exposure: { snap in
                guard let threshold = shortSleepThreshold, let hours = snap.sleepHours, hours > 0 else { return false }
                return hours <= threshold
            }),
        ]

        var results: [HabitCorrelationInsight] = []
        for spec in specs {
            for outcomeName in ["HRV", "RHR"] {
                var x: [Double] = []
                var y: [Double] = []
                var exposed = 0
                var control = 0
                for day in days {
                    guard let snap = byDay[day],
                          let next = calendar.date(byAdding: .day, value: 1, to: day),
                          let nextSnap = byDay[next] else { continue }
                    let outcome: Double?
                    if outcomeName == "HRV" {
                        outcome = nextSnap.hrvAverage
                    } else {
                        outcome = nextSnap.restingHeartRate
                    }
                    guard let outcome, outcome.isFinite else { continue }
                    let isExposed = spec.exposure(snap)
                    x.append(isExposed ? 1.0 : 0.0)
                    y.append(outcome)
                    if isExposed { exposed += 1 } else { control += 1 }
                }
                guard exposed >= 8, control >= 8 else { continue }
                let r = pearsonCorrelation(x, y)
                guard r.isFinite, abs(r) >= 0.15 else { continue }
                results.append(HabitCorrelationInsight(
                    habit: spec.name,
                    outcome: outcomeName,
                    lagDays: 1,
                    correlation: r,
                    sampleSize: x.count,
                    confidence: x.count >= 60 ? .high : .medium,
                    direction: r > 0 ? "positive" : "negative",
                    explanation: "基于三年生理记录的个人配对（无需手记）"
                ))
            }
        }
        return results
    }
}
