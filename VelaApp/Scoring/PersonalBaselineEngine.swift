import Foundation
import BodySeekDomain

struct PersonalBaselineFormation: Codable, Hashable, Sendable {
    enum Phase: String, Codable, Hashable, Sendable {
        case waitingForEvidence
        case learning
        case ready
    }

    static let requiredObservedDays = 7
    static let waiting = PersonalBaselineFormation(phase: .waitingForEvidence, observedDays: 0)
    static let ready = PersonalBaselineFormation(
        phase: .ready,
        observedDays: requiredObservedDays
    )

    var phase: Phase
    var observedDays: Int
    var requiredDays: Int = requiredObservedDays

    var progress: Double {
        guard requiredDays > 0 else { return 1 }
        return min(1, max(0, Double(observedDays) / Double(requiredDays)))
    }

    /// Debug-only visual-regression seam. It avoids mutating HealthKit fixtures
    /// just to inspect the first-week Today state in Simulator.
    static func visualRegressionValue(
        fallback: PersonalBaselineFormation,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> PersonalBaselineFormation {
        #if DEBUG
        guard let flag = arguments.firstIndex(of: "-velaBaselineObservedDays"),
              arguments.indices.contains(arguments.index(after: flag)),
              let requestedDays = Int(arguments[arguments.index(after: flag)]) else {
            return fallback
        }
        let observedDays = max(0, requestedDays)
        if observedDays == 0 { return .waiting }
        if observedDays < requiredObservedDays {
            return PersonalBaselineFormation(phase: .learning, observedDays: observedDays)
        }
        return PersonalBaselineFormation(phase: .ready, observedDays: observedDays)
        #else
        return fallback
        #endif
    }
}

// MARK: - Personal Baselines Data Structure

struct PersonalBaselines {
    var hrvBaselineMean: Double?
    var hrvBaselineSD: Double?
    var rhrBaselineMean: Double?
    var rhrBaselineSD: Double?
    var sleepHoursBaseline: Double?
    var sleepEfficiencyBaseline: Double?
    var deepSleepPercentBaseline: Double?
    var remSleepPercentBaseline: Double?
    var strainBaselineMean: Double?
    var stepsBaseline: Double?
    var activeCaloriesBaseline: Double?
    var calculatedAt: Date
    var daysOfData: Int

    // Personalized recovery & sleep score baselines
    var recoveryBaselineMean: Double? = nil
    var recoveryBaselineSD: Double? = nil
    var sleepScoreBaselineMean: Double? = nil
    var sleepScoreBaselineSD: Double? = nil
}

// MARK: - Personal Baseline Engine

enum PersonalBaselineEngine {
    private static let minimumSamples = 7

    /// Product-facing orientation for the first week. A day counts when at least
    /// one real signal used by a Personal Baseline is present. This progress does
    /// not bypass the per-metric seven-sample gates below: each metric still
    /// remains unavailable until its own evidence is sufficient.
    static func formationProgress(
        from snapshots: [DailyHealthSnapshot],
        selectedDate: Date,
        calendar: Calendar = .current
    ) -> PersonalBaselineFormation {
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let evidenceDays = Set(
            snapshots.compactMap { snapshot -> Date? in
                let day = calendar.startOfDay(for: snapshot.date)
                guard day <= selectedDay, hasBaselineEvidence(snapshot) else { return nil }
                return day
            }
        )
        let observedDays = evidenceDays.count

        if observedDays == 0 {
            return .waiting
        }
        if observedDays < minimumSamples {
            return PersonalBaselineFormation(phase: .learning, observedDays: observedDays)
        }
        return PersonalBaselineFormation(phase: .ready, observedDays: observedDays)
    }

    private static func hasBaselineEvidence(_ snapshot: DailyHealthSnapshot) -> Bool {
        snapshot.hrvAverage != nil
            || snapshot.restingHeartRate != nil
            || snapshot.sleepHours != nil
            || snapshot.strainScore != nil
            || snapshot.steps != nil
            || snapshot.activeCalories != nil
    }

    // MARK: - Compute

    /// Compute personalized baselines from the user's own historical snapshots (last 30 days).
    static func computeBaselines(
        from snapshots: [DailyHealthSnapshot],
        calculatedAt: Date = Date()
    ) -> PersonalBaselines {
        let sorted = snapshots.sorted { $0.date < $1.date }
        let recent = Array(sorted.suffix(30))

        let hrvValues = recent.compactMap(\.hrvAverage)
        let rhrValues = recent.compactMap(\.restingHeartRate)
        let sleepHoursValues = recent.compactMap(\.sleepHours)
        let sleepEfficiencyValues = recent.compactMap(\.sleepEfficiency)
        let deepSleepValues = recent.compactMap(\.deepSleepPercent)
        let remSleepValues = recent.compactMap(\.remSleepPercent)
        let strainValues = recent.compactMap(\.strainScore)
        let stepsValues = recent.compactMap(\.steps)
        let caloriesValues = recent.compactMap(\.activeCalories)
        let recoveryValues = recent.compactMap(\.recoveryScore)
        let sleepScoreValues = recent.compactMap(\.sleepScore)

        return PersonalBaselines(
            hrvBaselineMean: recencyMeanIfReady(hrvValues),
            hrvBaselineSD: standardDeviationIfReady(hrvValues),
            rhrBaselineMean: recencyMeanIfReady(rhrValues),
            rhrBaselineSD: standardDeviationIfReady(rhrValues),
            sleepHoursBaseline: recencyMeanIfReady(sleepHoursValues),
            sleepEfficiencyBaseline: recencyMeanIfReady(sleepEfficiencyValues),
            deepSleepPercentBaseline: recencyMeanIfReady(deepSleepValues),
            remSleepPercentBaseline: recencyMeanIfReady(remSleepValues),
            strainBaselineMean: recencyMeanIfReady(strainValues),
            stepsBaseline: recencyMeanIfReady(stepsValues),
            activeCaloriesBaseline: recencyMeanIfReady(caloriesValues),
            calculatedAt: calculatedAt,
            daysOfData: recent.count,
            recoveryBaselineMean: recencyMeanIfReady(recoveryValues),
            recoveryBaselineSD: standardDeviationIfReady(recoveryValues),
            sleepScoreBaselineMean: recencyMeanIfReady(sleepScoreValues),
            sleepScoreBaselineSD: standardDeviationIfReady(sleepScoreValues)
        )
    }

    // MARK: - Thresholds for AI Context

    private static func meanOfIfReady(_ values: [Double]) -> Double? {
        values.count >= minimumSamples ? meanOf(values) : nil
    }

    private static func recencyMeanIfReady(_ values: [Double]) -> Double? {
        values.count >= minimumSamples ? recencyWeightedMean(values) : nil
    }

    private static func standardDeviationIfReady(_ values: [Double]) -> Double? {
        values.count >= minimumSamples ? standardDeviationOf(values) : nil
    }

    /// Formats baselines as key-value strings suitable for AI coach context injection.
    static func thresholds(for baselines: PersonalBaselines) -> [String: String] {
        var result: [String: String] = [:]

        if let hrv = baselines.hrvBaselineMean {
            let sd = baselines.hrvBaselineSD.map { String(format: "%.0f", $0) } ?? "N/A"
            result["hrv_baseline_mean"] = String(format: "%.0f ms", hrv)
            result["hrv_baseline_sd"] = "\u{B1}\(sd) ms"
        }
        if let rhr = baselines.rhrBaselineMean {
            let sd = baselines.rhrBaselineSD.map { String(format: "%.0f", $0) } ?? "N/A"
            result["rhr_baseline_mean"] = String(format: "%.0f bpm", rhr)
            result["rhr_baseline_sd"] = "\u{B1}\(sd) bpm"
        }
        if let sleep = baselines.sleepHoursBaseline {
            result["sleep_hours_baseline"] = String(format: "%.1f hrs", sleep)
        }
        if let se = baselines.sleepEfficiencyBaseline {
            result["sleep_efficiency_baseline"] = String(format: "%.0f%%", se * 100)
        }
        if let deep = baselines.deepSleepPercentBaseline {
            result["deep_sleep_baseline"] = String(format: "%.0f%%", deep * 100)
        }
        if let rem = baselines.remSleepPercentBaseline {
            result["rem_sleep_baseline"] = String(format: "%.0f%%", rem * 100)
        }
        if let strain = baselines.strainBaselineMean {
            result["strain_baseline_mean"] = String(format: "%.0f", strain)
        }
        if let steps = baselines.stepsBaseline {
            result["steps_baseline"] = String(format: "%.0f steps", steps)
        }
        if let cal = baselines.activeCaloriesBaseline {
            result["active_calories_baseline"] = String(format: "%.0f kcal", cal)
        }
        if let rec = baselines.recoveryBaselineMean {
            let sd = baselines.recoveryBaselineSD.map { String(format: "%.0f", $0) } ?? "N/A"
            result["recovery_baseline_mean"] = String(format: "%.0f", rec)
            result["recovery_baseline_sd"] = "\u{B1}\(sd)"
        }
        if let sl = baselines.sleepScoreBaselineMean {
            let sd = baselines.sleepScoreBaselineSD.map { String(format: "%.0f", $0) } ?? "N/A"
            result["sleep_score_baseline_mean"] = String(format: "%.0f", sl)
            result["sleep_score_baseline_sd"] = "\u{B1}\(sd)"
        }
        result["baseline_days_of_data"] = "\(baselines.daysOfData)"
        result["baseline_calculated_at"] = ISO8601DateFormatter().string(from: baselines.calculatedAt)

        return result
    }

    // MARK: - Format for Wiki

    /// Generate a markdown string suitable for storage as baselines.md in the user Wiki.
    static func formatForWiki(_ baselines: PersonalBaselines) -> String {
        let th = thresholds(for: baselines)
        let dateStr = DateFormatter.localizedString(from: baselines.calculatedAt, dateStyle: .medium, timeStyle: .short)

        var lines: [String] = [
            "# Personal Baselines",
            "",
            "Your 30-day physiological baselines, computed from your own historical data.",
            "",
            "**Calculated:** \(dateStr)",
            "**Days of data:** \(baselines.daysOfData)",
            "",
            "| Metric | Baseline (Mean \u{B1} SD) |",
            "|--------|---------------------------|",
        ]

        if let hrv = th["hrv_baseline_mean"], let sd = th["hrv_baseline_sd"] {
            lines.append("| HRV | \(hrv) (\(sd)) |")
        }
        if let rhr = th["rhr_baseline_mean"], let sd = th["rhr_baseline_sd"] {
            lines.append("| RHR | \(rhr) (\(sd)) |")
        }
        if let sleep = th["sleep_hours_baseline"] {
            lines.append("| Sleep Duration | \(sleep) |")
        }
        if let se = th["sleep_efficiency_baseline"] {
            lines.append("| Sleep Efficiency | \(se) |")
        }
        if let deep = th["deep_sleep_baseline"] {
            lines.append("| Deep Sleep | \(deep) |")
        }
        if let rem = th["rem_sleep_baseline"] {
            lines.append("| REM Sleep | \(rem) |")
        }
        if let strain = th["strain_baseline_mean"] {
            lines.append("| Strain | \(strain) |")
        }
        if let steps = th["steps_baseline"] {
            lines.append("| Steps | \(steps) |")
        }
        if let cal = th["active_calories_baseline"] {
            lines.append("| Active Calories | \(cal) |")
        }
        if let rec = th["recovery_baseline_mean"], let sd = th["recovery_baseline_sd"] {
            lines.append("| Recovery | \(rec) (\(sd)) |")
        }
        if let sl = th["sleep_score_baseline_mean"], let sd = th["sleep_score_baseline_sd"] {
            lines.append("| Sleep Score | \(sl) (\(sd)) |")
        }

        return lines.joined(separator: "\n")
    }

    /// Format baselines as a concise natural-language block for the AI system prompt.
    static func formatForAIPrompt(_ baselines: PersonalBaselines) -> String {
        let th = thresholds(for: baselines)
        let dateStr = DateFormatter.localizedString(from: baselines.calculatedAt, dateStyle: .medium, timeStyle: .short)

        var parts: [String] = [
            "Calculated on \(dateStr) from \(baselines.daysOfData) days of your own historical data:",
        ]

        if let hrv = th["hrv_baseline_mean"], let sd = th["hrv_baseline_sd"] {
            parts.append("- HRV: \(hrv) (\(sd))")
        }
        if let rhr = th["rhr_baseline_mean"], let sd = th["rhr_baseline_sd"] {
            parts.append("- RHR: \(rhr) (\(sd))")
        }
        if let sleep = th["sleep_hours_baseline"] {
            parts.append("- Sleep Duration: \(sleep)")
        }
        if let se = th["sleep_efficiency_baseline"] {
            parts.append("- Sleep Efficiency: \(se)")
        }
        if let deep = th["deep_sleep_baseline"] {
            parts.append("- Deep Sleep: \(deep)")
        }
        if let rem = th["rem_sleep_baseline"] {
            parts.append("- REM Sleep: \(rem)")
        }
        if let strain = th["strain_baseline_mean"] {
            parts.append("- Strain: \(strain)")
        }
        if let steps = th["steps_baseline"] {
            parts.append("- Steps: \(steps)")
        }
        if let cal = th["active_calories_baseline"] {
            parts.append("- Active Calories: \(cal)")
        }
        if let rec = th["recovery_baseline_mean"], let sd = th["recovery_baseline_sd"] {
            parts.append("- Recovery: \(rec) (\(sd))")
        }
        if let sl = th["sleep_score_baseline_mean"], let sd = th["sleep_score_baseline_sd"] {
            parts.append("- Sleep Score: \(sl) (\(sd))")
        }

        return parts.joined(separator: "\n")
    }

    // MARK: - Save to Wiki

    /// Save computed baselines to baselines.md in the user Wiki for AI coach reference.
    /// longTerm 非空时追加「三年长期基线」章节（Layer 2：Coach 上下文自动携带）。
    static func saveBaselinesToWiki(_ baselines: PersonalBaselines, longTerm: LongTermBaselineReport? = nil) {
        var markdown = formatForWiki(baselines)
        if let longTerm {
            markdown += "\n" + LongTermBaselineEngine.formatForWiki(longTerm)
        }
        _ = try? WikiFileService.updateSection(filename: "baselines.md", content: markdown, mode: .replace)
    }

    // MARK: - Load from Wiki

    /// Attempts to load and parse previously saved baselines from the wiki.
    /// Returns nil if the file doesn't exist or cannot be parsed.
    static func loadBaselinesFromWiki() -> (baselines: PersonalBaselines, updatedAt: Date)? {
        let docs = WikiFileService.loadAllDocuments()
        guard let baselineDoc = docs.first(where: { $0.filename == "baselines.md" }),
              !baselineDoc.content.isEmpty,
              baselineDoc.content.count > 50 else {
            return nil
        }
        let content = baselineDoc.content
        var daysOfData = 0
        if let range = content.range(of: #"\*\*Days of data:\*\* (\d+)"#, options: .regularExpression) {
            let match = String(content[range])
            daysOfData = Int(match.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 0
        }
        let rows = baselineRows(from: content)
        let baselines = PersonalBaselines(
            hrvBaselineMean: firstNumber(in: rows["HRV"] ?? ""),
            hrvBaselineSD: standardDeviation(in: rows["HRV"] ?? ""),
            rhrBaselineMean: firstNumber(in: rows["RHR"] ?? ""),
            rhrBaselineSD: standardDeviation(in: rows["RHR"] ?? ""),
            sleepHoursBaseline: firstNumber(in: rows["Sleep Duration"] ?? ""),
            sleepEfficiencyBaseline: percentFraction(in: rows["Sleep Efficiency"] ?? ""),
            deepSleepPercentBaseline: percentFraction(in: rows["Deep Sleep"] ?? ""),
            remSleepPercentBaseline: percentFraction(in: rows["REM Sleep"] ?? ""),
            strainBaselineMean: firstNumber(in: rows["Strain"] ?? ""),
            stepsBaseline: firstNumber(in: rows["Steps"] ?? ""),
            activeCaloriesBaseline: firstNumber(in: rows["Active Calories"] ?? ""),
            calculatedAt: baselineDoc.updatedAt,
            daysOfData: daysOfData,
            recoveryBaselineMean: firstNumber(in: rows["Recovery"] ?? ""),
            recoveryBaselineSD: standardDeviation(in: rows["Recovery"] ?? ""),
            sleepScoreBaselineMean: firstNumber(in: rows["Sleep Score"] ?? ""),
            sleepScoreBaselineSD: standardDeviation(in: rows["Sleep Score"] ?? "")
        )
        return (baselines, baselineDoc.updatedAt)
    }

    // MARK: - Statistics Helpers

    private static func baselineRows(from markdown: String) -> [String: String] {
        var rows: [String: String] = [:]
        for line in markdown.components(separatedBy: .newlines) {
            let parts = line
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count >= 4,
                  !parts[1].isEmpty,
                  parts[1] != "Metric",
                  !parts[1].contains("---") else {
                continue
            }
            rows[parts[1]] = parts[2]
        }
        return rows
    }

    private static func firstNumber(in text: String) -> Double? {
        guard let range = text.range(of: #"-?\d+(?:,\d{3})*(?:\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return Double(text[range].replacingOccurrences(of: ",", with: ""))
    }

    private static func standardDeviation(in text: String) -> Double? {
        guard let range = text.range(of: #"±\s*-?\d+(?:\.\d+)?"#, options: .regularExpression) else {
            return nil
        }
        return firstNumber(in: String(text[range]))
    }

    private static func percentFraction(in text: String) -> Double? {
        guard let value = firstNumber(in: text) else { return nil }
        return value / 100.0
    }

    /// 时间衰减加权均值：最近 recentWindow 个样本（按时间升序的末尾）权重 ×recentWeight。
    /// 个人基线应对近期状态更敏感，同时保留长窗口的稳健性。
    static func recencyWeightedMean(
        _ values: [Double],
        recentWindow: Int = 7,
        recentWeight: Double = 2.0
    ) -> Double? {
        guard !values.isEmpty else { return nil }
        let recentStart = max(0, values.count - recentWindow)
        var weightedSum = 0.0
        var totalWeight = 0.0
        for (index, value) in values.enumerated() {
            let weight = index >= recentStart ? recentWeight : 1.0
            weightedSum += value * weight
            totalWeight += weight
        }
        guard totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }

    private static func meanOf(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func standardDeviationOf(_ values: [Double]) -> Double? {
        sampleStandardDeviation(values)
    }

    /// Shared Personal Baseline statistics used by Daily Health Computation and
    /// individual score implementations. The math lives in `ScoringMath`.
    static func median(_ values: [Double]) -> Double? {
        ScoringMath.median(values)
    }

    static func sampleStandardDeviation(_ values: [Double]) -> Double? {
        ScoringMath.sampleStandardDeviation(values)
    }

    static func robustStandardDeviation(
        _ values: [Double],
        around median: Double
    ) -> Double? {
        ScoringMath.robustStandardDeviation(values, around: median)
    }

    static func resolveThresholds() -> PersonalBaselineThresholds {
        var base: PersonalBaselineThresholds
        if let loaded = loadBaselinesFromWiki(),
           loaded.baselines.daysOfData >= 7,
           let recMean = loaded.baselines.recoveryBaselineMean,
           let recSD = loaded.baselines.recoveryBaselineSD,
           let sleepMean = loaded.baselines.sleepScoreBaselineMean,
           let sleepSD = loaded.baselines.sleepScoreBaselineSD {
            let recRest = min(50, max(30, recMean - 1.5 * recSD))
            let recCaution = min(70, max(50, recMean - 0.8 * recSD))
            let recHigh = min(80, max(60, recMean))
            let sleepCaution = min(75, max(55, sleepMean - 0.8 * sleepSD))
            let sleepRest = min(60, max(45, sleepMean - 1.5 * sleepSD))
            base = PersonalBaselineThresholds(
                recoveryRest: recRest,
                recoveryCaution: recCaution,
                recoveryHigh: recHigh,
                sleepCaution: sleepCaution,
                sleepRest: sleepRest,
                source: "using personal baseline"
            )
        } else {
            base = PersonalBaselineThresholds(
                recoveryRest: 40,
                recoveryCaution: 62,
                recoveryHigh: 70,
                sleepCaution: 68,
                sleepRest: 55,
                source: "using default conservative threshold"
            )
        }
        // 深度专项批次 6（管线 B）：strategies.md 的用户确认阈值覆盖——
        // AI 提议 → MemoryProposal → 用户确认写入 wiki → 此处生效（ADR 0008）。
        let strategiesLines = WikiFileService.loadPopulatedDictionary()["strategies.md"]?
            .components(separatedBy: "\n") ?? []
        let overridden = applyThresholdOverrides(strategiesLines, to: base)
        return overridden
    }

    /// 纯函数：从 strategies.md 行文本解析用户确认的阈值覆盖。
    /// 格式：`- recovery_rest: 45`（每项钳制在保守范围内，非法值忽略）。
    static func applyThresholdOverrides(
        _ lines: [String],
        to thresholds: PersonalBaselineThresholds
    ) -> PersonalBaselineThresholds {
        var resolved = thresholds
        var applied = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else { continue }
            let body = String(trimmed.dropFirst(2))
            guard let colon = body.firstIndex(of: ":") else { continue }
            let key = String(body[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let rawValue = String(body[body.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            guard let value = Double(rawValue), value.isFinite else { continue }
            switch key {
            case "recovery_rest":
                resolved.recoveryRest = min(50, max(30, value))
                applied = true
            case "recovery_caution":
                resolved.recoveryCaution = min(70, max(50, value))
                applied = true
            case "sleep_rest":
                resolved.sleepRest = min(60, max(45, value))
                applied = true
            case "sleep_caution":
                resolved.sleepCaution = min(75, max(55, value))
                applied = true
            default:
                break
            }
        }
        if applied {
            resolved.source = "user-confirmed strategies.md"
        }
        return resolved
    }

    // MARK: - Huber Loss Robust Estimator (Vertical Deep Optimization)

    /// Computes a Huber M-estimator robust mean resistant to single-day extreme outliers (e.g. alcohol / sensor noise).
    static func huberMean(_ values: [Double], k: Double = 1.5, maxIterations: Int = 10) -> Double? {
        guard !values.isEmpty else { return nil }
        var mu = median(values) ?? (values.reduce(0, +) / Double(values.count))
        let scale = (robustStandardDeviation(values, around: mu) ?? 1.0)

        guard scale > 0.001 else { return mu }

        for _ in 0..<maxIterations {
            var sumWeights = 0.0
            var sumWeightedValues = 0.0

            for x in values {
                let residual = (x - mu) / scale
                let absRes = abs(residual)
                let w = absRes <= k ? 1.0 : k / absRes
                sumWeights += w
                sumWeightedValues += w * x
            }

            guard sumWeights > 0 else { break }
            let nextMu = sumWeightedValues / sumWeights
            if abs(nextMu - mu) < 0.001 { break }
            mu = nextMu
        }
        return mu
    }
}

struct PersonalBaselineThresholds {
    var recoveryRest: Double
    var recoveryCaution: Double
    var recoveryHigh: Double
    var sleepCaution: Double
    var sleepRest: Double
    var source: String
}

// MARK: - Long-term baseline engine（三年长线基准）

enum LongTermBaselineMetric: String, CaseIterable, Hashable, Sendable, Identifiable {
    case restingHeartRate
    case hrv
    case sleepHours
    case bodyWeight
    case bodyFatPercent
    case steps
    case activeCalories

    var id: String { rawValue }

    var title: String {
        switch self {
        case .restingHeartRate: return "静息心率"
        case .hrv: return "HRV"
        case .sleepHours: return "睡眠时长"
        case .bodyWeight: return "体重"
        case .bodyFatPercent: return "体脂率"
        case .steps: return "步数"
        case .activeCalories: return "活动能量"
        }
    }

    var unit: String {
        switch self {
        case .restingHeartRate: return "bpm"
        case .hrv: return "ms"
        case .sleepHours: return "小时"
        case .bodyWeight: return "kg"
        case .bodyFatPercent: return "%"
        case .steps: return "步"
        case .activeCalories: return "kcal"
        }
    }

    /// 数值变大是否代表变好（趋势与偏离的解读方向）。
    var improvementIsPositive: Bool {
        switch self {
        case .restingHeartRate: return false
        case .hrv: return true
        case .sleepHours: return true
        case .bodyWeight: return false
        case .bodyFatPercent: return false
        case .steps: return true
        case .activeCalories: return true
        }
    }
}

/// 三年长线统计的一个输入日（只含原始字段）。
struct LongTermBaselinePoint: Hashable, Sendable {
    var date: Date
    var hrvAverage: Double?
    var restingHeartRate: Double?
    var sleepHours: Double?
    var bodyWeight: Double?
    var bodyFatPercent: Double?
    var steps: Double?
    var activeCalories: Double?
    var workoutCount: Int?
    var workoutDuration: Double?

    func value(for metric: LongTermBaselineMetric) -> Double? {
        switch metric {
        case .restingHeartRate: return restingHeartRate
        case .hrv: return hrvAverage
        case .sleepHours: return sleepHours
        case .bodyWeight: return bodyWeight
        case .bodyFatPercent: return bodyFatPercent
        case .steps: return steps
        case .activeCalories: return activeCalories
        }
    }
}

protocol LongTermBaselineSample {
    var date: Date { get }
    var hrvAverage: Double? { get }
    var restingHeartRate: Double? { get }
    var sleepHours: Double? { get }
    var bodyWeight: Double? { get }
    var bodyFatPercent: Double? { get }
    var steps: Double? { get }
    var activeCalories: Double? { get }
    var workoutCount: Int? { get }
    var workoutDuration: Double? { get }
}

extension LongTermBaselineSample {
    var longTermBaselinePoint: LongTermBaselinePoint {
        LongTermBaselinePoint(
            date: date,
            hrvAverage: hrvAverage,
            restingHeartRate: restingHeartRate,
            sleepHours: sleepHours,
            bodyWeight: bodyWeight,
            bodyFatPercent: bodyFatPercent,
            steps: steps,
            activeCalories: activeCalories,
            workoutCount: workoutCount,
            workoutDuration: workoutDuration
        )
    }
}

extension DailyHealthSnapshot: LongTermBaselineSample {}
extension DailyHealthSummaryRecord: LongTermBaselineSample {}

struct LongTermMetricBaseline: Hashable, Sendable {
    var metric: LongTermBaselineMetric
    var sampleCount: Int
    var threeYearMedian: Double?
    var percentile10: Double?
    var percentile25: Double?
    var percentile75: Double?
    var percentile90: Double?
    var recent30DayMean: Double?
    /// (近 30 天均值 - 三年中位) / 三年中位 × 100；缺失时不输出。
    var longTermDeviationPercent: Double?
    /// 今年（1/1 至今）均值 - 去年同期对齐时段均值；任一时段样本 < 7 天时为 nil。
    var yearOverYearDelta: Double?
    /// 三年月均值的年化斜率：improving / stable / worsening / nil（数据不足）。
    var trendLabel: String?
}

struct TrainingVolumeMonth: Hashable, Sendable {
    var date: Date
    var value: Double
}

struct TrainingVolumeLongTerm: Hashable, Sendable {
    /// 三年逐月训练分钟（键为当月 1 号）。
    var monthlyMinutes: [TrainingVolumeMonth] = []
    var currentMonthMinutes: Double = 0
    /// 本月分钟数在三年月分布中的百分位（0-100；样本不足时为 nil）。
    var currentMonthPercentile: Double?
    var lastYearSameMonthMinutes: Double?
    var sampleMonths: Int = 0
}

struct LongTermBaselineReport: Hashable, Sendable {
    var calculatedAt: Date
    var daysOfData: Int
    var earliestDate: Date?
    var latestDate: Date?
    var baselines: [LongTermBaselineMetric: LongTermMetricBaseline] = [:]
    var trainingVolume: TrainingVolumeLongTerm?
    // 深度专项批次 3：同期三年月度 MAD 带（今天 vs 同月三年）。
    var monthlyHRV: MonthlyMADBaseline? = nil
    var monthlyRHR: MonthlyMADBaseline? = nil
    // 深度专项批次 3：近 30 天 vs 三年轨迹的脱轨信号。
    var derailmentHRV: DerailmentSignal? = nil
    var derailmentRHR: DerailmentSignal? = nil
    // 深度专项批次 3：月历节律（季节性剖面）。
    var seasonalHRV: SeasonalProfile? = nil
    var seasonalRHR: SeasonalProfile? = nil
}

// MARK: - 深度专项批次 3：三年建模（月度 MAD 带 / 脱轨 / 季节性）

/// 某个月份的稳健基线（同月三年内逐日值）。
struct MonthlyBaselineBand: Hashable, Sendable {
    var month: Int            // 1-12
    var sampleCount: Int
    var median: Double
    var mad: Double           // 1.4826 × 绝对中位差
}

/// 同期三年月度 MAD 基线：吸收冬夏节律，避免「夏天 HRV 被当成冬天的异常」。
struct MonthlyMADBaseline: Hashable, Sendable {
    var metric: LongTermBaselineMetric
    var bands: [MonthlyBaselineBand] = []

    static let minimumMonthSamples = 20
    static let minimumTotalSamples = 60

    static func compute(
        points: [LongTermBaselinePoint],
        metric: LongTermBaselineMetric,
        today: Date,
        calendar: Calendar
    ) -> MonthlyMADBaseline? {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today
        let ordered = points.filter { $0.date < endOfToday }
        var byMonth: [Int: [Double]] = [:]
        for point in ordered {
            guard let value = point.value(for: metric), value.isFinite, value > 0 else { continue }
            if metric == .restingHeartRate, value <= 20 { continue }
            if metric == .bodyWeight, value <= 30 { continue }
            byMonth[calendar.component(.month, from: point.date), default: []].append(value)
        }
        var bands: [MonthlyBaselineBand] = []
        for (month, values) in byMonth.sorted(by: { $0.key < $1.key }) {
            guard values.count >= minimumMonthSamples,
                  let med = PersonalBaselineEngine.median(values) else { continue }
            let mad = PersonalBaselineEngine.median(values.map { abs($0 - med) }) ?? 0
            let scaledMAD = mad * 1.4826
            bands.append(MonthlyBaselineBand(month: month, sampleCount: values.count, median: med, mad: scaledMAD))
        }
        let total = bands.reduce(0) { $0 + $1.sampleCount }
        guard total >= minimumTotalSamples else { return nil }
        return MonthlyMADBaseline(metric: metric, bands: bands)
    }

    /// 今日值在「同月三年带」里的 z 值；带不存在或 MAD 为 0 时返回 nil。
    func zScore(for value: Double, month: Int) -> Double? {
        guard let band = bands.first(where: { $0.month == month }), band.mad > 0 else { return nil }
        return (value - band.median) / band.mad
    }

    /// 同月带的中位/MAD（供决策理由展示）。
    func band(for month: Int) -> MonthlyBaselineBand? {
        bands.first { $0.month == month }
    }
}

/// 近 30 天轨迹 vs 三年轨迹的脱轨信号（只报不利方向）。
struct DerailmentSignal: Hashable, Sendable {
    var metric: LongTermBaselineMetric
    var longTermSlopePerDay: Double
    var recentSlopePerDay: Double
    var recentSampleDays: Int

    var summary: String {
        let unit = metric.unit
        return "近 30 天 \(metric.title) 变化速度（\(String(format: "%+.2f", recentSlopePerDay)) \(unit)/天）明显快于三年轨迹（\(String(format: "%+.3f", longTermSlopePerDay)) \(unit)/天）"
    }

    /// 方向不利（RHR 上升 / HRV 下降）且近期速度显著快于长期轨迹时触发。
    static func detect(
        points: [LongTermBaselinePoint],
        metric: LongTermBaselineMetric,
        today: Date,
        calendar: Calendar
    ) -> DerailmentSignal? {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today
        let ordered = points
            .filter { $0.date < endOfToday }
            .sorted { $0.date < $1.date }
        guard ordered.count >= 180 else { return nil }
        let recentStart = calendar.date(byAdding: .day, value: -30, to: today) ?? today
        let recent = ordered.filter { $0.date >= recentStart }
        guard recent.count >= 20 else { return nil }

        // 三年月均值最小二乘斜率（天）。
        func monthStartDate(_ date: Date) -> Date {
            calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        }
        var monthly: [(x: Double, y: Double)] = []
        let groupedByMonth = Dictionary(grouping: ordered) { monthStartDate($0.date) }
        for (monthStart, pointsInMonth) in groupedByMonth {
            let valid = pointsInMonth.compactMap { $0.value(for: metric) }.filter { $0 > 0 && $0.isFinite }
            guard valid.count >= 5, let med = PersonalBaselineEngine.median(valid) else { continue }
            monthly.append((x: monthStart.timeIntervalSince1970 / 86_400, y: med))
        }
        guard monthly.count >= 6 else { return nil }
        let longSlope = leastSquaresSlope(monthly)
        // 近 30 天逐日最小二乘斜率（天）。
        var daily: [(x: Double, y: Double)] = []
        for point in recent {
            guard let value = point.value(for: metric), value > 0, value.isFinite else { continue }
            daily.append((x: point.date.timeIntervalSince1970 / 86_400, y: value))
        }
        guard daily.count >= 20 else { return nil }
        let recentSlope = leastSquaresSlope(daily)
        // 方向判定：RHR 上升不利、HRV 下降不利。
        let unfavorable: Bool
        switch metric {
        case .restingHeartRate: unfavorable = recentSlope > 0
        case .hrv: unfavorable = recentSlope < 0
        default: unfavorable = false
        }
        guard unfavorable else { return nil }
        // 触发：近期速度 ≥ 长期速度的 5 倍（且长期接近 0 时给最小绝对速度地板）。
        let floor: Double = metric == .restingHeartRate ? 0.02 : 0.05
        let threshold = max(5 * abs(longSlope), floor)
        guard abs(recentSlope) >= threshold else { return nil }
        return DerailmentSignal(
            metric: metric,
            longTermSlopePerDay: longSlope,
            recentSlopePerDay: recentSlope,
            recentSampleDays: daily.count
        )
    }

    private static func leastSquaresSlope(_ samples: [(x: Double, y: Double)]) -> Double {
        guard samples.count >= 2 else { return 0 }
        let n = Double(samples.count)
        let meanX = samples.reduce(0) { $0 + $1.x } / n
        let meanY = samples.reduce(0) { $0 + $1.y } / n
        let sxx = samples.reduce(0) { $0 + ($1.x - meanX) * ($1.x - meanX) }
        let sxy = samples.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        guard sxx > 0 else { return 0 }
        return sxy / sxx
    }
}

/// 12 个月份均值剖面与季节幅度（≥2 年数据才发布）。
struct SeasonalProfile: Hashable, Sendable {
    var metric: LongTermBaselineMetric
    var monthlyMeans: [Int: Double] = [:]
    var amplitudePercent: Double?     // (max-min)/三年中位 × 100
    var hasSeasonality: Bool
    var peakMonth: Int?
    var troughMonth: Int?

    var summary: String? {
        guard hasSeasonality, let amplitudePercent else { return nil }
        return "\(metric.title)存在约 ±\(String(format: "%.0f", amplitudePercent))% 的季节波动（峰值 \(peakMonth ?? 0) 月）"
    }

    static func detect(
        points: [LongTermBaselinePoint],
        metric: LongTermBaselineMetric,
        today: Date,
        calendar: Calendar
    ) -> SeasonalProfile? {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today
        let ordered = points.filter { $0.date < endOfToday }
        var byMonth: [Int: [Double]] = [:]
        for point in ordered {
            guard let value = point.value(for: metric), value > 0, value.isFinite else { continue }
            byMonth[calendar.component(.month, from: point.date), default: []].append(value)
        }
        let monthsPresent = byMonth.filter { $0.value.count >= 15 }
        guard monthsPresent.count >= 8, ordered.count >= 730 else { return nil }
        var means: [Int: Double] = [:]
        var allValues: [Double] = []
        for (month, values) in monthsPresent {
            let mean = values.reduce(0, +) / Double(values.count)
            means[month] = mean
            allValues.append(contentsOf: values)
        }
        guard let median = PersonalBaselineEngine.median(allValues), median > 0 else { return nil }
        let sortedMeans = means.sorted { $0.value < $1.value }
        let minMean = sortedMeans.first
        let maxMean = sortedMeans.last
        let amplitude = ((maxMean?.value ?? 0) - (minMean?.value ?? 0)) / median * 100
        let threshold = metric == .restingHeartRate ? 3.0 : 8.0
        let hasSeasonality = amplitude > threshold
        return SeasonalProfile(
            metric: metric,
            monthlyMeans: means,
            amplitudePercent: hasSeasonality ? amplitude : nil,
            hasSeasonality: hasSeasonality,
            peakMonth: hasSeasonality ? maxMean?.key : nil,
            troughMonth: hasSeasonality ? minMean?.key : nil
        )
    }
}

enum LongTermBaselineEngine {
    /// 单指标三年长线统计需要的最少天数（少于则整体不发布该指标）。
    static let minimumDays = 60

    static func compute(
        points: [LongTermBaselinePoint],
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> LongTermBaselineReport {
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: today)) ?? today
        let ordered = points
            .filter { $0.date < endOfToday }
            .sorted { $0.date < $1.date }
        guard !ordered.isEmpty else {
            return LongTermBaselineReport(calculatedAt: today, daysOfData: 0, earliestDate: nil, latestDate: nil)
        }

        var baselines: [LongTermBaselineMetric: LongTermMetricBaseline] = [:]
        for metric in LongTermBaselineMetric.allCases {
            let values = ordered
                .compactMap { point -> Double? in
                    guard let value = point.value(for: metric), value.isFinite else { return nil }
                    switch metric {
                    case .bodyWeight: return value > 30 ? value : nil
                    case .restingHeartRate: return value > 20 ? value : nil
                    default: return value > 0 ? value : nil
                    }
                }
            guard values.count >= minimumDays else { continue }
            let median = PersonalBaselineEngine.median(values)
            let recent30 = recentMean(of: ordered, for: metric, calendar: calendar, today: today)
            let yoy = samePeriodDelta(of: ordered, for: metric, calendar: calendar, today: today)
            let trend = trendLabel(of: ordered, for: metric, calendar: calendar)
            var deviation: Double?
            if let median, median > 0, let recent30 {
                deviation = (recent30 - median) / median * 100
            }
            baselines[metric] = LongTermMetricBaseline(
                metric: metric,
                sampleCount: values.count,
                threeYearMedian: median,
                percentile10: percentile(values, 0.10),
                percentile25: percentile(values, 0.25),
                percentile75: percentile(values, 0.75),
                percentile90: percentile(values, 0.90),
                recent30DayMean: recent30,
                longTermDeviationPercent: deviation,
                yearOverYearDelta: yoy,
                trendLabel: trend
            )
        }

        let volume = trainingVolume(of: ordered, calendar: calendar, today: today)

        // 深度专项批次 3：三年建模（月度 MAD 带 / 脱轨 / 季节性）。
        let monthlyHRV = MonthlyMADBaseline.compute(points: ordered, metric: .hrv, today: today, calendar: calendar)
        let monthlyRHR = MonthlyMADBaseline.compute(points: ordered, metric: .restingHeartRate, today: today, calendar: calendar)
        let derailmentHRV = DerailmentSignal.detect(points: ordered, metric: .hrv, today: today, calendar: calendar)
        let derailmentRHR = DerailmentSignal.detect(points: ordered, metric: .restingHeartRate, today: today, calendar: calendar)
        let seasonalHRV = SeasonalProfile.detect(points: ordered, metric: .hrv, today: today, calendar: calendar)
        let seasonalRHR = SeasonalProfile.detect(points: ordered, metric: .restingHeartRate, today: today, calendar: calendar)

        return LongTermBaselineReport(
            calculatedAt: today,
            daysOfData: ordered.count,
            earliestDate: ordered.first?.date,
            latestDate: ordered.last?.date,
            baselines: baselines,
            trainingVolume: volume,
            monthlyHRV: monthlyHRV,
            monthlyRHR: monthlyRHR,
            derailmentHRV: derailmentHRV,
            derailmentRHR: derailmentRHR,
            seasonalHRV: seasonalHRV,
            seasonalRHR: seasonalRHR
        )
    }

    // MARK: - Training volume

    static func trainingVolume(
        of points: [LongTermBaselinePoint],
        calendar: Calendar,
        today: Date
    ) -> TrainingVolumeLongTerm? {
        let start = calendar.date(byAdding: .year, value: -3, to: today) ?? today
        let window = points.filter { $0.date >= start && $0.date < today }
        guard !window.isEmpty else { return nil }

        var sums: [Date: Double] = [:]
        for point in window {
            guard let minutes = point.workoutDuration, minutes > 0 else { continue }
            let month = monthStart(of: point.date, calendar: calendar)
            sums[month, default: 0] += minutes
        }
        let monthly = sums.keys.sorted().map { TrainingVolumeMonth(date: $0, value: sums[$0] ?? 0) }
        guard monthly.count >= 6 else { return nil }

        let currentMonth = monthStart(of: today, calendar: calendar)
        let current = sums[currentMonth] ?? 0
        let priorMonths = monthly.filter { $0.date != currentMonth }.map(\.value)
        var percentileValue: Double?
        if !priorMonths.isEmpty {
            let below = priorMonths.filter { $0 <= current }.count
            percentileValue = Double(below) / Double(priorMonths.count) * 100
        }
        let lastYearSameMonth = calendar.date(byAdding: .year, value: -1, to: currentMonth)
            .flatMap { sums[$0] }

        return TrainingVolumeLongTerm(
            monthlyMinutes: monthly,
            currentMonthMinutes: current,
            currentMonthPercentile: percentileValue,
            lastYearSameMonthMinutes: lastYearSameMonth,
            sampleMonths: monthly.count
        )
    }

    // MARK: - Formatting

    /// 长线基线 → 中文证据行（Coach 上下文 / 决策理由共用）。
    static func contextLines(_ report: LongTermBaselineReport) -> [String] {
        var lines: [String] = []
        for metric in LongTermBaselineMetric.allCases {
            guard let baseline = report.baselines[metric],
                  let median = baseline.threeYearMedian else { continue }
            var parts: [String] = []
            let medianText = String(format: "%.0f", median)
            if let p25 = baseline.percentile25, let p75 = baseline.percentile75 {
                parts.append("三年中位 \(medianText) \(metric.unit)（P25–P75 \(String(format: "%.0f", p25))–\(String(format: "%.0f", p75))）")
            } else {
                parts.append("三年中位 \(medianText) \(metric.unit)")
            }
            if let recent = baseline.recent30DayMean {
                parts.append("近 30 天均值 \(String(format: "%.0f", recent))")
            }
            if let deviation = baseline.longTermDeviationPercent {
                parts.append("长期偏离 \(String(format: "%+.0f", deviation))%")
            }
            if let yoy = baseline.yearOverYearDelta {
                parts.append("今年 vs 去年 \(String(format: "%+.0f", yoy)) \(metric.unit)")
            }
            if let trend = baseline.trendLabel {
                let label: String
                switch trend {
                case "improving": label = "趋势 改善"
                case "worsening": label = "趋势 走弱"
                default: label = "趋势 平稳"
                }
                parts.append(label)
            }
            lines.append("\(metric.title)：\(parts.joined(separator: "，"))")
        }
        if let volume = report.trainingVolume {
            var line = "训练量：本月 \(Int(volume.currentMonthMinutes.rounded())) 分钟"
            if let pct = volume.currentMonthPercentile {
                line += "，处于三年月分布 P\(Int(pct.rounded()))"
            }
            if let lastYear = volume.lastYearSameMonthMinutes {
                line += "，去年同月 \(Int(lastYear.rounded())) 分钟"
            }
            lines.append(line)
        }
        return lines
    }

    /// baselines.md 的「三年长期基线」章节（30 天基线表之后追加；解析器按行名读取，互不冲突）。
    static func formatForWiki(_ report: LongTermBaselineReport) -> String {
        var lines: [String] = [
            "",
            "## Three-Year Long-Term Baselines",
            "",
            "**Days of long-term data:** \(report.daysOfData)",
        ]
        guard !report.baselines.isEmpty else {
            return lines.joined(separator: "\n")
        }
        lines.append(contentsOf: [
            "",
            "| Metric | 3-Year Median (P25-P75) | Last 30 Days | Year-over-Year | Trend |",
            "|--------|-------------------------|--------------|----------------|-------|",
        ])
        for metric in LongTermBaselineMetric.allCases {
            guard let baseline = report.baselines[metric],
                  let median = baseline.threeYearMedian else { continue }
            let p25 = baseline.percentile25.map { String(format: "%.0f", $0) } ?? "—"
            let p75 = baseline.percentile75.map { String(format: "%.0f", $0) } ?? "—"
            let recent = baseline.recent30DayMean.map { String(format: "%.0f", $0) } ?? "—"
            let yoy = baseline.yearOverYearDelta.map { String(format: "%+.0f", $0) } ?? "—"
            let trend = baseline.trendLabel ?? "—"
            lines.append("| \(metric.title) 3Y | \(median.formatted(.number.precision(.fractionLength(0)))) \(metric.unit) (\(p25)-\(p75)) | \(recent) | \(yoy) | \(trend) |")
        }
        if let volume = report.trainingVolume {
            lines.append("| 本月训练量 3Y | \(Int(volume.currentMonthMinutes.rounded())) 分钟 | P\(Int((volume.currentMonthPercentile ?? 0).rounded())) | \(volume.lastYearSameMonthMinutes.map { "\(Int($0.rounded())) 分钟" } ?? "—") | — |")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func recentMean(
        of points: [LongTermBaselinePoint],
        for metric: LongTermBaselineMetric,
        calendar: Calendar,
        today: Date
    ) -> Double? {
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -30, to: today) ?? today)
        let values = points
            .filter { $0.date >= cutoff }
            .compactMap { $0.value(for: metric) }
            .filter { $0.isFinite && $0 > 0 }
        guard values.count >= 7 else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 今年（1/1 至今）vs 去年同对齐时段；任一时段不足 7 天返回 nil。
    private static func samePeriodDelta(
        of points: [LongTermBaselinePoint],
        for metric: LongTermBaselineMetric,
        calendar: Calendar,
        today: Date
    ) -> Double? {
        let thisYearStart = yearStart(of: today, calendar: calendar)
        let lastYearStart = yearStart(
            of: calendar.date(byAdding: .year, value: -1, to: today) ?? today,
            calendar: calendar
        )
        let thisYearEnd = calendar.startOfDay(for: today)
        let lastYearEnd = calendar.date(byAdding: .year, value: -1, to: thisYearEnd) ?? thisYearEnd

        func mean(_ include: (Date) -> Bool) -> Double? {
            let values = points
                .filter { include($0.date) }
                .compactMap { $0.value(for: metric) }
                .filter { $0.isFinite && $0 > 0 }
            guard values.count >= 7 else { return nil }
            return values.reduce(0, +) / Double(values.count)
        }
        guard let thisYear = mean({ $0 >= thisYearStart && $0 <= thisYearEnd }),
              let lastYear = mean({ $0 >= lastYearStart && $0 <= lastYearEnd }) else {
            return nil
        }
        return thisYear - lastYear
    }

    /// 三年趋势：月均值最小二乘斜率年化，相对三年中位的百分比；
    /// |年化变化| < 1% → stable，方向按指标语义判定 improving/worsening。
    private static func trendLabel(
        of points: [LongTermBaselinePoint],
        for metric: LongTermBaselineMetric,
        calendar: Calendar
    ) -> String? {
        var sums: [Date: (Double, Int)] = [:]
        for point in points {
            guard let value = point.value(for: metric), value.isFinite, value > 0 else { continue }
            let month = monthStart(of: point.date, calendar: calendar)
            var bucket = sums[month] ?? (0, 0)
            bucket.0 += value
            bucket.1 += 1
            sums[month] = bucket
        }
        let monthly = sums.keys.sorted().map { (date: $0, mean: sums[$0]!.0 / Double(sums[$0]!.1)) }
        guard monthly.count >= 9 else { return nil }
        guard let grandMedian = PersonalBaselineEngine.median(monthly.map(\.mean)), grandMedian > 0 else { return nil }

        let n = Double(monthly.count)
        let xMean = (n - 1) / 2
        var sxx = 0.0
        var sxy = 0.0
        for (index, entry) in monthly.enumerated() {
            let x = Double(index) - xMean
            sxx += x * x
            sxy += x * entry.mean
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        let percentPerYear = slope / grandMedian * 12 * 100

        if abs(percentPerYear) < 1.0 { return "stable" }
        let rising = slope > 0
        return rising == metric.improvementIsPositive ? "improving" : "worsening"
    }

    private static func percentile(_ values: [Double], _ fraction: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * fraction).rounded())
        return sorted[max(0, min(index, sorted.count - 1))]
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
