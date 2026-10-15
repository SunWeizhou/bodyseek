import Foundation
import SwiftData

struct TrainingAnalyticsService: Sendable {

    init() {}

    func summarizeWorkout(
        _ workout: StrengthWorkoutDTO,
        history: [StrengthWorkoutDTO] = [],
        exerciseLibrary: [ExerciseDefinition] = ExerciseLibraryService.defaultDefinitionsDTO()
    ) -> StrengthWorkoutAnalysis {
        var volume = 0.0
        var plannedSets = 0
        var completedSets = 0
        var effectiveSets = 0
        var reps = 0
        var muscleGroupSets: [String: Int] = [:]
        var muscleGroupVolume: [String: Double] = [:]
        var e1RM: [String: Double] = [:]

        for exercise in workout.exercises {
            let muscle = resolvedMuscleGroup(for: exercise, library: exerciseLibrary)
            for set in exercise.sets {
                plannedSets += 1
                guard set.isCompleted == true else { continue }
                completedSets += 1
                reps += set.repetitions
                let setVolume = set.volumeKilograms
                volume += setVolume
                guard isEffective(set, equipment: exercise.equipment) else {
                    // 真实 1-2 次组不算「有效组」，但仍是 e1RM 测试数据（此前被
                    // reps>=3 门控排除，1RM 测试永不进 e1RM）。
                    if !set.isWarmup,
                       (1...12).contains(set.repetitions),
                       set.weightKilograms > 0,
                       (set.rpe ?? 8) >= 6 {
                        let value = set.weightKilograms * (1 + Double(set.repetitions) / 30)
                        e1RM[exercise.name] = max(e1RM[exercise.name] ?? 0, value)
                    }
                    continue
                }
                effectiveSets += 1
                muscleGroupSets[muscle, default: 0] += 1
                muscleGroupVolume[muscle, default: 0] += setVolume
                if set.repetitions >= 1, set.repetitions <= 12, set.weightKilograms > 0 {
                    let value = set.weightKilograms * (1 + Double(set.repetitions) / 30)
                    e1RM[exercise.name] = max(e1RM[exercise.name] ?? 0, value)
                }
            }
        }

        let records = detectPersonalRecords(workout: workout, history: history)
        let density = workout.durationMinutes > 0 ? volume / Double(workout.durationMinutes) : 0
        let muscleText = muscleGroupSets
            .sorted { $0.key < $1.key }
            .map { "\(localizedMuscle($0.key)) \($0.value) 组" }
            .joined(separator: "、")
        let uncompletedSets = max(0, plannedSets - completedSets)
        let summary = localizedWorkoutSummary(
            title: workout.title,
            completedSets: completedSets,
            plannedSets: plannedSets,
            effectiveSets: effectiveSets,
            volume: volume,
            uncompletedSets: uncompletedSets,
            muscleText: muscleText
        )
        return StrengthWorkoutAnalysis(
            totalVolumeKg: volume,
            plannedSets: plannedSets,
            completedSets: completedSets,
            uncompletedSets: uncompletedSets,
            totalSets: plannedSets,
            effectiveSets: effectiveSets,
            totalReps: reps,
            muscleGroupSets: muscleGroupSets,
            muscleGroupVolume: muscleGroupVolume,
            estimatedOneRepMaxByExercise: e1RM,
            personalRecords: records,
            densityKgPerMinute: density,
            summaryText: summary
        )
    }

    func detectPersonalRecords(workout: StrengthWorkoutDTO, history: [StrengthWorkoutDTO]) -> [PersonalRecord] {
        var records: [PersonalRecord] = []
        for exercise in workout.exercises {
            let workSets = exercise.sets.filter { !$0.isWarmup && $0.isCompleted == true }
            guard let maxWeight = workSets.map(\.weightKilograms).max(), !workSets.isEmpty else { continue }
            let maxE1RM = workSets
                .filter { $0.weightKilograms > 0 && $0.repetitions >= 1 && $0.repetitions <= 12 }
                .map { $0.weightKilograms * (1 + Double($0.repetitions) / 30) }
                .max() ?? 0
            let priorSets = history.flatMap(\.exercises).filter { namesMatch($0.name, exercise.name) }.flatMap(\.sets).filter { !$0.isWarmup && $0.isCompleted == true }
            guard !priorSets.isEmpty else { continue }
            let priorMaxWeight = priorSets.map(\.weightKilograms).max() ?? 0
            let priorMaxE1RM = priorSets
                .filter { $0.weightKilograms > 0 && $0.repetitions >= 1 && $0.repetitions <= 12 }
                .map { $0.weightKilograms * (1 + Double($0.repetitions) / 30) }
                .max() ?? 0
            if maxWeight > priorMaxWeight {
                records.append(PersonalRecord(exerciseName: exercise.name, kind: "max_weight", value: maxWeight, previousValue: priorMaxWeight))
            }
            if maxE1RM > priorMaxE1RM {
                records.append(PersonalRecord(exerciseName: exercise.name, kind: "estimated_1rm", value: maxE1RM, previousValue: priorMaxE1RM))
            }
        }
        return records
    }

    func buildRecentSummary(
        workouts: [StrengthWorkoutDTO],
        days: Int,
        endingAt: Date = Date(),
        exerciseLibrary: [ExerciseDefinition] = ExerciseLibraryService.defaultDefinitionsDTO()
    ) -> RecentTrainingSummary {
        let start = endingAt.addingTimeInterval(-Double(days) * 86_400)
        let sorted = workouts.sorted { $0.startedAt < $1.startedAt }
        let recentCount = sorted.lazy.filter { $0.startedAt >= start && $0.startedAt <= endingAt }.count
        guard recentCount > 0 else { return .empty(days: days) }

        var totalSets = 0
        var totalVolume = 0.0
        var muscles: [String: Int] = [:]
        var records: [PersonalRecord] = []
        var prior: [StrengthWorkoutDTO] = []
        var latestRecentSummary: String?

        // 按 startedAt 分组推进先例集合：同一时刻的训练彼此不进入历史比较，
        // 与旧实现 `startedAt < current.startedAt` 语义一致，但整体从 O(n²) 降为 O(n log n)。
        let groupedByStart = Dictionary(grouping: sorted, by: { $0.startedAt })
        for start in groupedByStart.keys.sorted() {
            let batch = groupedByStart[start] ?? []
            for workout in batch {
                let isRecent = workout.startedAt >= start && workout.startedAt <= endingAt
                guard isRecent else { continue }
                let analysis = summarizeWorkout(workout, history: prior, exerciseLibrary: exerciseLibrary)
                totalSets += analysis.effectiveSets
                totalVolume += analysis.totalVolumeKg
                records.append(contentsOf: analysis.personalRecords)
                for (muscle, count) in analysis.muscleGroupSets {
                    muscles[muscle, default: 0] += count
                }
                latestRecentSummary = analysis.summaryText
            }
            prior.append(contentsOf: batch)
        }

        return RecentTrainingSummary(
            days: days,
            sessions: recentCount,
            effectiveSets: totalSets,
            volumeKg: totalVolume,
            muscleGroupSets: muscles,
            recentPRs: records,
            lastWorkoutSummary: latestRecentSummary ?? "No strength training sessions logged in the past \(days) days.",
            localFatigue: computeLocalFatigue(workouts: workouts, endingAt: endingAt, exerciseLibrary: exerciseLibrary)
        )
    }

    func computeLocalFatigue(
        workouts: [StrengthWorkoutDTO],
        endingAt: Date = Date(),
        exerciseLibrary: [ExerciseDefinition] = ExerciseLibraryService.defaultDefinitionsDTO()
    ) -> [String: LocalMuscleFatigue] {
        let start7d = endingAt.addingTimeInterval(-7 * 86_400)
        let start48h = endingAt.addingTimeInterval(-48 * 3_600)
        var result: [String: LocalMuscleFatigue] = [:]
        for workout in workouts where workout.startedAt >= start7d && workout.startedAt <= endingAt {
            for exercise in workout.exercises {
                let muscle = resolvedMuscleGroup(for: exercise, library: exerciseLibrary)
                for set in exercise.sets where isEffective(set, equipment: exercise.equipment) {
                    var fatigue = result[muscle] ?? LocalMuscleFatigue(muscleGroup: muscle, setsLast48h: 0, setsLast7d: 0, volumeLast7d: 0)
                    if workout.startedAt >= start48h { fatigue.setsLast48h += 1 }
                    fatigue.setsLast7d += 1
                    fatigue.volumeLast7d += set.volumeKilograms
                    result[muscle] = fatigue
                }
            }
        }
        return result
    }

    private func isEffective(_ set: StrengthSetLog, equipment: String) -> Bool {
        guard set.isCompleted == true else { return false }
        guard !set.isWarmup, set.repetitions >= 3 else { return false }
        let supportsBodyweight = equipment.lowercased().contains("bodyweight") || equipment.contains("自重")
        guard set.weightKilograms > 0 || supportsBodyweight else { return false }
        if let rpe = set.rpe, rpe < 6 { return false }
        if let rir = set.rir, rir > 4 { return false }
        return true
    }

    private func localizedWorkoutSummary(
        title: String,
        completedSets: Int,
        plannedSets: Int,
        effectiveSets: Int,
        volume: Double,
        uncompletedSets: Int,
        muscleText: String
    ) -> String {
        let volumeText = "\(Int(volume.rounded())) kg"
        if AppLanguage.stored.isChinese {
            var facts = [
                "已完成 \(completedSets)/\(plannedSets) 组",
                "\(effectiveSets) 组有效组",
                "训练容量 \(volumeText)"
            ]
            if uncompletedSets > 0 {
                facts.append("另有 \(uncompletedSets) 组未完成")
            }
            if !muscleText.isEmpty {
                facts.append(muscleText)
            }
            return "\(title) · \(facts.joined(separator: " · "))"
        }

        var facts = [
            "\(completedSets)/\(plannedSets) sets completed",
            "\(effectiveSets) effective sets",
            "\(volumeText) volume"
        ]
        if uncompletedSets > 0 {
            facts.append("\(uncompletedSets) unfinished")
        }
        if !muscleText.isEmpty {
            facts.append(muscleText)
        }
        return "\(title) · \(facts.joined(separator: " · "))"
    }

    private func localizedMuscle(_ muscle: String) -> String {
        guard AppLanguage.stored.isChinese else { return muscle }
        return [
            "chest": "胸部",
            "back": "背部",
            "quads": "股四头肌",
            "hamstrings": "腘绳肌",
            "glutes": "臀部",
            "shoulders": "肩部",
            "biceps": "肱二头肌",
            "triceps": "肱三头肌",
            "core": "核心",
            "other": "其他"
        ][muscle] ?? muscle
    }

    public func resolvedMuscleGroup(for exercise: StrengthExerciseLog, library: [ExerciseDefinition]) -> String {
        if let explicit = exercise.primaryMuscleGroup, !explicit.isEmpty { return explicit }
        if let canonicalKey = exercise.exerciseCanonicalKey,
           let definition = library.first(where: { $0.canonicalKey == canonicalKey }) {
            return definition.primaryMuscleGroup
        }
        if let definition = library.first(where: { namesMatch($0.name, exercise.name) || $0.aliases.contains(where: { namesMatch($0, exercise.name) }) }) {
            return definition.primaryMuscleGroup
        }
        let name = exercise.name.lowercased()
        if name.contains("bench") || name.contains("卧推") || name.contains("夹胸") { return "chest" }
        if name.contains("row") || name.contains("划船") || name.contains("下拉") || name.contains("引体") { return "back" }
        if name.contains("squat") || name.contains("深蹲") || name.contains("腿") { return "quads" }
        if name.contains("curl") || name.contains("弯举") { return "biceps" }
        if name.contains("press") || name.contains("推举") || name.contains("侧平举") { return "shoulders" }
        if name.contains("plank") || name.contains("卷腹") { return "core" }
        return "other"
    }

    private func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == rhs.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

struct XunjiImportSummary: Codable, Hashable, Sendable {
    var importedCount: Int
    var updatedCount: Int
    var skippedCount: Int
    var importedTitles: [String]

    static let empty = XunjiImportSummary(importedCount: 0, updatedCount: 0, skippedCount: 0, importedTitles: [])
}

struct XunjiTrainingAPIClient: Sendable {
    private let baseURL = URL(string: "https://trains.xunjiapp.cn") ?? URL(fileURLWithPath: "/")
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchTraining(
        apiKey: String,
        datestr: String,
        includeFullData: Bool
    ) async throws -> Data {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw XunjiAPIError.missingAPIKey }

        var request = URLRequest(url: baseURL.appending(path: "api_trains_for_llm_v2"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(XunjiReadRequest(
            datestr: datestr,
            includeFullData: includeFullData
        ))

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw XunjiAPIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw XunjiAPIError.httpStatus(http.statusCode)
        }
        return data
    }
}

enum XunjiAPIError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先填写训记 Open API Key。"
        case .invalidResponse:
            return "训记接口返回了无法识别的响应。"
        case .httpStatus(let status):
            return "训记接口请求失败（HTTP \(status)）。"
        }
    }
}

private struct XunjiReadRequest: Encodable {
    let schemaVersion = "train_open_api_v2"
    var datestr: String
    var includeFullData: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case datestr
        case includeFullData = "include_full_data"
    }
}

struct XunjiTrainingImportService: Sendable {

    /// 深度专项批次 1：训记↔本地力量的双录判定（纯函数，便于回归测试）。
    /// 收紧为「同日 且 开始差≤60min 且 时长差≤10min」——宁可重复显示也不丢训练。
    static func isSameSessionDuplicate(
        existing: StrengthWorkoutRecord,
        candidateStart: Date,
        candidateDurationMinutes: Int,
        calendar: Calendar
    ) -> Bool {
        calendar.isDate(existing.startedAt, inSameDayAs: candidateStart)
            && abs(existing.startedAt.timeIntervalSince(candidateStart)) <= 3_600
            && abs(existing.durationMinutes - candidateDurationMinutes) <= 10
    }
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }

    @MainActor
    func importResponseData(
        _ data: Data,
        datestr: String,
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws -> XunjiImportSummary {
        let response: XunjiTrainingAPIResponse
        do {
            response = try decoder.decode(XunjiTrainingAPIResponse.self, from: data)
        } catch let decodingError as DecodingError {
            throw XunjiImportError.decodingError(XunjiImportError.formatDecodingError(decodingError))
        } catch {
            throw error
        }
        guard response.success else {
            if let errMsg = response.errorMessage {
                throw XunjiImportError.apiError(errMsg)
            } else {
                throw XunjiImportError.unsuccessfulResponse
            }
        }

        let trains = response.res.trains.filter { ($0.datestr ?? datestr) == datestr }
        guard !trains.isEmpty else { return .empty }

        let existingMirrors = try XunjiWorkoutMirrorRepository(modelContext: modelContext).fetchAll()
        let history = WorkoutHistoryRepository(modelContext: modelContext)
        let existingWorkouts = try history.fetchStrengthWorkouts()
        let existingEvents = try history.fetchWorkoutEvents()
        var imported = 0
        var updated = 0
        var skipped = 0
        var deduped = 0
        var titles: [String] = []
        var affectedDatesByIdentifier: [String: Date] = [:]
        func markAffected(_ date: Date) {
            let day = calendar.startOfDay(for: date)
            affectedDatesByIdentifier[DailyHealthSummaryRecord.dayIdentifier(for: day, calendar: calendar)] = day
        }

        let deletedRecords = (try? DeletedWorkoutRepository(modelContext: modelContext).fetchAll()) ?? []
        let blacklistedIDs = Set(deletedRecords.map(\.id))

        for train in trains {
            guard let normalized = normalize(train: train, fallbackDatestr: datestr, calendar: calendar) else {
                skipped += 1
                continue
            }

            if blacklistedIDs.contains(normalized.externalID) {
                skipped += 1
                continue
            }

            let rawData = (try? encoder.encode(train)) ?? Data()
            let mirror = existingMirrors.first { $0.externalID == normalized.externalID }
            let workout: StrengthWorkoutRecord
            if let mirror,
               let linkedID = mirror.linkedStrengthWorkoutID,
               let existing = existingWorkouts.first(where: { $0.id == linkedID }) {
                workout = existing
                markAffected(workout.startedAt)
                workout.title = normalized.title
                workout.startedAt = normalized.startedAt
                workout.durationMinutes = normalized.durationMinutes
                workout.notes = normalized.notes
                workout.exercises = normalized.exercises
                workout.completedAt = normalized.startedAt.addingTimeInterval(TimeInterval(normalized.durationMinutes * 60))
                updated += 1
            } else {
                // 双录防护：同日已存在时长相近的本地记录时视为同一场训练，
                // 不再创建第二条 StrengthWorkoutRecord（否则 sessions/volume 翻倍）。
                // 深度专项批次 1：原判定为「时长差≤10 || 开始差≤60min」——|| 会把
                // 同日两场时长相近（如都约 50 分钟）但相隔数小时的不同训练误合并，
                // 违反「宁可重复显示也不丢训练」。收紧为「同日 且 开始差≤60min
                // 且 时长差≤10min」，只合并时间窗内重叠的同场双录。
                if let duplicate = existingWorkouts.first(where: {
                    Self.isSameSessionDuplicate(
                        existing: $0,
                        candidateStart: normalized.startedAt,
                        candidateDurationMinutes: normalized.durationMinutes,
                        calendar: calendar
                    )
                }) {
                    markAffected(duplicate.startedAt)
                    deduped += 1
                    continue
                }
                workout = StrengthWorkoutRecord(
                    title: normalized.title,
                    startedAt: normalized.startedAt,
                    durationMinutes: normalized.durationMinutes,
                    notes: normalized.notes,
                    exercises: normalized.exercises
                )
                modelContext.insert(workout)
                imported += 1
            }
            markAffected(workout.startedAt)

            let analysis = TrainingAnalyticsService().summarizeWorkout(
                workout.dto,
                history: existingWorkouts.filter { $0.id != workout.id }.map { $0.dto },
                exerciseLibrary: ExerciseLibraryService.defaultDefinitionsDTO()
            )
            // T7 修复：analyticsJSON 只写不读（详情页每次按需重算），停止写入；
            // 内容哈希改用训练事实本身，语义不变。
            let artifactHash = ContentHash.hash(
                "xunji-\(normalized.externalID)-\(workout.totalVolumeKilograms)-\(workout.exercises.flatMap(\.sets).count)"
            )
            let workoutIdStr = workout.id.uuidString
            let existingArtifacts = (try? CoachArtifactRepository(modelContext: modelContext).fetchAll()) ?? []
            
            for art in existingArtifacts {
                if art.actionsJSON.contains(workoutIdStr) {
                    modelContext.delete(art)
                }
            }
            
            modelContext.insert(CoachArtifactRecord(artifact: CoachArtifact.postWorkoutReview(
                workout: workout,
                summary: analysis,
                readinessDecision: "xunji_import",
                sourceContextHash: artifactHash
            )))

            let matchedEvent = WorkoutAggregationService.shared.findMergeCandidate(
                for: workout,
                in: existingEvents,
                calendar: calendar
            )

            let event: WorkoutEventRecord
            if let matched = matchedEvent {
                event = matched
                WorkoutAggregationService.shared.mergeStrengthWorkoutDetails(
                    event: event,
                    strengthWorkout: workout,
                    displayTitle: normalized.title,
                    sessionRPE: normalized.sessionRPE,
                    calendar: calendar
                )
                // P1-3：训记导入的力量训练也要参与计划日打卡（此前只有手动路径）。
                if event.linkedTrainingPlanDayId == nil {
                    try? WorkoutAggregationService.shared.linkActivePlanDay(
                        for: event,
                        strengthWorkout: workout,
                        modelContext: modelContext,
                        calendar: calendar
                    )
                }
                // Clean up any previously imported duplicate xunji event
                if let oldXunjiEvent = existingEvents.first(where: { $0.linkedStrengthWorkoutId == workout.id && $0.source == "xunji" }) {
                    modelContext.delete(oldXunjiEvent)
                }
            } else if let existingEvent = existingEvents.first(where: { $0.linkedStrengthWorkoutId == workout.id && $0.source == "xunji" }) {
                event = existingEvent
            } else {
                event = WorkoutEventRecord(
                    source: "xunji",
                    startedAt: workout.startedAt,
                    endedAt: workout.endedAt,
                    activityType: workout.title,
                    title: workout.title,
                    energyKilocalories: nil,
                    averageHeartRate: normalized.averageHeartRate,
                    rpe: normalized.sessionRPE,
                    linkedStrengthWorkoutId: workout.id,
                    calendar: calendar
                )
                modelContext.insert(event)
            }

            if event.source == "xunji" {
                event.startedAt = workout.startedAt
                event.endedAt = workout.endedAt
                event.dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: workout.startedAt, calendar: calendar)
                event.activityType = workout.title
                event.title = workout.title
                event.durationMinutes = Double(workout.durationMinutes)
                event.averageHeartRate = normalized.averageHeartRate
                event.rpe = normalized.sessionRPE
                event.updatedAt = Date()
            } else {
                event.updatedAt = Date()
            }

            workout.linkedWorkoutEventId = event.id

            if let mirror {
                mirror.datestr = normalized.datestr
                mirror.linkedStrengthWorkoutID = workout.id
                mirror.linkedWorkoutEventID = event.id
                mirror.rawTrainData = rawData
                mirror.lastImportedAt = Date()
            } else {
                modelContext.insert(XunjiWorkoutMirrorRecord(
                    externalID: normalized.externalID,
                    datestr: normalized.datestr,
                    linkedStrengthWorkoutID: workout.id,
                    linkedWorkoutEventID: event.id,
                    rawTrainData: rawData
                ))
            }

            titles.append(workout.title)
        }

        try modelContext.save()
        for affectedDate in affectedDatesByIdentifier.values {
            try WorkoutAggregationService.shared.aggregateDay(
                date: affectedDate,
                modelContext: modelContext,
                calendar: calendar
            )
        }
        try modelContext.save()
        return XunjiImportSummary(
            importedCount: imported,
            updatedCount: updated,
            skippedCount: skipped + deduped,
            importedTitles: titles
        )
    }

    func normalizedWorkouts(
        from data: Data,
        datestr: String,
        calendar: Calendar = .current
    ) throws -> [XunjiNormalizedWorkout] {
        let response: XunjiTrainingAPIResponse
        do {
            response = try decoder.decode(XunjiTrainingAPIResponse.self, from: data)
        } catch let decodingError as DecodingError {
            throw XunjiImportError.decodingError(XunjiImportError.formatDecodingError(decodingError))
        } catch {
            throw error
        }
        guard response.success else {
            if let errMsg = response.errorMessage {
                throw XunjiImportError.apiError(errMsg)
            } else {
                throw XunjiImportError.unsuccessfulResponse
            }
        }
        return response.res.trains.compactMap { normalize(train: $0, fallbackDatestr: datestr, calendar: calendar) }
    }

    private func normalize(
        train: XunjiTrain,
        fallbackDatestr: String,
        calendar: Calendar
    ) -> XunjiNormalizedWorkout? {
        let trainDate = train.datestr ?? fallbackDatestr
        let start = train.startDate ?? dateFrom(datestr: trainDate, calendar: calendar)
        let end = train.endDate ?? start.addingTimeInterval(60 * 60)
        let durationMinutes = max(1, Int(end.timeIntervalSince(start) / 60))
        let exercises = flattenExercises(
            from: train.movements,
            exerciseLibrary: ExerciseLibraryService.defaultDefinitions(),
            completedAtFallback: start
        )
        guard !exercises.isEmpty else { return nil }
        let externalID = train.localid.map(String.init) ?? "\(trainDate)-\(train.title ?? "workout")-\(Int(start.timeIntervalSince1970))"
        let metrics = train.movements.flatMap(\.sets).compactMap(\.metrics)
        let averageHeartRate = metrics.compactMap(\.avgHeartRate).average
        return XunjiNormalizedWorkout(
            externalID: externalID,
            datestr: trainDate,
            title: train.title?.trimmedNonEmpty ?? "训记训练",
            startedAt: start,
            durationMinutes: durationMinutes,
            notes: train.note ?? train.remark ?? "",
            sessionRPE: train.rpe,
            averageHeartRate: averageHeartRate,
            exercises: exercises
        )
    }

    private func flattenExercises(
        from movements: [XunjiMovement],
        exerciseLibrary: [ExerciseDefinitionRecord],
        completedAtFallback: Date? = nil
    ) -> [StrengthExerciseLog] {
        var grouped: [String: StrengthExerciseLog] = [:]
        var order: [String] = []

        func appendSet(_ set: StrengthSetLog, movementName: String) {
            let name = movementName.trimmedNonEmpty ?? "未命名动作"
            if grouped[name] == nil {
                // Resolve bodyweight equipment from the library so Xunji-imported
                // bodyweight exercises (weight 0, unknown equipment) still count
                // toward volume/fatigue via isEffective. Falls back to "其他".
                let definition = exerciseLibrary.first {
                    $0.canonicalKey == name.toCanonicalKey()
                        || $0.name.caseInsensitiveCompare(name) == .orderedSame
                }
                grouped[name] = StrengthExerciseLog(
                    exerciseCanonicalKey: name.toCanonicalKey(),
                    name: name,
                    equipment: definition?.equipment ?? "其他",
                    primaryMuscleGroup: nil,
                    sets: []
                )
                order.append(name)
            }
            grouped[name]?.sets.append(set)
        }

        for movement in movements {
            for set in movement.sets {
                if !set.items.isEmpty {
                    for item in set.items {
                        appendSet(item.set.strengthSet(doneFallback: set.done, completedAtFallback: completedAtFallback), movementName: item.name ?? movement.name)
                    }
                } else {
                    appendSet(set.strengthSet(doneFallback: set.done, completedAtFallback: completedAtFallback), movementName: movement.name)
                }
            }
        }

        return order.compactMap { grouped[$0] }.filter { !$0.sets.isEmpty }
    }

    private func dateFrom(datestr: String, calendar: Calendar) -> Date {
        var components = DateComponents()
        let parts = datestr.split(separator: "-").compactMap { Int($0) }
        components.year = parts.count > 0 ? parts[0] : nil
        components.month = parts.count > 1 ? parts[1] : nil
        components.day = parts.count > 2 ? parts[2] : nil
        components.hour = 18
        return calendar.date(from: components) ?? Date()
    }
}

enum XunjiImportError: Error, LocalizedError {
    case unsuccessfulResponse
    case apiError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .unsuccessfulResponse:
            return "训记接口返回了失败响应。"
        case .apiError(let message):
            return message
        case .decodingError(let details):
            return "数据格式错误: \(details)"
        }
    }

    static func formatDecodingError(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "类型不匹配: 期望 \(type), 路径 \(path). \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "未找到值: 期望 \(type), 路径 \(path). \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            let path = (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            return "缺失字段: '\(key.stringValue)', 路径 \(path). \(context.debugDescription)"
        case .dataCorrupted(let context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "数据损坏: 路径 \(path). \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }
}

struct XunjiNormalizedWorkout: Codable, Hashable, Sendable {
    var externalID: String
    var datestr: String
    var title: String
    var startedAt: Date
    var durationMinutes: Int
    var notes: String
    var sessionRPE: Double?
    var averageHeartRate: Double?
    var exercises: [StrengthExerciseLog]
}

private struct XunjiTrainingAPIResponse: Decodable {
    var success: Bool
    var res: XunjiTrainingResult
    var errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case success
        case res
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        let successVal = try container.decodeIfPresent(Bool.self, forKey: .success)
        
        if let successVal {
            self.success = successVal
            if successVal {
                if let resultObj = try? container.decode(XunjiTrainingResult.self, forKey: .res) {
                    self.res = resultObj
                } else {
                    let trainsArr = try container.decode([XunjiTrain].self, forKey: .res)
                    self.res = XunjiTrainingResult(trains: trainsArr)
                }
                self.errorMessage = nil
            } else {
                if let errorStr = try? container.decode(String.self, forKey: .res) {
                    self.errorMessage = errorStr
                } else {
                    self.errorMessage = nil
                }
                self.res = XunjiTrainingResult(trains: [])
            }
        } else {
            if let result = try? container.decode(XunjiTrainingResult.self, forKey: .res) {
                self.success = true
                self.res = result
                self.errorMessage = nil
            } else if let trainsArr = try? container.decode([XunjiTrain].self, forKey: .res) {
                self.success = true
                self.res = XunjiTrainingResult(trains: trainsArr)
                self.errorMessage = nil
            } else if let errorStr = try? container.decode(String.self, forKey: .res) {
                self.success = false
                self.errorMessage = errorStr
                self.res = XunjiTrainingResult(trains: [])
            } else {
                self.success = false
                self.errorMessage = nil
                self.res = try container.decode(XunjiTrainingResult.self, forKey: .res)
            }
        }
    }
}

private struct XunjiTrainingResult: Decodable {
    var trains: [XunjiTrain]
}


private struct XunjiTrain: Codable {
    var datestr: String?
    var localid: Int?
    var title: String?
    var start: Int64?
    var end: Int64?
    var note: String?
    var remark: String?
    var rpe: Double?
    var movements: [XunjiMovement]

    var startDate: Date? { start.map { Date(timeIntervalSince1970: Double($0) / 1_000) } }
    var endDate: Date? { end.map { Date(timeIntervalSince1970: Double($0) / 1_000) } }

    enum CodingKeys: String, CodingKey {
        case datestr, localid, title, start, end, note, remark, rpe, movements
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        datestr = try container.decodeFlexibleStringIfPresent(forKey: .datestr)
        localid = try container.decodeFlexibleIntIfPresent(forKey: .localid)
        title = try container.decodeFlexibleStringIfPresent(forKey: .title)
        start = try container.decodeFlexibleInt64IfPresent(forKey: .start)
        end = try container.decodeFlexibleInt64IfPresent(forKey: .end)
        note = try container.decodeFlexibleStringIfPresent(forKey: .note)
        remark = try container.decodeFlexibleStringIfPresent(forKey: .remark)
        rpe = try container.decodeFlexibleDoubleIfPresent(forKey: .rpe)
        movements = try container.decodeIfPresent([XunjiMovement].self, forKey: .movements) ?? []
    }
}

private struct XunjiMovement: Codable {
    var name: String
    var sets: [XunjiSet]

    enum CodingKeys: String, CodingKey {
        case name, sets
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeFlexibleStringIfPresent(forKey: .name) ?? "未命名动作"
        sets = try container.decodeIfPresent([XunjiSet].self, forKey: .sets) ?? []
    }
}

private struct XunjiSet: Codable {
    var done: Bool?
    var weight: String?
    var weightKg: Double?
    var unit: String?
    var reps: String?
    var time: String?
    var durationSeconds: Double?
    var selfWeight: Bool?
    var rpe: Double?
    var rir: Double?
    var note: String?
    var metrics: XunjiSetMetrics?
    var items: [XunjiSetItem]

    enum CodingKeys: String, CodingKey {
        case done, weight, unit, reps, time, selfWeight, rpe, rir, note, metrics, items
        case weightKg = "weight_kg"
        case durationSeconds = "duration_s"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        done = try container.decodeFlexibleBoolIfPresent(forKey: .done)
        weight = try container.decodeFlexibleStringIfPresent(forKey: .weight)
        weightKg = try container.decodeFlexibleDoubleIfPresent(forKey: .weightKg)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        reps = try container.decodeFlexibleStringIfPresent(forKey: .reps)
        time = try container.decodeFlexibleStringIfPresent(forKey: .time)
        durationSeconds = try container.decodeFlexibleDoubleIfPresent(forKey: .durationSeconds)
        selfWeight = try container.decodeFlexibleBoolIfPresent(forKey: .selfWeight)
        rpe = try container.decodeFlexibleDoubleIfPresent(forKey: .rpe)
        rir = try container.decodeFlexibleDoubleIfPresent(forKey: .rir)
        note = try container.decodeIfPresent(String.self, forKey: .note)
        metrics = try container.decodeIfPresent(XunjiSetMetrics.self, forKey: .metrics)
        items = try container.decodeIfPresent([XunjiSetItem].self, forKey: .items) ?? []
    }

    func strengthSet(doneFallback: Bool?, completedAtFallback: Date? = nil) -> StrengthSetLog {
        let completed = done ?? doneFallback ?? true
        return StrengthSetLog(
            repetitions: reps.flatMap { Int(Double($0) ?? 0) }.flatMap { $0 > 0 ? $0 : nil } ?? 1,
            weightKilograms: resolvedWeightKilograms,
            isWarmup: false,
            rpe: rpe,
            rir: rir,
            isCompleted: completed,
            completedAt: completed ? (completedAtFallback ?? Date()) : nil
        )
    }

    private var resolvedWeightKilograms: Double {
        if let weightKg { return weightKg }
        let numeric = weight.flatMap(Double.init) ?? 0
        guard unit?.lowercased() == "lb" || unit?.lowercased() == "lbs" else { return numeric }
        return numeric * 0.45359237
    }
}

private struct XunjiSetItem: Codable {
    var name: String?
    var set: XunjiSet

    enum CodingKeys: String, CodingKey {
        case name, set
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeFlexibleStringIfPresent(forKey: .name)
        set = try container.decode(XunjiSet.self, forKey: .set)
    }
}

private struct XunjiSetMetrics: Codable {
    // T8 修复：distance/kcal/calories/workoutTime/maxHeartRate 解析后全仓无消费者
    //（WorkoutEventRecord 无对应字段，零 schema 变更政策下也无法透传），
    // 保留唯一被消费的 avgHeartRate，其余停止解析。
    var avgHeartRate: Double?

    enum CodingKeys: String, CodingKey {
        case avgHeartRate
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        avgHeartRate = try container.decodeFlexibleDoubleIfPresent(forKey: .avgHeartRate)
    }
}

private extension KeyedDecodingContainer {
    func decodeFlexibleIntIfPresent(forKey key: Key) throws -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }

    func decodeFlexibleInt64IfPresent(forKey key: Key) throws -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Int64(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int64(value) }
        return nil
    }

    func decodeFlexibleDoubleIfPresent(forKey key: Key) throws -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return Double(value) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Double(value) }
        return nil
    }

    func decodeFlexibleStringIfPresent(forKey key: Key) throws -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return String(value) }
        return nil
    }

    func decodeFlexibleBoolIfPresent(forKey key: Key) throws -> Bool? {
        if let value = try? decodeIfPresent(Bool.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value != 0 }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            let lowered = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            return lowered == "true" || lowered == "1" || lowered == "yes"
        }
        return nil
    }
}

enum TrainingScheduleResolver: Sendable {
    static func resolve(
        plan: TrainingPlanDTO,
        on date: Date,
        events: [WorkoutEventDTO],
        calendar: Calendar = .current
    ) -> TrainingDay? {
        let selectedDay = calendar.startOfDay(for: date)
        let planStart = calendar.startOfDay(for: plan.startDate)
        guard selectedDay >= planStart else { return nil }

        let selectedDayEnd = calendar.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        let completedDayIDs = Set(
            events
                .filter { $0.startedAt < selectedDayEnd }
                .compactMap(\.linkedTrainingPlanDayId)
        )
        let executableDays = plan.days.filter {
            !$0.isCompleted && !completedDayIDs.contains($0.id)
        }
        guard !executableDays.isEmpty else { return nil }

        let scheduled = executableDays.compactMap { day -> (day: TrainingDay, date: Date)? in
            guard let scheduledDate = scheduledDate(
                for: day,
                planStart: planStart,
                calendar: calendar
            ) else {
                return nil
            }
            return (day, scheduledDate)
        }
        .sorted {
            if $0.date == $1.date {
                return $0.day.id.uuidString < $1.day.id.uuidString
            }
            return $0.date < $1.date
        }

        if let exact = scheduled.first(where: {
            calendar.isDate($0.date, inSameDayAs: selectedDay)
        }) {
            return exact.day
        }
        if let earliestOverdue = scheduled.first(where: { $0.date < selectedDay && $0.date >= planStart }) {
            return earliestOverdue.day
        }
        return scheduled.first(where: { $0.date > selectedDay })?.day
    }

    static func scheduledDate(
        for day: TrainingDay,
        planStart: Date,
        calendar: Calendar = .current
    ) -> Date? {
        let start = calendar.startOfDay(for: planStart)
        let weekday = calendar.component(.weekday, from: start)
        let daysSinceMonday = (weekday + 5) % 7
        guard let weekOneMonday = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: start
        ) else {
            return nil
        }
        let offset = max(0, day.weekNumber - 1) * 7 + max(0, min(6, day.dayNumber - 1))
        return calendar.date(byAdding: .day, value: offset, to: weekOneMonday)
    }
}

struct TrainingPlanReview: Equatable, Sendable {
    var scheduledSessions: Int
    var completedSessions: Int
    var completionRate: Double
    var averageAdherence: Double?
    var measuredResponses: Int
    var averageRecoveryDelta: Double?
    var statusTitle: String
    var recommendation: String
}

enum TrainingPlanReviewService {
    static func review(
        plan: TrainingPlanDTO,
        events: [WorkoutEventDTO],
        responses: [TrainingResponseDTO],
        through date: Date = Date(),
        calendar: Calendar = .current
    ) -> TrainingPlanReview {
        let endOfDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) ?? date
        let completedEventDayIDs = Set(
            events
                .filter { $0.startedAt < endOfDay }
                .compactMap(\.linkedTrainingPlanDayId)
        )
        let planStartDay = calendar.startOfDay(for: plan.startDate)
        let scheduled = plan.days.filter { day in
            guard day.focus != "rest",
                  let scheduledDate = TrainingScheduleResolver.scheduledDate(
                    for: day,
                    planStart: plan.startDate,
                    calendar: calendar
                  ) else { return false }
            // 排除计划开始日之前的「幽灵日」（周中建计划时起始周早于计划日的排期）。
            return scheduledDate >= planStartDay && scheduledDate < endOfDay
        }
        let completed = scheduled.filter {
            $0.isCompleted || completedEventDayIDs.contains($0.id)
        }
        let adherenceValues = completed.compactMap(\.adherenceScore)
        // 力量训练响应存的是 StrengthWorkoutRecord.id，而 plan day 关联的是事件 ID：
        // 两种 ID 空间合并，否则力量驱动的响应永远匹配不上。
        let completedDayIDs = Set(completed.map(\.id))
        let linkedWorkoutIDs = Set(
            completed.flatMap(\.linkedWorkoutEventIds)
            + events
                .filter { $0.linkedTrainingPlanDayId.map(completedDayIDs.contains) ?? false }
                .compactMap(\.linkedStrengthWorkoutId)
        )
        let measured = responses.filter { linkedWorkoutIDs.contains($0.workoutId) }
        let recoveryDeltas = measured.compactMap(\.nextDayRecoveryDelta)

        let completionRate = scheduled.isEmpty
            ? 0
            : Double(completed.count) / Double(scheduled.count)
        let averageAdherence = adherenceValues.isEmpty
            ? nil
            : adherenceValues.reduce(0, +) / Double(adherenceValues.count)
        let averageRecoveryDelta = recoveryDeltas.isEmpty
            ? nil
            : recoveryDeltas.reduce(0, +) / Double(recoveryDeltas.count)

        let statusTitle: String
        let recommendation: String
        if scheduled.count < 3 {
            statusTitle = "正在建立计划基线"
            recommendation = "至少完成 3 节计划训练并记录 RPE 后，Vela 才会给出周期调整判断。"
        } else if measured.count >= 3, (averageRecoveryDelta ?? 0) <= -8 {
            statusTitle = "近期恢复成本偏高"
            recommendation = "下周总容量建议降低 10–20%，优先保留动作质量，并观察连续 3 次训练后的恢复变化。"
        } else if completionRate < 0.60 {
            statusTitle = "计划与实际节奏不匹配"
            recommendation = "减少每周训练频次或缩短单次时长；比补做逾期训练更重要的是恢复可持续节奏。"
        } else if completionRate >= 0.85, (averageAdherence ?? 0.8) >= 0.80 {
            statusTitle = "计划节奏稳定"
            recommendation = "继续当前安排；只有在恢复稳定且主观用力未持续升高时，才小幅增加容量。"
        } else {
            statusTitle = "计划执行基本稳定"
            recommendation = "继续记录实际训练和次日状态，积累足够响应数据后再判断是否进阶。"
        }

        return TrainingPlanReview(
            scheduledSessions: scheduled.count,
            completedSessions: completed.count,
            completionRate: completionRate,
            averageAdherence: averageAdherence,
            measuredResponses: measured.count,
            averageRecoveryDelta: averageRecoveryDelta,
            statusTitle: statusTitle,
            recommendation: recommendation
        )
    }
}

struct TrainingSessionDraft: Equatable, Identifiable {
    var id: UUID { planDayId }

    enum Action: String, Equatable {
        case strength
        case cardio
        case flexibility
        case rest
        case unsupported
    }

    var action: Action
    var title: String
    var startedAt: Date
    var durationMinutes: Int
    var notes: String
    var exercises: [StrengthExerciseLog]
    var planDayId: UUID
}

struct TrainingSessionDraftBuilder {
    func build(
        day: TrainingDay,
        decision: DailyTrainingDecision,
        history: [StrengthWorkoutRecord],
        scheduledAt: Date
    ) -> TrainingSessionDraft {
        let action = action(for: day.focus)
        let exercises = action == .strength
            ? strengthExercises(day: day, decision: decision, history: history)
            : []
        let notes = [
            day.description,
            decision.userFacingSummary,
            decision.reasons.joined(separator: " ")
        ]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        .joined(separator: "\n")

        return TrainingSessionDraft(
            action: action,
            title: day.title,
            startedAt: scheduledAt,
            durationMinutes: day.durationMinutes,
            notes: notes,
            exercises: exercises,
            planDayId: day.id
        )
    }

    private func action(for focus: String) -> TrainingSessionDraft.Action {
        switch focus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "strength":
            return .strength
        case "cardio":
            return .cardio
        case "flexibility", "mobility":
            return .flexibility
        case "rest", "recovery":
            return .rest
        default:
            return .unsupported
        }
    }

    /// T5：按历史组反推 e1RM（Epley），再按目标次数正推同 RPE 强度重量。
    /// 单次增幅封顶 +2.5%（保守渐进），返回 nil 表示无法处方（无历史组）。
    private func prescribedWeight(forReps reps: Int, previous: StrengthSetLog?) -> Double? {
        guard let previous else { return nil }
        let previousE1RM = previous.weightKilograms * (1.0 + Double(previous.repetitions) / 30.0)
        let target = previousE1RM / (1.0 + Double(reps) / 30.0)
        return min(target, previous.weightKilograms * 1.025)
    }

    private func strengthExercises(
        day: TrainingDay,
        decision: DailyTrainingDecision,
        history: [StrengthWorkoutRecord]
    ) -> [StrengthExerciseLog] {
        guard let data = day.plannedExercisesJSON.data(using: .utf8),
              let planned = try? JSONDecoder().decode([WorkoutTemplateExercise].self, from: data) else {
            return []
        }
        let library = ExerciseLibraryService.defaultDefinitions()

        return planned.map { item in
            let previousSets = StrengthWorkoutSessionPrefill.previousCompletedSets(
                for: item.name,
                in: history
            )
            let definition = library.first {
                if let key = item.exerciseCanonicalKey {
                    return $0.canonicalKey == key
                }
                return $0.name.caseInsensitiveCompare(item.name) == .orderedSame
            }
            let targetSetCount = max(
                1,
                Int((Double(item.targetSets) * decision.volumeMultiplier).rounded(.down))
            )
            let targetReps = StrengthWorkoutTemplateParser.reps(from: item.targetReps)
            let targetRPE = min(
                item.targetRPE ?? Double(decision.intensityCap),
                Double(decision.intensityCap)
            )
            let fallbackWeight = ExerciseLoadDefaults.initialWeight(
                equipment: definition?.equipment ?? "other",
                exerciseName: item.name,
                previousSets: previousSets
            )
            let sets = (0..<targetSetCount).map { index in
                let previous = index < previousSets.count ? previousSets[index] : nil
                // T5：负荷处方优先参考 e1RM 渐进——按目标次数反推与历史同 RPE 的重量
                //（Epley 反解），单次增幅封顶 +2.5% 保守渐进；替代直接复制上一组重量。
                let prescribed = prescribedWeight(forReps: targetReps, previous: previous)
                    ?? previous?.weightKilograms
                    ?? fallbackWeight
                return StrengthSetLog(
                    repetitions: targetReps,
                    weightKilograms: prescribed,
                    isWarmup: false,
                    rpe: targetRPE,
                    rir: nil,
                    isCompleted: false,
                    completedAt: nil
                )
            }

            return StrengthExerciseLog(
                exerciseDefinitionId: item.exerciseDefinitionId ?? definition?.id,
                exerciseCanonicalKey: item.exerciseCanonicalKey ?? definition?.canonicalKey,
                name: item.name,
                equipment: definition?.equipment ?? "other",
                primaryMuscleGroup: definition?.primaryMuscleGroup,
                sets: sets
            )
        }
    }
}

enum ExerciseLoadDefaults {
    static func initialWeight(
        equipment: String,
        exerciseName: String,
        previousSets: [StrengthSetLog]
    ) -> Double {
        if let previous = previousSets.first {
            return previous.weightKilograms
        }
        let normalizedEquipment = equipment.lowercased()
        let normalizedName = exerciseName.lowercased()
        if normalizedEquipment.contains("bodyweight")
            || normalizedEquipment.contains("assisted")
            || normalizedName.contains("pull up")
            || normalizedName.contains("pull-up")
            || normalizedName.contains("push up")
            || normalizedName.contains("push-up")
            || normalizedName.contains("dip") {
            return 0
        }
        return 0
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

private extension Array where Element == Double {
    var average: Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}

// MARK: - AI 未来训练规划（Coach 参与决策）

/// LLM 返回的规划条目（解析层）。
struct AIPlanDay: Codable {
    let day: Int
    let groups: [String]
    let note: String?
}

enum TrainingPlanAdvisorError: Error {
    case unparseable
}

/// Coach 参与未来训练决策：本地推荐器先给出即时建议，本服务让 LLM
/// 结合疲劳/恢复/历史复核并给出未来三天规划。只提议、不落盘（ADR 0008）。
enum TrainingPlanAdvisor {
    static let allowedGroups = ["chest", "back", "shoulders", "legs", "biceps", "triceps", "core", "other"]

    /// 解析 LLM 返回（容忍 markdown 代码块包裹与前后多余文字）。
    static func parsePlan(from content: String) -> [RotationDayRecommendation] {
        guard let start = content.firstIndex(of: "["),
              let end = content.lastIndex(of: "]"),
              start < end else { return [] }
        let jsonText = String(content[start...end])
        guard let data = jsonText.data(using: .utf8),
              let days = try? JSONDecoder().decode([AIPlanDay].self, from: data) else { return [] }
        return days.compactMap { day in
            guard (1...7).contains(day.day) else { return nil }
            let groups = day.groups.filter { allowedGroups.contains($0.lowercased()) }
            return RotationDayRecommendation(
                dayOffset: day.day,
                groups: Array(groups.prefix(2)),
                note: day.note ?? "",
                source: "ai"
            )
        }
    }

    static func suggestNextDays(
        contextText: String,
        apiKey: String?,
        language: AppLanguage = .stored
    ) async throws -> [RotationDayRecommendation] {
        guard let apiKey, !apiKey.isEmpty else {
            throw LLMProviderError.missingAPIKey
        }
        let provider = RetryingLLMProvider(base: DeepSeekProvider(apiKey: apiKey))
        let system = language.isChinese ? zhSystemPrompt : enSystemPrompt
        // 深度专项批次 2：20s 总 deadline（此前无超时，最坏挂起数分钟）。
        let response = try await LLMProviderDeadline.withTimeout(seconds: 20) {
            try await provider.complete(request: LLMRequest(
                systemPrompt: system,
                userPrompt: contextText,
                contextJSON: ""
            ))
        }
        let parsed = parsePlan(from: response.content)
        guard !parsed.isEmpty else {
            throw TrainingPlanAdvisorError.unparseable
        }
        return parsed
    }

    private static let zhSystemPrompt = """
    你是 Vela 的训练规划助手。基于用户提供的真实数据（生理档案、各肌群疲劳组数、恢复/睡眠/压力/负荷评分、三年基线、最近训练历史、本地轮转建议），为未来两天（明天 day=1、后天 day=2）每天推荐一个训练部位或休息。规则：高疲劳（48h≥\(LocalMuscleFatigue.highFatigue48hSets) 组或 7 天≥\(LocalMuscleFatigue.highFatigue7dSets) 组）的肌群必须避开；相邻两天不重复同一部位；恢复评分偏低时明天安排休息或轻活动；优先力量部位，休息日 groups 为空数组；note 用一句话给出依据（引用具体组数与恢复分数）。只输出一个 JSON 数组，不要任何其他文字。格式：[{"day":1,"groups":["legs"],"note":"依据：48h 0 组 · 7 天 3 组"}]
    """

    private static let enSystemPrompt = """
    You are Vela's training planner. Based on real data provided (muscle-group fatigue sets, recovery/sleep/strain scores, recent training history, local rotation suggestion), recommend one muscle group or rest for each of the next two days (tomorrow day=1, the day after day=2). Rules: avoid high-fatigue groups (48h>=\(LocalMuscleFatigue.highFatigue48hSets) or 7d>=\(LocalMuscleFatigue.highFatigue7dSets) sets); never repeat the same group on consecutive days; if recovery is low, day 1 is rest or light activity; rest days use an empty groups array; note explains the reasoning with concrete numbers. Output only a JSON array, nothing else. Format: [{"day":1,"groups":["legs"],"note":"Based on: 48h 0 sets, 7d 3 sets"}]
    """
}

// MARK: - Muscle daily set aggregation

extension TrainingAnalyticsService {
    /// 每个肌群最近 `days` 天（含 `endingAt` 当天）的逐日有效组数。
    /// 返回字典：肌群键 → 长度为 `days` 的数组，index 0 = 最旧一天。
    /// 纯函数、可测试；训练页「局部训练状态」的 7 天迷你条同源。
    static func dailySetsByMuscle(
        workouts: [StrengthWorkoutDTO],
        days: Int = 7,
        endingAt: Date,
        calendar: Calendar = .current
    ) -> [String: [Int]] {
        let endDay = calendar.startOfDay(for: endingAt)
        guard days > 0 else { return [:] }

        var buckets: [Date: [String: Int]] = [:]
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else { continue }
            buckets[day] = [:]
        }

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startedAt)
            guard buckets[day] != nil else { continue }
            let analysis = TrainingAnalyticsService().summarizeWorkout(workout)
            var dayBucket = buckets[day] ?? [:]
            for (muscle, sets) in analysis.muscleGroupSets {
                dayBucket[muscle, default: 0] += sets
            }
            buckets[day] = dayBucket
        }

        var result: [String: [Int]] = [:]
        for offset in stride(from: days - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: endDay) else { continue }
            for (muscle, sets) in buckets[day] ?? [:] {
                var series = result[muscle] ?? Array(repeating: 0, count: days)
                series[days - 1 - offset] = sets
                result[muscle] = series
            }
        }
        return result
    }
}

// MARK: - 深度专项批次 3：训记历史批量回填

/// 逐日拉取训记训练并导入（默认近 90 天，游标存 UserDefaults 可断点续传）。
/// 三年 e1RM/容量/肌群频率轨迹的前置条件：训记组次数据目前只有最近 3 天自动导入。
@MainActor
final class XunjiHistoryBackfillService: ObservableObject {
    static let shared = XunjiHistoryBackfillService()

    private static let cursorKey = "vela.xunji.backfill.next_offset"
    private static let totalDaysKey = "vela.xunji.backfill.total_days"

    @Published private(set) var isRunning = false
    @Published private(set) var completedDays = 0
    @Published private(set) var importedCount = 0
    @Published private(set) var errorMessage: String?
    @Published var totalDays: Int {
        didSet { UserDefaults.standard.set(totalDays, forKey: Self.totalDaysKey) }
    }
    private var isCancelled = false

    private init() {
        let stored = UserDefaults.standard.integer(forKey: Self.totalDaysKey)
        totalDays = stored > 0 ? stored : 90
        completedDays = UserDefaults.standard.integer(forKey: Self.cursorKey)
    }

    static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func cancel() {
        isCancelled = true
        isRunning = false
    }

    /// 从游标处继续：逐日导入，单日失败不中断；连续 5 天失败暂停并报错。
    func run(
        modelContext: ModelContext,
        apiKey: String,
        calendar: Calendar = .current
    ) async {
        guard !isRunning else { return }
        isRunning = true
        isCancelled = false
        errorMessage = nil
        defer { isRunning = false }

        let start = UserDefaults.standard.integer(forKey: Self.cursorKey)
        var consecutiveFailures = 0
        for offset in start..<totalDays {
            guard !isCancelled else { break }
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { break }
            let datestr = Self.dateString(date)
            do {
                let data = try await XunjiTrainingAPIClient().fetchTraining(
                    apiKey: apiKey,
                    datestr: datestr,
                    includeFullData: true
                )
                let summary = try XunjiTrainingImportService().importResponseData(
                    data,
                    datestr: datestr,
                    modelContext: modelContext
                )
                importedCount += summary.importedCount
                consecutiveFailures = 0
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures >= 5 {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    UserDefaults.standard.set(offset, forKey: Self.cursorKey)
                    return
                }
            }
            completedDays = offset + 1
            UserDefaults.standard.set(offset + 1, forKey: Self.cursorKey)
        }
        if completedDays >= totalDays {
            UserDefaults.standard.removeObject(forKey: Self.cursorKey)
        }
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: Self.cursorKey)
        completedDays = 0
        importedCount = 0
        errorMessage = nil
        isCancelled = false
    }
}
