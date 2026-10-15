import Foundation
import BodySeekDomain

enum DomainMetricAdapter {
    static func metric(_ value: BodySeekDomain.MetricResult) -> MetricResult {
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

public typealias ScoreEngine = BodySeekDomain.ScoreEngine
public typealias MetricBand = BodySeekDomain.MetricBand
public typealias MetricState = BodySeekDomain.MetricState
public typealias MetricSource = BodySeekDomain.MetricSource
public typealias ScoredHealthDomain = BodySeekDomain.ScoredHealthDomain
public typealias ScoreDirection = BodySeekDomain.ScoreDirection
public typealias ScoreDataCoverage = BodySeekDomain.ScoreDataCoverage
public typealias StrainTargetStatus = BodySeekDomain.StrainTargetStatus
public typealias ScoringAlgorithmVersions = BodySeekDomain.ScoringAlgorithmVersions
public typealias ScoreBand = BodySeekDomain.ScoreBand
public typealias ScoreConfidence = BodySeekDomain.ScoreConfidence
public typealias StandardScoreResult = BodySeekDomain.StandardScoreResult
public typealias ScoringMath = BodySeekDomain.ScoringMath

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
            evidence: evidence
        )
        return mapResult(BodySeekDomain.SleepScoreEngine(calendar: calendar).calculate(from: input))
    }

    private static func mapResult(_ value: BodySeekDomain.MetricResult) -> MetricResult {
        DomainMetricAdapter.metric(value)
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

/// Production entry. It maps app snapshots and long-term baseline context into
/// `BodySeekDomain.DailyHealthComputation`, which owns the five-score assembly.
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
        let domainResult = BodySeekDomain.DailyHealthComputation(
            calendar: calendar,
            now: now,
            profile: BodySeekDomain.DailyHealthComputationProfile(
                sleepTargetMinutes: profile.sleepTargetMinutes,
                maxHeartRate: profile.maxHeartRate,
                biologicalSex: profile.biologicalSex
            )
        ).compute(
            for: snapshot,
            history: history,
            sleepEvidence: sleepEvidence,
            recoveryLongTerm: recoveryLongTermContext(from: longTermBaselines, asOf: asOf),
            longTermQuietHeartRateMedian: longTermBaselines?.baselines[.restingHeartRate]?.threeYearMedian
        )
        return ScoredHealthEvidence(
            sleep: mapDomainMetric(domainResult.sleep),
            recovery: mapDomainMetric(domainResult.recovery),
            strain: mapDomainMetric(domainResult.strain),
            physiologicalStress: mapDomainMetric(domainResult.physiologicalStress),
            energy: mapDomainMetric(domainResult.energy)
        )
    }

    private func mapDomainMetric(_ value: BodySeekDomain.MetricResult) -> MetricResult {
        DomainMetricAdapter.metric(value)
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

}
