import Foundation

public enum PreviewSeedFactory {
    /// Produces a deterministic multi-day preview window with Watch HR zone breakdowns,
    /// iOS 18/26 workout effort scores, realistic sleep segments, and intentional gap days.
    public static func makeRawWindow(
        endingAt referenceDate: Date = Date(),
        days: Int = 60,
        calendar: Calendar = .current
    ) -> [DailyRawMetrics] {
        let refStart = calendar.startOfDay(for: referenceDate)
        var result: [DailyRawMetrics] = []
        result.reserveCapacity(days)

        for offset in stride(from: -(days - 1), through: 0, by: 1) {
            guard let date = calendar.date(byAdding: .day, value: offset, to: refStart) else { continue }
            let dayIndex = offset + (days - 1)

            if offset == -12 || offset == -13 {
                continue
            }

            let wave = sin(Double(dayIndex) * 0.48)
            let wave2 = cos(Double(dayIndex) * 0.31)

            let hrv = (56.0 + wave * 11.5 + wave2 * 5.0).rounded()
            let rhr = (57.0 - wave * 3.5 + wave2 * 1.5).rounded()
            let resp = ((14.2 + wave2 * 0.8) * 10).rounded() / 10
            let meanHR = (72.0 + abs(wave2) * 14.0).rounded()

            let asleepMinutes = offset == 0 ? 412 : Int((425 + wave * 38 + wave2 * 22).rounded())
            let deep = Int((Double(asleepMinutes) * 0.21).rounded())
            let rem = Int((Double(asleepMinutes) * 0.23).rounded())
            let core = max(0, asleepMinutes - deep - rem)
            let awake = offset == 0 ? 18 : 14
            let inBed = asleepMinutes + awake

            let wakeAnchor = calendar.date(bySettingHour: 6, minute: 45, second: 0, of: date) ?? date
            let bedStart = wakeAnchor.addingTimeInterval(-Double(inBed * 60))

            let sleepSegments: [SleepStageSegment] = if offset == 0 {
                buildSampleSleepSegments(start: bedStart, deepMin: deep, coreMin: core, remMin: rem, awakeMin: awake)
            } else {
                []
            }

            let activeKcal = offset == 0 ? 395.0 : (320.0 + (wave2 + 1.0) * 185.0).rounded()
            let exerciseMin = offset == 0 ? 38 : Int((24.0 + (wave2 + 1.0) * 28.0).rounded())
            let steps = offset == 0 ? 7420 : Int((5400.0 + (wave2 + 1.0) * 3200.0).rounded())

            var workouts: [WorkoutSummary] = []
            if offset == 0 {
                let runStart = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: date) ?? date
                workouts.append(
                    WorkoutSummary(
                        activityName: "户外跑步 · Apple Watch",
                        symbolName: "figure.run",
                        startDate: runStart,
                        durationMinutes: 36,
                        activeEnergyKcal: 312,
                        averageHeartRate: 148,
                        effortScore: 7.4,
                        heartRateZones: WorkoutHeartRateZones(
                            zone1Minutes: 4,
                            zone2Minutes: 12,
                            zone3Minutes: 13,
                            zone4Minutes: 6,
                            zone5Minutes: 1,
                            maxHeartRate: 174
                        )
                    )
                )
            } else if dayIndex % 3 == 0 {
                let stStart = calendar.date(bySettingHour: 18, minute: 15, second: 0, of: date) ?? date
                let z2 = max(8, exerciseMin / 2)
                let z3 = max(4, exerciseMin / 3)
                workouts.append(
                    WorkoutSummary(
                        activityName: "力量训练 · Apple Watch",
                        symbolName: "dumbbell.fill",
                        startDate: stStart,
                        durationMinutes: exerciseMin,
                        activeEnergyKcal: activeKcal * 0.7,
                        averageHeartRate: 132,
                        effortScore: 6.8,
                        heartRateZones: WorkoutHeartRateZones(
                            zone1Minutes: 6,
                            zone2Minutes: z2,
                            zone3Minutes: z3,
                            zone4Minutes: 3,
                            zone5Minutes: 0,
                            maxHeartRate: 162
                        )
                    )
                )
            }

            let spo2: Double? = offset == 0 ? nil : 98.0

            result.append(
                DailyRawMetrics(
                    date: date,
                    hrvMs: offset == 0 ? 54 : hrv,
                    restingHeartRateBpm: offset == 0 ? 58 : rhr,
                    respiratoryRateBrpm: resp,
                    wristTempDeltaC: ((wave * 0.18) * 100).rounded() / 100,
                    oxygenSaturationPct: spo2,
                    sleepAsleepMinutes: asleepMinutes,
                    sleepInBedMinutes: inBed,
                    deepMinutes: deep,
                    remMinutes: rem,
                    coreMinutes: core,
                    awakeMinutes: awake,
                    sleepStart: bedStart,
                    sleepEnd: wakeAnchor,
                    sleepSegments: sleepSegments,
                    activeEnergyKcal: activeKcal,
                    exerciseMinutes: exerciseMin,
                    steps: steps,
                    workouts: workouts,
                    daytimeMeanHeartRateBpm: meanHR,
                    daytimeMaxHeartRateBpm: meanHR + 45,
                    hasAuthorizedHealthData: true,
                    sourceNames: ["Apple Watch (示例数据)"]
                )
            )
        }

        return result
    }

    public static func makeSampleLoggedWorkouts(referenceDate: Date = Date(), calendar: Calendar = .current) -> [LoggedWorkoutSession] {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: referenceDate) ?? referenceDate

        let push = LoggedWorkoutSession(
            title: "上肢推力 · 胸肩三头",
            startedAt: yesterday.addingTimeInterval(-2700),
            completedAt: yesterday,
            exercises: [
                LoggedExerciseRecord(
                    exerciseID: "barbell-bench-press",
                    sets: [
                        LoggedSetEntry(setIndex: 1, weightKg: 60, reps: 8, isCompleted: true),
                        LoggedSetEntry(setIndex: 2, weightKg: 62.5, reps: 8, isCompleted: true),
                        LoggedSetEntry(setIndex: 3, weightKg: 62.5, reps: 7, isCompleted: true),
                    ]
                ),
                LoggedExerciseRecord(
                    exerciseID: "overhead-shoulder-press",
                    sets: [
                        LoggedSetEntry(setIndex: 1, weightKg: 16, reps: 10, isCompleted: true),
                        LoggedSetEntry(setIndex: 2, weightKg: 16, reps: 10, isCompleted: true),
                    ]
                ),
            ],
            rpe: 8,
            estimatedCalories: 265,
            notes: "推力主项稳定，左肩感觉良好"
        )

        let legs = LoggedWorkoutSession(
            title: "下肢与后链强化",
            startedAt: twoDaysAgo.addingTimeInterval(-3000),
            completedAt: twoDaysAgo,
            exercises: [
                LoggedExerciseRecord(
                    exerciseID: "barbell-back-squat",
                    sets: [
                        LoggedSetEntry(setIndex: 1, weightKg: 70, reps: 6, isCompleted: true),
                        LoggedSetEntry(setIndex: 2, weightKg: 70, reps: 6, isCompleted: true),
                    ]
                ),
                LoggedExerciseRecord(
                    exerciseID: "romanian-deadlift",
                    sets: [
                        LoggedSetEntry(setIndex: 1, weightKg: 60, reps: 8, isCompleted: true),
                    ]
                ),
            ],
            rpe: 7,
            estimatedCalories: 310
        )

        return [push, legs]
    }

    public static func makeEmptyRawWindow(
        endingAt referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [DailyRawMetrics] {
        [DailyRawMetrics(date: calendar.startOfDay(for: referenceDate), hasAuthorizedHealthData: false)]
    }

    private static func buildSampleSleepSegments(
        start: Date,
        deepMin: Int,
        coreMin: Int,
        remMin: Int,
        awakeMin: Int
    ) -> [SleepStageSegment] {
        var cursor = start
        func seg(_ stage: SleepStage, _ minutes: Int) -> SleepStageSegment {
            let end = cursor.addingTimeInterval(Double(minutes * 60))
            defer { cursor = end }
            return SleepStageSegment(stage: stage, startDate: cursor, endDate: end)
        }

        let core1 = coreMin / 4
        let deep1 = deepMin / 2
        let core2 = coreMin / 4
        let rem1 = remMin / 2
        let core3 = coreMin / 4
        let deep2 = deepMin - deep1
        let rem2 = remMin - rem1
        let core4 = max(10, coreMin - core1 - core2 - core3)

        return [
            seg(.core, core1),
            seg(.deep, deep1),
            seg(.core, core2),
            seg(.rem, rem1),
            seg(.awake, max(4, awakeMin / 2)),
            seg(.core, core3),
            seg(.deep, deep2),
            seg(.awake, max(4, awakeMin - awakeMin / 2)),
            seg(.rem, rem2),
            seg(.core, core4),
        ]
    }
}
