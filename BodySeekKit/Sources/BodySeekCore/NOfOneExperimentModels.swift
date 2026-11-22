import Foundation

public extension DayKey {
    /// Returns the `DayKey` offset by `days` calendar days using Gregorian calendar arithmetic.
    func addingDays(_ days: Int) -> DayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let comps = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let anchor = calendar.date(from: comps),
              let shifted = calendar.date(byAdding: .day, value: days, to: anchor) else {
            return self
        }
        let next = calendar.dateComponents([.year, .month, .day], from: shifted)
        return DayKey(
            year: next.year ?? year,
            month: next.month ?? month,
            day: next.day ?? day
        )
    }
}

public enum NOfOneExposureRule: String, Hashable, Codable, Sendable {
    case bedtimeBefore2330
    case stepsAtLeast10000
    case sleepAtLeast420Min

    public var ruleDescription: String {
        switch self {
        case .bedtimeBefore2330: "入睡时刻早于 23:30"
        case .stepsAtLeast10000: "全天步数 ≥ 10,000 步"
        case .sleepAtLeast420Min: "夜间有效睡眠 ≥ 7 小时（420 分钟）"
        }
    }
}

public enum NOfOneTargetMetric: String, Hashable, Codable, Sendable {
    case restingHeartRateBpm = "resting_hr_bpm"
    case hrvSdnnMs = "hrv_sdnn_ms"
    case sleepEfficiencyPct = "sleep_efficiency_pct"

    public var title: String {
        switch self {
        case .restingHeartRateBpm: "晨间静息心率 (RHR)"
        case .hrvSdnnMs: "次日夜间 HRV (SDNN)"
        case .sleepEfficiencyPct: "次日睡眠效率 (%)"
        }
    }

    public var unit: String {
        switch self {
        case .restingHeartRateBpm: "bpm"
        case .hrvSdnnMs: "ms"
        case .sleepEfficiencyPct: "%"
        }
    }
}

public struct NOfOneExperimentTemplate: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let title: String
    public let hypothesis: String
    public let durationDays: Int
    public let exposureRule: NOfOneExposureRule
    public let targetMetric: NOfOneTargetMetric

    public init(
        id: String,
        title: String,
        hypothesis: String,
        durationDays: Int = 14,
        exposureRule: NOfOneExposureRule,
        targetMetric: NOfOneTargetMetric
    ) {
        self.id = id
        self.title = title
        self.hypothesis = hypothesis
        self.durationDays = durationDays
        self.exposureRule = exposureRule
        self.targetMetric = targetMetric
    }

    public static let presets: [NOfOneExperimentTemplate] = [
        NOfOneExperimentTemplate(
            id: "early_bedtime_2330",
            title: "连续 14 天 23:30 前入睡",
            hypothesis: "基于个人历史规律（晚睡 RHR +1.81 bpm），检验早睡周期是否伴随更低静息心率。",
            durationDays: 14,
            exposureRule: .bedtimeBefore2330,
            targetMetric: .restingHeartRateBpm
        ),
        NOfOneExperimentTemplate(
            id: "daily_steps_10k",
            title: "14 天万步活动日测试",
            hypothesis: "检验日均 ≥ 10,000 步对次日夜间 HRV 的个体差异表现。",
            durationDays: 14,
            exposureRule: .stepsAtLeast10000,
            targetMetric: .hrvSdnnMs
        ),
        NOfOneExperimentTemplate(
            id: "sleep_duration_7h",
            title: "连续 14 天睡眠 ≥ 7 小时",
            hypothesis: "观察连续充足睡眠时长对次日睡眠效率的稳定性变化。",
            durationDays: 14,
            exposureRule: .sleepAtLeast420Min,
            targetMetric: .sleepEfficiencyPct
        ),
    ]
}

/// Persisted inside `PlanItemRecord.payloadJSON` with `kind = .experiment`.
public struct NOfOneExperimentRecord: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let templateID: String
    public let title: String
    public let hypothesis: String
    public let startDayKey: DayKey
    public let durationDays: Int
    public let exposureRule: NOfOneExposureRule
    public let targetMetric: NOfOneTargetMetric

    public init(
        id: UUID = UUID(),
        templateID: String,
        title: String,
        hypothesis: String,
        startDayKey: DayKey,
        durationDays: Int = 14,
        exposureRule: NOfOneExposureRule,
        targetMetric: NOfOneTargetMetric
    ) {
        self.id = id
        self.templateID = templateID
        self.title = title
        self.hypothesis = hypothesis
        self.startDayKey = startDayKey
        self.durationDays = durationDays
        self.exposureRule = exposureRule
        self.targetMetric = targetMetric
    }

    public init(template: NOfOneExperimentTemplate, startDayKey: DayKey, id: UUID = UUID()) {
        self.init(
            id: id,
            templateID: template.id,
            title: template.title,
            hypothesis: template.hypothesis,
            startDayKey: startDayKey,
            durationDays: template.durationDays,
            exposureRule: template.exposureRule,
            targetMetric: template.targetMetric
        )
    }

    public var endDayKey: DayKey {
        startDayKey.addingDays(max(0, durationDays - 1))
    }
}

public struct NOfOneExperimentEvaluation: Equatable, Hashable, Sendable {
    public let elapsedDays: Int
    public let durationDays: Int
    public let adherentDays: Int
    public let nonAdherentDays: Int
    public let excludedMissingDays: Int
    public let adherentMean: Double?
    public let nonAdherentMean: Double?
    public let delta: Double?
    public let targetUnit: String
    public let isSufficientSample: Bool
    public let summary: String
    public let disclaimer: String

    public init(
        elapsedDays: Int,
        durationDays: Int,
        adherentDays: Int,
        nonAdherentDays: Int,
        excludedMissingDays: Int,
        adherentMean: Double?,
        nonAdherentMean: Double?,
        delta: Double?,
        targetUnit: String,
        isSufficientSample: Bool,
        summary: String,
        disclaimer: String = "个人 N-of-1 观察对比 · 非临床因果结论"
    ) {
        self.elapsedDays = elapsedDays
        self.durationDays = durationDays
        self.adherentDays = adherentDays
        self.nonAdherentDays = nonAdherentDays
        self.excludedMissingDays = excludedMissingDays
        self.adherentMean = adherentMean
        self.nonAdherentMean = nonAdherentMean
        self.delta = delta
        self.targetUnit = targetUnit
        self.isSufficientSample = isSufficientSample
        self.summary = summary
        self.disclaimer = disclaimer
    }
}

/// Evaluates N-of-1 experiments without imputing missing days as zero or leaking post-reference days.
public enum NOfOneExperimentEvaluator {
    public static func evaluate(
        record: NOfOneExperimentRecord,
        historyDays: [DailyComputedDay],
        referenceDayKey: DayKey
    ) -> NOfOneExperimentEvaluation {
        let effectiveEnd = min(record.endDayKey, referenceDayKey)
        var byKey: [DayKey: DailyComputedDay] = [:]
        for day in historyDays where day.dayKey <= referenceDayKey {
            byKey[day.dayKey] = day
        }

        var cursor = record.startDayKey
        var elapsed = 0
        var adherentOutcomes: [Double] = []
        var nonAdherentOutcomes: [Double] = []
        var excludedMissing = 0

        let maxSpan = max(1, record.durationDays)
        while cursor <= effectiveEnd && elapsed < maxSpan {
            elapsed += 1
            if let adhered = evaluateAdherenceAndOutcome(
                dayKey: cursor,
                record: record,
                byKey: byKey
            ) {
                if adhered.didAdhere {
                    adherentOutcomes.append(adhered.outcome)
                } else {
                    nonAdherentOutcomes.append(adhered.outcome)
                }
            } else {
                excludedMissing += 1
            }
            cursor = cursor.addingDays(1)
        }

        let adherentMean = adherentOutcomes.isEmpty
            ? nil
            : adherentOutcomes.reduce(0, +) / Double(adherentOutcomes.count)
        let nonAdherentMean = nonAdherentOutcomes.isEmpty
            ? nil
            : nonAdherentOutcomes.reduce(0, +) / Double(nonAdherentOutcomes.count)

        let delta: Double?
        if let a = adherentMean, let b = nonAdherentMean {
            delta = a - b
        } else {
            delta = nil
        }

        let validPairs = adherentOutcomes.count + nonAdherentOutcomes.count
        let isSufficient = validPairs >= 4 && !adherentOutcomes.isEmpty && !nonAdherentOutcomes.isEmpty

        let summary: String
        if let a = adherentMean, let b = nonAdherentMean, let d = delta, isSufficient {
            let sign = d >= 0 ? "+" : ""
            summary = String(
                format: "达标日 (%d天) 均值 %.1f %@ vs 未达标日 (%d天) %.1f %@（差值 %@%.1f %@，已排除 %d 缺失天）",
                adherentOutcomes.count, a, record.targetMetric.unit,
                nonAdherentOutcomes.count, b, record.targetMetric.unit,
                sign, d, record.targetMetric.unit,
                excludedMissing
            )
        } else {
            summary = "已追踪 \(elapsed)/\(record.durationDays) 天（达标 \(adherentOutcomes.count) 天 / 对照 \(nonAdherentOutcomes.count) 天），缺失 \(excludedMissing) 天已排除（不作零计），达标与对照各 ≥ 1 天且累计 ≥ 4 个有效配对日后展示均值差。"
        }

        return NOfOneExperimentEvaluation(
            elapsedDays: max(1, elapsed),
            durationDays: record.durationDays,
            adherentDays: adherentOutcomes.count,
            nonAdherentDays: nonAdherentOutcomes.count,
            excludedMissingDays: excludedMissing,
            adherentMean: adherentMean,
            nonAdherentMean: nonAdherentMean,
            delta: delta,
            targetUnit: record.targetMetric.unit,
            isSufficientSample: isSufficient,
            summary: summary
        )
    }

    private struct PairOutcome {
        let didAdhere: Bool
        let outcome: Double
    }

    private static func evaluateAdherenceAndOutcome(
        dayKey: DayKey,
        record: NOfOneExperimentRecord,
        byKey: [DayKey: DailyComputedDay]
    ) -> PairOutcome? {
        guard let exposureDay = byKey[dayKey] else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        switch record.exposureRule {
        case .bedtimeBefore2330:
            // `sleepStart` on morning `dayKey` represents the bedtime leading into that night's sleep & morning RHR.
            guard let sleepStart = exposureDay.raw.sleepStart,
                  let rhr = outcomeValue(for: record.targetMetric, day: exposureDay) else {
                return nil
            }
            let comps = calendar.dateComponents([.hour, .minute], from: sleepStart)
            guard let hour = comps.hour, let minute = comps.minute else { return nil }
            let adhered = (hour >= 18 && hour < 23) || (hour == 23 && minute < 30)
            return PairOutcome(didAdhere: adhered, outcome: rhr)

        case .stepsAtLeast10000:
            guard let steps = exposureDay.raw.steps,
                  exposureDay.raw.hasAuthorizedHealthData else {
                return nil
            }
            let nextKey = dayKey.addingDays(1)
            guard let outcomeDay = byKey[nextKey],
                  let val = outcomeValue(for: record.targetMetric, day: outcomeDay) else {
                return nil
            }
            return PairOutcome(didAdhere: steps >= 10_000, outcome: val)

        case .sleepAtLeast420Min:
            guard let asleep = exposureDay.raw.sleepAsleepMinutes else { return nil }
            let nextKey = dayKey.addingDays(1)
            guard let outcomeDay = byKey[nextKey],
                  let val = outcomeValue(for: record.targetMetric, day: outcomeDay) else {
                return nil
            }
            return PairOutcome(didAdhere: asleep >= 420, outcome: val)
        }
    }

    private static func outcomeValue(for metric: NOfOneTargetMetric, day: DailyComputedDay) -> Double? {
        switch metric {
        case .restingHeartRateBpm:
            return day.raw.restingHeartRateBpm
        case .hrvSdnnMs:
            return day.raw.hrvMs
        case .sleepEfficiencyPct:
            guard let asleep = day.raw.sleepAsleepMinutes, asleep > 0 else { return nil }
            let denom = max(day.raw.sleepInBedMinutes ?? 0, asleep + (day.raw.awakeMinutes ?? 0))
            guard denom > 0 else { return nil }
            return min(100.0, max(0.0, Double(asleep) / Double(denom) * 100.0))
        }
    }
}

/// Anonymized statistical findings from M4a (`personal-patterns-v1`) seeded only in preview/demo mode.
public enum M4APersonalPatternSeeds {
    public static let seedIDs: Set<UUID> = Set(defaultCandidates().map(\.id))

    public static func defaultCandidates() -> [PatternFindingRecord] {
        [
            PatternFindingRecord(
                id: UUID(uuid: (0xA4, 0xA0, 0x00, 0x01, 0x00, 0x01, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01)),
                statement: "夜间睡眠不足 6 小时后，次日夜间总睡眠平均变化 -68.0 分钟（95% CI [-98.53, -36.20]，FDR q=0.0153）",
                effect: -68.00,
                ciLow: -98.53,
                ciHigh: -36.20,
                sampleSize: 417,
                method: "Block-Bootstrap + BH FDR q=0.0153 (M4a)",
                modelVersion: "personal-patterns-v1",
                status: .candidate
            ),
            PatternFindingRecord(
                id: UUID(uuid: (0xA4, 0xA0, 0x00, 0x01, 0x00, 0x02, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02)),
                statement: "单日万步（≥10,000 步）后，次日夜间 HRV 平均高 +3.61 ms（95% CI [+1.55, +5.55]，FDR q=0.0153）",
                effect: 3.61,
                ciLow: 1.55,
                ciHigh: 5.55,
                sampleSize: 809,
                method: "Block-Bootstrap + BH FDR q=0.0153 (M4a)",
                modelVersion: "personal-patterns-v1",
                status: .candidate
            ),
            PatternFindingRecord(
                id: UUID(uuid: (0xA4, 0xA0, 0x00, 0x01, 0x00, 0x03, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03)),
                statement: "入睡晚于 00:00 后，次日静息心率平均偏高 +1.81 bpm（95% CI [+0.72, +2.78]，FDR q=0.0345）",
                effect: 1.81,
                ciLow: 0.72,
                ciHigh: 2.78,
                sampleSize: 443,
                method: "Block-Bootstrap + BH FDR q=0.0345 (M4a)",
                modelVersion: "personal-patterns-v1",
                status: .candidate
            ),
            PatternFindingRecord(
                id: UUID(uuid: (0xA4, 0xA0, 0x00, 0x01, 0x00, 0x04, 0x40, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x04)),
                statement: "跑步训练日 vs 休息日，次日静息心率平均低 -1.81 bpm（95% CI [-2.69, -0.92]，FDR q=0.0153）",
                effect: -1.81,
                ciLow: -2.69,
                ciHigh: -0.92,
                sampleSize: 481,
                method: "Block-Bootstrap + BH FDR q=0.0153 (M4a)",
                modelVersion: "personal-patterns-v1",
                status: .candidate
            ),
        ]
    }
}
