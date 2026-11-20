import Foundation

public struct SystemicRecoveryFactor: Hashable, Codable, Sendable {
    public let alpha: Double
    public let sleepHoursPriorNight: Double?
    public let hrvDeltaPct: Double?
    public let rhrDeltaBpm: Double?
    public let summary: String

    public init(
        alpha: Double,
        sleepHoursPriorNight: Double?,
        hrvDeltaPct: Double?,
        rhrDeltaBpm: Double?,
        summary: String
    ) {
        self.alpha = min(1.30, max(0.80, alpha))
        self.sleepHoursPriorNight = sleepHoursPriorNight
        self.hrvDeltaPct = hrvDeltaPct
        self.rhrDeltaBpm = rhrDeltaBpm
        self.summary = summary
    }
}

public struct MuscleLoadEvent: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let workoutUUID: String
    public let workoutTitle: String
    public let completedAt: Date
    public let muscle: BodyRegionMuscle
    public let role: MuscleLoadRole
    public let load: Double
    public let lateralNote: String?
    public let sourceKind: String

    public init(
        workoutUUID: String,
        workoutTitle: String,
        completedAt: Date,
        muscle: BodyRegionMuscle,
        role: MuscleLoadRole,
        load: Double,
        lateralNote: String? = nil,
        sourceKind: String = "watch"
    ) {
        self.id = "\(workoutUUID)_\(muscle.rawValue)"
        self.workoutUUID = workoutUUID
        self.workoutTitle = workoutTitle
        self.completedAt = completedAt
        self.muscle = muscle
        self.role = role
        self.load = max(0.0, load)
        self.lateralNote = lateralNote
        self.sourceKind = sourceKind
    }
}

public struct MuscleRecoveryEstimate: Identifiable, Hashable, Codable, Sendable {
    public var id: BodyRegionMuscle { muscle }
    public let muscle: BodyRegionMuscle
    /// Cumulative exponentially-decayed fatigue score $F_m \ge 0$.
    public let fatigue: Double
    /// Positive bounded recovery ratio $R_m = e^{-F_m} \in (0, 1]$.
    public let recoveryRatio: Double
    public let tauHours: Double
    public let effectiveTauHours: Double
    public let lastTrainedAt: Date?
    public let lastWorkoutTitle: String?
    public let hoursUntilReady: Double
    public let contributingEvents: [MuscleLoadEvent]
    public let algorithmVersion: AlgorithmVersion
    public let disclaimer: String

    public var recoveryPercent: Int {
        Int((recoveryRatio * 100.0).rounded())
    }

    public var fatigueIntensityForHeatmap: Double {
        min(1.0, max(0.0, 1.0 - recoveryRatio))
    }

    public var isReadyForPrimaryWork: Bool {
        recoveryRatio >= 0.85
    }

    public var readyETADescription: String {
        if lastTrainedAt == nil || fatigue <= 0.01 {
            return "近期未记录直接刺激（启发式估计：已就绪）"
        }
        if isReadyForPrimaryWork || hoursUntilReady <= 0.5 {
            return "启发式估计已达目标可练阈值 (≥ 85%)"
        }
        if hoursUntilReady < 24 {
            return String(format: "预计 %.0f 小时后达 85%% 阈值", hoursUntilReady.rounded())
        }
        let days = Int(floor(hoursUntilReady / 24.0))
        let remHours = Int((hoursUntilReady - Double(days) * 24.0).rounded())
        return "预计 \(days) 天 \(remHours) 小时后达 85% 阈值"
    }
}

public struct MuscleRecoverySnapshot: Hashable, Codable, Sendable {
    public let asOf: Date
    public let systemicFactor: SystemicRecoveryFactor
    public let estimates: [BodyRegionMuscle: MuscleRecoveryEstimate]
    public let algorithmVersion: AlgorithmVersion

    public init(
        asOf: Date,
        systemicFactor: SystemicRecoveryFactor,
        estimates: [BodyRegionMuscle: MuscleRecoveryEstimate],
        algorithmVersion: AlgorithmVersion = .recoveryHeuristicV1
    ) {
        self.asOf = asOf
        self.systemicFactor = systemicFactor
        self.estimates = estimates
        self.algorithmVersion = algorithmVersion
    }

    public static let empty = MuscleRecoverySnapshot(
        asOf: Date(timeIntervalSince1970: 0),
        systemicFactor: SystemicRecoveryFactor(
            alpha: 1.0,
            sleepHoursPriorNight: nil,
            hrvDeltaPct: nil,
            rhrDeltaBpm: nil,
            summary: "暂无近期生理基线，采用中性衰减系数 α = 1.00"
        ),
        estimates: Dictionary(
            uniqueKeysWithValues: BodyRegionMuscle.allCases.map { muscle in
                let tau = MuscleRecoveryEngine.baseTauHours(for: muscle)
                return (
                    muscle,
                    MuscleRecoveryEstimate(
                        muscle: muscle,
                        fatigue: 0,
                        recoveryRatio: 1.0,
                        tauHours: tau,
                        effectiveTauHours: tau,
                        lastTrainedAt: nil,
                        lastWorkoutTitle: nil,
                        hoursUntilReady: 0,
                        contributingEvents: [],
                        algorithmVersion: .recoveryHeuristicV1,
                        disclaimer: MuscleRecoveryEngine.heuristicDisclaimer
                    )
                )
            }
        )
    )

    public var heatmapFatigueIntensities: [BodyRegionMuscle: Double] {
        var map: [BodyRegionMuscle: Double] = [:]
        for (muscle, est) in estimates {
            let intensity = est.fatigueIntensityForHeatmap
            if intensity > 0.015 {
                map[muscle] = intensity
            }
        }
        return map
    }

    public var rankedByFatigue: [MuscleRecoveryEstimate] {
        estimates.values
            .filter { $0.lastTrainedAt != nil || $0.fatigue > 0.01 }
            .sorted { lhs, rhs in
                if lhs.recoveryRatio != rhs.recoveryRatio {
                    return lhs.recoveryRatio < rhs.recoveryRatio
                }
                return (lhs.lastTrainedAt ?? .distantPast) > (rhs.lastTrainedAt ?? .distantPast)
            }
    }

    public func estimate(for muscle: BodyRegionMuscle) -> MuscleRecoveryEstimate {
        if let hit = estimates[muscle] {
            return hit
        }
        let tau = MuscleRecoveryEngine.baseTauHours(for: muscle)
        return MuscleRecoveryEstimate(
            muscle: muscle,
            fatigue: 0,
            recoveryRatio: 1.0,
            tauHours: tau,
            effectiveTauHours: tau * systemicFactor.alpha,
            lastTrainedAt: nil,
            lastWorkoutTitle: nil,
            hoursUntilReady: 0,
            contributingEvents: [],
            algorithmVersion: algorithmVersion,
            disclaimer: MuscleRecoveryEngine.heuristicDisclaimer
        )
    }
}

/// Deterministic Watch workout auto-attribution (`running`, `walking`, `badminton`, other cardio).
/// Strength workouts return `nil` so they stay `.unreviewed` and enter the one-sentence Review Inbox.
public enum WorkoutAutoAttributor {
    public static func isStrengthWorkout(type: String) -> Bool {
        let lower = type.lowercased()
        return lower.contains("力量")
            || lower.contains("strength")
            || lower.contains("weight")
            || lower.contains("举铁")
    }

    public static func autoAttribute(
        workout: StoredWorkoutRecord,
        dominantHand: DominantHand
    ) -> (loads: [WorkoutMuscleLoadRecord], note: String)? {
        guard !isStrengthWorkout(type: workout.type) else {
            return nil
        }

        let durationMin = max(5.0, workout.end.timeIntervalSince(workout.start) / 60.0)
        let trimpFactor: Double
        if let trimp = workout.zones?.trimpScore, trimp > 0 {
            trimpFactor = min(1.45, max(0.35, trimp / 95.0))
        } else if let avgHR = workout.avgHR, avgHR > 80 {
            let hrScale = max(0.30, (avgHR - 90.0) / 70.0)
            trimpFactor = min(1.35, max(0.35, (durationMin / 45.0) * hrScale))
        } else {
            trimpFactor = min(1.30, max(0.25, durationMin / 50.0))
        }

        let lower = workout.type.lowercased()

        if lower.contains("羽毛球") || lower.contains("badminton") {
            let handLabel = dominantHand == .right ? "持拍右手" : "持拍左手"
            let base = min(1.25, 0.72 * trimpFactor)
            let loads = [
                makeLoad(workout.hkUUID, .quadriceps, .primary, base * 0.95),
                makeLoad(workout.hkUUID, .calves, .primary, base * 0.90),
                makeLoad(workout.hkUUID, .gluteal, .secondary, base * 0.65),
                makeLoad(workout.hkUUID, .deltoids, .primary, base * 0.85),
                makeLoad(workout.hkUUID, .forearm, .primary, base * 0.80),
                makeLoad(workout.hkUUID, .abs, .secondary, base * 0.50),
                makeLoad(workout.hkUUID, .obliques, .secondary, base * 0.55),
                makeLoad(workout.hkUUID, .lowerBack, .stabilizer, base * 0.40),
            ]
            return (loads, "羽毛球自动归因：下肢急停蹬转 + \(handLabel)肩袖/前臂 + 核心（启发式）")
        }

        if lower.contains("跑") || lower.contains("running") || lower.contains("trail") {
            let base = min(1.30, 0.78 * trimpFactor)
            let loads = [
                makeLoad(workout.hkUUID, .quadriceps, .primary, base),
                makeLoad(workout.hkUUID, .calves, .primary, base * 0.95),
                makeLoad(workout.hkUUID, .hamstring, .primary, base * 0.82),
                makeLoad(workout.hkUUID, .gluteal, .secondary, base * 0.65),
                makeLoad(workout.hkUUID, .lowerBack, .stabilizer, base * 0.35),
                makeLoad(workout.hkUUID, .abs, .stabilizer, base * 0.30),
            ]
            return (loads, "跑步心率区间与时长自动归因至下肢肌群（启发式）")
        }

        if lower.contains("步行") || lower.contains("健走") || lower.contains("徒步") || lower.contains("walking") || lower.contains("hiking") {
            let base = min(0.85, 0.35 * trimpFactor)
            let loads = [
                makeLoad(workout.hkUUID, .quadriceps, .primary, base),
                makeLoad(workout.hkUUID, .calves, .primary, base * 0.90),
                makeLoad(workout.hkUUID, .gluteal, .secondary, base * 0.70),
            ]
            return (loads, "步行/徒步低冲击下肢负荷归因（启发式）")
        }

        if lower.contains("单车") || lower.contains("骑行") || lower.contains("cycling") {
            let base = min(1.20, 0.70 * trimpFactor)
            let loads = [
                makeLoad(workout.hkUUID, .quadriceps, .primary, base),
                makeLoad(workout.hkUUID, .gluteal, .secondary, base * 0.75),
                makeLoad(workout.hkUUID, .hamstring, .secondary, base * 0.60),
                makeLoad(workout.hkUUID, .calves, .stabilizer, base * 0.45),
            ]
            return (loads, "骑行自动归因（启发式）")
        }

        if lower.contains("划船") || lower.contains("rowing") {
            let base = min(1.15, 0.68 * trimpFactor)
            let loads = [
                makeLoad(workout.hkUUID, .upperBack, .primary, base * 0.90),
                makeLoad(workout.hkUUID, .quadriceps, .primary, base * 0.85),
                makeLoad(workout.hkUUID, .lowerBack, .secondary, base * 0.65),
                makeLoad(workout.hkUUID, .biceps, .secondary, base * 0.55),
                makeLoad(workout.hkUUID, .forearm, .stabilizer, base * 0.50),
            ]
            return (loads, "划船自动归因（启发式）")
        }

        if lower.contains("游泳") || lower.contains("swimming") {
            let base = min(1.05, 0.60 * trimpFactor)
            let loads = [
                makeLoad(workout.hkUUID, .upperBack, .primary, base * 0.90),
                makeLoad(workout.hkUUID, .deltoids, .primary, base * 0.85),
                makeLoad(workout.hkUUID, .triceps, .secondary, base * 0.55),
                makeLoad(workout.hkUUID, .abs, .stabilizer, base * 0.45),
            ]
            return (loads, "游泳自动归因（启发式）")
        }

        // Generic cardio / ball sport fallback so non-strength sessions are not left unattributed
        let base = min(1.00, 0.55 * trimpFactor)
        let loads = [
            makeLoad(workout.hkUUID, .quadriceps, .primary, base * 0.85),
            makeLoad(workout.hkUUID, .calves, .secondary, base * 0.75),
            makeLoad(workout.hkUUID, .abs, .stabilizer, base * 0.45),
        ]
        return (loads, "综合有氧/球类负荷自动归因（启发式）")
    }

    private static func makeLoad(
        _ uuid: String,
        _ muscle: BodyRegionMuscle,
        _ role: MuscleLoadRole,
        _ load: Double
    ) -> WorkoutMuscleLoadRecord {
        WorkoutMuscleLoadRecord(
            workoutUUID: uuid,
            muscle: muscle,
            role: role,
            load: (max(0.05, min(1.50, load)) * 100.0).rounded() / 100.0,
            algorithmVersion: .recoveryHeuristicV1
        )
    }
}

/// Heuristic local muscle fatigue & recovery estimator (`recovery-heuristic-v1`):
/// Accumulates $F_m = \sum_i L_{m,i} e^{-\Delta t_i / (\tau_m \cdot \alpha_{\text{sys}})}$ and outputs $R_m = e^{-F_m} \in (0, 1]$.
/// Systemic decay factor $\alpha_{\text{sys}}$ reads ONLY raw prior-night sleep & morning HRV/RHR (no circular Strain dependency).
public enum MuscleRecoveryEngine {
    public static let heuristicDisclaimer = "启发式估计（recovery-heuristic-v1），仅供训练安排参考，不代表临床肌电/生化恢复检测"
    public static let readinessThresholdRecovery = 0.85
    public static let lookbackWindowHours: TimeInterval = 168.0 * 3600.0

    public static func baseTauHours(for muscle: BodyRegionMuscle) -> Double {
        switch muscle {
        case .quadriceps, .hamstring, .gluteal, .lowerBack:
            60.0
        case .chest, .upperBack:
            48.0
        case .deltoids, .trapezius:
            42.0
        case .biceps, .triceps, .forearm, .calves, .abs, .obliques:
            30.0
        }
    }

    public static func computeSystemicFactor(
        historyDays: [DailyComputedDay],
        referenceDate: Date,
        sleepGoalMinutes: Int
    ) -> SystemicRecoveryFactor {
        let refDayKey = referenceDate.physiologicalDayKey()
        let pastOrToday = historyDays
            .filter { $0.dayKey <= refDayKey }
            .sorted { $0.dayKey < $1.dayKey }

        let latestRaw = pastOrToday.last?.raw
        let baselineWindow = pastOrToday.dropLast().suffix(28)

        let priorSleepMin = latestRaw?.sleepAsleepMinutes
        let priorSleepHours = priorSleepMin.map { Double($0) / 60.0 }

        var hrvDeltaPct: Double?
        if let todayHRV = latestRaw?.hrvMs, todayHRV > 0 {
            let baseHRVs = baselineWindow.compactMap(\.raw.hrvMs).filter { $0 > 0 }
            if baseHRVs.count >= 3 {
                let meanBase = baseHRVs.reduce(0, +) / Double(baseHRVs.count)
                if meanBase > 0 {
                    hrvDeltaPct = ((todayHRV - meanBase) / meanBase) * 100.0
                }
            }
        }

        var rhrDeltaBpm: Double?
        if let todayRHR = latestRaw?.restingHeartRateBpm {
            let baseRHRs = baselineWindow.compactMap(\.raw.restingHeartRateBpm)
            if baseRHRs.count >= 3 {
                let meanBase = baseRHRs.reduce(0, +) / Double(baseRHRs.count)
                rhrDeltaBpm = todayRHR - meanBase
            }
        }

        var alpha = 1.0
        var notes: [String] = []

        if let priorSleepMin {
            let goal = Double(max(360, sleepGoalMinutes))
            if priorSleepMin < 360 {
                alpha += 0.14
                notes.append(String(format: "昨夜短睡 %.1fh 减缓恢复", Double(priorSleepMin) / 60.0))
            } else if Double(priorSleepMin) >= goal {
                alpha -= 0.08
                notes.append(String(format: "昨夜睡眠达标 %.1fh", Double(priorSleepMin) / 60.0))
            }
        }

        if let hrvDeltaPct {
            if hrvDeltaPct <= -12.0 {
                alpha += 0.10
                notes.append(String(format: "晨起 HRV 偏低 %.0f%%", hrvDeltaPct))
            } else if hrvDeltaPct >= 8.0 {
                alpha -= 0.06
                notes.append(String(format: "晨起 HRV 高于基线 +%.0f%%", hrvDeltaPct))
            }
        }

        if let rhrDeltaBpm {
            if rhrDeltaBpm >= 4.0 {
                alpha += 0.06
                notes.append(String(format: "静息心率偏高 +%.1f bpm", rhrDeltaBpm))
            } else if rhrDeltaBpm <= -2.0 {
                alpha -= 0.04
            }
        }

        let clamped = min(1.30, max(0.80, alpha))
        let summary = if notes.isEmpty {
            String(format: "依据昨夜原始睡眠与晨起自主神经基线（α = %.2f，无循环训练依赖）", clamped)
        } else {
            String(format: "%@（α = %.2f）", notes.joined(separator: " · "), clamped)
        }

        return SystemicRecoveryFactor(
            alpha: clamped,
            sleepHoursPriorNight: priorSleepHours,
            hrvDeltaPct: hrvDeltaPct,
            rhrDeltaBpm: rhrDeltaBpm,
            summary: summary
        )
    }

    public static func compute(
        asOf: Date,
        storedWorkouts: [StoredWorkoutRecord],
        muscleLoads: [WorkoutMuscleLoadRecord],
        manualSessions: [LoggedWorkoutSession] = [],
        historyDays: [DailyComputedDay] = [],
        sleepGoalMinutes: Int = 450,
        dominantHand: DominantHand = .right
    ) -> MuscleRecoverySnapshot {
        let systemic = computeSystemicFactor(
            historyDays: historyDays,
            referenceDate: asOf,
            sleepGoalMinutes: sleepGoalMinutes
        )

        var workoutByUUID: [String: StoredWorkoutRecord] = [:]
        for w in storedWorkouts where w.end <= asOf {
            workoutByUUID[w.hkUUID.lowercased()] = w
        }

        // Group persisted DB loads by workoutUUID
        var loadsByWorkoutUUID: [String: [WorkoutMuscleLoadRecord]] = [:]
        for record in muscleLoads {
            loadsByWorkoutUUID[record.workoutUUID.lowercased(), default: []].append(record)
        }

        var eventsByMuscle: [BodyRegionMuscle: [MuscleLoadEvent]] = [:]

        // 1. Persisted Watch workouts + DB loads (and inline auto-attribution when unpersisted non-strength exists)
        var representedUUIDs = Set<String>()
        for workout in workoutByUUID.values {
            guard asOf.timeIntervalSince(workout.end) <= lookbackWindowHours else { continue }
            representedUUIDs.insert(workout.hkUUID.lowercased())

            if let dbLoads = loadsByWorkoutUUID[workout.hkUUID.lowercased()], !dbLoads.isEmpty {
                for rec in dbLoads where rec.load > 0 {
                    let event = MuscleLoadEvent(
                        workoutUUID: workout.hkUUID,
                        workoutTitle: workout.type,
                        completedAt: workout.end,
                        muscle: rec.muscle,
                        role: rec.role,
                        load: rec.load,
                        lateralNote: workout.type.lowercased().contains("羽毛球")
                            ? (dominantHand == .right ? "持拍右手" : "持拍左手")
                            : nil,
                        sourceKind: workout.reviewState == .autoAttributed ? "auto" : "annotated"
                    )
                    eventsByMuscle[rec.muscle, default: []].append(event)
                }
            } else if workout.reviewState == .unreviewed,
                      let auto = WorkoutAutoAttributor.autoAttribute(workout: workout, dominantHand: dominantHand)
            {
                for rec in auto.loads where rec.load > 0 {
                    let event = MuscleLoadEvent(
                        workoutUUID: workout.hkUUID,
                        workoutTitle: workout.type,
                        completedAt: workout.end,
                        muscle: rec.muscle,
                        role: rec.role,
                        load: rec.load,
                        lateralNote: workout.type.lowercased().contains("羽毛球")
                            ? (dominantHand == .right ? "持拍右手" : "持拍左手")
                            : nil,
                        sourceKind: "auto"
                    )
                    eventsByMuscle[rec.muscle, default: []].append(event)
                }
            }
        }

        // 2. Fallback: raw historyDays workouts not yet in storedWorkouts (e.g. cold preview/unit tests)
        for day in historyDays {
            for summary in day.raw.workouts {
                let uuid = (summary.healthKitUUID ?? summary.id).uuidString
                guard !representedUUIDs.contains(uuid.lowercased()) else { continue }
                let end = summary.endDate
                guard end <= asOf, asOf.timeIntervalSince(end) <= lookbackWindowHours else { continue }
                let stored = StoredWorkoutRecord(
                    hkUUID: uuid,
                    type: summary.activityName,
                    start: summary.startDate,
                    end: end,
                    energy: summary.activeEnergyKcal,
                    avgHR: summary.averageHeartRate,
                    zones: summary.heartRateZones,
                    effortUser: summary.effortScore,
                    effortEstimated: summary.estimatedEffortScore,
                    reviewState: .unreviewed
                )
                if let auto = WorkoutAutoAttributor.autoAttribute(workout: stored, dominantHand: dominantHand) {
                    representedUUIDs.insert(uuid.lowercased())
                    for rec in auto.loads where rec.load > 0 {
                        eventsByMuscle[rec.muscle, default: []].append(
                            MuscleLoadEvent(
                                workoutUUID: uuid,
                                workoutTitle: summary.activityName,
                                completedAt: end,
                                muscle: rec.muscle,
                                role: rec.role,
                                load: rec.load,
                                sourceKind: "auto"
                            )
                        )
                    }
                }
            }
        }

        // A linked manual session can fill muscles the imported record does not cover.
        for session in manualSessions {
            guard session.completedAt <= asOf,
                  asOf.timeIntervalSince(session.completedAt) <= lookbackWindowHours
            else { continue }
            for (muscle, intensity) in session.muscleLoadIntensities where intensity > 0 {
                let workoutUUID = session.syncedHealthKitUUID ?? session.id.uuidString
                if eventsByMuscle[muscle]?.contains(where: {
                    $0.workoutUUID.caseInsensitiveCompare(workoutUUID) == .orderedSame
                }) == true {
                    continue
                }
                eventsByMuscle[muscle, default: []].append(
                    MuscleLoadEvent(
                        workoutUUID: workoutUUID,
                        workoutTitle: session.title,
                        completedAt: session.completedAt,
                        muscle: muscle,
                        role: intensity >= 0.40 ? .primary : .secondary,
                        load: intensity,
                        sourceKind: "manual"
                    )
                )
            }
        }

        let targetFatigueThreshold = -log(readinessThresholdRecovery)
        var estimates: [BodyRegionMuscle: MuscleRecoveryEstimate] = [:]

        for muscle in BodyRegionMuscle.allCases {
            let tau = baseTauHours(for: muscle)
            let effTau = tau * systemic.alpha
            let events = (eventsByMuscle[muscle] ?? []).sorted { $0.completedAt > $1.completedAt }

            var fatigue = 0.0
            for ev in events {
                let dtHours = max(0.0, asOf.timeIntervalSince(ev.completedAt) / 3600.0)
                fatigue += ev.load * exp(-dtHours / effTau)
            }
            let recovery = exp(-fatigue)
            let hoursUntilReady: Double = if fatigue <= targetFatigueThreshold {
                0.0
            } else {
                effTau * log(fatigue / targetFatigueThreshold)
            }

            estimates[muscle] = MuscleRecoveryEstimate(
                muscle: muscle,
                fatigue: fatigue,
                recoveryRatio: min(1.0, max(0.0001, recovery)),
                tauHours: tau,
                effectiveTauHours: effTau,
                lastTrainedAt: events.first?.completedAt,
                lastWorkoutTitle: events.first?.workoutTitle,
                hoursUntilReady: hoursUntilReady,
                contributingEvents: events,
                algorithmVersion: .recoveryHeuristicV1,
                disclaimer: heuristicDisclaimer
            )
        }

        return MuscleRecoverySnapshot(
            asOf: asOf,
            systemicFactor: systemic,
            estimates: estimates,
            algorithmVersion: .recoveryHeuristicV1
        )
    }
}
