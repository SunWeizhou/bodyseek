import Foundation
import BodySeekDomain

enum UserProfileSettings {
    static let ageKey = "vela_user_age"
    static let weightKey = "vela_user_weight"
    static let heightKey = "vela_user_height"
    static let maxHeartRateKey = "vela_max_hr"
    static let biologicalSexKey = "vela_user_biological_sex"

    static func age(defaults: UserDefaults = .standard) -> Int? {
        guard let value = defaults.object(forKey: ageKey) as? NSNumber else { return nil }
        let age = value.intValue
        return (10...100).contains(age) ? age : nil
    }

    static func maxHeartRate(defaults: UserDefaults = .standard) -> Double? {
        guard let value = defaults.object(forKey: maxHeartRateKey) as? NSNumber else { return nil }
        return validatedMaxHeartRate(value.doubleValue)
    }

    static func weightKilograms(defaults: UserDefaults = .standard) -> Double? {
        guard let value = defaults.object(forKey: weightKey) as? NSNumber else { return nil }
        let weight = value.doubleValue
        return (25...350).contains(weight) ? weight : nil
    }

    static func heightCentimeters(defaults: UserDefaults = .standard) -> Double? {
        guard let value = defaults.object(forKey: heightKey) as? NSNumber else { return nil }
        let height = value.doubleValue
        return (100...250).contains(height) ? height : nil
    }

    static func biologicalSex(defaults: UserDefaults = .standard) -> String? {
        let value = defaults.string(forKey: biologicalSexKey)
        return ["male", "female", "other"].contains(value) ? value : nil
    }

    /// One-time migration: UserDefaults previously received Apple Health values via
    /// `hydrateMissingValuesFromHealth`, which (under the new manual-first resolution)
    /// would freeze stale HealthKit values as if they were user overrides.
    /// Reset those auto-filled values once so the profile genuinely follows Apple Health.
    static let priorityMigrationKey = "vela_user_profile_priority_v2_migrated"

    static func migrateLegacyHydratedValuesIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: priorityMigrationKey) else { return }
        defaults.removeObject(forKey: ageKey)
        defaults.removeObject(forKey: weightKey)
        defaults.removeObject(forKey: heightKey)
        defaults.removeObject(forKey: biologicalSexKey)
        defaults.set(true, forKey: priorityMigrationKey)
    }

    static func bodyMassIndex(weightKilograms: Double?, heightCentimeters: Double?) -> Double? {
        guard let weightKilograms,
              let heightCentimeters,
              (25...350).contains(weightKilograms),
              (100...250).contains(heightCentimeters) else { return nil }
        let heightMeters = heightCentimeters / 100
        return weightKilograms / (heightMeters * heightMeters)
    }

    static func inferredMaxHeartRate(age: Int) -> Double {
        Double(max(100, 220 - age))
    }

    static func resolvedMaxHeartRate(
        age: Int,
        wiki: Double? = nil,
        defaults: UserDefaults = .standard
    ) -> Double {
        // explicit 参数此前无任何调用方传入（死参数已删除），
        // 与引擎解析链一致：UserDefaults → wiki → 年龄推断。
        maxHeartRate(defaults: defaults)
            ?? wiki.flatMap(validatedMaxHeartRate)
            ?? inferredMaxHeartRate(age: age)
    }

    private static func validatedMaxHeartRate(_ value: Double) -> Double? {
        (100...240).contains(value) ? value : nil
    }
}

/// Adapter that makes the Foundation-only Domain Core the production Sleep
/// fact source while keeping the app's existing presentation contract stable.
/// HealthKit and SwiftData types stop at the caller; only value semantics cross
/// this boundary.
enum DomainSleepScoreAdapter {
    static func calculate(
        asOf: Date,
        totalSleepMinutes: Double?,
        sleepTargetMinutes: Double,
        todayBedtime: Date?,
        recentBedtimes: [Date],
        awakeMinutes: Double?,
        awakeEpisodeCount: Int?,
        remMinutes: Double?,
        deepMinutes: Double?,
        inBedMinutes: Double?,
        evidence: SleepEvidenceContext?,
        calendar: Calendar = .current
    ) -> MetricResult {
        let input = BodySeekDomain.SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: totalSleepMinutes,
            sleepTargetMinutes: sleepTargetMinutes,
            todayBedtime: todayBedtime,
            recentBedtimes: recentBedtimes,
            awakeMinutes: awakeMinutes,
            awakeEpisodeCount: awakeEpisodeCount,
            remMinutes: remMinutes,
            deepMinutes: deepMinutes,
            inBedMinutes: inBedMinutes,
            evidence: evidence.map(mapEvidence)
        )
        return mapResult(BodySeekDomain.SleepScoreEngine(calendar: calendar).calculate(from: input))
    }

    private static func mapEvidence(_ value: SleepEvidenceContext) -> BodySeekDomain.SleepEvidenceContext {
        BodySeekDomain.SleepEvidenceContext(
            queryOutcome: value.queryOutcome.flatMap { BodySeekDomain.HealthQueryOutcomeKind(rawValue: $0.rawValue) },
            freshness: value.freshness.flatMap { BodySeekDomain.DataFreshness(rawValue: $0.rawValue) },
            totalSleep: mapObservation(value.totalSleep),
            bedtime: mapObservation(value.bedtime),
            wakeTime: mapObservation(value.wakeTime),
            inBed: mapObservation(value.inBed),
            awake: mapObservation(value.awake),
            rem: mapObservation(value.rem),
            deep: mapObservation(value.deep),
            episodeCount: mapObservation(value.episodeCount)
        )
    }

    private static func mapObservation(_ value: SleepComponentObservation) -> BodySeekDomain.SleepComponentObservation {
        BodySeekDomain.SleepComponentObservation(
            value: value.value,
            availability: BodySeekDomain.SleepObservationAvailability(rawValue: value.availability.rawValue) ?? .missing,
            reason: value.reason,
            observedWindow: value.observedWindow
        )
    }

    private static func mapResult(_ value: BodySeekDomain.MetricResult) -> MetricResult {
        MetricResult(
            domain: ScoredHealthDomain(rawValue: value.domain.rawValue),
            name: value.name,
            value: value.value,
            band: MetricBand(rawValue: value.band.rawValue) ?? .low,
            confidence: MetricConfidence(rawValue: value.confidence.rawValue) ?? .low,
            components: value.components,
            componentWeights: value.componentWeights,
            reasons: value.reasons,
            missingInputs: value.missingInputs,
            dataWindow: value.dataWindow,
            source: MetricSource(rawValue: value.source.rawValue) ?? .derived,
            algorithmVersion: value.algorithmVersion,
            lastUpdated: value.lastUpdated,
            observedWindow: value.observedWindow,
            observedAt: value.observedAt,
            computedAt: value.computedAt
        )
    }
}

/// Display-only projections derived from canonical Daily Health Computation results.
enum DashboardMetricProjection {
    // MARK: - Health Age

    static func healthAge(
        from context: DailyHealthContext,
        recovery: MetricResult,
        sleepScore: MetricResult,
        strain: MetricResult
    ) -> HealthAgeTrendInput {
        var factors: [HealthAgeTrendFactor] = []
        if let vo2 = context.bodyMetrics.vo2Max {
            factors.append(.init(name: "VO2 Max", direction: vo2 >= 40 ? .positive : .neutral))
        }
        if let rhr = context.recoveryMetrics.restingHeartRate {
            factors.append(.init(name: "Resting heart rate", direction: rhr <= 62 ? .positive : .negative))
        }
        if let bf = context.bodyMetrics.bodyFatPercentage {
            factors.append(.init(name: "Body fat", direction: (10...30).contains(bf) ? .positive : .negative))
        }
        if let weight = context.bodyMetrics.weightKilograms, let lean = context.bodyMetrics.leanBodyMassKilograms, weight > 0 {
            let leanRatio = lean / weight
            factors.append(.init(name: "Lean mass ratio", direction: leanRatio >= 0.65 ? .positive : .neutral))
        }
        if let value = sleepScore.value {
            factors.append(.init(name: "Sleep duration", direction: value >= 70 ? .positive : .negative))
        }
        factors.append(.init(name: "Recovery trend", direction: recovery.score >= 70 ? .positive : (recovery.score < 40 ? .negative : .neutral)))
        factors.append(.init(name: "Activity consistency", direction: strain.confidence == .high ? .positive : .neutral))
        return HealthAgeTrendInput(factors: factors)
    }

    // MARK: - Resolved Sleep Summary

    static func resolvedSleepSummary(
        from context: DailyHealthContext,
        sleepScore: Double?
    ) -> SleepSummary {
        let summary = context.sleepSummary ?? SleepSummary(
            date: context.date,
            totalSleepMinutes: 0,
            bedtime: nil,
            wakeTime: nil,
            stageMinutes: [:],
            segments: [],
            sleepScore: nil
        )
        return SleepSummary(
            date: summary.date,
            totalSleepMinutes: summary.totalSleepMinutes,
            bedtime: summary.bedtime,
            wakeTime: summary.wakeTime,
            stageMinutes: summary.stageMinutes,
            segments: summary.segments,
            sleepScore: sleepScore
        )
    }
}

// MARK: - Daily Health Computation

/// The five independent Scored Health Evidence results for one Daily Health Snapshot.
/// No aggregate health score is produced because each domain has different directionality.
struct ScoredHealthEvidence: Hashable {
    var sleep: MetricResult
    var recovery: MetricResult
    var strain: MetricResult
    var physiologicalStress: MetricResult
    var energy: MetricResult

    // Compatibility names while callers migrate to the domain language.
    var sleepScore: MetricResult { sleep }
    var stress: MetricResult { physiologicalStress }

    func applying(to snapshot: DailyHealthSnapshot) -> DailyHealthSnapshot {
        var result = snapshot
        result.sleepScore = sleep.value
        result.recoveryScore = recovery.value
        result.strainScore = strain.value
        result.stressIndex = physiologicalStress.value
        result.morningEnergy = energy.components["morningEnergy"]
        result.currentEnergy = energy.value
        result.energyBank = energy.value
        result.dailyLoad = strain.components["daily_load"]
        result.workoutLoad = strain.components["workout_load"]
        result.activityLoad = strain.components["activity_load"]
        result.trainingLoadRatio = strain.components["training_load_ratio"]
        result.atl = energy.components["atl"]
        result.ctl = energy.components["ctl"]
        result.tsb = energy.components["tsb"]
        result.acwr = energy.components["acwr"]
        return result
    }
}

/// The origin of a resolved profile value.  The score engines must never need
/// to know whether a value came from UserDefaults, HealthKit, or the wiki.
enum ProfileValueSource: String, Codable, Hashable, Sendable {
    case manual
    case healthKit
    case wiki
    case inferred
}

/// A profile value with enough provenance to explain a score input later.
/// This is deliberately small and value typed so it can be used by replay
/// fixtures without opening SwiftData, HealthKit, or the filesystem.
struct ProfileValue<Value: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    let value: Value
    let source: ProfileValueSource
    let resolvedAt: Date

    init(value: Value, source: ProfileValueSource, resolvedAt: Date) {
        self.value = value
        self.source = source
        self.resolvedAt = resolvedAt
    }
}

/// Canonical, resolved inputs that affect deterministic scoring.
///
/// Adapters resolve source priority once, then pass this snapshot into the
/// scoring module.  Keeping provenance here prevents UI and AI callers from
/// silently re-resolving the same field through a different fallback chain.
struct ProfileSnapshot: Codable, Hashable, Sendable {
    static let schemaVersion = "profile.snapshot.v1"

    let schemaVersion: String
    let age: ProfileValue<Int>?
    let maxHeartRate: ProfileValue<Double>?
    let biologicalSex: ProfileValue<String>?

    init(
        age: ProfileValue<Int>?,
        maxHeartRate: ProfileValue<Double>?,
        biologicalSex: ProfileValue<String>?,
        schemaVersion: String = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.age = age
        self.maxHeartRate = maxHeartRate
        self.biologicalSex = biologicalSex
    }

    /// Resolves the existing manual → HealthKit → wiki priority without
    /// changing any score formula or fallback semantics.
    static func resolve(
        manualAge: Int?,
        healthKitAge: Int?,
        wikiAge: Int?,
        manualMaxHeartRate: Double?,
        wikiMaxHeartRate: Double?,
        manualBiologicalSex: String?,
        healthKitBiologicalSex: String?,
        resolvedAt: Date = Date()
    ) -> ProfileSnapshot {
        let age = firstValid(
            (manualAge, .manual),
            (healthKitAge, .healthKit),
            (wikiAge, .wiki),
            where: { (10...100).contains($0) }
        ).map { ProfileValue(value: $0.value, source: $0.source, resolvedAt: resolvedAt) }

        let maxHeartRate = firstValid(
            (manualMaxHeartRate, .manual),
            (wikiMaxHeartRate, .wiki),
            where: { (100...240).contains($0) }
        ).map { ProfileValue(value: $0.value, source: $0.source, resolvedAt: resolvedAt) }

        let biologicalSex = firstValid(
            (manualBiologicalSex, .manual),
            (healthKitBiologicalSex, .healthKit),
            where: { ["male", "female", "other"].contains($0) }
        ).map { ProfileValue(value: $0.value, source: $0.source, resolvedAt: resolvedAt) }

        let resolvedMaxHeartRate = maxHeartRate
            ?? age.map {
                ProfileValue(
                    value: UserProfileSettings.inferredMaxHeartRate(age: $0.value),
                    source: .inferred,
                    resolvedAt: resolvedAt
                )
            }

        return ProfileSnapshot(
            age: age,
            maxHeartRate: resolvedMaxHeartRate,
            biologicalSex: biologicalSex
        )
    }

    private static func firstValid<Value>(
        _ candidates: (Value?, ProfileValueSource)...,
        where predicate: (Value) -> Bool
    ) -> (value: Value, source: ProfileValueSource)? {
        for candidate in candidates {
            let (value, source) = candidate
            guard let value, predicate(value) else { continue }
            return (value, source)
        }
        return nil
    }
}

/// The complete value contract consumed by `DailyHealthComputation`.
/// `profile` is immutable and can be serialized alongside a replay fixture.
struct ScoringContext: Codable, Hashable, Sendable {
    static let schemaVersion = "scoring.context.v1"

    let schemaVersion: String
    let sleepTargetMinutes: Double
    let profile: ProfileSnapshot

    var maxHeartRate: Double? { profile.maxHeartRate?.value }
    var biologicalSex: String? { profile.biologicalSex?.value }

    init(
        sleepTargetMinutes: Double,
        profile: ProfileSnapshot,
        schemaVersion: String = Self.schemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.sleepTargetMinutes = sleepTargetMinutes
        self.profile = profile
    }

    static func current(
        ageFallback: Int? = nil,
        biologicalSexFallback: String? = nil,
        resolvedAt: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> ScoringContext {
        let profile = ProfileSnapshot.resolve(
            manualAge: UserProfileSettings.age(defaults: defaults),
            healthKitAge: ageFallback,
            wikiAge: WikiFileService.getAgeFromWiki(),
            manualMaxHeartRate: UserProfileSettings.maxHeartRate(defaults: defaults),
            wikiMaxHeartRate: WikiFileService.getMaxHeartRateFromWiki(),
            manualBiologicalSex: UserProfileSettings.biologicalSex(defaults: defaults),
            healthKitBiologicalSex: biologicalSexFallback,
            resolvedAt: resolvedAt
        )
        return ScoringContext(
            sleepTargetMinutes: SleepTargetSettings.targetMinutes(),
            profile: profile
        )
    }
}

/// Compatibility projection retained for existing replay fixtures and tests.
/// New production callers should pass `ScoringContext` directly.
struct DailyHealthComputationProfile: Sendable {
    let sleepTargetMinutes: Double
    let maxHeartRate: Double?
    let biologicalSex: String?

    init(sleepTargetMinutes: Double, maxHeartRate: Double?, biologicalSex: String?) {
        self.sleepTargetMinutes = sleepTargetMinutes
        self.maxHeartRate = maxHeartRate
        self.biologicalSex = biologicalSex
    }

    init(context: ScoringContext) {
        self.init(
            sleepTargetMinutes: context.sleepTargetMinutes,
            maxHeartRate: context.maxHeartRate,
            biologicalSex: context.biologicalSex
        )
    }

    static func current(
        ageFallback: Int? = nil,
        biologicalSexFallback: String? = nil
    ) -> DailyHealthComputationProfile {
        DailyHealthComputationProfile(
            context: ScoringContext.current(
                ageFallback: ageFallback,
                biologicalSexFallback: biologicalSexFallback
            )
        )
    }
}

/// The sole deterministic transformation from a Daily Health Snapshot plus
/// Personal Baseline history into Scored Health Evidence.
final class DailyHealthComputation {
    private let calendar: Calendar
    private let now: Date
    private let profile: DailyHealthComputationProfile

    init(
        calendar: Calendar = .current,
        now: Date = Date(),
        profile: DailyHealthComputationProfile = .current()
    ) {
        self.calendar = calendar
        self.now = now
        self.profile = profile
    }

    init(
        calendar: Calendar = .current,
        now: Date = Date(),
        scoringContext: ScoringContext
    ) {
        self.calendar = calendar
        self.now = now
        self.profile = DailyHealthComputationProfile(context: scoringContext)
    }

    func compute(
        for snapshot: DailyHealthSnapshot,
        history: [DailyHealthSnapshot],
        longTermBaselines: LongTermBaselineReport? = nil,
        sleepEvidence: SleepEvidenceContext? = nil
    ) -> ScoredHealthEvidence {
        let asOf = evaluationDate(for: snapshot)
        let baselineHistory = personalBaselineHistory(for: snapshot, from: history)
        let sleepHistoryStart = calendar.date(
            byAdding: .day,
            value: -13,
            to: calendar.startOfDay(for: snapshot.date)
        ) ?? .distantPast
        let recentBedtimes = baselineHistory
            .filter { calendar.startOfDay(for: $0.date) >= sleepHistoryStart }
            .compactMap(\.bedtime)
        let (dailyLoadObservations, validDailyLoadDays) = continuousDailyLoadGrid(for: snapshot, from: history, maxDays: 42)
        let hrvHistory = baselineHistory.compactMap(\.hrvAverage)
        let hrvRmssdHistory = baselineHistory.compactMap(\.hrvRmssdMilliseconds)
        let rhrHistory = baselineHistory.compactMap(\.restingHeartRate)
        let respiratoryHistory = baselineHistory.compactMap(\.respiratoryRate)
        // Keep the numeric array only for legacy StrainScoreInput callers. The
        // typed observations carry the authoritative missing/zero/excluded
        // semantics through the current scoring path.
        let dailyLoadHistory = dailyLoadObservations.map { observation in
            observation.availability.contributesToLoad ? (observation.value ?? 0.0) : 0.0
        }
        let temperatureDelta = wristTemperatureDelta(
            current: snapshot.wristTemperature,
            history: baselineHistory
        )

        let sleep = DomainSleepScoreAdapter.calculate(
            asOf: asOf,
            totalSleepMinutes: snapshot.sleepHours.map { $0 * 60 },
            sleepTargetMinutes: profile.sleepTargetMinutes,
            todayBedtime: snapshot.bedtime,
            recentBedtimes: recentBedtimes,
            awakeMinutes: snapshot.awakeMinutes,
            awakeEpisodeCount: snapshot.awakeEpisodeCount,
            remMinutes: snapshot.remSleepMinutes,
            deepMinutes: snapshot.deepSleepMinutes,
            inBedMinutes: sleepEvidence?.inBed.value,
            evidence: sleepEvidence,
            calendar: calendar
        )
        /*
        let sleep = SleepScoreEngine().calculate(from: SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: snapshot.sleepHours.map { $0 * 60 },
            sleepTargetMinutes: profile.sleepTargetMinutes,
            todayBedtime: snapshot.bedtime,
            recentBedtimes: baselineHistory.prefix(13).compactMap(\.bedtime),
            awakeMinutes: snapshot.awakeMinutes,
            awakeEpisodeCount: snapshot.awakeEpisodeCount,
            remMinutes: snapshot.remSleepMinutes,
            deepMinutes: snapshot.deepSleepMinutes,
            inBedMinutes: sleepEvidence?.inBed.value,
            evidence: sleepEvidence,
        ))
        */

        let yesterday = calendar.date(byAdding: .day, value: -1, to: snapshot.date) ?? snapshot.date
        let yesterdayStrain = baselineHistory.first {
            calendar.isDate($0.date, inSameDayAs: yesterday)
        }?.strainScore
        let recovery = RecoveryScoreEngine().calculate(from: RecoveryScoreInput(
            asOf: asOf,
            hrvToday: snapshot.hrvAverage,
            hrvBaseline: PersonalBaselineEngine.median(hrvHistory),
            hrvHistory: hrvHistory,
            hrvRmssdToday: snapshot.hrvRmssdMilliseconds,
            hrvRmssdBaseline: PersonalBaselineEngine.median(hrvRmssdHistory),
            hrvRmssdHistory: hrvRmssdHistory,
            restingHeartRateToday: snapshot.restingHeartRate,
            restingHeartRateBaseline: PersonalBaselineEngine.median(rhrHistory),
            rhrHistory: rhrHistory,
            sleepScoreLastNight: sleep.value,
            strainScoreYesterday: yesterdayStrain,
            respiratoryRateToday: snapshot.respiratoryRate,
            respiratoryRateBaseline: PersonalBaselineEngine.median(respiratoryHistory),
            respiratoryRateHistory: respiratoryHistory,
            bodyTempDelta: temperatureDelta,
            SpO2: snapshot.oxygenSaturation,
            longTermContext: recoveryLongTermContext(from: longTermBaselines, asOf: asOf),
            observedAt: snapshot.hrvObservedAt ?? snapshot.rhrObservedAt,
            observedWindow: snapshot.hrvObservedWindow
        ))

        let strain = StrainScoreEngine().calculate(from: StrainScoreInput(
            asOf: asOf,
            workouts: snapshot.workouts.map {
                WorkoutInput(
                    id: $0.id,
                    durationMinutes: $0.end.timeIntervalSince($0.start) / 60,
                    averageHeartRate: $0.averageHeartRate,
                    rpe: $0.rpe
                )
            },
            activeEnergyToday: snapshot.activeCalories,
            exerciseMinutesToday: snapshot.activeMinutes ?? snapshot.workoutDuration,
            stepCount: snapshot.steps,
            restingHR: snapshot.restingHeartRate ?? 0,
            maxHR: profile.maxHeartRate ?? 0,
            biologicalSex: profile.biologicalSex,
            last28DaysDailyLoads: Array(dailyLoadHistory.prefix(28)),
            validObservedDaysCount: min(28, validDailyLoadDays),
            dailyLoadObservations: Array(dailyLoadObservations.prefix(28)),
            recoveryScore: recovery.value
        ))

        let respiratorySD = PersonalBaselineEngine.sampleStandardDeviation(respiratoryHistory)
        let physiologicalStress = StressIndexEngine().calculate(from: StressIndexInput(
            asOf: asOf,
            quietHRToday: snapshot.restingHeartRate,
            quietHRBaseline: PersonalBaselineEngine.median(rhrHistory),
            quietHRSD: PersonalBaselineEngine.sampleStandardDeviation(rhrHistory),
            hrvToday: snapshot.hrvAverage,
            hrvBaseline: PersonalBaselineEngine.median(hrvHistory),
            hrvSD: PersonalBaselineEngine.sampleStandardDeviation(hrvHistory),
            respRateToday: snapshot.respiratoryRate,
            respRateBaseline: PersonalBaselineEngine.median(respiratoryHistory),
            respRateSD: respiratorySD,
            bodyTempDelta: temperatureDelta,
            sleepScoreLastNight: sleep.value,
            strainScoreToday: strain.value,
            isWithinWorkoutWindow: isInsideWorkoutRecoveryWindow(
                snapshot: snapshot,
                asOf: asOf
            ),
            longTermQuietHRMedian: longTermBaselines?.baselines[.restingHeartRate]?.threeYearMedian
        ))

        let respiratoryRateZ: Double? = {
            guard let current = snapshot.respiratoryRate,
                  let baseline = PersonalBaselineEngine.median(respiratoryHistory),
                  let respiratorySD else { return nil }
            return (current - baseline) / respiratorySD
        }()
        let energy = EnergyBankEngine().calculate(from: EnergyBankInput(
            asOf: asOf,
            recoveryScore: recovery.value,
            sleepScore: sleep.value,
            strainScore: strain.value,
            stressIndex: physiologicalStress.value,
            hrvToday: snapshot.hrvAverage,
            hrvBaseline: PersonalBaselineEngine.median(hrvHistory),
            rhrToday: snapshot.restingHeartRate,
            rhrBaseline: PersonalBaselineEngine.median(rhrHistory),
            sleepHours: snapshot.sleepHours,
            strainHistory: dailyLoadHistory,
            trainingLoadHistory: dailyLoadObservations,
            todayLoad: strain.components["daily_load"],
            todayLoadObservation: todayLoadObservation(
                for: snapshot,
                dailyLoad: strain.components["daily_load"],
                asOf: asOf
            ),
            bodyTempDelta: temperatureDelta,
            hoursSinceWake: hoursSinceWake(snapshot: snapshot, asOf: asOf),
            respiratoryRateZ: respiratoryRateZ,
            SpO2: snapshot.oxygenSaturation,
            mindfulMinutes: nil,
            napMinutes: nil,
            trainingLoadStatus: strain.trainingLoadStatus,
            recoveryConfidence: recovery.confidence,
            sleepConfidence: sleep.confidence
        ))

        return ScoredHealthEvidence(
            sleep: sleep,
            recovery: recovery,
            strain: strain,
            physiologicalStress: physiologicalStress,
            energy: energy
        )
    }

    private func evaluationDate(for snapshot: DailyHealthSnapshot) -> Date {
        if calendar.isDate(snapshot.date, inSameDayAs: now) {
            return now
        }
        let start = calendar.startOfDay(for: snapshot.date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return nextDay.addingTimeInterval(-1)
    }

    /// Layer 3：从三年长线报告提取 HRV 分布上下文（样本不足 60 天时返回 nil，不启用修正）。
    /// 深度专项批次 3：同时提取「同月三年 MAD 带」的保守下限（median − 1.5×MAD）。
    private func recoveryLongTermContext(
        from report: LongTermBaselineReport?,
        asOf date: Date
    ) -> RecoveryLongTermContext? {
        guard let report,
              let hrvBaseline = report.baselines[.hrv],
              hrvBaseline.sampleCount >= 60 else { return nil }
        let month = calendar.component(.month, from: date)
        var gate: Double?
        if let band = report.monthlyHRV?.band(for: month), band.mad > 0 {
            gate = band.median - 1.5 * band.mad
        }
        return RecoveryLongTermContext(
            hrvPercentile10: hrvBaseline.percentile10,
            hrvPercentile90: hrvBaseline.percentile90,
            hrvSampleCount: hrvBaseline.sampleCount,
            hrvMonthlyGateThreshold: gate
        )
    }

    private func continuousDailyLoadGrid(
        for snapshot: DailyHealthSnapshot,
        from history: [DailyHealthSnapshot],
        maxDays: Int = 42
    ) -> (grid: [DailyLoadObservation], validDays: Int) {
        let dayStart = calendar.startOfDay(for: snapshot.date)
        var loadsByDay: [Date: Double] = [:]
        var earliestDate: Date?

        for item in history {
            let itemDay = calendar.startOfDay(for: item.date)
            if itemDay < dayStart {
                if earliestDate == nil || itemDay < earliestDate! {
                    earliestDate = itemDay
                }
                // Older snapshots may contain a fabricated zero from a day
                // with no activity inputs. Only preserve zero when the original
                // snapshot also contains an activity observation.
                if let load = item.dailyLoad, load != 0 || hasActivityEvidence(in: item) {
                    loadsByDay[itemDay] = max(loadsByDay[itemDay] ?? 0.0, load)
                }
            }
        }

        guard let earliest = earliestDate else {
            return ([], 0)
        }

        let totalDays = min(maxDays, max(1, calendar.dateComponents([.day], from: earliest, to: dayStart).day ?? 1))

        var grid: [DailyLoadObservation] = []
        var validDays = 0
        grid.reserveCapacity(totalDays)

        for offset in 1...totalDays {
            guard let targetDate = calendar.date(byAdding: .day, value: -offset, to: dayStart) else { break }
            if let load = loadsByDay[targetDate] {
                grid.append(DailyLoadObservation(
                    date: targetDate,
                    value: load,
                    availability: load == 0 ? .knownZero : .observed,
                    observedWindow: DateInterval(start: targetDate, duration: 24 * 60 * 60)
                ))
                if offset <= 28 {
                    validDays += 1
                }
            } else {
                // Gap day keeps its calendar position for decay but is not a
                // measured zero and does not increase valid observed days.
                grid.append(DailyLoadObservation(
                    date: targetDate,
                    value: nil,
                    availability: .missing,
                    reason: "缺少该日负荷覆盖",
                    observedWindow: DateInterval(start: targetDate, duration: 24 * 60 * 60)
                ))
            }
        }

        return (grid, validDays)
    }

    private func hasActivityEvidence(in snapshot: DailyHealthSnapshot) -> Bool {
        !snapshot.workouts.isEmpty
            || snapshot.activeCalories != nil
            || snapshot.activeMinutes != nil
            || snapshot.workoutDuration != nil
            || snapshot.steps != nil
    }

    private func todayLoadObservation(
        for snapshot: DailyHealthSnapshot,
        dailyLoad: Double?,
        asOf: Date
    ) -> DailyLoadObservation {
        let day = calendar.startOfDay(for: asOf)
        guard hasActivityEvidence(in: snapshot) else {
            return DailyLoadObservation(
                date: day,
                value: nil,
                availability: .missing,
                reason: "今日没有训练或活动覆盖证据"
            )
        }

        let value = dailyLoad ?? 0.0
        return DailyLoadObservation(
            date: day,
            value: value,
            availability: value == 0 ? .knownZero : .observed,
            reason: dailyLoad == nil ? "今日活动已覆盖，但负荷尚未计算" : nil
        )
    }

    private func personalBaselineHistory(
        for snapshot: DailyHealthSnapshot,
        from history: [DailyHealthSnapshot]
    ) -> [DailyHealthSnapshot] {
        let dayStart = calendar.startOfDay(for: snapshot.date)
        let earliest = calendar.date(byAdding: .day, value: -42, to: dayStart) ?? .distantPast
        return history
            .filter {
                let date = calendar.startOfDay(for: $0.date)
                return date >= earliest && date < dayStart
            }
            .sorted { $0.date > $1.date }
    }

    private func wristTemperatureDelta(
        current: Double?,
        history: [DailyHealthSnapshot]
    ) -> Double? {
        guard let current else { return nil }
        let samples = history.compactMap(\.wristTemperature)
        guard samples.count >= 5,
              let baseline = PersonalBaselineEngine.median(samples) else { return nil }
        return current - baseline
    }

    private func isInsideWorkoutRecoveryWindow(
        snapshot: DailyHealthSnapshot,
        asOf: Date
    ) -> Bool {
        guard calendar.isDate(snapshot.date, inSameDayAs: asOf) else { return false }
        return snapshot.workouts.contains { workout in
            asOf >= workout.start && asOf <= workout.end.addingTimeInterval(90 * 60)
        }
    }

    private func hoursSinceWake(
        snapshot: DailyHealthSnapshot,
        asOf: Date
    ) -> Double? {
        guard let wakeTime = snapshot.wakeTime, asOf >= wakeTime else { return nil }
        return max(0, min(24, asOf.timeIntervalSince(wakeTime) / 3_600))
    }
}
