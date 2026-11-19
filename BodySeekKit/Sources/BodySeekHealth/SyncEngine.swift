import BodySeekCore
import BodySeekStore
import Foundation
import os
#if os(iOS)
import HealthKit
#endif

public struct SystemConditions: Equatable, Hashable, Sendable {
    public let isLowPowerModeEnabled: Bool
    public let isThermallyThrottled: Bool

    public init(isLowPowerModeEnabled: Bool = false, isThermallyThrottled: Bool = false) {
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.isThermallyThrottled = isThermallyThrottled
    }
}

public protocol SystemConditionProvider: Sendable {
    func currentConditions() async -> SystemConditions
}

public struct LiveSystemConditionProvider: SystemConditionProvider {
    public init() {}

    public func currentConditions() async -> SystemConditions {
        let info = ProcessInfo.processInfo
        let thermalThrottled: Bool
        switch info.thermalState {
        case .serious, .critical:
            thermalThrottled = true
        case .nominal, .fair:
            thermalThrottled = false
        @unknown default:
            thermalThrottled = false
        }
        return SystemConditions(
            isLowPowerModeEnabled: info.isLowPowerModeEnabled,
            isThermallyThrottled: thermalThrottled
        )
    }
}

public struct SyncBatch: Sendable {
    public let dayMetrics: [DayMetricRecord]
    public let hourlyMetrics: [HourlyMetricRecord]
    public let rawSleepSamples: [RawSleepSample]
    public let workouts: [StoredWorkoutRecord]
    public let workoutSymbols: [String: String]
    public let affectedDayKeys: Set<DayKey>
    public let nextAnchorData: Data?

    public init(
        dayMetrics: [DayMetricRecord] = [],
        hourlyMetrics: [HourlyMetricRecord] = [],
        rawSleepSamples: [RawSleepSample] = [],
        workouts: [StoredWorkoutRecord] = [],
        workoutSymbols: [String: String] = [:],
        affectedDayKeys: Set<DayKey> = [],
        nextAnchorData: Data? = nil
    ) {
        self.dayMetrics = dayMetrics
        self.hourlyMetrics = hourlyMetrics
        self.rawSleepSamples = rawSleepSamples
        self.workouts = workouts
        self.workoutSymbols = workoutSymbols
        self.affectedDayKeys = affectedDayKeys
        self.nextAnchorData = nextAnchorData
    }
}

public protocol HealthKitSyncSource: Sendable {
    func fetchAnchoredRecent(
        anchorData: Data?,
        lookbackDays: Int,
        referenceDate: Date
    ) async throws -> SyncBatch

    func fetchMonthlyBackfill(
        monthStart: Date,
        monthEnd: Date
    ) async throws -> SyncBatch
}

public struct SyncRunSummary: Equatable, Hashable, Sendable {
    public let syncedDayKeys: Set<DayKey>
    public let sleepEpisodesSaved: Int
    public let workoutsSaved: Int
    public let scoresComputed: Int

    public init(
        syncedDayKeys: Set<DayKey>,
        sleepEpisodesSaved: Int,
        workoutsSaved: Int,
        scoresComputed: Int
    ) {
        self.syncedDayKeys = syncedDayKeys
        self.sleepEpisodesSaved = sleepEpisodesSaved
        self.workoutsSaved = workoutsSaved
        self.scoresComputed = scoresComputed
    }
}

public enum BackfillPauseReason: String, Equatable, Hashable, Sendable, Codable {
    case lowPowerMode
    case thermalThrottle
}

public struct BackfillRunSummary: Equatable, Hashable, Sendable {
    public let monthsCompleted: Int
    public let pausedReason: BackfillPauseReason?
    public let lastCursor: DayKey?
    public let completedAll: Bool

    public init(
        monthsCompleted: Int,
        pausedReason: BackfillPauseReason?,
        lastCursor: DayKey?,
        completedAll: Bool
    ) {
        self.monthsCompleted = monthsCompleted
        self.pausedReason = pausedReason
        self.lastCursor = lastCursor
        self.completedAll = completedAll
    }
}

/// Coordinates HealthKit anchored incremental sync (30d first), resumable 3-year monthly backfill
/// (pausing under low-power mode or thermal throttling), 3-second observer debounce,
/// versioned `SleepMergePolicy`, and incremental `BevelScoringEngine` score snapshots.
public actor SyncEngine {
    public static let recentAnchorType = "hk_recent_v1"
    public static let backfillAnchorType = "hk_backfill_v1"
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "SyncEngine")

    public let repository: BodySeekRepository
    public let source: any HealthKitSyncSource
    public let conditions: any SystemConditionProvider
    public let debounceDuration: Duration
    public var sleepGoalMinutes: Int
    public let calendar: Calendar

    private var debounceTask: Task<Void, Never>?

    public init(
        repository: BodySeekRepository,
        source: any HealthKitSyncSource,
        conditions: any SystemConditionProvider = LiveSystemConditionProvider(),
        debounceDuration: Duration = .seconds(3),
        sleepGoalMinutes: Int = 450,
        calendar: Calendar = .current
    ) {
        self.repository = repository
        self.source = source
        self.conditions = conditions
        self.debounceDuration = debounceDuration
        self.sleepGoalMinutes = sleepGoalMinutes
        self.calendar = calendar
    }

    public func updateSleepGoal(minutes: Int) {
        self.sleepGoalMinutes = minutes
    }

    @discardableResult
    public func syncRecentWindow(
        days: Int = 30,
        referenceDate: Date = Date()
    ) async throws -> SyncRunSummary {
        let signpost = BodySeekSignposts.shared.begin(.healthKitWindowFetch)
        defer { BodySeekSignposts.shared.end(.healthKitWindowFetch, signpost) }

        let anchorState = try await repository.loadSyncAnchor(type: Self.recentAnchorType)
        let batch = try await source.fetchAnchoredRecent(
            anchorData: anchorState?.anchorData,
            lookbackDays: days,
            referenceDate: referenceDate
        )

        let summary = try await persistAndRecompute(batch: batch, referenceDate: referenceDate)

        if let nextAnchor = batch.nextAnchorData {
            try await repository.saveSyncAnchor(
                SyncAnchorState(
                    type: Self.recentAnchorType,
                    anchorData: nextAnchor,
                    backfillCursor: anchorState?.backfillCursor,
                    updatedAt: referenceDate
                )
            )
        }

        return summary
    }

    @discardableResult
    public func runResumableBackfill(
        totalMonths: Int = 36,
        referenceDate: Date = Date()
    ) async throws -> BackfillRunSummary {
        let initialAnchor = try await repository.loadSyncAnchor(type: Self.backfillAnchorType)
        let refStart = calendar.startOfDay(for: referenceDate)
        let earliestTarget = calendar.date(byAdding: .month, value: -max(1, totalMonths), to: refStart) ?? refStart
        let earliestKey = DayKey(date: earliestTarget, cutoverHour: 4, timeZone: calendar.timeZone)

        var currentEndKey = initialAnchor?.backfillCursor
            ?? DayKey(date: refStart, cutoverHour: 4, timeZone: calendar.timeZone)

        if currentEndKey <= earliestKey {
            return BackfillRunSummary(
                monthsCompleted: 0,
                pausedReason: nil,
                lastCursor: currentEndKey,
                completedAll: true
            )
        }

        var monthsCompleted = 0

        while currentEndKey > earliestKey {
            let sys = await conditions.currentConditions()
            if sys.isLowPowerModeEnabled {
                Self.logger.info("Pausing 3y HealthKit backfill at \(currentEndKey.isoString, privacy: .public) due to Low Power Mode.")
                return BackfillRunSummary(
                    monthsCompleted: monthsCompleted,
                    pausedReason: .lowPowerMode,
                    lastCursor: currentEndKey,
                    completedAll: false
                )
            }
            if sys.isThermallyThrottled {
                Self.logger.info("Pausing 3y HealthKit backfill at \(currentEndKey.isoString, privacy: .public) due to thermal throttling.")
                return BackfillRunSummary(
                    monthsCompleted: monthsCompleted,
                    pausedReason: .thermalThrottle,
                    lastCursor: currentEndKey,
                    completedAll: false
                )
            }

            let windowEnd = currentEndKey.startDate(cutoverHour: 4, timeZone: calendar.timeZone)
            let rawWindowStart = calendar.date(byAdding: .month, value: -1, to: windowEnd) ?? earliestTarget
            let clampedStart = max(earliestTarget, rawWindowStart)
            let nextCursorKey = DayKey(date: clampedStart, cutoverHour: 4, timeZone: calendar.timeZone)

            let batch = try await source.fetchMonthlyBackfill(
                monthStart: clampedStart,
                monthEnd: windowEnd
            )
            _ = try await persistAndRecompute(batch: batch, referenceDate: referenceDate)

            monthsCompleted += 1
            currentEndKey = nextCursorKey

            try await repository.saveSyncAnchor(
                SyncAnchorState(
                    type: Self.backfillAnchorType,
                    anchorData: batch.nextAnchorData,
                    backfillCursor: currentEndKey,
                    updatedAt: Date()
                )
            )

            if monthsCompleted >= totalMonths {
                break
            }
        }

        return BackfillRunSummary(
            monthsCompleted: monthsCompleted,
            pausedReason: nil,
            lastCursor: currentEndKey,
            completedAll: currentEndKey <= earliestKey
        )
    }

    /// Coalesces rapid HealthKit observer updates with a 3-second debounce window before syncing.
    public func scheduleDebouncedSync(
        referenceDate: Date = Date(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        onCompleted: (@Sendable (Result<SyncRunSummary, Error>) async -> Void)? = nil
    ) {
        debounceTask?.cancel()
        let waitDuration = debounceDuration
        debounceTask = Task {
            do {
                try await sleep(waitDuration)
                try Task.checkCancellation()
                let summary = try await self.syncRecentWindow(days: 30, referenceDate: referenceDate)
                await onCompleted?(.success(summary))
            } catch is CancellationError {
                // Coalesced by a newer notification within the 3s debounce window.
            } catch {
                Self.logger.error("Debounced HealthKit sync failed: \(error.localizedDescription, privacy: .public)")
                await onCompleted?(.failure(error))
            }
        }
    }

    private func persistAndRecompute(
        batch: SyncBatch,
        referenceDate: Date
    ) async throws -> SyncRunSummary {
        var dirtyKeys = batch.affectedDayKeys
        for m in batch.dayMetrics {
            dirtyKeys.insert(m.dayKey)
        }
        for w in batch.workouts {
            dirtyKeys.insert(w.start.physiologicalDayKey(cutoverHour: 4, timeZone: calendar.timeZone))
        }

        var mergedEpisodes: [MergedSleepEpisode] = []
        var sleepDays: Set<DayKey> = []
        var sleepDayMetrics: [DayMetricRecord] = []

        if !batch.rawSleepSamples.isEmpty {
            let mergedByDay = SleepMergePolicy.merge(
                samples: batch.rawSleepSamples,
                cutoverHour: 4,
                timeZone: calendar.timeZone
            )
            for (dayKey, result) in mergedByDay {
                dirtyKeys.insert(dayKey)
                sleepDays.insert(dayKey)
                mergedEpisodes.append(contentsOf: result.episodes)

                let primarySources = result.primaryEpisode?.sources ?? []
                if let asleep = result.totalAsleepMinutes {
                    sleepDayMetrics.append(
                        DayMetricRecord(
                            dayKey: dayKey,
                            metric: DayMetricField.sleepAsleepMinutes.rawValue,
                            value: Double(asleep),
                            state: asleep > 0 ? .available : .knownZero,
                            coverage: 1.0,
                            sources: primarySources
                        )
                    )
                }
                if let inBed = result.totalInBedMinutes {
                    sleepDayMetrics.append(
                        DayMetricRecord(
                            dayKey: dayKey,
                            metric: DayMetricField.sleepInBedMinutes.rawValue,
                            value: Double(inBed),
                            state: inBed > 0 ? .available : .knownZero,
                            coverage: 1.0,
                            sources: primarySources
                        )
                    )
                }
                if let deep = result.deepMinutes {
                    sleepDayMetrics.append(
                        DayMetricRecord(
                            dayKey: dayKey,
                            metric: DayMetricField.deepMinutes.rawValue,
                            value: Double(deep),
                            state: .available,
                            coverage: 1.0,
                            sources: primarySources
                        )
                    )
                }
                if let rem = result.remMinutes {
                    sleepDayMetrics.append(
                        DayMetricRecord(
                            dayKey: dayKey,
                            metric: DayMetricField.remMinutes.rawValue,
                            value: Double(rem),
                            state: .available,
                            coverage: 1.0,
                            sources: primarySources
                        )
                    )
                }
                if let core = result.coreMinutes {
                    sleepDayMetrics.append(
                        DayMetricRecord(
                            dayKey: dayKey,
                            metric: DayMetricField.coreMinutes.rawValue,
                            value: Double(core),
                            state: .available,
                            coverage: 1.0,
                            sources: primarySources
                        )
                    )
                }
                if let awake = result.awakeMinutes {
                    sleepDayMetrics.append(
                        DayMetricRecord(
                            dayKey: dayKey,
                            metric: DayMetricField.awakeMinutes.rawValue,
                            value: Double(awake),
                            state: .available,
                            coverage: 1.0,
                            sources: primarySources
                        )
                    )
                }
            }
        }

        let allDayMetrics = batch.dayMetrics + sleepDayMetrics
        if !allDayMetrics.isEmpty {
            try await repository.upsertDayMetrics(allDayMetrics)
        }
        if !batch.hourlyMetrics.isEmpty {
            try await repository.upsertHourlyMetrics(batch.hourlyMetrics)
        }
        if !mergedEpisodes.isEmpty {
            try await repository.saveSleepEpisodes(mergedEpisodes, replacingDays: sleepDays)
        }
        if !batch.workouts.isEmpty {
            try await repository.upsertWorkouts(batch.workouts, symbolByUUID: batch.workoutSymbols)
        }

        guard !dirtyKeys.isEmpty else {
            return SyncRunSummary(
                syncedDayKeys: [],
                sleepEpisodesSaved: mergedEpisodes.count,
                workoutsSaved: batch.workouts.count,
                scoresComputed: 0
            )
        }

        let allRawDays = try await repository.loadRawDays(calendar: calendar)
        let snapshot = BevelScoringEngine.recomputeIncremental(
            existingByDayKey: [:],
            allRawDays: allRawDays,
            dirtyDayKeys: dirtyKeys,
            sleepGoalMinutes: sleepGoalMinutes,
            referenceDate: referenceDate,
            sourceLabel: "Apple 健康 · SyncEngine",
            isAuthorized: true,
            calendar: calendar
        )

        let dirtyStarts = dirtyKeys.map { $0.calendarDayStart(calendar: calendar) }
        let daysToSave = snapshot.historyDays.filter { computed in
            let dayStart = computed.dayKey.calendarDayStart(calendar: calendar)
            return dirtyStarts.contains { dirtyStart in
                let delta = calendar.dateComponents([.day], from: dirtyStart, to: dayStart).day ?? -1
                return (0...28).contains(delta)
            }
        }

        try await repository.saveComputedDays(daysToSave.isEmpty ? snapshot.historyDays : daysToSave)

        return SyncRunSummary(
            syncedDayKeys: dirtyKeys,
            sleepEpisodesSaved: mergedEpisodes.count,
            workoutsSaved: batch.workouts.count,
            scoresComputed: daysToSave.isEmpty ? snapshot.historyDays.count : daysToSave.count
        )
    }
}

#if os(iOS)
public final class LiveHealthKitSyncSource: HealthKitSyncSource, @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "LiveHealthKitSyncSource")
    private let store: HKHealthStore
    private let calendar: Calendar

    private struct QuantitySampleDTO: Sendable {
        let value: Double
        let endDate: Date
        let source: SourceRef
    }

    public init(store: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public func enableBackgroundDelivery() async {
        let backgroundTypes: [HKSampleType] = [
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.restingHeartRate),
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.appleExerciseTime),
        ]
        for sampleType in backgroundTypes {
            do {
                try await store.enableBackgroundDelivery(for: sampleType, frequency: .immediate)
            } catch {
                Self.logger.error("Failed enabling background delivery for \(sampleType.identifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func fetchAnchoredRecent(
        anchorData: Data?,
        lookbackDays: Int,
        referenceDate: Date
    ) async throws -> SyncBatch {
        let end = referenceDate
        let start = calendar.date(byAdding: .day, value: -max(1, lookbackDays), to: calendar.startOfDay(for: end)) ?? end
        return try await fetchWindow(start: start, end: end, incomingAnchorData: anchorData, useAnchoredWorkouts: true)
    }

    public func fetchMonthlyBackfill(
        monthStart: Date,
        monthEnd: Date
    ) async throws -> SyncBatch {
        try await fetchWindow(start: monthStart, end: monthEnd, incomingAnchorData: nil, useAnchoredWorkouts: false)
    }

    private func fetchWindow(
        start: Date,
        end: Date,
        incomingAnchorData: Data?,
        useAnchoredWorkouts: Bool
    ) async throws -> SyncBatch {
        guard HKHealthStore.isHealthDataAvailable() else {
            return SyncBatch()
        }

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        var dayMetrics: [DayMetricRecord] = []
        var affectedDays = Set<DayKey>()
        let tz = calendar.timeZone

        // 1. Discrete daily quantity signals
        let discreteSpecs: [(HKQuantityTypeIdentifier, HKUnit, DayMetricField, Bool)] = [
            (.heartRateVariabilitySDNN, .secondUnit(with: .milli), .hrvMs, false),
            (.restingHeartRate, .count().unitDivided(by: .minute()), .restingHeartRateBpm, false),
            (.respiratoryRate, .count().unitDivided(by: .minute()), .respiratoryRateBrpm, false),
            (.oxygenSaturation, .percent(), .oxygenSaturationPct, true),
            (.appleSleepingWristTemperature, .degreeCelsius(), .wristTempDeltaC, false),
            (.walkingHeartRateAverage, .count().unitDivided(by: .minute()), .walkingHeartRateAvgBpm, false),
            (.vo2Max, HKUnit(from: "ml/kg*min"), .vo2MaxMlKgMin, false),
            (.heartRateRecoveryOneMinute, .count().unitDivided(by: .minute()), .heartRateRecovery1MinBpm, false),
            (.bodyMass, .gramUnit(with: .kilo), .bodyMassKg, false),
            (.physicalEffort, HKUnit(from: "kcal/(kg*hr)"), .physicalEffortKcalPerKgHr, false),
        ]

        for (identifier, unit, field, scalePercent) in discreteSpecs {
            do {
                let samples = try await queryQuantitySamples(
                    identifier: identifier,
                    unit: unit,
                    scalePercent: scalePercent,
                    predicate: predicate
                )
                let windowWristBaseline: Double? = field == .wristTempDeltaC
                    ? BevelScoringEngine.median(samples.map(\.value))
                    : nil
                let grouped = Dictionary(grouping: samples) { sample in
                    sample.endDate.physiologicalDayKey(cutoverHour: 4, timeZone: tz)
                }
                for (dayKey, items) in grouped {
                    let values = items.map(\.value)
                    guard !values.isEmpty else { continue }
                    let meanValue = values.reduce(0, +) / Double(values.count)
                    let value = if field == .wristTempDeltaC, let windowWristBaseline {
                        meanValue - windowWristBaseline
                    } else {
                        meanValue
                    }
                    let sources = Self.uniqueSourceRefs(items.map(\.source))
                    dayMetrics.append(
                        DayMetricRecord(
                            dayKey: dayKey,
                            metric: field.rawValue,
                            value: value,
                            state: .available,
                            coverage: 1.0,
                            sources: sources
                        )
                    )
                    affectedDays.insert(dayKey)
                }
            } catch {
                Self.logger.error("HealthKit query failed for \(identifier.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // 2. Cumulative statistics (steps, activeEnergy, exerciseMinutes)
        let cumulativeSpecs: [(HKQuantityTypeIdentifier, HKUnit, DayMetricField)] = [
            (.activeEnergyBurned, .kilocalorie(), .activeEnergyKcal),
            (.appleExerciseTime, .minute(), .exerciseMinutes),
            (.stepCount, .count(), .steps),
        ]
        for (identifier, unit, field) in cumulativeSpecs {
            do {
                let byDay = try await queryDailyCumulativeSums(
                    identifier: identifier,
                    unit: unit,
                    start: start,
                    end: end
                )
                for (dayKey, total) in byDay {
                    dayMetrics.append(
                        DayMetricRecord(
                            dayKey: dayKey,
                            metric: field.rawValue,
                            value: total,
                            state: total == 0 ? .knownZero : .available,
                            reason: total == 0 ? "当日零活动" : nil,
                            coverage: 1.0
                        )
                    )
                    affectedDays.insert(dayKey)
                }
            } catch {
                Self.logger.error("HealthKit statistics query failed for \(identifier.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // 3. Hourly heart rate + daytime mean/max
        var hourlyRecords: [HourlyMetricRecord] = []
        do {
            let hrByHour = try await queryHourlyAverages(
                identifier: .heartRate,
                unit: .count().unitDivided(by: .minute()),
                start: start,
                end: end
            )
            var daytimeByDay: [DayKey: [Double]] = [:]
            for (hourStart, avgBPM) in hrByHour {
                hourlyRecords.append(
                    HourlyMetricRecord(hourStart: hourStart, metric: "hr_bpm", value: avgBPM, coverage: 1.0)
                )
                let key = hourStart.physiologicalDayKey(cutoverHour: 4, timeZone: calendar.timeZone)
                daytimeByDay[key, default: []].append(avgBPM)
            }
            for (dayKey, bpms) in daytimeByDay where !bpms.isEmpty {
                let mean = bpms.reduce(0, +) / Double(bpms.count)
                let maxVal = bpms.max() ?? mean
                dayMetrics.append(
                    DayMetricRecord(
                        dayKey: dayKey,
                        metric: DayMetricField.daytimeMeanHeartRateBpm.rawValue,
                        value: mean,
                        state: .available,
                        coverage: min(1.0, Double(bpms.count) / 16.0)
                    )
                )
                dayMetrics.append(
                    DayMetricRecord(
                        dayKey: dayKey,
                        metric: DayMetricField.daytimeMaxHeartRateBpm.rawValue,
                        value: maxVal,
                        state: .available,
                        coverage: min(1.0, Double(bpms.count) / 16.0)
                    )
                )
                affectedDays.insert(dayKey)
            }
        } catch {
            Self.logger.error("HealthKit hourly heartRate failed: \(error.localizedDescription, privacy: .public)")
        }

        // 4. Raw sleep samples for SleepMergePolicy
        var rawSleepSamples: [RawSleepSample] = []
        do {
            rawSleepSamples = try await querySleepSamples(predicate: predicate)
            for sample in rawSleepSamples {
                affectedDays.insert(sample.endDate.physiologicalDayKey(cutoverHour: 4, timeZone: tz))
            }
        } catch {
            Self.logger.error("HealthKit sleepAnalysis query failed: \(error.localizedDescription, privacy: .public)")
        }

        // 5. Workouts (separating user workoutEffortScore from estimatedWorkoutEffortScore)
        var workoutRecords: [StoredWorkoutRecord] = []
        var workoutSymbols: [String: String] = [:]
        var nextAnchorData: Data? = incomingAnchorData

        do {
            let result = try await queryWorkouts(
                predicate: useAnchoredWorkouts ? nil : predicate,
                anchorData: useAnchoredWorkouts ? incomingAnchorData : nil
            )
            workoutRecords = result.records
            workoutSymbols = result.symbols
            nextAnchorData = result.nextAnchor ?? incomingAnchorData
            for record in workoutRecords {
                affectedDays.insert(record.start.physiologicalDayKey(cutoverHour: 4, timeZone: tz))
            }
        } catch {
            Self.logger.error("HealthKit anchored workout query failed: \(error.localizedDescription, privacy: .public)")
        }

        return SyncBatch(
            dayMetrics: dayMetrics,
            hourlyMetrics: hourlyRecords,
            rawSleepSamples: rawSleepSamples,
            workouts: workoutRecords,
            workoutSymbols: workoutSymbols,
            affectedDayKeys: affectedDays,
            nextAnchorData: nextAnchorData
        )
    }

    private func queryQuantitySamples(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        scalePercent: Bool,
        predicate: NSPredicate
    ) async throws -> [QuantitySampleDTO] {
        let type = HKQuantityType(identifier)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let dtos = ((samples as? [HKQuantitySample]) ?? []).map { s in
                    let rawVal = s.quantity.doubleValue(for: unit)
                    let scaled = (scalePercent && rawVal <= 1.0) ? rawVal * 100.0 : rawVal
                    return QuantitySampleDTO(
                        value: scaled,
                        endDate: s.endDate,
                        source: Self.makeSourceRef(from: s)
                    )
                }
                continuation.resume(returning: dtos)
            }
            store.execute(query)
        }
    }

    private func querySleepSamples(predicate: NSPredicate) async throws -> [RawSleepSample] {
        let type = HKCategoryType(.sleepAnalysis)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let converted: [RawSleepSample] = ((samples as? [HKCategorySample]) ?? []).compactMap { sample in
                    guard let stage = Self.mapSleepStage(rawValue: sample.value) else { return nil }
                    return RawSleepSample(
                        id: sample.uuid,
                        startDate: sample.startDate,
                        endDate: sample.endDate,
                        stage: stage,
                        source: Self.makeSourceRef(from: sample),
                        deviceIdentifier: sample.device?.localIdentifier
                    )
                }
                continuation.resume(returning: converted)
            }
            store.execute(query)
        }
    }

    private func queryWorkouts(
        predicate: NSPredicate?,
        anchorData: Data?
    ) async throws -> (records: [StoredWorkoutRecord], symbols: [String: String], nextAnchor: Data?) {
        var anchor: HKQueryAnchor?
        if let anchorData {
            do {
                anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: anchorData)
            } catch {
                Self.logger.error("Failed unarchiving HKQueryAnchor: \(error.localizedDescription, privacy: .public)")
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: HKObjectType.workoutType(),
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, _, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var archived: Data?
                if let newAnchor {
                    do {
                        archived = try NSKeyedArchiver.archivedData(
                            withRootObject: newAnchor,
                            requiringSecureCoding: true
                        )
                    } catch {
                        Self.logger.error("Failed archiving HKQueryAnchor: \(error.localizedDescription, privacy: .public)")
                    }
                }
                let energyType = HKQuantityType(.activeEnergyBurned)
                let hrType = HKQuantityType(.heartRate)
                let userEffortType = HKQuantityType(.workoutEffortScore)
                let estEffortType = HKQuantityType(.estimatedWorkoutEffortScore)
                var records: [StoredWorkoutRecord] = []
                var symbols: [String: String] = [:]

                for workout in (samples as? [HKWorkout]) ?? [] {
                    let kcal = workout.statistics(for: energyType)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    let avgHR = workout.statistics(for: hrType)?.averageQuantity()?
                        .doubleValue(for: .count().unitDivided(by: .minute()))
                    let effortUser = workout.statistics(for: userEffortType)?.mostRecentQuantity()?
                        .doubleValue(for: .appleEffortScore())
                    let effortEstimated = workout.statistics(for: estEffortType)?.mostRecentQuantity()?
                        .doubleValue(for: .appleEffortScore())

                    let (activityName, symbolName) = SpeziHealthKitFetcher.activityDisplay(for: workout.workoutActivityType)
                    let uuidStr = workout.uuid.uuidString
                    symbols[uuidStr] = symbolName
                    records.append(
                        StoredWorkoutRecord(
                            hkUUID: uuidStr,
                            type: activityName,
                            start: workout.startDate,
                            end: workout.endDate,
                            energy: kcal,
                            avgHR: avgHR,
                            zones: nil,
                            effortUser: effortUser,
                            effortEstimated: effortEstimated,
                            reviewState: .unreviewed
                        )
                    )
                }
                continuation.resume(returning: (records, symbols, archived))
            }
            store.execute(query)
        }
    }

    private func queryDailyCumulativeSums(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [DayKey: Double] {
        let type = HKQuantityType(identifier)
        let anchorDate = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: start) ?? start
        let interval = DateComponents(day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { [calendar] _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [:])
                    return
                }
                var totals: [DayKey: Double] = [:]
                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let sum = stats.sumQuantity()?.doubleValue(for: unit) {
                        let key = stats.startDate.physiologicalDayKey(cutoverHour: 4, timeZone: calendar.timeZone)
                        totals[key] = sum
                    }
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    private func queryHourlyAverages(
        identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        start: Date,
        end: Date
    ) async throws -> [(Date, Double)] {
        let type = HKQuantityType(identifier)
        let anchorDate = calendar.startOfDay(for: start)
        let interval = DateComponents(hour: 1)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .discreteAverage,
                anchorDate: anchorDate,
                intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var rows: [(Date, Double)] = []
                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    if let avg = stats.averageQuantity()?.doubleValue(for: unit) {
                        rows.append((stats.startDate, avg))
                    }
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }

    private static func mapSleepStage(rawValue: Int) -> RawSleepSampleStage? {
        guard let val = HKCategoryValueSleepAnalysis(rawValue: rawValue) else { return nil }
        switch val {
        case .inBed:
            return .inBed
        case .asleepUnspecified:
            return .asleepUnspecified
        case .awake:
            return .awake
        case .asleepCore:
            return .core
        case .asleepDeep:
            return .deep
        case .asleepREM:
            return .rem
        @unknown default:
            return .asleepUnspecified
        }
    }

    private static func makeSourceRef(from sample: HKSample) -> SourceRef {
        let bundle = sample.sourceRevision.source.bundleIdentifier
        let name = sample.sourceRevision.source.name
        let model = sample.device?.model ?? sample.sourceRevision.productType
        let isWatch = (model?.lowercased().contains("watch") == true) || name.lowercased().contains("watch")
        let isAutoSleep = bundle.lowercased().contains("autosleep") || bundle.lowercased().contains("tantsissa")
        let priority = isWatch ? 100 : (isAutoSleep ? 60 : 20)
        return SourceRef(bundleIdentifier: bundle, name: name, deviceModel: model, priority: priority)
    }

    private static func uniqueSourceRefs(_ refs: [SourceRef]) -> [SourceRef] {
        var seen = Set<SourceRef>()
        var ordered: [SourceRef] = []
        for ref in refs {
            if seen.insert(ref).inserted {
                ordered.append(ref)
            }
        }
        return ordered
    }
}
#endif
