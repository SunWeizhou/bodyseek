#if DEBUG
import Foundation

/// Generates preview/demo data using the production scoring entry with fixed
/// seed evidence. When engine algorithms change, previews update automatically.
enum PreviewDataFactory {

    /// Synthetic, read-only history for native chart previews. Missing days
    /// deliberately remain gaps; these snapshots are never written to HealthKit or SwiftData.
    static func makeTrendSnapshots(endingAt date: Date, calendar: Calendar = .current) -> [DailyHealthSnapshot] {
        (0..<30).compactMap { offset in
            guard ![10, 11, 12].contains(offset),
                  let day = calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: date)) else { return nil }
            let dashboard = makeDashboard(date: day)
            let evidence = previewEvidenceSnapshot(for: day, sleepHours: 7.2, calendar: calendar)
            var snapshot = DailyHealthSnapshot(date: day, createdAt: day)
            snapshot.recoveryScore = dashboard.recovery.value
            snapshot.sleepScore = dashboard.sleepScore.value
            snapshot.strainScore = dashboard.strain.value
            snapshot.stressIndex = dashboard.stress.value
            snapshot.currentEnergy = dashboard.energy.value
            snapshot.hrvAverage = evidence.hrvAverage
            snapshot.restingHeartRate = evidence.restingHeartRate
            return snapshot
        }
    }

    /// A realistic "healthy user" seed input that produces moderate-to-high scores.
    /// Five scores come only from `DailyHealthComputation`; individual engines
    /// are not assembled here.
    static func makeDashboard(date: Date = Date()) -> DashboardSummary {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        let sleepSummary = PreviewHealthDataProvider.sleepSummary(for: date)
        let sleepHours = Double(sleepSummary.totalSleepMinutes) / 60.0

        var history: [DailyHealthSnapshot] = []
        history.reserveCapacity(14)
        for offset in (1...14).reversed() {
            guard let past = calendar.date(byAdding: .day, value: -offset, to: day) else { continue }
            history.append(previewEvidenceSnapshot(for: past, sleepHours: 7.2, calendar: calendar))
        }

        let snapshot = previewEvidenceSnapshot(
            for: day,
            sleepHours: sleepHours,
            calendar: calendar,
            activeCalories: 420,
            activeMinutes: 28
        )
        let scored = DailyHealthComputation(
            calendar: calendar,
            now: date,
            profile: DailyHealthComputationProfile(
                sleepTargetMinutes: 450,
                maxHeartRate: 190,
                biologicalSex: "male"
            )
        ).compute(for: snapshot, history: history)

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
            sleepScore: scored.sleep,
            recovery: scored.recovery,
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
            strain: scored.strain,
            stress: scored.physiologicalStress,
            energy: scored.energy,
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

    private static func previewEvidenceSnapshot(
        for day: Date,
        sleepHours: Double,
        calendar: Calendar,
        activeCalories: Double = 500,
        activeMinutes: Double = 35
    ) -> DailyHealthSnapshot {
        var snapshot = DailyHealthSnapshot(date: day, createdAt: day)
        snapshot.hrvAverage = 42 + Double(calendar.component(.day, from: day) % 5)
        snapshot.restingHeartRate = 60 + Double(calendar.component(.day, from: day) % 3)
        snapshot.sleepHours = sleepHours
        snapshot.activeCalories = activeCalories
        snapshot.activeMinutes = activeMinutes
        snapshot.respiratoryRate = 14
        snapshot.steps = 8_000
        if let bedtime = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: day) {
            snapshot.bedtime = bedtime
        }
        if let wake = calendar.date(byAdding: .hour, value: Int(sleepHours.rounded()), to: snapshot.bedtime ?? day) {
            snapshot.wakeTime = wake
        }
        return snapshot
    }
}
#endif
