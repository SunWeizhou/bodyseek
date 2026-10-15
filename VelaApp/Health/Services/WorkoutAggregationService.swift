import Foundation
import SwiftData

@MainActor
public final class WorkoutAggregationService {
    public static let shared = WorkoutAggregationService()

    /// 未填写 RPE 时的保守负荷系数（轻强度下限）。
    /// 方向要求：跳过的自评不能被解释为“中等强度”，因此缺省按轻强度估算，
    /// 而不是按 RPE 5-6 的中等强度捏造负荷。
    public static let missingRPELoadFactor: Double = 3.0
    private static let duplicateTimeTolerance: TimeInterval = 120
    
    private init() {}
    
    /// Merges HealthKit synced workouts with manual and strength workouts in SwiftData for a clean consolidated list.
    public func aggregateWorkouts(
        healthKitWorkouts: [WorkoutSummary],
        for date: Date,
        modelContext: ModelContext,
        blacklistedIDs: Set<String> = [],
        calendar: Calendar = .current
    ) -> [WorkoutSummary] {
        // 用「日历日」而非 04:00 健康日边界取事件：record 主键是日历午夜。
        // 此前 00:00–04:00 的训练会落入前一天的查询窗，而 aggregateDay 只重算
        // 当天 → workoutCount/时长/热量写错记录。
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

        let localRecords = consolidateLocalEvents(
            (try? WorkoutHistoryRepository(modelContext: modelContext).fetchWorkoutEvents(from: dayStart, until: dayEnd)) ?? []
        )

        var merged: [WorkoutSummary] = []

        // 1. Keep HealthKit workouts unless a mirrored WorkoutEventRecord already represents them.
        // P1-2 修复：黑名单（用户在 App 删除过的训练）必须同时过滤 HK 摘要与本地镜像事件，
        // 否则删除后仍被重新计数。
        let filteredHealthKit = healthKitWorkouts.filter { !blacklistedIDs.contains($0.id.uuidString) }
        let filteredLocal = localRecords.filter { record in
            if blacklistedIDs.contains(record.id.uuidString) { return false }
            if let hkId = record.linkedHealthKitWorkoutId,
               blacklistedIDs.contains(hkId.uuidString) { return false }
            return true
        }

        for hk in filteredHealthKit {
            if !filteredLocal.contains(where: { localRecordRepresentsHealthKitWorkout($0, hk) }) {
                merged.append(WorkoutSummary(
                    id: hk.id,
                    start: hk.start,
                    end: hk.end,
                    activityName: hk.activityName,
                    energyKilocalories: hk.energyKilocalories,
                    averageHeartRate: hk.averageHeartRate,
                    heartRateRecoveryOneMinuteBPM: hk.heartRateRecoveryOneMinuteBPM,
                    distanceMeters: hk.distanceMeters,
                    source: hk.source ?? "healthKit",
                    rpe: hk.rpe
                ))
            }
        }
        
        // 2. Add local records (manual / strength / xunji / HealthKit mirrors).
        for local in filteredLocal {
            let matchedHK = filteredHealthKit.first { localRecordRepresentsHealthKitWorkout(local, $0) }
            let useHealthKitTiming = local.linkedHealthKitWorkoutId != nil && matchedHK != nil
            let useLocalDisplay = local.linkedStrengthWorkoutId != nil
            
            merged.append(WorkoutSummary(
                id: local.id,
                start: useHealthKitTiming ? matchedHK?.start ?? local.startedAt : local.startedAt,
                end: useHealthKitTiming ? matchedHK?.end ?? local.endedAt : local.endedAt,
                activityName: useLocalDisplay ? local.title : (useHealthKitTiming ? matchedHK?.activityName ?? local.activityType : local.activityType),
                energyKilocalories: local.energyKilocalories ?? matchedHK?.energyKilocalories,
                averageHeartRate: local.averageHeartRate ?? matchedHK?.averageHeartRate,
                heartRateRecoveryOneMinuteBPM: matchedHK?.heartRateRecoveryOneMinuteBPM,
                distanceMeters: matchedHK?.distanceMeters,
                source: local.source,
                rpe: local.rpe
            ))
        }
        
        return deduplicateSummaries(merged).sorted { $0.start < $1.start }
    }

    public func upsertHealthKitWorkoutEvents(
        _ healthKitWorkouts: [WorkoutSummary],
        on date: Date,
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        // 1. Identify and remove any previously synced HealthKit workouts for this day that are no longer in healthKitWorkouts payload
        let dayRange = DateRangeQuery.singleDay(date, calendar: calendar)
        let dayStart = dayRange.start
        let dayEnd = dayRange.end
        
        let existingEvents = (try? WorkoutHistoryRepository(modelContext: modelContext).fetchWorkoutEvents(
            from: dayStart,
            until: dayEnd
        )) ?? []
        let currentHKIDs = Set(healthKitWorkouts.map { $0.id })
        
        for event in existingEvents {
            if let hkId = event.linkedHealthKitWorkoutId, !currentHKIDs.contains(hkId) {
                if event.linkedStrengthWorkoutId != nil {
                    event.linkedHealthKitWorkoutId = nil
                    event.source = "strengthLog"
                    event.updatedAt = Date()
                } else {
                    modelContext.delete(event)
                }
            }
        }

        // 2. Upsert current HealthKit workouts
        for workout in healthKitWorkouts {
            let healthKitID = workout.id
            let event: WorkoutEventRecord
            if let existing = try WorkoutHistoryRepository(modelContext: modelContext)
                .fetchEvents(linkedHealthKitWorkoutId: healthKitID)
                .first {
                event = existing
                event.startedAt = workout.start
                event.endedAt = workout.end
                event.dayIdentifier = DailyHealthSummaryRecord.healthDayIdentifier(forSampleAt: workout.start, calendar: calendar)
                if existing.linkedStrengthWorkoutId == nil {
                    event.activityType = workout.activityName
                    event.title = workout.activityName
                }
                event.durationMinutes = max(0, workout.end.timeIntervalSince(workout.start) / 60)
                event.energyKilocalories = workout.energyKilocalories
                event.averageHeartRate = workout.averageHeartRate
                event.linkedHealthKitWorkoutId = healthKitID
                event.source = resolvedSource(for: event)
                event.updatedAt = Date()
            } else if let matched = try findMergeCandidate(for: workout, modelContext: modelContext, calendar: calendar) {
                event = matched
                event.startedAt = workout.start
                event.endedAt = workout.end
                event.dayIdentifier = DailyHealthSummaryRecord.healthDayIdentifier(forSampleAt: workout.start, calendar: calendar)
                if event.linkedStrengthWorkoutId != nil {
                    event.activityType = event.title
                }
                event.durationMinutes = max(0, workout.end.timeIntervalSince(workout.start) / 60)
                event.energyKilocalories = workout.energyKilocalories
                event.averageHeartRate = workout.averageHeartRate
                event.linkedHealthKitWorkoutId = healthKitID
                event.source = resolvedSource(for: event)
                event.updatedAt = Date()
            } else {
                event = WorkoutEventRecord(
                    id: workout.id,
                    source: "healthKit",
                    startedAt: workout.start,
                    endedAt: workout.end,
                    activityType: workout.activityName,
                    energyKilocalories: workout.energyKilocalories,
                    averageHeartRate: workout.averageHeartRate,
                    linkedHealthKitWorkoutId: workout.id,
                    calendar: calendar
                )
                modelContext.insert(event)
            }
            // P1-3：Apple Watch 有氧等 HealthKit 训练也要参与计划日打卡
            //（此前只有手动力量路径会关联计划）。
            if event.linkedTrainingPlanDayId == nil {
                try? linkActivePlanDay(
                    for: event,
                    strengthWorkout: nil,
                    modelContext: modelContext,
                    calendar: calendar
                )
            }
        }
        try modelContext.save()
    }

    func mergeStrengthWorkoutDetails(
        event: WorkoutEventRecord,
        strengthWorkout: StrengthWorkoutRecord,
        displayTitle: String,
        sessionRPE: Double?,
        calendar: Calendar = .current
    ) {
        event.linkedStrengthWorkoutId = strengthWorkout.id
        event.activityType = displayTitle
        event.title = displayTitle
        event.rpe = event.rpe ?? sessionRPE
        event.source = resolvedSource(for: event)
        event.updatedAt = Date()
        strengthWorkout.linkedWorkoutEventId = event.id
    }

    func findMergeCandidate(
        for strengthWorkout: StrengthWorkoutRecord,
        in events: [WorkoutEventRecord],
        calendar: Calendar = .current
    ) -> WorkoutEventRecord? {
        events
            .compactMap { event -> (event: WorkoutEventRecord, score: Double)? in
                guard event.linkedStrengthWorkoutId == nil || event.linkedStrengthWorkoutId == strengthWorkout.id else {
                    return nil
                }
                guard event.linkedHealthKitWorkoutId != nil || event.source == "healthKit" else {
                    return nil
                }
                guard strengthEventRepresentsSameRealWorkout(event, strengthWorkout, calendar: calendar) else {
                    return nil
                }
                return (event, strengthMergeScore(event: event, strengthWorkout: strengthWorkout))
            }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.event.updatedAt > rhs.event.updatedAt
                }
                return lhs.score > rhs.score
            }
            .first?
            .event
    }

    @discardableResult
    func upsertWorkoutEvent(
        from strengthWorkout: StrengthWorkoutRecord,
        modelContext: ModelContext,
        sessionRPE: Double? = nil,
        calendar: Calendar = .current
    ) throws -> WorkoutEventRecord {
        let event = try prepareWorkoutEvent(
            from: strengthWorkout,
            modelContext: modelContext,
            sessionRPE: sessionRPE,
            calendar: calendar
        )
        try aggregateDay(date: strengthWorkout.startedAt, modelContext: modelContext, calendar: calendar)
        try modelContext.save()
        return event
    }

    @discardableResult
    func prepareWorkoutEvent(
        from strengthWorkout: StrengthWorkoutRecord,
        modelContext: ModelContext,
        sessionRPE: Double? = nil,
        calendar: Calendar = .current
    ) throws -> WorkoutEventRecord {
        let workoutID = strengthWorkout.id
        let resolvedRPE = sessionRPE ?? strengthWorkout.sessionRPE
        let event: WorkoutEventRecord
        if let existing = try WorkoutHistoryRepository(modelContext: modelContext)
            .fetchEvents(linkedStrengthWorkoutId: workoutID)
            .first {
            event = existing
            event.startedAt = strengthWorkout.startedAt
            event.endedAt = strengthWorkout.endedAt
            event.dayIdentifier = DailyHealthSummaryRecord.healthDayIdentifier(forSampleAt: strengthWorkout.startedAt, calendar: calendar)
            event.activityType = strengthWorkout.title
            event.title = strengthWorkout.title
            event.durationMinutes = Double(strengthWorkout.durationMinutes)
            event.energyKilocalories = event.energyKilocalories ?? Double(strengthWorkout.durationMinutes) * 6
            event.rpe = resolvedRPE
            event.updatedAt = Date()
        } else {
            // Find if there is an overlapping HealthKit event to merge with (30 mins range)
            let dayRange = HealthDayBoundary(calendar: calendar).range(containing: strengthWorkout.startedAt)
            let dayStart = dayRange.start
            let dayEnd = dayRange.end
            let existingEvents = (try? WorkoutHistoryRepository(modelContext: modelContext)
                .fetchEventsWithoutStrengthLink(from: dayStart, until: dayEnd)) ?? []
            if let matched = findMergeCandidate(for: strengthWorkout, in: existingEvents, calendar: calendar) {
                event = matched
                event.linkedStrengthWorkoutId = strengthWorkout.id
                event.title = strengthWorkout.title
                event.activityType = strengthWorkout.title
                event.rpe = event.rpe ?? resolvedRPE
                event.source = resolvedSource(for: event)
                event.updatedAt = Date()
            } else {
                event = WorkoutEventRecord(
                    source: "strengthLog",
                    startedAt: strengthWorkout.startedAt,
                    endedAt: strengthWorkout.endedAt,
                    activityType: strengthWorkout.title,
                    energyKilocalories: Double(strengthWorkout.durationMinutes) * 6,
                    rpe: resolvedRPE,
                    linkedStrengthWorkoutId: strengthWorkout.id,
                    calendar: calendar
                )
                modelContext.insert(event)
            }
        }
        strengthWorkout.linkedWorkoutEventId = event.id
        strengthWorkout.sessionRPE = resolvedRPE
        strengthWorkout.completedAt = strengthWorkout.endedAt
        try linkActivePlanDay(for: event, strengthWorkout: strengthWorkout, modelContext: modelContext, calendar: calendar)
        return event
    }

    public func aggregateDay(
        date: Date,
        modelContext: ModelContext,
        calendar: Calendar = .current,
        resetActivityTotals: Bool = false
    ) throws {
        try PersistenceWriteGate.shared.withSerializedWrite(
            operation: "WorkoutAggregationService.aggregateDay"
        ) {
            let dayStart = calendar.startOfDay(for: date)
            let identifier = DailyHealthSummaryRecord.dayIdentifier(for: dayStart, calendar: calendar)
            let record: DailyHealthSummaryRecord
            if let existing = try SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
                .fetchRecord(dayIdentifier: identifier) {
                record = existing
            } else {
                record = DailyHealthSummaryRecord(dayIdentifier: identifier, date: dayStart)
                modelContext.insert(record)
            }

            // P1-1 修复：不再回读 workoutsData 自反馈缓存（旧 JSON 会让已删除的
            // HealthKit 训练自我复活）。HK 训练已由 upsertHealthKitWorkoutEvents
            // 落成事件，这里只合并事件 + 黑名单过滤。
            let deletedRecords = (try? DeletedWorkoutRepository(modelContext: modelContext).fetchAll()) ?? []
            let blacklistedIDs = Set(deletedRecords.map(\.id))
            let merged = aggregateWorkouts(
                healthKitWorkouts: [],
                for: dayStart,
                modelContext: modelContext,
                blacklistedIDs: blacklistedIDs,
                calendar: calendar
            )
            let duration = merged.reduce(0) { $0 + max(0, $1.end.timeIntervalSince($1.start) / 60) }
            let energy = merged.compactMap(\.energyKilocalories).reduce(0, +)
            let load = merged.reduce(0) { partial, workout in
                partial + max(0, workout.end.timeIntervalSince(workout.start) / 60) * (workout.rpe ?? Self.missingRPELoadFactor) * 0.3
            }
            // Algorithm v1/workoutAggregation: session-RPE fallback load.
            // Source: WorkoutEventRecord + current day's HealthKit workoutsData.
            // Confidence: medium for HR/RPE workouts, low for duration-only workouts.
            let activityLoad = normalizedActivityLoad(record)
            let dailyLoad = activityLoad + load
            // 深度专项批次 1：回填日（45 天前的历史日）没有 WorkoutEventRecord，
            // workoutsData 也为 nil（回填只写计数/时长/类型）。此时若用空事件表
            // 覆盖，会把回填的 HealthKit 训练计数抹成 0，年度统计漏计。
            // 保留回填值；有事件或强制重置（删除回滚）时维持原行为。
            if !(merged.isEmpty && !resetActivityTotals && record.workoutsData == nil) {
                record.workoutsData = try JSONEncoder().encode(merged)
                record.workoutCount = merged.count
                record.workoutTypes = Set(merged.map(\.activityName)).sorted().joined(separator: ", ")
                record.workoutDuration = duration
            }
            // 删除回滚（[5]）：resetActivityTotals 时用训练侧数值整体重算，
            // 否则 max() 语义让已删除训练的热量/分钟永久残留（下次 HK 同步会恢复总量）。
            if resetActivityTotals {
                record.activeCalories = energy
                record.activeMinutes = max(0, duration)
            } else {
                record.activeMinutes = max(record.activeMinutes ?? 0, duration)
                record.activeCalories = max(record.activeCalories ?? 0, energy)
            }
            record.activityLoad = activityLoad
            // 引擎（TRIMP 域）已在 apply(snapshot:) 写入 dailyLoad/workoutLoad 时
            // 保留引擎值；仅在无引擎结果（导入/手动补录路径）时以 session-RPE 兜底，
            // 防止两套公式写同一字段造成量纲混用。
            if record.dailyLoad == nil {
                record.workoutLoad = load
                record.dailyLoad = dailyLoad
            }
            record.updatedAt = Date()
        }
    }

    private func normalizedActivityLoad(_ record: DailyHealthSummaryRecord) -> Double {
        guard let activityLoad = record.activityLoad else { return 0 }
        guard let previousWorkoutLoad = record.workoutLoad,
              previousWorkoutLoad > 0,
              let previousDailyLoad = record.dailyLoad,
              abs(previousDailyLoad - activityLoad) < 0.01 else {
            return activityLoad
        }
        return max(0, activityLoad - previousWorkoutLoad)
    }

    private func consolidateLocalEvents(_ events: [WorkoutEventRecord]) -> [WorkoutEventRecord] {
        var result: [String: WorkoutEventRecord] = [:]
        for event in events {
            let key = stableEventKey(event)
            if let existing = result[key] {
                result[key] = existing.updatedAt >= event.updatedAt ? existing : event
            } else {
                result[key] = event
            }
        }
        return Array(result.values).sorted { $0.startedAt < $1.startedAt }
    }

    private func stableEventKey(_ event: WorkoutEventRecord) -> String {
        if let linkedStrengthWorkoutId = event.linkedStrengthWorkoutId {
            return "strength:\(linkedStrengthWorkoutId.uuidString)"
        }
        if let linkedHealthKitWorkoutId = event.linkedHealthKitWorkoutId {
            return "healthKit:\(linkedHealthKitWorkoutId.uuidString)"
        }
        return [
            event.source,
            event.activityType.normalizedWorkoutText,
            "\(Int(event.startedAt.timeIntervalSince1970 / Self.duplicateTimeTolerance))",
            "\(Int(event.endedAt.timeIntervalSince1970 / Self.duplicateTimeTolerance))"
        ].joined(separator: "|")
    }

    private func localRecordRepresentsHealthKitWorkout(_ local: WorkoutEventRecord, _ healthKit: WorkoutSummary) -> Bool {
        if local.linkedHealthKitWorkoutId == healthKit.id || local.id == healthKit.id {
            return true
        }
        if workoutsOverlapByIdentity(
            lhsStart: local.startedAt,
            lhsEnd: local.endedAt,
            lhsActivity: local.activityType,
            rhsStart: healthKit.start,
            rhsEnd: healthKit.end,
            rhsActivity: healthKit.activityName
        ) {
            return true
        }
        let timeDifference = abs(local.startedAt.timeIntervalSince(healthKit.start))
        if timeDifference <= 30 * 60 && activitiesAreCompatible(local.activityType, healthKit.activityName) {
            return true
        }
        return false
    }

    private func deduplicateSummaries(_ workouts: [WorkoutSummary]) -> [WorkoutSummary] {
        var result: [String: WorkoutSummary] = [:]
        for workout in workouts {
            let key = summaryStableKey(workout)
            if let existing = result[key] {
                result[key] = richerSummary(existing, workout)
            } else {
                result[key] = workout
            }
        }
        return Array(result.values)
    }

    private func summaryStableKey(_ workout: WorkoutSummary) -> String {
        let source = workout.source ?? "healthKit"
        if source == "healthKit" {
            return "healthKit:\(workout.id.uuidString)"
        }
        return [
            source,
            workout.activityName.normalizedWorkoutText,
            "\(Int(workout.start.timeIntervalSince1970 / Self.duplicateTimeTolerance))",
            "\(Int(workout.end.timeIntervalSince1970 / Self.duplicateTimeTolerance))"
        ].joined(separator: "|")
    }

    private func richerSummary(_ lhs: WorkoutSummary, _ rhs: WorkoutSummary) -> WorkoutSummary {
        let lhsScore = [lhs.energyKilocalories, lhs.averageHeartRate, lhs.distanceMeters, lhs.rpe].compactMap { $0 }.count
        let rhsScore = [rhs.energyKilocalories, rhs.averageHeartRate, rhs.distanceMeters, rhs.rpe].compactMap { $0 }.count
        return rhsScore > lhsScore ? rhs : lhs
    }

    private func findMergeCandidate(
        for healthKitWorkout: WorkoutSummary,
        modelContext: ModelContext,
        calendar: Calendar
    ) throws -> WorkoutEventRecord? {
        let dayRange = HealthDayBoundary(calendar: calendar).range(containing: healthKitWorkout.start)
        let dayStart = dayRange.start
        let dayEnd = dayRange.end
        return try WorkoutHistoryRepository(modelContext: modelContext)
            .fetchWorkoutEvents(from: dayStart, until: dayEnd)
            .first { event in
                event.linkedHealthKitWorkoutId == nil
                    && eventRepresentsSameRealWorkout(event, healthKitWorkout)
            }
    }

    private func eventRepresentsSameRealWorkout(_ event: WorkoutEventRecord, _ healthKit: WorkoutSummary) -> Bool {
        guard healthKitWorkoutCanMergeWithStrengthDetails(healthKit.activityName) else { return false }
        guard activitiesAreCompatible(event.activityType, healthKit.activityName) else { return false }
        let overlapRatio = overlapRatio(
            lhsStart: event.startedAt,
            lhsEnd: event.endedAt,
            rhsStart: healthKit.start,
            rhsEnd: healthKit.end
        )
        let startClose = abs(event.startedAt.timeIntervalSince(healthKit.start)) <= 20 * 60
        let endClose = abs(event.endedAt.timeIntervalSince(healthKit.end)) <= 20 * 60
        return overlapRatio >= 0.5 && (startClose || endClose)
    }

    private func strengthEventRepresentsSameRealWorkout(
        _ event: WorkoutEventRecord,
        _ strengthWorkout: StrengthWorkoutRecord,
        calendar: Calendar
    ) -> Bool {
        guard calendar.isDate(event.startedAt, inSameDayAs: strengthWorkout.startedAt)
                || intervalsOverlap(
                    lhsStart: event.startedAt,
                    lhsEnd: event.endedAt,
                    rhsStart: strengthWorkout.startedAt,
                    rhsEnd: strengthWorkout.endedAt
                ) else {
            return false
        }
        guard healthKitWorkoutCanMergeWithStrengthDetails(event.activityType) else { return false }
        let overlapRatio = overlapRatio(
            lhsStart: event.startedAt,
            lhsEnd: event.endedAt,
            rhsStart: strengthWorkout.startedAt,
            rhsEnd: strengthWorkout.endedAt
        )
        let startClose = abs(event.startedAt.timeIntervalSince(strengthWorkout.startedAt)) <= 20 * 60
        let endClose = abs(event.endedAt.timeIntervalSince(strengthWorkout.endedAt)) <= 20 * 60
        return overlapRatio >= 0.5 && (startClose || endClose)
    }

    private func strengthMergeScore(event: WorkoutEventRecord, strengthWorkout: StrengthWorkoutRecord) -> Double {
        let overlap = overlapRatio(
            lhsStart: event.startedAt,
            lhsEnd: event.endedAt,
            rhsStart: strengthWorkout.startedAt,
            rhsEnd: strengthWorkout.endedAt
        )
        let startCloseness = closenessScore(abs(event.startedAt.timeIntervalSince(strengthWorkout.startedAt)), tolerance: 20 * 60)
        let endCloseness = closenessScore(abs(event.endedAt.timeIntervalSince(strengthWorkout.endedAt)), tolerance: 20 * 60)
        let durationDelta = abs(event.durationMinutes - Double(strengthWorkout.durationMinutes)) * 60
        let durationCloseness = closenessScore(durationDelta, tolerance: 30 * 60)
        let existingLinkBonus = event.linkedHealthKitWorkoutId != nil ? 0.1 : 0
        return overlap * 0.55 + max(startCloseness, endCloseness) * 0.25 + durationCloseness * 0.15 + existingLinkBonus
    }

    private func closenessScore(_ difference: TimeInterval, tolerance: TimeInterval) -> Double {
        guard tolerance > 0 else { return 0 }
        return max(0, 1 - difference / tolerance)
    }

    private func intervalsOverlap(
        lhsStart: Date,
        lhsEnd: Date,
        rhsStart: Date,
        rhsEnd: Date
    ) -> Bool {
        min(lhsEnd, rhsEnd) > max(lhsStart, rhsStart)
    }

    private func overlapRatio(
        lhsStart: Date,
        lhsEnd: Date,
        rhsStart: Date,
        rhsEnd: Date
    ) -> Double {
        let overlap = min(lhsEnd, rhsEnd).timeIntervalSince(max(lhsStart, rhsStart))
        guard overlap > 0 else { return 0 }
        let shorterDuration = min(lhsEnd.timeIntervalSince(lhsStart), rhsEnd.timeIntervalSince(rhsStart))
        guard shorterDuration > 0 else { return 0 }
        return overlap / shorterDuration
    }

    private func activitiesAreCompatible(_ lhs: String, _ rhs: String) -> Bool {
        let left = lhs.normalizedWorkoutText
        let right = rhs.normalizedWorkoutText
        if left == right { return true }
        let strengthTerms = ["strength", "traditionalstrengthtraining", "functionalstrengthtraining", "weight", "力量", "胸", "背", "肩", "腿", "臀", "二头", "三头"]
        let leftStrength = strengthTerms.contains { left.contains($0) }
        let rightStrength = strengthTerms.contains { right.contains($0) }
        return leftStrength && rightStrength
    }

    private func healthKitWorkoutCanMergeWithStrengthDetails(_ activity: String) -> Bool {
        let normalized = activity.normalizedWorkoutText
        let strengthTerms = [
            "strength",
            "traditionalstrengthtraining",
            "functionalstrengthtraining",
            "weighttraining",
            "力量",
            "传统力量训练",
            "功能性力量训练"
        ]
        return strengthTerms.contains { normalized.contains($0) }
    }

    private func resolvedSource(for event: WorkoutEventRecord) -> String {
        if event.linkedHealthKitWorkoutId != nil, event.linkedStrengthWorkoutId != nil {
            return "healthKit+xunji"
        }
        if event.linkedHealthKitWorkoutId != nil {
            return "healthKit"
        }
        return event.source
    }

    private func workoutsOverlapByIdentity(
        lhsStart: Date,
        lhsEnd: Date,
        lhsActivity: String,
        rhsStart: Date,
        rhsEnd: Date,
        rhsActivity: String
    ) -> Bool {
        lhsActivity.normalizedWorkoutText == rhsActivity.normalizedWorkoutText
            && abs(lhsStart.timeIntervalSince(rhsStart)) <= Self.duplicateTimeTolerance
            && abs(lhsEnd.timeIntervalSince(rhsEnd)) <= Self.duplicateTimeTolerance
    }

    public func rebuildRecentDays(
        days: Int,
        endingAt: Date = Date(),
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        for offset in 0..<max(0, days) {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: endingAt) else { continue }
            try aggregateDay(date: date, modelContext: modelContext, calendar: calendar)
        }
        try modelContext.save()
    }

    /// P1-3：把计划日关联从「仅手动力量」扩展到 Apple Watch 有氧与训记导入——
    /// 所有事件统一走此收口（strengthWorkout 为 nil 时按活动类型匹配）。
    func linkActivePlanDay(
        for event: WorkoutEventRecord,
        strengthWorkout: StrengthWorkoutRecord?,
        modelContext: ModelContext,
        calendar: Calendar
    ) throws {
        let plans = try TrainingPlanRepository(modelContext: modelContext).fetchActivePlans()
        let linker = TrainingPlanLinkingService()
        
        for plan in plans {
            let planStart = calendar.startOfDay(for: plan.startDate)
            var bestMatchIndex: Int?
            var bestMatchScore = 0.0
            
            for (index, day) in plan.days.enumerated() {
                // 与 TrainingScheduleResolver 同一锚点（planStart 所在周的周一），
                // 否则非周一起始的计划「展示的日期」与「完成标记的日期」错位，
                // 周三的计划日永远无法被周三的训练完成。
                let expectedDate = TrainingScheduleResolver.scheduledDate(
                    for: day,
                    planStart: plan.startDate,
                    calendar: calendar
                ) ?? planStart
                let score = linker.calculateMatchScore(
                    event: event,
                    planDay: day,
                    strengthWorkout: strengthWorkout,
                    expectedDate: expectedDate,
                    calendar: calendar
                )
                if score > bestMatchScore {
                    bestMatchScore = score
                    bestMatchIndex = index
                }
            }
            
            if let index = bestMatchIndex, linker.isHighConfidenceMatch(score: bestMatchScore) {
                var day = plan.days[index]
                if !day.linkedWorkoutEventIds.contains(event.id) {
                    day.linkedWorkoutEventIds.append(event.id)
                }
                day.isCompleted = true
                day.completedAt = event.endedAt
                day.loggedStrain = event.durationMinutes * (event.rpe ?? Self.missingRPELoadFactor) * 0.3
                day.adherenceScore = day.durationMinutes > 0
                    ? min(1.5, event.durationMinutes / Double(day.durationMinutes))
                    : 1
                let actual = [
                    "title": event.title,
                    "duration_minutes": event.durationMinutes.formatted(.number.precision(.fractionLength(0))),
                    "source": event.source
                ]
                if let data = try? JSONEncoder().encode(actual),
                   let json = String(data: data, encoding: .utf8) {
                    day.actualSummaryJSON = json
                }
                plan.days[index] = day
                plan.updatedAt = Date()
                event.linkedTrainingPlanDayId = day.id
                if let strengthWorkout {
                    strengthWorkout.planDayId = day.id
                }
                break
            }
        }
    }

    /// Creates or updates a TrainingResponseRecord linked to a StrengthWorkoutRecord.
    @discardableResult
    func upsertTrainingResponseRecord(
        for workout: StrengthWorkoutRecord,
        sessionRPE: Double?,
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws -> TrainingResponseRecord {
        let workoutID = workout.id
        let existing = (try? TrainingResponseRepository(modelContext: modelContext)
            .fetchResponses(workoutId: workoutID))?.first

        let primaryMuscles = Set(workout.exercises.compactMap { $0.primaryMuscleGroup }.filter { !$0.isEmpty })
        let muscleGroupsArray = Array(primaryMuscles)
        let effectiveSets = workout.exercises.flatMap(\.sets).filter { $0.isWarmup != true && $0.isCompleted != false }.count
        let totalVolume = workout.totalVolumeKilograms
        let nextDay = calendar.date(byAdding: .day, value: 1, to: workout.startedAt) ?? workout.startedAt.addingTimeInterval(86400)

        if let record = existing {
            record.date = workout.startedAt
            record.nextDayDate = nextDay
            record.primaryMuscleGroups = muscleGroupsArray
            record.totalEffectiveSets = effectiveSets
            record.totalVolumeKg = totalVolume
            record.sessionRPE = sessionRPE ?? workout.sessionRPE
            return record
        } else {
            let record = TrainingResponseRecord(
                workoutId: workoutID,
                date: workout.startedAt,
                nextDayDate: nextDay,
                primaryMuscleGroups: muscleGroupsArray,
                totalEffectiveSets: effectiveSets,
                totalVolumeKg: totalVolume,
                sessionRPE: sessionRPE ?? workout.sessionRPE
            )
            modelContext.insert(record)
            return record
        }
    }

    /// P3-8：插入黑名单前查重（id 为 @Attribute(.unique)，双入口重复插入会导致保存冲突）。
    func blacklistWorkout(id: String, modelContext: ModelContext) {
        let descriptor = FetchDescriptor<DeletedWorkoutRecord>(
            predicate: #Predicate<DeletedWorkoutRecord> { $0.id == id }
        )
        let existing = (try? modelContext.fetch(descriptor)) ?? []
        if existing.isEmpty {
            modelContext.insert(DeletedWorkoutRecord(id: id))
        }
    }

    /// P2-6：删除训练时回滚其关联的计划日打卡（此前日历该日仍打勾、执行率仍计数）。
    private func rollbackLinkedPlanDays(
        for events: [WorkoutEventRecord],
        modelContext: ModelContext
    ) {
        let dayIDs = Set(events.compactMap(\.linkedTrainingPlanDayId))
        guard !dayIDs.isEmpty else { return }
        let plans = (try? TrainingPlanRepository(modelContext: modelContext).fetchAll()) ?? []
        for plan in plans {
            var changed = false
            for (index, day) in plan.days.enumerated() where dayIDs.contains(day.id) {
                var updated = day
                updated.linkedWorkoutEventIds = []
                updated.isCompleted = false
                updated.completedAt = nil
                updated.loggedStrain = nil
                updated.actualSummaryJSON = ""
                updated.adherenceScore = nil
                plan.days[index] = updated
                changed = true
            }
            if changed {
                plan.updatedAt = Date()
            }
        }
    }

    /// Deletes a StrengthWorkoutRecord and cleans up its linked WorkoutEventRecord, XunjiWorkoutMirrorRecord, TrainingResponseRecord, and daily load.
    func deleteStrengthWorkout(
        _ workout: StrengthWorkoutRecord,
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        let workoutID = workout.id
        let workoutDate = workout.startedAt
        
        // 1. Find linked events
        let events = try WorkoutHistoryRepository(modelContext: modelContext)
            .fetchEvents(linkedStrengthWorkoutId: workoutID)
        for event in events {
            if let hkId = event.linkedHealthKitWorkoutId {
                blacklistWorkout(id: hkId.uuidString, modelContext: modelContext)
            }
            if event.source == "xunji" || event.source == "strengthLog" {
                modelContext.delete(event)
            } else {
                // If it is a HealthKit or other synced event, keep the event but unlink it.
                // P3-9：解除关联后必须重算 source，否则列表仍把已删训练标成「Apple + 训记」。
                event.linkedStrengthWorkoutId = nil
                event.source = resolvedSource(for: event)
                event.updatedAt = Date()
            }
        }

        // P2-6 修复：删除训练后回滚计划日打卡——此前日历该日仍打勾、
        // 计划执行率仍按 isCompleted 计数。
        rollbackLinkedPlanDays(for: events, modelContext: modelContext)
        
        // 2. Find Xunji mirror records
        let mirrors = try XunjiWorkoutMirrorRepository(modelContext: modelContext)
            .fetch(linkedStrengthWorkoutId: workoutID)
        for mirror in mirrors {
            blacklistWorkout(id: mirror.externalID, modelContext: modelContext)
            modelContext.delete(mirror)
        }

        // 3. Find linked TrainingResponseRecords
        let responses = try TrainingResponseRepository(modelContext: modelContext).fetchResponses(workoutId: workoutID)
        for resp in responses {
            modelContext.delete(resp)
        }
        
        // 4. Delete the StrengthWorkoutRecord itself
        modelContext.delete(workout)
        
        try modelContext.save()
        
        // 5. Recalculate summary and aggregation for the affected day
        // 删除回滚：activeCalories/activeMinutes 需整体重算（max 语义会残留旧值）。
        try aggregateDay(date: workoutDate, modelContext: modelContext, calendar: calendar, resetActivityTotals: true)
        try modelContext.save()
        
        // Trigger DailyPlanRefreshCoordinator
        let dateToRefresh = workoutDate
        DailyPlanRefreshCoordinator.shared.schedulePlanRefresh(
            for: [dateToRefresh],
            container: modelContext.container
        )
    }
}

@MainActor
struct WorkoutSaveCoordinator {
    enum Stage: Int, CaseIterable, Sendable {
        case workoutInsertion = 1
        case eventUpsert
        case artifactInsertion
        case aggregation
        case draftDeletion
        case save
    }

    struct CommitResult {
        let workout: StrengthWorkoutRecord
        let event: WorkoutEventRecord
    }

    typealias FailureInjector = @MainActor (Stage) throws -> Void

    private let failureInjector: FailureInjector
    private let aggregationService: WorkoutAggregationService
    private let calendar: Calendar

    init(
        aggregationService: WorkoutAggregationService = .shared,
        calendar: Calendar = .current,
        failureInjector: @escaping FailureInjector = { _ in }
    ) {
        self.aggregationService = aggregationService
        self.calendar = calendar
        self.failureInjector = failureInjector
    }

    init(failureInjector: @escaping FailureInjector) {
        self.init(
            aggregationService: .shared,
            calendar: .current,
            failureInjector: failureInjector
        )
    }

    func commitNewWorkout(
        workout: StrengthWorkoutRecord,
        artifact: CoachArtifactRecord,
        sessionRPE: Double?,
        modelContext: ModelContext
    ) throws -> CommitResult {
        do {
            try PersistenceWriteGate.shared.assertWritable(
                operation: "WorkoutSaveCoordinator.commitNewWorkout",
                modelContext: modelContext
            )

            try failureInjector(.workoutInsertion)
            modelContext.insert(workout)

            try failureInjector(.eventUpsert)
            let event = try aggregationService.prepareWorkoutEvent(
                from: workout,
                modelContext: modelContext,
                sessionRPE: sessionRPE,
                calendar: calendar
            )
            _ = try aggregationService.upsertTrainingResponseRecord(
                for: workout,
                sessionRPE: sessionRPE,
                modelContext: modelContext,
                calendar: calendar
            )

            try failureInjector(.artifactInsertion)
            modelContext.insert(artifact)

            try failureInjector(.aggregation)
            try aggregationService.aggregateDay(
                date: workout.startedAt,
                modelContext: modelContext,
                calendar: calendar
            )

            try failureInjector(.draftDeletion)
            try deleteActiveDrafts(modelContext: modelContext)

            try failureInjector(.save)
            try modelContext.save()

            DailyPlanRefreshCoordinator.shared.schedulePlanRefresh(
                for: [workout.startedAt],
                container: modelContext.container
            )

            return CommitResult(workout: workout, event: event)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    func commitWorkoutEdit(
        workout: StrengthWorkoutRecord,
        previousStartDate: Date,
        sessionRPE: Double?,
        modelContext: ModelContext
    ) throws -> CommitResult {
        do {
            try PersistenceWriteGate.shared.assertWritable(
                operation: "WorkoutSaveCoordinator.commitWorkoutEdit",
                modelContext: modelContext
            )

            try failureInjector(.eventUpsert)
            let event = try aggregationService.prepareWorkoutEvent(
                from: workout,
                modelContext: modelContext,
                sessionRPE: sessionRPE,
                calendar: calendar
            )
            _ = try aggregationService.upsertTrainingResponseRecord(
                for: workout,
                sessionRPE: sessionRPE,
                modelContext: modelContext,
                calendar: calendar
            )

            try failureInjector(.aggregation)
            if !calendar.isDate(previousStartDate, inSameDayAs: workout.startedAt) {
                try aggregationService.aggregateDay(
                    date: previousStartDate,
                    modelContext: modelContext,
                    calendar: calendar
                )
            }
            try aggregationService.aggregateDay(
                date: workout.startedAt,
                modelContext: modelContext,
                calendar: calendar
            )

            try failureInjector(.save)
            try modelContext.save()

            let prevDate = previousStartDate
            let refreshDates = Calendar.current.isDate(prevDate, inSameDayAs: workout.startedAt)
                ? [workout.startedAt]
                : [workout.startedAt, prevDate]
            DailyPlanRefreshCoordinator.shared.schedulePlanRefresh(
                for: refreshDates,
                container: modelContext.container
            )

            return CommitResult(workout: workout, event: event)
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func deleteActiveDrafts(modelContext: ModelContext) throws {
        for draft in try ActiveWorkoutDraftRepository(modelContext: modelContext).fetchAll() {
            modelContext.delete(draft)
        }
    }
}

private extension String {
    var normalizedWorkoutText: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
    }
}
