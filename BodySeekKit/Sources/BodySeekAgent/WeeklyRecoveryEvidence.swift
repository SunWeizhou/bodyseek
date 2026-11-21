import BodySeekCore
import Foundation

/// Deterministic evidence for comparing the most recent seven physiological days
/// with the preceding, non-overlapping 28 days.
///
/// The builder is shared by the cloud tool and the Apple Foundation Models adapter.
/// It only reads already-computed scores and local records; it never re-scores.
public enum WeeklyRecoveryEvidenceError: LocalizedError, Sendable {
    case invalidDayKey(String)
    case futureDayKey(requested: String, latest: String)

    public var errorDescription: String? {
        switch self {
        case let .invalidDayKey(value):
            "日期格式无效：\(value)。请使用 YYYY-MM-DD。"
        case let .futureDayKey(requested, latest):
            "请求的结束日 \(requested) 晚于当前生理日 \(latest)。"
        }
    }
}

/// One number that the model may cite. Facts carry the metric, window/date and unit
/// so the provenance verifier can reject a number that exists elsewhere but is used
/// under the wrong metric, date or unit.
public struct EvidenceFact: Codable, Hashable, Sendable {
    public let key: String
    public let value: Double
    public let unit: String
    public let metric: String
    public let scope: String
    public let dayKey: String?
    public let state: String
    public let isEstimate: Bool
    public let source: String

    public init(
        key: String,
        value: Double,
        unit: String,
        metric: String,
        scope: String,
        dayKey: String? = nil,
        state: String = "available",
        isEstimate: Bool = false,
        source: String = "local"
    ) {
        self.key = key
        self.value = value
        self.unit = unit
        self.metric = metric
        self.scope = scope
        self.dayKey = dayKey
        self.state = state
        self.isEstimate = isEstimate
        self.source = source
    }
}

public struct WeeklyRecoveryEvidence: Codable, Hashable, Sendable {
    public let schemaVersion: Int
    public let referenceDayKey: String
    public let generatedAt: Date
    public let timeZoneIdentifier: String
    public let cutoverHour: Int
    public let endDayIsPartial: Bool
    public let target: WeeklyRecoveryWindow
    public let control: WeeklyRecoveryWindow
    public let recovery: WeeklyRecoveryComparison
    public let daily: [WeeklyRecoveryDay]
    public let coffeeObservations: [WeeklyCoffeeObservation]
    public let notes: [String]
    public let evidence: [EvidenceFact]
    public let truncated: Bool
}

public struct WeeklyRecoveryWindow: Codable, Hashable, Sendable {
    public let label: String
    public let startDayKey: String
    public let endDayKey: String
    public let days: Int
    public let metricStats: [WeeklyMetricWindowStats]
    public let rawStats: [WeeklyRawMetricWindowStats]
    public let workouts: WeeklyWorkoutSummary
    public let checkIns: WeeklyCheckInSummary
    public let nutrition: WeeklyNutritionSummary
}

public struct WeeklyMetricWindowStats: Codable, Hashable, Sendable {
    public let metric: String
    public let unit: String
    public let availableDays: Int
    public let knownZeroDays: Int
    public let missingDays: Int
    public let excludedDays: Int
    public let coverage: Double
    public let sampleCount: Int
    public let median: Int?
    public let p25: Int?
    public let p75: Int?
    public let minValue: Int?
    public let maxValue: Int?
    public let latestValue: Int?
    public let latestDayKey: String?
}

public struct WeeklyRawMetricWindowStats: Codable, Hashable, Sendable {
    public let metric: String
    public let unit: String
    public let availableDays: Int
    public let missingDays: Int
    public let coverage: Double
    public let sampleCount: Int
    public let median: Double?
    public let p25: Double?
    public let p75: Double?
    public let minValue: Double?
    public let maxValue: Double?
    public let latestValue: Double?
    public let latestDayKey: String?
}

public struct WeeklyRecoveryComparison: Codable, Hashable, Sendable {
    public let metric: String
    public let targetMedian: Int?
    public let controlMedian: Int?
    public let delta: Int?
    public let direction: String
    public let isDecline: Bool
    public let evidenceSufficient: Bool
    public let targetSampleCount: Int
    public let controlSampleCount: Int
    public let minimumControlSamples: Int
    public let note: String
}

public struct WeeklyRecoveryDay: Codable, Hashable, Sendable {
    public let dayKey: String
    public let isPartial: Bool
    public let metrics: [WeeklyDayMetric]
    public let sleep: WeeklyDaySleep?
    public let checkIn: WeeklyDayCheckIn?
    public let nutrition: WeeklyDayNutrition?
    public let workouts: [WeeklyDayWorkout]
}

public struct WeeklyDayMetric: Codable, Hashable, Sendable {
    public let metric: String
    public let value: Int?
    public let state: String
    public let baselineDelta: Int?
}

public struct WeeklyDaySleep: Codable, Hashable, Sendable {
    public let score: Int?
    public let state: String
    public let asleepMinutes: Int?
    public let inBedMinutes: Int?
    public let deepMinutes: Int?
    public let remMinutes: Int?
    public let coreMinutes: Int?
    public let awakeMinutes: Int?
    public let efficiencyPct: Int?
    public let goalMinutes: Int
    public let start: Date?
    public let end: Date?
}

public struct WeeklyDayCheckIn: Codable, Hashable, Sendable {
    public let energy: Int
    public let mood: Int
    public let stress: Int
    public let sorenessMax: Int?
    public let sorenessCount: Int
    public let note: String?
}

public struct WeeklyDayNutrition: Codable, Hashable, Sendable {
    public let dayComplete: Bool?
    public let kcal: Double?
    public let kcalLower: Double?
    public let kcalUpper: Double?
    public let proteinG: Double?
    public let carbsG: Double?
    public let fatG: Double?
    public let fiberG: Double?
    public let waterMl: Double?
    public let entryCount: Int
    public let estimatedEntryCount: Int
    public let partialFields: [String]
    /// Meal timing has no reliable source in the current schema. `recordedAt` is the
    /// save time, never the meal time, so this stays unknown.
    public let mealTimePrecision: String
    public let recordedAtIsSaveTime: Bool
    public let coffeeCount: Int
}

public struct WeeklyDayWorkout: Codable, Hashable, Sendable {
    public let uuid: String
    public let source: String
    public let type: String
    public let dayKey: String
    public let start: Date
    public let end: Date
    public let durationMinutes: Int
    public let energyKcal: Double?
    public let avgHR: Double?
    public let effortUser: Double?
    public let effortEstimated: Double?
    public let reviewState: String
    public let annotationText: String?
    public let primaryMuscles: [String]
}

public struct WeeklyWorkoutSummary: Codable, Hashable, Sendable {
    public let count: Int
    public let totalMinutes: Int
    public let totalEnergyKcal: Double
    public let byType: [String: Int]
    public let truncated: Bool
}

public struct WeeklyCheckInSummary: Codable, Hashable, Sendable {
    public let days: Int
    public let averageEnergy: Double?
    public let averageMood: Double?
    public let averageStress: Double?
}

public struct WeeklyNutritionSummary: Codable, Hashable, Sendable {
    public let recordedDays: Int
    public let completeDays: Int
    public let partialDays: Int
    public let averageKcal: Double?
    public let averageProteinG: Double?
    public let mealTimePrecision: String
}

public struct WeeklyCoffeeObservation: Codable, Hashable, Sendable {
    public let dayKey: String
    public let name: String
    public let mealType: String
    public let timeKnown: Bool
    public let note: String
}

public enum WeeklyRecoveryEvidenceBuilder {
    private static let cutoverHour = 4
    private static let targetDays = 7
    private static let controlDays = 28
    private static let maximumFacts = 400
    private static let maximumWorkoutsPerDay = 8
    private static let coffeeKeywords = ["咖啡", "拿铁", "美式", "摩卡", "浓缩", "cappuccino", "latte", "espresso"]

    public static func build(
        endDayKey: DayKey?,
        asOf: Date,
        context: AgentExecutionContext,
        calendar: Calendar = .current
    ) throws -> WeeklyRecoveryEvidence {
        let timeZone = calendar.timeZone
        let currentKey = asOf.physiologicalDayKey(cutoverHour: cutoverHour, timeZone: timeZone)
        let endKey = endDayKey ?? currentKey
        if endKey > currentKey {
            throw WeeklyRecoveryEvidenceError.futureDayKey(
                requested: endKey.isoString,
                latest: currentKey.isoString
            )
        }

        let targetKeys = (0..<targetDays).map { endKey.addingDays($0 - (targetDays - 1)) }
        let controlKeys = (0..<controlDays).map { endKey.addingDays($0 - (controlDays + 6)) }
        let targetSet = Set(targetKeys)
        let controlSet = Set(controlKeys)
        guard targetSet.isDisjoint(with: controlSet) else {
            throw WeeklyRecoveryEvidenceError.invalidDayKey(endKey.isoString)
        }

        let historyByKey = Dictionary(
            context.snapshot.historyDays.map { ($0.dayKey, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        let endIsPartial = endKey == currentKey

        var facts: [EvidenceFact] = []
        var truncated = false

        let target = buildWindow(
            label: "target",
            keys: targetKeys,
            historyByKey: historyByKey,
            context: context,
            asOf: asOf,
            currentKey: currentKey,
            timeZone: timeZone,
            facts: &facts
        )
        let control = buildWindow(
            label: "control",
            keys: controlKeys,
            historyByKey: historyByKey,
            context: context,
            asOf: asOf,
            currentKey: currentKey,
            timeZone: timeZone,
            facts: &facts
        )

        let recoveryTarget = target.metricStats.first { $0.metric == MetricKind.recovery.rawValue }
        let recoveryControl = control.metricStats.first { $0.metric == MetricKind.recovery.rawValue }
        let recovery = makeRecoveryComparison(target: recoveryTarget, control: recoveryControl)
        appendRecoveryFacts(recovery, target: recoveryTarget, control: recoveryControl, facts: &facts)

        var coffeeFindings: [WeeklyCoffeeObservation] = []
        let daily = targetKeys.map { key -> WeeklyRecoveryDay in
            let day = historyByKey[key]
            let checkIn = latestCheckIn(for: key, in: context.checkIns, timeZone: timeZone)
            let nutrition = nutritionSummary(for: key, context: context)
            if let nutrition {
                coffeeFindings.append(contentsOf: coffeeObservations(for: key, context: context))
                appendNutritionFacts(key: key, value: nutrition, facts: &facts)
            }
            if let checkIn {
                appendCheckInFacts(key: key, value: checkIn, facts: &facts)
            }
            var workouts = dayWorkouts(for: key, context: context, asOf: asOf, timeZone: timeZone)
            if workouts.count > maximumWorkoutsPerDay {
                workouts = Array(workouts.prefix(maximumWorkoutsPerDay))
                truncated = true
            }
            if let day {
                appendDailyMetricFacts(key: key, day: day, facts: &facts)
            }
            appendWorkoutCountFact(key: key, workouts: workouts, facts: &facts)
            return WeeklyRecoveryDay(
                dayKey: key.isoString,
                isPartial: key == currentKey,
                metrics: MetricKind.allCases.map { kind in
                    let score = day?.score(for: kind)
                    return WeeklyDayMetric(
                        metric: kind.rawValue,
                        value: score?.value,
                        state: score.map { stateLabel(for: $0.availability) } ?? "missing",
                        baselineDelta: score?.baselineDelta
                    )
                },
                sleep: day.map { sleepSummary($0, goalMinutes: context.sleepGoalMinutes) },
                checkIn: checkIn,
                nutrition: nutrition,
                workouts: workouts
            )
        }

        // Keep the newest coffee observations first and bounded.
        coffeeFindings = Array(coffeeFindings.sorted { $0.dayKey > $1.dayKey }.prefix(12))

        var notes: [String] = [
            "目标窗与对照窗不重叠：目标窗为最近 7 个 04:00 生理日，对照窗为其之前的 28 个生理日。",
            "覆盖率为有效观测天数除以窗口天数；统计样本数单列，二者不可互换。",
            "恢复比较是点估计与四分位，不构成显著性、因果或医学结论。",
            "进食时刻当前没有可靠来源；recorded_at 只是录入/保存时间，不能当作进食时间。咖啡名称仅作观察线索。",
        ]
        if endIsPartial {
            notes.append("目标窗最后一天是当前生理日，数据尚未结束。")
        }
        if recovery.controlSampleCount < recovery.minimumControlSamples {
            notes.append("对照窗恢复有效样本 \(recovery.controlSampleCount)/\(controlDays) 天，低于 \(recovery.minimumControlSamples) 天，证据不足。")
        }
        if target.workouts.truncated || control.workouts.truncated || truncated {
            notes.append("部分日期的训练或记录超过返回上限，已标注截断。")
        }
        if !coffeeFindings.isEmpty {
            notes.append("检测到 \(coffeeFindings.count) 条咖啡记录，但无法确认饮用时刻。")
        }
        if facts.count > maximumFacts {
            facts = Array(facts.prefix(maximumFacts))
            truncated = true
        }

        return WeeklyRecoveryEvidence(
            schemaVersion: 1,
            referenceDayKey: currentKey.isoString,
            generatedAt: asOf,
            timeZoneIdentifier: timeZone.identifier,
            cutoverHour: cutoverHour,
            endDayIsPartial: endIsPartial,
            target: target,
            control: control,
            recovery: recovery,
            daily: daily,
            coffeeObservations: coffeeFindings,
            notes: notes,
            evidence: facts,
            truncated: truncated
        )
    }

    // MARK: - Windows

    private static func buildWindow(
        label: String,
        keys: [DayKey],
        historyByKey: [DayKey: DailyComputedDay],
        context: AgentExecutionContext,
        asOf: Date,
        currentKey: DayKey,
        timeZone: TimeZone,
        facts: inout [EvidenceFact]
    ) -> WeeklyRecoveryWindow {
        let metricStats = MetricKind.allCases.map { kind in
            metricStats(for: kind, keys: keys, historyByKey: historyByKey)
        }
        let rawStats = [
            rawStats(metric: "hrv", unit: "ms", keys: keys, historyByKey: historyByKey) { $0.hrvMs },
            rawStats(metric: "resting_heart_rate", unit: "bpm", keys: keys, historyByKey: historyByKey) { $0.restingHeartRateBpm },
            rawStats(metric: "sleep_asleep", unit: "minutes", keys: keys, historyByKey: historyByKey) { $0.sleepAsleepMinutes.map(Double.init) },
            rawStats(metric: "active_energy", unit: "kcal", keys: keys, historyByKey: historyByKey) { $0.activeEnergyKcal },
            rawStats(metric: "exercise_minutes", unit: "minutes", keys: keys, historyByKey: historyByKey) { $0.exerciseMinutes.map(Double.init) },
        ]
        let workouts = workoutSummary(keys: keys, context: context, asOf: asOf, timeZone: timeZone)
        let checkIns = checkInSummary(keys: keys, context: context, timeZone: timeZone)
        let nutrition = nutritionSummary(keys: keys, context: context)

        for stat in metricStats {
            appendWindowStatFacts(label: label, stat: stat, facts: &facts)
        }
        for stat in rawStats {
            appendRawWindowStatFacts(label: label, stat: stat, facts: &facts)
        }
        facts.append(EvidenceFact(
            key: "weekly.\(label).workouts.count",
            value: Double(workouts.count),
            unit: "count",
            metric: "workout_count",
            scope: label,
            source: "healthkit"
        ))
        facts.append(EvidenceFact(
            key: "weekly.\(label).nutrition.recorded_days",
            value: Double(nutrition.recordedDays),
            unit: "count",
            metric: "nutrition_recorded_days",
            scope: label,
            source: "user"
        ))

        return WeeklyRecoveryWindow(
            label: label,
            startDayKey: keys.first?.isoString ?? "",
            endDayKey: keys.last?.isoString ?? "",
            days: keys.count,
            metricStats: metricStats,
            rawStats: rawStats,
            workouts: workouts,
            checkIns: checkIns,
            nutrition: nutrition
        )
    }

    private static func metricStats(
        for kind: MetricKind,
        keys: [DayKey],
        historyByKey: [DayKey: DailyComputedDay]
    ) -> WeeklyMetricWindowStats {
        var available = 0
        var knownZero = 0
        var missing = 0
        var excluded = 0
        var values: [Int] = []
        var latest: (DayKey, Int)?

        for key in keys {
            guard let day = historyByKey[key] else {
                missing += 1
                continue
            }
            let score = day.score(for: kind)
            switch score.availability {
            case .available:
                available += 1
                if let value = score.value {
                    values.append(value)
                    latest = (key, value)
                }
            case .knownZero:
                knownZero += 1
                values.append(0)
                latest = (key, 0)
            case .missing:
                missing += 1
            case .excluded:
                excluded += 1
            }
        }

        let sorted = values.sorted()
        return WeeklyMetricWindowStats(
            metric: kind.rawValue,
            unit: "score_0_100",
            availableDays: available,
            knownZeroDays: knownZero,
            missingDays: missing,
            excludedDays: excluded,
            coverage: keys.isEmpty ? 0 : Double(available + knownZero) / Double(keys.count),
            sampleCount: values.count,
            median: percentile(sorted, 0.5),
            p25: percentile(sorted, 0.25),
            p75: percentile(sorted, 0.75),
            minValue: sorted.first,
            maxValue: sorted.last,
            latestValue: latest?.1,
            latestDayKey: latest?.0.isoString
        )
    }

    private static func rawStats(
        metric: String,
        unit: String,
        keys: [DayKey],
        historyByKey: [DayKey: DailyComputedDay],
        value: (DailyRawMetrics) -> Double?
    ) -> WeeklyRawMetricWindowStats {
        var values: [Double] = []
        var missing = 0
        var latest: (DayKey, Double)?
        for key in keys {
            guard let day = historyByKey[key], let raw = value(day.raw) else {
                missing += 1
                continue
            }
            values.append(raw)
            latest = (key, raw)
        }
        let sorted = values.sorted()
        return WeeklyRawMetricWindowStats(
            metric: metric,
            unit: unit,
            availableDays: values.count,
            missingDays: missing,
            coverage: keys.isEmpty ? 0 : Double(values.count) / Double(keys.count),
            sampleCount: values.count,
            median: percentile(sorted, 0.5),
            p25: percentile(sorted, 0.25),
            p75: percentile(sorted, 0.75),
            minValue: sorted.first,
            maxValue: sorted.last,
            latestValue: latest?.1,
            latestDayKey: latest?.0.isoString
        )
    }

    // MARK: - Comparison

    private static func makeRecoveryComparison(
        target: WeeklyMetricWindowStats?,
        control: WeeklyMetricWindowStats?
    ) -> WeeklyRecoveryComparison {
        let minimum = 7
        let delta: Int? = {
            guard let targetMedian = target?.median, let controlMedian = control?.median else { return nil }
            return targetMedian - controlMedian
        }()
        let sufficient = (control?.sampleCount ?? 0) >= minimum
        let direction: String
        if delta == nil {
            direction = "insufficient"
        } else if let delta, delta <= -1 {
            direction = "declined"
        } else if let delta, delta >= 1 {
            direction = "improved"
        } else {
            direction = "stable"
        }
        return WeeklyRecoveryComparison(
            metric: MetricKind.recovery.rawValue,
            targetMedian: target?.median,
            controlMedian: control?.median,
            delta: delta,
            direction: direction,
            isDecline: direction == "declined",
            evidenceSufficient: sufficient,
            targetSampleCount: target?.sampleCount ?? 0,
            controlSampleCount: control?.sampleCount ?? 0,
            minimumControlSamples: minimum,
            note: sufficient
                ? "比较为最近 7 天与之前 28 天的固定窗口点估计；不包含显著性检验。"
                : "对照窗有效样本不足 \(minimum) 天，不能判断趋势。"
        )
    }

    // MARK: - Day records

    private static func sleepSummary(_ day: DailyComputedDay, goalMinutes: Int) -> WeeklyDaySleep {
        let raw = day.raw
        let efficiency: Int? = {
            guard let asleep = raw.sleepAsleepMinutes, let inBed = raw.sleepInBedMinutes, inBed > 0 else { return nil }
            return Int((Double(asleep) / Double(inBed) * 100).rounded())
        }()
        return WeeklyDaySleep(
            score: day.sleep.value,
            state: stateLabel(for: day.sleep.availability),
            asleepMinutes: raw.sleepAsleepMinutes,
            inBedMinutes: raw.sleepInBedMinutes,
            deepMinutes: raw.deepMinutes,
            remMinutes: raw.remMinutes,
            coreMinutes: raw.coreMinutes,
            awakeMinutes: raw.awakeMinutes,
            efficiencyPct: efficiency,
            goalMinutes: goalMinutes,
            start: raw.sleepStart,
            end: raw.sleepEnd
        )
    }

    private static func latestCheckIn(
        for key: DayKey,
        in checkIns: [DailyCheckIn],
        timeZone: TimeZone
    ) -> WeeklyDayCheckIn? {
        let matches = checkIns
            .filter { $0.dayKey == key }
            .sorted { $0.recordedAt > $1.recordedAt }
        guard let checkIn = matches.first else { return nil }
        return WeeklyDayCheckIn(
            energy: checkIn.energy,
            mood: checkIn.mood,
            stress: checkIn.stress,
            sorenessMax: checkIn.soreness.values.max(),
            sorenessCount: checkIn.soreness.values.filter { $0 > 0 }.count,
            note: checkIn.note.map { String($0.prefix(160)) }
        )
    }

    private static func nutritionSummary(
        for key: DayKey,
        context: AgentExecutionContext
    ) -> WeeklyDayNutrition? {
        let log = context.nutritionLogs.first { $0.dayKey == key }
            ?? (context.todayNutritionLog?.dayKey == key ? context.todayNutritionLog : nil)
        guard let log else { return nil }
        let estimatedCount = log.entries.filter(\.isEstimated).count
        let lower = log.entries.reduce(0.0) { $0 + ($1.energyEstimate?.lowerKcal ?? $1.kcal ?? 0) }
        let upper = log.entries.reduce(0.0) { $0 + ($1.energyEstimate?.upperKcal ?? $1.kcal ?? 0) }
        let hasRange = log.entries.contains { $0.energyEstimate != nil }
        let coffeeCount = log.entries.filter { entry in
            coffeeKeywords.contains { entry.foodName.localizedCaseInsensitiveContains($0) }
        }.count
        return WeeklyDayNutrition(
            dayComplete: log.dietDayComplete,
            kcal: log.dietKcal,
            kcalLower: hasRange ? lower : nil,
            kcalUpper: hasRange ? upper : nil,
            proteinG: log.dietProteinG,
            carbsG: log.dietCarbsG,
            fatG: log.dietFatG,
            fiberG: log.dietFiberG,
            waterMl: log.dietWaterMl,
            entryCount: log.entries.count,
            estimatedEntryCount: estimatedCount,
            partialFields: log.dietPartialFields,
            mealTimePrecision: "unknown",
            recordedAtIsSaveTime: true,
            coffeeCount: coffeeCount
        )
    }

    private static func coffeeObservations(
        for key: DayKey,
        context: AgentExecutionContext
    ) -> [WeeklyCoffeeObservation] {
        let log = context.nutritionLogs.first { $0.dayKey == key }
            ?? (context.todayNutritionLog?.dayKey == key ? context.todayNutritionLog : nil)
        guard let log else { return [] }
        return log.entries.compactMap { entry in
            guard coffeeKeywords.contains(where: { entry.foodName.localizedCaseInsensitiveContains($0) }) else {
                return nil
            }
            return WeeklyCoffeeObservation(
                dayKey: key.isoString,
                name: entry.foodName,
                mealType: entry.mealType.title,
                timeKnown: false,
                note: "仅记录名称与餐次；进食时刻未知，recorded_at 是保存时间。"
            )
        }
    }

    private static func dayWorkouts(
        for key: DayKey,
        context: AgentExecutionContext,
        asOf: Date,
        timeZone: TimeZone
    ) -> [WeeklyDayWorkout] {
        var seen = Set<String>()
        var result: [WeeklyDayWorkout] = []
        for workout in context.storedWorkouts
            .filter({ $0.end <= asOf && $0.start.physiologicalDayKey(cutoverHour: cutoverHour, timeZone: timeZone) == key })
            .sorted(by: { $0.start < $1.start })
        {
            let uuid = workout.hkUUID.lowercased()
            guard seen.insert(uuid).inserted else { continue }
            let loads = context.muscleLoads.filter {
                $0.workoutUUID.caseInsensitiveCompare(workout.hkUUID) == .orderedSame && $0.role == .primary && $0.load > 0
            }
            result.append(WeeklyDayWorkout(
                uuid: workout.hkUUID,
                source: "healthkit",
                type: workout.type,
                dayKey: key.isoString,
                start: workout.start,
                end: workout.end,
                durationMinutes: max(1, Int((workout.end.timeIntervalSince(workout.start) / 60).rounded())),
                energyKcal: workout.energy,
                avgHR: workout.avgHR,
                effortUser: workout.effortUser,
                effortEstimated: workout.effortEstimated,
                reviewState: workout.reviewState.rawValue,
                annotationText: context.annotationsByWorkoutUUID[workout.hkUUID]?.rawText,
                primaryMuscles: loads.map(\.muscle.rawValue).sorted()
            ))
        }
        for session in context.sessions
            .filter({ $0.completedAt <= asOf && $0.startedAt.physiologicalDayKey(cutoverHour: cutoverHour, timeZone: timeZone) == key })
            .sorted(by: { $0.startedAt < $1.startedAt })
        {
            let linked = session.syncedHealthKitUUID?.lowercased()
            if let linked, seen.contains(linked) { continue }
            guard seen.insert(session.id.uuidString.lowercased()).inserted else { continue }
            let muscles = session.muscleLoadIntensities.filter { $0.value > 0 }.keys.map(\.rawValue).sorted()
            result.append(WeeklyDayWorkout(
                uuid: session.id.uuidString,
                source: "manual",
                type: session.title,
                dayKey: key.isoString,
                start: session.startedAt,
                end: session.completedAt,
                durationMinutes: session.durationMinutes,
                energyKcal: session.estimatedCalories,
                avgHR: nil,
                effortUser: Double(session.rpe),
                effortEstimated: nil,
                reviewState: "manual",
                annotationText: session.notes.isEmpty ? nil : String(session.notes.prefix(160)),
                primaryMuscles: muscles
            ))
        }
        return result.sorted { $0.start < $1.start }
    }

    private static func workoutSummary(
        keys: [DayKey],
        context: AgentExecutionContext,
        asOf: Date,
        timeZone: TimeZone
    ) -> WeeklyWorkoutSummary {
        let workouts = keys.flatMap { dayWorkouts(for: $0, context: context, asOf: asOf, timeZone: timeZone) }
        var byType: [String: Int] = [:]
        for workout in workouts {
            byType[workout.type, default: 0] += 1
        }
        return WeeklyWorkoutSummary(
            count: workouts.count,
            totalMinutes: workouts.reduce(0) { $0 + $1.durationMinutes },
            totalEnergyKcal: workouts.compactMap(\.energyKcal).reduce(0, +),
            byType: byType,
            truncated: workouts.count > 200
        )
    }

    private static func checkInSummary(
        keys: [DayKey],
        context: AgentExecutionContext,
        timeZone: TimeZone
    ) -> WeeklyCheckInSummary {
        let values = keys.compactMap { latestCheckIn(for: $0, in: context.checkIns, timeZone: timeZone) }
        guard !values.isEmpty else {
            return WeeklyCheckInSummary(days: 0, averageEnergy: nil, averageMood: nil, averageStress: nil)
        }
        let count = Double(values.count)
        return WeeklyCheckInSummary(
            days: values.count,
            averageEnergy: Double(values.reduce(0) { $0 + $1.energy }) / count,
            averageMood: Double(values.reduce(0) { $0 + $1.mood }) / count,
            averageStress: Double(values.reduce(0) { $0 + $1.stress }) / count
        )
    }

    private static func nutritionSummary(
        keys: [DayKey],
        context: AgentExecutionContext
    ) -> WeeklyNutritionSummary {
        let logs = keys.compactMap { key in
            context.nutritionLogs.first { $0.dayKey == key }
                ?? (context.todayNutritionLog?.dayKey == key ? context.todayNutritionLog : nil)
        }
        let kcalValues = logs.compactMap(\.dietKcal)
        let proteinValues = logs.compactMap(\.dietProteinG)
        return WeeklyNutritionSummary(
            recordedDays: logs.count,
            completeDays: logs.filter { $0.dietDayComplete == true }.count,
            partialDays: logs.filter { $0.dietDayComplete != true }.count,
            averageKcal: kcalValues.isEmpty ? nil : kcalValues.reduce(0, +) / Double(kcalValues.count),
            averageProteinG: proteinValues.isEmpty ? nil : proteinValues.reduce(0, +) / Double(proteinValues.count),
            mealTimePrecision: "unknown"
        )
    }

    // MARK: - Facts

    private static func appendWindowStatFacts(
        label: String,
        stat: WeeklyMetricWindowStats,
        facts: inout [EvidenceFact]
    ) {
        let prefix = "weekly.\(label).\(stat.metric)"
        if let median = stat.median {
            facts.append(EvidenceFact(
                key: "\(prefix).median", value: Double(median), unit: "score_0_100",
                metric: stat.metric, scope: label
            ))
        }
        facts.append(EvidenceFact(
            key: "\(prefix).coverage", value: stat.coverage, unit: "ratio",
            metric: stat.metric, scope: label
        ))
        facts.append(EvidenceFact(
            key: "\(prefix).sample_count", value: Double(stat.sampleCount), unit: "count",
            metric: stat.metric, scope: label
        ))
    }

    private static func appendRawWindowStatFacts(
        label: String,
        stat: WeeklyRawMetricWindowStats,
        facts: inout [EvidenceFact]
    ) {
        guard let median = stat.median else { return }
        facts.append(EvidenceFact(
            key: "weekly.\(label).\(stat.metric).median", value: median, unit: stat.unit,
            metric: stat.metric, scope: label, source: "healthkit"
        ))
    }

    private static func appendRecoveryFacts(
        _ comparison: WeeklyRecoveryComparison,
        target: WeeklyMetricWindowStats?,
        control: WeeklyMetricWindowStats?,
        facts: inout [EvidenceFact]
    ) {
        if let targetMedian = comparison.targetMedian {
            facts.append(EvidenceFact(
                key: "weekly.target.recovery.median", value: Double(targetMedian), unit: "score_0_100",
                metric: "recovery", scope: "target"
            ))
        }
        if let controlMedian = comparison.controlMedian {
            facts.append(EvidenceFact(
                key: "weekly.control.recovery.median", value: Double(controlMedian), unit: "score_0_100",
                metric: "recovery", scope: "control"
            ))
        }
        if let delta = comparison.delta {
            facts.append(EvidenceFact(
                key: "weekly.recovery.delta", value: Double(delta), unit: "score_points",
                metric: "recovery", scope: "target_vs_control"
            ))
        }
        if let coverage = target?.coverage {
            facts.append(EvidenceFact(
                key: "weekly.target.recovery.coverage", value: coverage, unit: "ratio",
                metric: "recovery", scope: "target"
            ))
        }
        if let coverage = control?.coverage {
            facts.append(EvidenceFact(
                key: "weekly.control.recovery.coverage", value: coverage, unit: "ratio",
                metric: "recovery", scope: "control"
            ))
        }
        facts.append(EvidenceFact(
            key: "weekly.control.recovery.sample_count",
            value: Double(comparison.controlSampleCount),
            unit: "count",
            metric: "recovery",
            scope: "control"
        ))
    }

    private static func appendDailyMetricFacts(
        key: DayKey,
        day: DailyComputedDay,
        facts: inout [EvidenceFact]
    ) {
        for kind in MetricKind.allCases {
            let score = day.score(for: kind)
            let state = stateLabel(for: score.availability)
            if let value = score.value {
                facts.append(EvidenceFact(
                    key: "day.\(key.isoString).\(kind.rawValue)", value: Double(value),
                    unit: "score_0_100", metric: kind.rawValue, scope: "day:\(key.isoString)",
                    dayKey: key.isoString, state: state
                ))
            }
        }
        if let hrv = day.raw.hrvMs {
            facts.append(EvidenceFact(
                key: "day.\(key.isoString).hrv", value: hrv, unit: "ms", metric: "hrv",
                scope: "day:\(key.isoString)", dayKey: key.isoString, source: "healthkit"
            ))
        }
        if let rhr = day.raw.restingHeartRateBpm {
            facts.append(EvidenceFact(
                key: "day.\(key.isoString).resting_heart_rate", value: rhr, unit: "bpm",
                metric: "resting_heart_rate", scope: "day:\(key.isoString)", dayKey: key.isoString,
                source: "healthkit"
            ))
        }
        if let asleep = day.raw.sleepAsleepMinutes {
            facts.append(EvidenceFact(
                key: "day.\(key.isoString).sleep_asleep", value: Double(asleep), unit: "minutes",
                metric: "sleep_asleep", scope: "day:\(key.isoString)", dayKey: key.isoString,
                source: "healthkit"
            ))
        }
        if let energy = day.raw.activeEnergyKcal {
            facts.append(EvidenceFact(
                key: "day.\(key.isoString).active_energy", value: energy, unit: "kcal",
                metric: "active_energy", scope: "day:\(key.isoString)", dayKey: key.isoString,
                source: "healthkit"
            ))
        }
    }

    private static func appendCheckInFacts(
        key: DayKey,
        value: WeeklyDayCheckIn,
        facts: inout [EvidenceFact]
    ) {
        facts.append(EvidenceFact(
            key: "day.\(key.isoString).checkin_energy", value: Double(value.energy), unit: "1-5",
            metric: "checkin_energy", scope: "day:\(key.isoString)", dayKey: key.isoString, source: "user"
        ))
        facts.append(EvidenceFact(
            key: "day.\(key.isoString).checkin_mood", value: Double(value.mood), unit: "1-5",
            metric: "checkin_mood", scope: "day:\(key.isoString)", dayKey: key.isoString, source: "user"
        ))
        facts.append(EvidenceFact(
            key: "day.\(key.isoString).checkin_stress", value: Double(value.stress), unit: "1-5",
            metric: "checkin_stress", scope: "day:\(key.isoString)", dayKey: key.isoString, source: "user"
        ))
    }

    private static func appendNutritionFacts(
        key: DayKey,
        value: WeeklyDayNutrition,
        facts: inout [EvidenceFact]
    ) {
        if let kcal = value.kcal {
            facts.append(EvidenceFact(
                key: "day.\(key.isoString).nutrition_kcal", value: kcal, unit: "kcal",
                metric: "nutrition_kcal", scope: "day:\(key.isoString)", dayKey: key.isoString,
                isEstimate: value.estimatedEntryCount > 0, source: "user"
            ))
        }
        if let protein = value.proteinG {
            facts.append(EvidenceFact(
                key: "day.\(key.isoString).nutrition_protein", value: protein, unit: "g",
                metric: "nutrition_protein", scope: "day:\(key.isoString)", dayKey: key.isoString,
                isEstimate: value.estimatedEntryCount > 0, source: "user"
            ))
        }
    }

    private static func appendWorkoutCountFact(
        key: DayKey,
        workouts: [WeeklyDayWorkout],
        facts: inout [EvidenceFact]
    ) {
        facts.append(EvidenceFact(
            key: "day.\(key.isoString).workout_count", value: Double(workouts.count), unit: "count",
            metric: "workout_count", scope: "day:\(key.isoString)", dayKey: key.isoString,
            source: "healthkit"
        ))
    }

    // MARK: - Utilities

    private static func stateLabel(for availability: MetricAvailability) -> String {
        switch availability {
        case .available: "available"
        case .knownZero: "knownZero"
        case .missing: "missing"
        case .excluded: "excluded"
        }
    }

    private static func percentile(_ sorted: [Int], _ fraction: Double) -> Int? {
        guard !sorted.isEmpty else { return nil }
        if sorted.count == 1 { return sorted[0] }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let weight = position - Double(lower)
        return Int((Double(sorted[lower]) * (1 - weight) + Double(sorted[upper]) * weight).rounded())
    }

    private static func percentile(_ sorted: [Double], _ fraction: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        if sorted.count == 1 { return sorted[0] }
        let position = fraction * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(sorted.count - 1, lower + 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }
}

private extension MealType {
    var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        case .water: "饮水"
        }
    }
}
