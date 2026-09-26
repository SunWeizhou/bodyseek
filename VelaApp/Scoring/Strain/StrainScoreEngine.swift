import Foundation

struct HeartRateZoneSummary: Hashable {
    struct Zone: Identifiable, Hashable {
        let id: Int
        let title: String
        let detail: String
        let minutes: Double
    }

    let zones: [Zone]

    var totalMinutes: Double {
        zones.reduce(0.0) { $0 + $1.minutes }
    }
}

enum HeartRateZoneCalculator {
    static func summarize(
        samples: [HeartRateSample],
        restingHeartRate: Double,
        maxHeartRate: Double,
        maxSampleGap: TimeInterval = 120
    ) -> HeartRateZoneSummary? {
        summarize(
            sampleGroups: [samples],
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            maxSampleGap: maxSampleGap
        )
    }

    static func summarize(
        sampleGroups: [[HeartRateSample]],
        restingHeartRate: Double,
        maxHeartRate: Double,
        maxSampleGap: TimeInterval = 120
    ) -> HeartRateZoneSummary? {
        guard maxHeartRate > restingHeartRate,
              maxSampleGap > 0 else { return nil }

        let definitions = [
            (title: "Zone 1", detail: "恢复"),
            (title: "Zone 2", detail: "有氧基础"),
            (title: "Zone 3", detail: "节奏"),
            (title: "Zone 4", detail: "阈值"),
            (title: "Zone 5", detail: "高强度")
        ]
        let heartRateRange = maxHeartRate - restingHeartRate
        var minutes = Array(repeating: 0.0, count: definitions.count)

        for samples in sampleGroups {
            let sortedSamples = samples.sorted { $0.date < $1.date }
            for index in sortedSamples.indices.dropLast() {
                let interval = sortedSamples[index + 1].date.timeIntervalSince(sortedSamples[index].date)
                guard interval > 0 else { continue }

                let boundedInterval = min(interval, maxSampleGap)
                let reserve = (sortedSamples[index].bpm - restingHeartRate) / heartRateRange
                let zoneIndex: Int
                if reserve >= 0.9 {
                    zoneIndex = 4
                } else if reserve >= 0.8 {
                    zoneIndex = 3
                } else if reserve >= 0.7 {
                    zoneIndex = 2
                } else if reserve >= 0.6 {
                    zoneIndex = 1
                } else {
                    zoneIndex = 0
                }
                minutes[zoneIndex] += boundedInterval / 60.0
            }
        }

        guard minutes.contains(where: { $0 > 0 }) else { return nil }

        return HeartRateZoneSummary(
            zones: definitions.indices.reversed().map { index in
                HeartRateZoneSummary.Zone(
                    id: index + 1,
                    title: definitions[index].title,
                    detail: definitions[index].detail,
                    minutes: minutes[index]
                )
            }
        )
    }
}

public struct WorkoutInput: Codable, Hashable {
    public var id: UUID
    public var durationMinutes: Double
    public var averageHeartRate: Double?
    public var heartRateSamples: [Double] = []
    public var rpe: Double?

    public init(
        id: UUID = UUID(),
        durationMinutes: Double,
        averageHeartRate: Double? = nil,
        heartRateSamples: [Double] = [],
        rpe: Double? = nil
    ) {
        self.id = id
        self.durationMinutes = durationMinutes
        self.averageHeartRate = averageHeartRate
        self.heartRateSamples = heartRateSamples
        self.rpe = rpe
    }
}

public struct StrainScoreInput: Hashable {
    public var asOf: Date
    public var workouts: [WorkoutInput] = []
    public var activeEnergyToday: Double?
    public var exerciseMinutesToday: Double?
    public var stepCount: Double?
    
    public var restingHR: Double
    public var maxHR: Double
    public var biologicalSex: String? // "male" / "female" / "other"
    
    public var last28DaysDailyLoads: [Double] = [] // historical daily loads
    public var validObservedDaysCount: Int? = nil
    /// Evidence-preserving daily history. When supplied, this takes precedence
    /// over the legacy numeric array for baseline and training-load gates.
    public var dailyLoadObservations: [DailyLoadObservation]? = nil
    
    // Legacy support fields
    public var activeEnergyBaseline: Double?
    public var exerciseMinutesBaseline: Double?
    public var workoutIntensityLoad: Double?
    public var recoveryScore: Double?

    public init(
        asOf: Date,
        workouts: [WorkoutInput] = [],
        activeEnergyToday: Double? = nil,
        exerciseMinutesToday: Double? = nil,
        stepCount: Double? = nil,
        restingHR: Double = 0,
        maxHR: Double = 0,
        biologicalSex: String? = nil,
        last28DaysDailyLoads: [Double] = [],
        validObservedDaysCount: Int? = nil,
        dailyLoadObservations: [DailyLoadObservation]? = nil,
        activeEnergyBaseline: Double? = nil,
        exerciseMinutesBaseline: Double? = nil,
        workoutIntensityLoad: Double? = nil,
        recoveryScore: Double? = nil
    ) {
        self.asOf = asOf
        self.workouts = workouts
        self.activeEnergyToday = activeEnergyToday
        self.exerciseMinutesToday = exerciseMinutesToday
        self.stepCount = stepCount
        self.restingHR = restingHR
        self.maxHR = maxHR
        self.biologicalSex = biologicalSex
        self.last28DaysDailyLoads = last28DaysDailyLoads
        self.validObservedDaysCount = validObservedDaysCount
        self.dailyLoadObservations = dailyLoadObservations
        self.activeEnergyBaseline = activeEnergyBaseline
        self.exerciseMinutesBaseline = exerciseMinutesBaseline
        self.workoutIntensityLoad = workoutIntensityLoad
        self.recoveryScore = recoveryScore
    }
}



public struct StrainScoreEngine: ScoreEngine {
    public typealias Input = StrainScoreInput
    public typealias Output = MetricResult

    public init() {}

    /// Banister 性别系数：male (0.64/1.92)、female (0.86/1.67)；
    /// other/未设置用插值 (0.75/1.80)（未经验证，但与 Method B 历史行为一致，
    /// 此前 Method A 把 other 一律按男性处理，两方法口径不一致）。
    private static func banisterConstants(sex: String?) -> (alpha: Double, beta: Double) {
        switch sex {
        case "female": return (0.86, 1.67)
        case "male": return (0.64, 1.92)
        default: return (0.75, 1.80)
        }
    }

    public func calculate(from input: StrainScoreInput) -> MetricResult {
        var components: [String: Double] = [:]
        var componentWeights: [String: Double] = [:]
        var reasons: [String] = []
        var missingInputs: [String] = []

        let hasActivityEvidence = !input.workouts.isEmpty
            || input.activeEnergyToday != nil
            || input.exerciseMinutesToday != nil
            || input.stepCount != nil
        if !hasActivityEvidence {
            missingInputs.append(contentsOf: [
                "workouts",
                "activeEnergyToday",
                "exerciseMinutesToday",
                "stepCount"
            ])
            reasons.append("需要训练、活动能量、运动分钟或步数中的至少一项，才会给出负荷评分。")
            return MetricResult(
                domain: .strain,
                name: "Strain Score",
                value: nil,
                band: .low,
                confidence: .low,
                components: [:],
                componentWeights: [:],
                reasons: reasons,
                missingInputs: missingInputs,
                dataWindow: DateInterval(
                    start: Calendar.current.date(byAdding: .day, value: -28, to: input.asOf) ?? input.asOf,
                    end: input.asOf
                ),
                source: .healthKit,
                algorithmVersion: ScoringAlgorithmVersions.strain,
                lastUpdated: input.asOf
            )
        }

        let hasHeartRateReserve = input.restingHR > 0 && input.maxHR > input.restingHR
        let restingHR = input.restingHR
        let maxHR = input.maxHR
        let hrRange = maxHR - restingHR

        // 1. Calculate Workout Loads (with UUID deduplication)
        var seenWorkoutIDs = Set<UUID>()
        var deduplicatedWorkouts: [WorkoutInput] = []
        for w in input.workouts {
            if !seenWorkoutIDs.contains(w.id) {
                seenWorkoutIDs.insert(w.id)
                deduplicatedWorkouts.append(w)
            }
        }

        var totalWorkoutLoad = 0.0
        var methodCode = 0.0
        for workout in deduplicatedWorkouts {
            var workoutLoad = 0.0
            if hasHeartRateReserve && !workout.heartRateSamples.isEmpty {
                // Method A: Continuous Banister TRIMP exponential sample integration
                methodCode = max(methodCode, 1.0)
                let sampleWeight = workout.durationMinutes / Double(workout.heartRateSamples.count)
                let (alpha, beta) = Self.banisterConstants(sex: input.biologicalSex)
                for hr in workout.heartRateSamples {
                    let hrr = (hr - restingHR) / hrRange
                    let clampedHRR = ScoringMath.clamp(hrr, min: 0.01, max: 1.0)
                    workoutLoad += sampleWeight * clampedHRR * alpha * exp(beta * clampedHRR)
                }
            } else if hasHeartRateReserve, let avgHR = workout.averageHeartRate {
                // Method B: Banister TRIMP using average heart rate fallback
                methodCode = max(methodCode, 2.0)
                let hrr = (avgHR - restingHR) / hrRange
                let clampedHRR = ScoringMath.clamp(hrr, min: 0.01, max: 1.0)
                // gender-neutral fallback: 0.75 / 1.80 为未经验证的插值（仅 other/未设置）。
                let (alpha, beta) = Self.banisterConstants(sex: input.biologicalSex)
                workoutLoad = workout.durationMinutes * clampedHRR * alpha * exp(beta * clampedHRR)
            } else if let rpe = workout.rpe {
                // Method C: Foster's session RPE scaled to TRIMP units (duration * rpe * 0.3)
                methodCode = max(methodCode, 3.0)
                workoutLoad = workout.durationMinutes * rpe * 0.3
            } else {
                // Method D: duration fallback
                methodCode = max(methodCode, 4.0)
                workoutLoad = workout.durationMinutes * 1.5
            }
            totalWorkoutLoad += workoutLoad
        }

        // 2. Non-workout activity load
        let activeEnergy = input.activeEnergyToday ?? 0.0
        let steps = input.stepCount ?? 0.0
        let exerciseMin = input.exerciseMinutesToday ?? 0.0
        
        let rawActivityLoad = 0.02 * activeEnergy + 0.0015 * steps + 0.5 * exerciseMin
        let activityMultiplier = deduplicatedWorkouts.isEmpty ? 1.0 : 0.35
        let activityLoad = rawActivityLoad * activityMultiplier

        // Total daily load
        let dailyLoad = totalWorkoutLoad + activityLoad

        // 3. Baseline & Score Mapping
        let observedHistoryValues: [Double] = if let observations = input.dailyLoadObservations {
            observations
                .filter(\.isObservedValue)
                .compactMap(\.value)
        } else {
            input.last28DaysDailyLoads
        }
        let historyToUse = observedHistoryValues.filter { $0 > 0 }
        // A static reference scale is only used until a personal load history exists.
        // It must never be described as the user's baseline.
        let hasPersonalLoadBaseline = !historyToUse.isEmpty
        let baselineDailyLoad = PersonalBaselineEngine.median(historyToUse) ?? 60.0
        let loadRatio = dailyLoad / baselineDailyLoad
        
        // Logarithmic saturation Daily Strain curve
        let strainValue = hasActivityEvidence
            ? 100.0 * (1.0 - exp(-0.75 * loadRatio))
            : nil
        
        components["workout_load"] = totalWorkoutLoad
        components["workout_load_method_code"] = methodCode
        components["activity_load"] = activityLoad
        components["raw_activity_load"] = rawActivityLoad
        components["activity_multiplier"] = activityMultiplier
        components["daily_load"] = dailyLoad
        components["steps_raw"] = steps
        components["active_energy_raw"] = activeEnergy
        components["exercise_minutes_raw"] = exerciseMin
        
        componentWeights["workout_load"] = 0.60
        componentWeights["activity_load"] = 0.40

        // Reasons
        if !deduplicatedWorkouts.isEmpty {
            reasons.append("今日完成了 \(deduplicatedWorkouts.count) 次运动训练，贡献了主要身体负荷")
        }
        reasons.append("非运动日常活动负荷为 \(Int(activityLoad)) (步数: \(Int(steps)), 活动能量: \(Int(activeEnergy)) kcal；已应用 \(activityMultiplier) 启发式系数降低双重计算风险)")

        // 4. Training Load Status (ATL / CTL)
        // `last28DaysDailyLoads` is newest-first (see personalBaselineHistory).
        // EWMA must iterate oldest→newest ending at today, so reverse it.
        let ascendingHistory: [Double] = if let observations = input.dailyLoadObservations {
            observations
                .sorted { $0.date < $1.date }
                .map { observation in
                    observation.availability.contributesToLoad ? (observation.value ?? 0.0) : 0.0
                }
        } else {
            Array(input.last28DaysDailyLoads.reversed())
        }
        let loadsIncludingToday = ascendingHistory + [dailyLoad]
        let atl = ewma(loadsIncludingToday, lambda: 2.0 / (7.0 + 1.0))
        let ctl28 = ewma(loadsIncludingToday, lambda: 2.0 / (28.0 + 1.0))
        let trainingLoadRatio = ctl28 > 0 ? atl / ctl28 : 1.0

        var baseConfidence: MetricConfidence = input.activeEnergyToday != nil ? .high : .medium

        if !hasHeartRateReserve && deduplicatedWorkouts.contains(where: { !$0.heartRateSamples.isEmpty || $0.averageHeartRate != nil }) {
            baseConfidence = .low
            reasons.append("缺少个人静息心率或最大心率，心率数据未用于个体化负荷计算。")
        }
        
        let observedDays = input.dailyLoadObservations?
            .filter(\.isObservedValue)
            .count
            ?? input.validObservedDaysCount
            ?? historyToUse.count
        if observedDays < 7 {
            // Insufficient history for ATL/CTL
            baseConfidence = .low
            reasons.append(hasPersonalLoadBaseline
                ? "历史负荷不足 7 天，已停用近期训练负荷状态评估。"
                : "尚未形成个人历史负荷基线；当前负荷仅按统一参考尺度展示，置信度较低。")
            components["recommended_lower"] = Double(recommendedRange(for: input.recoveryScore).lowerBound)
            components["recommended_upper"] = Double(recommendedRange(for: input.recoveryScore).upperBound)
        } else {
            let loadStatus: TrainingLoadStatus
            if trainingLoadRatio < 0.60 {
                loadStatus = .wellBelow
                reasons.append("近期训练负荷显著低于过去 28 天平均水平，可能处于减量或停训状态。")
            } else if trainingLoadRatio <= 0.85 {
                loadStatus = .below
                reasons.append("近期训练负荷略低于基线水平。")
            } else if trainingLoadRatio <= 1.20 {
                loadStatus = .optimal
                reasons.append("近期训练负荷处于个人历史范围附近，可继续结合恢复和主观用力观察。")
            } else if trainingLoadRatio <= 1.50 {
                loadStatus = .elevated
                reasons.append("近期训练负荷已偏高，建议控制强度，避免连续高负荷。")
            } else {
                loadStatus = .highRisk
                reasons.append("近期训练负荷显著高于过去 28 天平均水平，建议控制增量并关注恢复与不适。")
            }

            components["training_load_ratio"] = trainingLoadRatio
            components["acute_7d_load"] = atl * 7.0
            components["chronic_28d_equivalent"] = ctl28 * 7.0
            let statusCode: Double
            switch loadStatus {
            case .wellBelow: statusCode = 0.0
            case .below: statusCode = 1.0
            case .optimal: statusCode = 2.0
            case .elevated: statusCode = 3.0
            case .highRisk: statusCode = 4.0
            case .unknown: statusCode = -1.0
            }
            components["training_load_status_code"] = statusCode
            components["recommended_lower"] = Double(recommendedRange(for: input.recoveryScore).lowerBound)
            components["recommended_upper"] = Double(recommendedRange(for: input.recoveryScore).upperBound)
            
            if historyToUse.count < 28 {
                baseConfidence = .medium
                reasons.append("由于历史负荷数据少于 28 天，近期训练负荷的基线评估仅为估算（中等置信度）。")
            }
        }

        let band = strainValue.map(ScoringMath.band(for:)) ?? .low
        let confidence: MetricConfidence = hasActivityEvidence ? baseConfidence : .low

        let dataWindow = DateInterval(
            start: Calendar.current.date(byAdding: .day, value: -28, to: input.asOf) ?? input.asOf,
            end: input.asOf
        )

        return MetricResult(
            domain: .strain,
            name: "Strain Score",
            value: strainValue,
            band: band,
            confidence: confidence,
            components: components,
            componentWeights: componentWeights,
            reasons: reasons,
            missingInputs: missingInputs,
            dataWindow: dataWindow,
            source: .healthKit,
            algorithmVersion: ScoringAlgorithmVersions.strain,
            lastUpdated: input.asOf
        )
    }

    private func recommendedRange(for recoveryScore: Double?) -> ClosedRange<Int> {
        guard let recoveryScore else { return 40...70 }
        if recoveryScore < 40 {
            return 15...40   // Low recovery → rest or very light
        } else if recoveryScore < 70 {
            return 35...65   // Moderate → controlled training
        } else {
            return 55...85   // High recovery → can push harder
        }
    }

    private func ewma(_ values: [Double], lambda: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        // 暖启动：用初期（最多 7 个）样本的均值作种子，降低首值冷启动偏差。
        let warmupCount = min(7, values.count)
        let seed = values.prefix(warmupCount).reduce(0, +) / Double(warmupCount)
        var result = seed
        for value in values.dropFirst(warmupCount) {
            result = value * lambda + result * (1.0 - lambda)
        }
        return result
    }
}
