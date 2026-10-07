#if DEBUG
import Foundation

/// Generates preview/demo data using real scoring engines with fixed seed inputs.
/// When engine algorithms change, previews update automatically — no manual sync needed.
enum PreviewDataFactory {

    /// Synthetic, read-only history for native chart previews. Missing days
    /// deliberately remain gaps; these snapshots are never written to HealthKit or SwiftData.
    static func makeTrendSnapshots(endingAt date: Date, calendar: Calendar = .current) -> [DailyHealthSnapshot] {
        (0..<30).compactMap { offset in
            guard ![10, 11, 12].contains(offset),
                  let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date)) else { return nil }
            let dashboard = makeDashboard(date: day)
            var snapshot = DailyHealthSnapshot(date: day, createdAt: day)
            snapshot.recoveryScore = dashboard.recovery.value
            snapshot.sleepScore = dashboard.sleepScore.value
            snapshot.strainScore = dashboard.strain.value
            snapshot.stressIndex = dashboard.stress.value
            snapshot.currentEnergy = dashboard.energy.value
            return snapshot
        }
    }

    /// A realistic "healthy user" seed input that produces moderate-to-high scores.
    static func makeDashboard(date: Date = Date()) -> DashboardSummary {
        let sleepSummary = PreviewHealthDataProvider.sleepSummary(for: date)

        // Sleep — same production path as Today: DomainSleepScoreAdapter → BodySeekDomain.SleepScoreEngine.
        let sleepScore = DomainSleepScoreAdapter.calculate(
            asOf: date,
            totalSleepMinutes: Double(sleepSummary.totalSleepMinutes),
            sleepTargetMinutes: 450,
            todayBedtime: nil,
            recentBedtimes: [],
            awakeMinutes: nil,
            awakeEpisodeCount: nil,
            remMinutes: nil,
            deepMinutes: nil,
            inBedMinutes: nil,
            evidence: nil
        )

        // Recovery — simulate a user with HRV slightly below baseline (mild fatigue)
        let recoveryInput = RecoveryScoreInput(
            asOf: date,
            hrvToday: 42,
            hrvBaseline: 45,
            hrvHistory: [44, 46, 43, 47, 42, 45, 44],
            restingHeartRateToday: 62,
            restingHeartRateBaseline: 60,
            rhrHistory: [59, 60, 61, 58, 62, 60, 59],
            sleepScoreLastNight: sleepScore.score,
            strainScoreYesterday: 58
        )
        let recovery = RecoveryScoreEngine().calculate(from: recoveryInput)

        // Strain
        let strainInput = StrainScoreInput(
            asOf: date,
            activeEnergyToday: 420,
            exerciseMinutesToday: 28,
            activeEnergyBaseline: 500,
            exerciseMinutesBaseline: 35,
            workoutIntensityLoad: 42,
            recoveryScore: recovery.score
        )
        let strain = StrainScoreEngine().calculate(from: strainInput)

        // Stress
        let stressInput = StressIndexInput(
            asOf: date,
            heartRateElevationScore: 38,
            hrvSuppressionScore: 45,
            sleepDebtStressScore: max(0, 100 - sleepScore.score),
            recentStrainStressScore: strain.score
        )
        let stress = StressIndexEngine().calculate(from: stressInput)

        // Energy
        let energyInput = EnergyBankInput(
            asOf: date,
            recoveryScore: recovery.score,
            sleepScore: sleepScore.score,
            strainScore: strain.score,
            stressIndex: stress.stressIndex,
            hrvToday: 42,
            hrvBaseline: 45,
            rhrToday: 62,
            rhrBaseline: 60,
            sleepHours: 7.2,
            strainHistory: [45, 52, 58, 55, 48, 60, 58],
            todayLoad: strain.components["daily_load"],
            bodyTempDelta: 0.0
        )
        let energy = EnergyBankEngine().calculate(from: energyInput)

        // Health Age
        let healthAgeInput = HealthAgeTrendInput(
            factors: [
                .init(name: "VO2 Max", direction: .neutral),
                .init(name: "Resting heart rate", direction: .positive),
                .init(name: "Sleep regularity", direction: .negative),
                .init(name: "Activity consistency", direction: .positive)
            ]
        )
        let healthAge = HealthAgeTrendEngine().calculate(from: healthAgeInput)

        return DashboardSummary(
            date: date,
            sleepSummary: sleepSummary,
            sleepScore: sleepScore,
            recovery: recovery,
            recoveryMetrics: RecoveryMetricSummary(
                hrvMilliseconds: 42,
                restingHeartRate: 62,
                sleepHeartRate: 58,
                respiratoryRate: 14
            ),
            recoveryBaseline: RecoveryMetricSummary(
                hrvMilliseconds: 45,
                restingHeartRate: 60,
                sleepHeartRate: nil,
                respiratoryRate: nil
            ),
            strain: strain,
            stress: stress,
            energy: energy,
            healthAge: healthAge,
            bodyMetrics: BodyMetricsSummary(
                vo2Max: 42,
                weightKilograms: 72,
                bodyFatPercentage: 18,
                leanBodyMassKilograms: 59
            ),
            extendedMetrics: ExtendedHealthMetrics(age: 28, biologicalSex: "male", heightCm: 175),
            workouts: [],
            dailyInsight: L10n.t(
                "Recovery is moderate. Keep training controlled and protect sleep timing tonight.",
                "恢复处于中等水平。今天训练保持可控，今晚优先保护睡眠时间。"
            ),
            source: .preview
        )
    }
}
#endif
