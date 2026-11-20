import BodySeekCore
import BodySeekHealth
import ComposableArchitecture
import Foundation

public enum BodySideOption: String, CaseIterable, Equatable, Hashable, Sendable {
    case front
    case back

    public var title: String {
        switch self {
        case .front: "正面肌群"
        case .back: "背面肌群"
        }
    }
}

public struct WorkoutReviewDraft: Equatable, Sendable {
    public let workout: StoredWorkoutRecord
    public var inputText: String
    public var proposal: WorkoutAnnotationProposal?
    public var primaryMuscles: [BodyRegionMuscle]
    public var secondaryMuscles: [BodyRegionMuscle]
    public var rpe: Int
    public var exercises: [String]
    public var bodySignals: [WorkoutBodySignal]
    public var isParsing: Bool = false
    public var isSaving: Bool = false

    public init(
        workout: StoredWorkoutRecord,
        inputText: String = "",
        proposal: WorkoutAnnotationProposal? = nil,
        primaryMuscles: [BodyRegionMuscle] = [.chest],
        secondaryMuscles: [BodyRegionMuscle] = [],
        rpe: Int = 7,
        exercises: [String] = [],
        bodySignals: [WorkoutBodySignal] = [],
        isParsing: Bool = false,
        isSaving: Bool = false
    ) {
        self.workout = workout
        self.inputText = inputText
        self.proposal = proposal
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.rpe = min(10, max(1, rpe))
        self.exercises = exercises
        self.bodySignals = bodySignals
        self.isParsing = isParsing
        self.isSaving = isSaving
    }
}

@Reducer
public struct WorkoutFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var snapshot: BodySeekDashboardSnapshot
        public var templates: [WorkoutTemplate] = []
        public var sessions: [LoggedWorkoutSession] = []
        public var dominantHand: DominantHand = .right
        public var sleepGoalMinutes: Int = 450
        public var storedWorkouts: [StoredWorkoutRecord] = []
        public var annotationsByWorkoutUUID: [String: WorkoutAnnotationRecord] = [:]
        public var muscleLoads: [WorkoutMuscleLoadRecord] = []
        public var recoverySnapshot: MuscleRecoverySnapshot = .empty
        public var reviewDraft: WorkoutReviewDraft?
        public var inspectedMuscleForRecovery: BodyRegionMuscle?
        public var inspectedWorkoutDetail: StoredWorkoutRecord?
        public var selectedBodySide: BodySideOption = .front
        public var selectedMuscle: BodyRegionMuscle?
        public var pendingProposal: WorkoutProposal?
        public var activeWorkout: ActiveWorkoutDraft?
        public var isExercisePickerPresented: Bool = false
        public var isSavingWorkout: Bool = false
        public var statusMessage: String?
        public var lastError: String?

        public init(
            snapshot: BodySeekDashboardSnapshot,
            templates: [WorkoutTemplate] = ExerciseCatalog.defaultTemplates,
            sessions: [LoggedWorkoutSession] = [],
            dominantHand: DominantHand = .right,
            sleepGoalMinutes: Int = 450
        ) {
            self.snapshot = snapshot
            self.templates = templates
            self.sessions = sessions
            self.dominantHand = dominantHand
            self.sleepGoalMinutes = sleepGoalMinutes
            self.storedWorkouts = Self.storedRecords(from: snapshot.historyDays)
            self.recoverySnapshot = MuscleRecoveryEngine.compute(
                asOf: snapshot.referenceDate,
                storedWorkouts: self.storedWorkouts,
                muscleLoads: [],
                manualSessions: sessions,
                historyDays: snapshot.historyDays,
                sleepGoalMinutes: sleepGoalMinutes,
                dominantHand: dominantHand
            )
        }

        public static func storedRecords(from historyDays: [DailyComputedDay]) -> [StoredWorkoutRecord] {
            var seen = Set<String>()
            var out: [StoredWorkoutRecord] = []
            for day in historyDays.suffix(30) {
                for w in day.raw.workouts {
                    let uuid = (w.healthKitUUID ?? w.id).uuidString
                    guard seen.insert(uuid).inserted else { continue }
                    let end = w.startDate.addingTimeInterval(Double(max(1, w.durationMinutes)) * 60.0)
                    out.append(
                        StoredWorkoutRecord(
                            hkUUID: uuid,
                            type: w.activityName,
                            start: w.startDate,
                            end: end,
                            energy: w.activeEnergyKcal,
                            avgHR: w.averageHeartRate,
                            zones: w.heartRateZones,
                            effortUser: w.effortScore,
                            effortEstimated: w.estimatedEffortScore,
                            reviewState: .unreviewed
                        )
                    )
                }
            }
            return out.sorted { $0.start > $1.start }
        }

        public mutating func recomputeRecoverySnapshot() {
            recoverySnapshot = MuscleRecoveryEngine.compute(
                asOf: snapshot.referenceDate,
                storedWorkouts: storedWorkouts,
                muscleLoads: muscleLoads,
                manualSessions: sessions,
                historyDays: snapshot.historyDays,
                sleepGoalMinutes: sleepGoalMinutes,
                dominantHand: dominantHand
            )
        }

        public var unreviewedWorkouts: [StoredWorkoutRecord] {
            let cutoff = snapshot.referenceDate.addingTimeInterval(-14 * 86_400)
            return storedWorkouts
                .filter { w in
                    w.end >= cutoff
                        && w.reviewState == .unreviewed
                        && WorkoutAutoAttributor.isStrengthWorkout(type: w.type)
                }
                .sorted { $0.start > $1.start }
        }

        public var archiveWorkouts: [StoredWorkoutRecord] {
            let cutoff = snapshot.referenceDate.addingTimeInterval(-30 * 86_400)
            return storedWorkouts
                .filter { $0.end >= cutoff }
                .sorted { $0.start > $1.start }
        }

        public var muscleLoadLast72h: [BodyRegionMuscle: Double] {
            recoverySnapshot.heatmapFatigueIntensities
        }

        public var loadedMusclesRanked: [(muscle: BodyRegionMuscle, load: Double)] {
            recoverySnapshot.rankedByFatigue
                .map { ($0.muscle, $0.fatigueIntensityForHeatmap) }
        }

        public var filteredExercises: [ExerciseDefinition] {
            guard let selectedMuscle else { return ExerciseCatalog.all }
            return ExerciseCatalog.exercises(for: selectedMuscle)
        }

        public var recentHealthWorkouts: [WorkoutSummary] {
            snapshot.historyDays
                .suffix(14)
                .flatMap(\.raw.workouts)
                .sorted { $0.startDate > $1.startDate }
        }

        public var weeklyVolumeKg: Double {
            let cutoff = snapshot.referenceDate.addingTimeInterval(-7 * 86_400)
            return sessions
                .filter { $0.completedAt >= cutoff }
                .reduce(0) { $0 + $1.totalVolumeKg }
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case syncWatchWorkouts
        case watchWorkoutsLoaded(
            workouts: [StoredWorkoutRecord],
            annotations: [WorkoutAnnotationRecord],
            loads: [WorkoutMuscleLoadRecord]
        )
        case watchSyncFailed(String)
        case openReviewTapped(StoredWorkoutRecord)
        case dismissReviewSheet
        case reviewTextChanged(String)
        case parseReviewTapped
        case reviewParsed(WorkoutAnnotationProposal)
        case toggleMuscleInDraft(BodyRegionMuscle)
        case addMuscleToDraft(BodyRegionMuscle, asPrimary: Bool)
        case removeMuscleFromDraft(BodyRegionMuscle)
        case reviewRPEChanged(Int)
        case toggleBodySignalMemory(UUID)
        case confirmReviewTapped
        case reviewPersisted(
            workouts: [StoredWorkoutRecord],
            annotations: [WorkoutAnnotationRecord],
            loads: [WorkoutMuscleLoadRecord],
            committedMemories: [AthleteMemoryItem]
        )
        case reviewPersistFailed(String)
        case skipReviewTapped(StoredWorkoutRecord)
        case inspectMuscleRecovery(BodyRegionMuscle?)
        case inspectWorkoutDetail(StoredWorkoutRecord?)
        case bodySideChanged(BodySideOption)
        case muscleSelected(BodyRegionMuscle?)
        case startTemplateTapped(WorkoutTemplate)
        case startMuscleTargetedWorkoutTapped(BodyRegionMuscle)
        case startQuickEmptyTapped
        case acceptProposalTapped(WorkoutProposal, startImmediately: Bool)
        case dismissProposalTapped
        case activeWorkoutTitleChanged(String)
        case activeWorkoutWeightChanged(exerciseIndex: Int, setIndex: Int, weightKg: Double)
        case activeWorkoutRepsChanged(exerciseIndex: Int, setIndex: Int, reps: Int)
        case activeWorkoutToggleSetCompleted(exerciseIndex: Int, setIndex: Int)
        case activeWorkoutAddSetTapped(exerciseIndex: Int)
        case activeWorkoutAddExercisePresented(Bool)
        case activeWorkoutAddExerciseTapped(ExerciseDefinition)
        case activeWorkoutRPEChanged(Int)
        case restTimerTick
        case adjustRestTimerTapped(Int)
        case skipRestTimerTapped
        case discardActiveWorkoutTapped
        case completeActiveWorkoutTapped
        case workoutPersisted(LoggedWorkoutSession, hkWarning: String?)
        case workoutPersistFailed(String)
        case templatePersistFailed(String)
        case askCoachForMuscleTapped(BodyRegionMuscle?)
        case openTrendsTapped
        case clearStatusBanner
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case sessionSaved(LoggedWorkoutSession)
            case templateSaved(WorkoutTemplate)
            case memoryCommitted(AthleteMemoryItem)
            case askCoach(String)
            case openTrends
        }
    }

    private enum CancelID {
        case restTimer
    }

    @Dependency(\.bodySeekStoreClient) var bodySeekStoreClient
    @Dependency(\.workoutReviewParserClient) var workoutReviewParserClient
    @Dependency(\.fitnessStoreClient) var fitnessStoreClient
    @Dependency(\.healthKitClient) var healthKitClient
    @Dependency(\.restTimerClient) var restTimerClient
    @Dependency(\.continuousClock) var clock
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear, .syncWatchWorkouts:
                return syncWatchWorkoutsEffect(
                    historyDays: state.snapshot.historyDays,
                    asOf: state.snapshot.referenceDate,
                    dominantHand: state.dominantHand
                )

            case let .watchWorkoutsLoaded(workouts, annotations, loads):
                if !workouts.isEmpty {
                    state.storedWorkouts = workouts
                }
                var map: [String: WorkoutAnnotationRecord] = [:]
                for ann in annotations where map[ann.workoutUUID] == nil {
                    map[ann.workoutUUID] = ann
                }
                state.annotationsByWorkoutUUID = map
                state.muscleLoads = loads
                state.recomputeRecoverySnapshot()
                return .none

            case let .watchSyncFailed(reason):
                state.lastError = reason
                return .none

            case let .openReviewTapped(workout):
                let existingText = state.annotationsByWorkoutUUID[workout.hkUUID]?.rawText ?? ""
                let existingLoads = state.muscleLoads.filter { $0.workoutUUID == workout.hkUUID }
                let existingPrimary = existingLoads.filter { $0.role == .primary }.map(\.muscle)
                let existingSecondary = existingLoads.filter { $0.role != .primary }.map(\.muscle)
                let defaultRPE = Int((workout.effortUser ?? workout.effortEstimated ?? 7).rounded())
                state.reviewDraft = WorkoutReviewDraft(
                    workout: workout,
                    inputText: existingText,
                    proposal: nil,
                    primaryMuscles: existingPrimary.isEmpty ? [.chest] : existingPrimary,
                    secondaryMuscles: existingSecondary,
                    rpe: min(10, max(1, defaultRPE)),
                    exercises: [],
                    bodySignals: []
                )
                return .none

            case .dismissReviewSheet:
                state.reviewDraft = nil
                return .none

            case let .reviewTextChanged(text):
                state.reviewDraft?.inputText = text
                return .none

            case .parseReviewTapped:
                guard var draft = state.reviewDraft else { return .none }
                let text = draft.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else {
                    state.lastError = "请先输入或口述一句训练内容再解析"
                    return .none
                }
                draft.isParsing = true
                state.reviewDraft = draft
                state.lastError = nil
                return .run { send in
                    let proposal = await workoutReviewParserClient.parse(text)
                    await send(.reviewParsed(proposal))
                }

            case let .reviewParsed(proposal):
                guard var draft = state.reviewDraft else { return .none }
                draft.isParsing = false
                draft.proposal = proposal
                if !proposal.primaryMuscles.isEmpty {
                    draft.primaryMuscles = proposal.primaryMuscles
                }
                draft.secondaryMuscles = proposal.secondaryMuscles
                if let parsedRPE = proposal.rpe {
                    draft.rpe = min(10, max(1, parsedRPE))
                }
                draft.exercises = proposal.exercises
                draft.bodySignals = proposal.bodySignals
                state.reviewDraft = draft
                return .none

            case let .toggleMuscleInDraft(muscle):
                guard var draft = state.reviewDraft else { return .none }
                if draft.primaryMuscles.contains(muscle) {
                    draft.primaryMuscles.removeAll { $0 == muscle }
                    if !draft.secondaryMuscles.contains(muscle) {
                        draft.secondaryMuscles.append(muscle)
                    }
                } else if draft.secondaryMuscles.contains(muscle) {
                    draft.secondaryMuscles.removeAll { $0 == muscle }
                    draft.primaryMuscles.append(muscle)
                } else {
                    draft.primaryMuscles.append(muscle)
                }
                state.reviewDraft = draft
                return .none

            case let .addMuscleToDraft(muscle, asPrimary):
                guard var draft = state.reviewDraft else { return .none }
                draft.primaryMuscles.removeAll { $0 == muscle }
                draft.secondaryMuscles.removeAll { $0 == muscle }
                if asPrimary {
                    draft.primaryMuscles.append(muscle)
                } else {
                    draft.secondaryMuscles.append(muscle)
                }
                state.reviewDraft = draft
                return .none

            case let .removeMuscleFromDraft(muscle):
                guard var draft = state.reviewDraft else { return .none }
                draft.primaryMuscles.removeAll { $0 == muscle }
                draft.secondaryMuscles.removeAll { $0 == muscle }
                state.reviewDraft = draft
                return .none

            case let .reviewRPEChanged(rpe):
                state.reviewDraft?.rpe = min(10, max(1, rpe))
                return .none

            case let .toggleBodySignalMemory(signalID):
                guard var draft = state.reviewDraft else { return .none }
                if let idx = draft.bodySignals.firstIndex(where: { $0.id == signalID }) {
                    draft.bodySignals[idx].includeAsMemory.toggle()
                    state.reviewDraft = draft
                }
                return .none

            case .confirmReviewTapped:
                guard var draft = state.reviewDraft, !draft.isSaving else { return .none }
                if draft.primaryMuscles.isEmpty && draft.secondaryMuscles.isEmpty {
                    state.lastError = "请至少保留一个主受刺激肌群后再确认"
                    return .none
                }
                draft.isSaving = true
                state.reviewDraft = draft
                state.lastError = nil

                let capturedDraft = draft
                let referenceNow = now
                let durationMin = max(10, Int((capturedDraft.workout.end.timeIntervalSince(capturedDraft.workout.start) / 60).rounded()))
                let loads = WorkoutLoadBuilder.buildMuscleLoads(
                    workoutUUID: capturedDraft.workout.hkUUID,
                    durationMinutes: durationMin,
                    primaryMuscles: capturedDraft.primaryMuscles,
                    secondaryMuscles: capturedDraft.secondaryMuscles,
                    rpe: capturedDraft.rpe
                )
                let rawTextToSave: String = {
                    let trimmed = capturedDraft.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                    let names = (capturedDraft.primaryMuscles + capturedDraft.secondaryMuscles).map(\.title).joined(separator: "、")
                    return "确认肌群：\(names)（RPE \(capturedDraft.rpe)）"
                }()

                return .run { send in
                    do {
                        try await bodySeekStoreClient.upsertStoredWorkouts(
                            [capturedDraft.workout],
                            [capturedDraft.workout.hkUUID: "dumbbell.fill"]
                        )
                        let annotatePayload = AnnotateWorkoutPayload(
                            workoutUUID: capturedDraft.workout.hkUUID,
                            rawText: rawTextToSave,
                            parserVersion: .workoutParserV1,
                            muscleLoads: loads,
                            reviewState: .annotated
                        )
                        let proposal = try ActionProposal(
                            kind: .annotateWorkout,
                            origin: .user,
                            encodablePayload: annotatePayload,
                            rationale: "用户确认 Watch 训练一句话复盘"
                        )
                        _ = try await bodySeekStoreClient.executeProposal(proposal)

                        var committedMemories: [AthleteMemoryItem] = []
                        for signal in capturedDraft.bodySignals where signal.includeAsMemory {
                            let expiry = referenceNow.addingTimeInterval(Double(signal.defaultExpiryDays) * 86_400)
                            let memRecord = TieredMemoryRecord(
                                tier: .activeConstraint,
                                content: signal.suggestedConstraint,
                                scopeJSON: #"{"source":"workout_review"}"#,
                                confidence: 0.90,
                                expiresAt: expiry,
                                confirmedAt: referenceNow
                            )
                            let memProposal = try ActionProposal(
                                kind: .commitMemory,
                                origin: .user,
                                encodablePayload: CommitMemoryPayload(memory: memRecord),
                                rationale: "练后身体不适信号自动转为 14 天活跃约束"
                            )
                            _ = try await bodySeekStoreClient.executeProposal(memProposal)
                            committedMemories.append(
                                AthleteMemoryItem(
                                    id: memRecord.id,
                                    category: .injury,
                                    content: signal.suggestedConstraint,
                                    updatedAt: referenceNow
                                )
                            )
                        }

                        let reloadedWorkouts = try await bodySeekStoreClient.loadStoredWorkouts(120)
                        let reloadedAnnotations = try await bodySeekStoreClient.loadWorkoutAnnotations(nil)
                        let reloadedLoads = try await bodySeekStoreClient.loadAllMuscleLoads(referenceNow.addingTimeInterval(-14 * 86_400))
                        await send(.reviewPersisted(
                            workouts: reloadedWorkouts,
                            annotations: reloadedAnnotations,
                            loads: reloadedLoads,
                            committedMemories: committedMemories
                        ))
                    } catch {
                        await send(.reviewPersistFailed(error.localizedDescription))
                    }
                }

            case let .reviewPersisted(workouts, annotations, loads, committedMemories):
                state.reviewDraft = nil
                if !workouts.isEmpty {
                    state.storedWorkouts = workouts
                }
                var map: [String: WorkoutAnnotationRecord] = [:]
                for ann in annotations where map[ann.workoutUUID] == nil {
                    map[ann.workoutUUID] = ann
                }
                state.annotationsByWorkoutUUID = map
                state.muscleLoads = loads
                state.recomputeRecoverySnapshot()
                if !committedMemories.isEmpty {
                    state.statusMessage = "已更新肌群恢复估计，并写入 \(committedMemories.count) 条 14 天身体约束记忆"
                    return .merge(
                        committedMemories.map { .send(.delegate(.memoryCommitted($0))) }
                    )
                } else {
                    state.statusMessage = "已确认训练复盘并更新肌群恢复（启发式估计）"
                    return .none
                }

            case let .reviewPersistFailed(reason):
                state.reviewDraft?.isSaving = false
                state.lastError = "保存训练复盘失败：\(reason)"
                return .none

            case let .skipReviewTapped(workout):
                let referenceNow = now
                return .run { send in
                    do {
                        try await bodySeekStoreClient.upsertStoredWorkouts(
                            [workout],
                            [workout.hkUUID: "dumbbell.fill"]
                        )
                        let skipPayload = AnnotateWorkoutPayload(
                            workoutUUID: workout.hkUUID,
                            rawText: "用户跳过本次复盘",
                            parserVersion: .workoutParserV1,
                            muscleLoads: [],
                            reviewState: .skipped
                        )
                        let proposal = try ActionProposal(
                            kind: .annotateWorkout,
                            origin: .user,
                            encodablePayload: skipPayload,
                            rationale: "用户跳过 Watch 力量训练复盘"
                        )
                        _ = try await bodySeekStoreClient.executeProposal(proposal)
                        let reloadedWorkouts = try await bodySeekStoreClient.loadStoredWorkouts(120)
                        let reloadedAnnotations = try await bodySeekStoreClient.loadWorkoutAnnotations(nil)
                        let reloadedLoads = try await bodySeekStoreClient.loadAllMuscleLoads(referenceNow.addingTimeInterval(-14 * 86_400))
                        await send(.watchWorkoutsLoaded(
                            workouts: reloadedWorkouts,
                            annotations: reloadedAnnotations,
                            loads: reloadedLoads
                        ))
                    } catch {
                        await send(.reviewPersistFailed(error.localizedDescription))
                    }
                }

            case let .inspectMuscleRecovery(muscle):
                state.inspectedMuscleForRecovery = muscle
                return .none

            case let .inspectWorkoutDetail(workout):
                state.inspectedWorkoutDetail = workout
                return .none
            case let .bodySideChanged(side):
                state.selectedBodySide = side
                return .none

            case let .muscleSelected(muscle):
                if state.selectedMuscle == muscle {
                    state.selectedMuscle = nil
                } else {
                    state.selectedMuscle = muscle
                }
                return .none

            case let .startTemplateTapped(template):
                state.lastError = nil
                state.statusMessage = nil
                state.activeWorkout = ActiveWorkoutDraft.from(template: template, now: now)
                return .none

            case let .startMuscleTargetedWorkoutTapped(muscle):
                let exercises = ExerciseCatalog.exercises(for: muscle).prefix(4)
                let items = exercises.map {
                    PlannedExerciseItem(
                        id: uuid(),
                        exerciseID: $0.id,
                        targetSets: 3,
                        targetReps: 10,
                        targetWeightKg: $0.equipment == "自重" ? 0 : 20,
                        restSeconds: 90
                    )
                }
                let template = WorkoutTemplate(
                    id: uuid(),
                    title: "\(muscle.title)专项训练",
                    subtitle: "按肌群热图筛选生成的即刻训练",
                    focusTag: muscle.title,
                    estimatedMinutes: max(20, items.count * 10),
                    exercises: items
                )
                state.activeWorkout = ActiveWorkoutDraft.from(template: template, now: now)
                return .none

            case .startQuickEmptyTapped:
                let starter = ExerciseCatalog.all.first!
                let defaultRecord = LoggedExerciseRecord(
                    id: uuid(),
                    exerciseID: starter.id,
                    sets: [
                        LoggedSetEntry(id: uuid(), setIndex: 1, weightKg: 40, reps: 8, isCompleted: false),
                    ],
                    restSeconds: 90
                )
                state.activeWorkout = ActiveWorkoutDraft(
                    id: uuid(),
                    title: "自由力量记录",
                    startedAt: now,
                    exercises: [defaultRecord]
                )
                return .none

            case let .acceptProposalTapped(proposal, startImmediately):
                state.lastError = nil
                if let idx = state.templates.firstIndex(where: { $0.id == proposal.template.id }) {
                    state.templates[idx] = proposal.template
                } else {
                    state.templates.insert(proposal.template, at: 0)
                }
                state.pendingProposal = nil
                if startImmediately {
                    state.activeWorkout = ActiveWorkoutDraft.from(template: proposal.template, now: now)
                } else {
                    state.statusMessage = "已将「\(proposal.template.title)」加入你的训练模板库"
                }
                let templateToSave = proposal.template
                return .run { send in
                    do {
                        try await fitnessStoreClient.saveTemplate(templateToSave)
                        await send(.delegate(.templateSaved(templateToSave)))
                    } catch {
                        await send(.templatePersistFailed(error.localizedDescription))
                    }
                }

            case .dismissProposalTapped:
                state.pendingProposal = nil
                return .none

            case let .activeWorkoutTitleChanged(title):
                state.activeWorkout?.title = title
                return .none

            case let .activeWorkoutWeightChanged(exIdx, setIdx, weightKg):
                guard var draft = state.activeWorkout,
                      draft.exercises.indices.contains(exIdx),
                      draft.exercises[exIdx].sets.indices.contains(setIdx) else { return .none }
                draft.exercises[exIdx].sets[setIdx].weightKg = max(0, min(500, weightKg))
                state.activeWorkout = draft
                return .none

            case let .activeWorkoutRepsChanged(exIdx, setIdx, reps):
                guard var draft = state.activeWorkout,
                      draft.exercises.indices.contains(exIdx),
                      draft.exercises[exIdx].sets.indices.contains(setIdx) else { return .none }
                draft.exercises[exIdx].sets[setIdx].reps = max(1, min(100, reps))
                state.activeWorkout = draft
                return .none

            case let .activeWorkoutToggleSetCompleted(exIdx, setIdx):
                guard var draft = state.activeWorkout,
                      draft.exercises.indices.contains(exIdx),
                      draft.exercises[exIdx].sets.indices.contains(setIdx) else { return .none }
                let wasCompleted = draft.exercises[exIdx].sets[setIdx].isCompleted
                draft.exercises[exIdx].sets[setIdx].isCompleted.toggle()
                if !wasCompleted {
                    let rest = draft.exercises[exIdx].restSeconds
                    draft.restSecondsRemaining = rest
                    draft.restEndsAt = now.addingTimeInterval(TimeInterval(rest))
                    state.activeWorkout = draft
                    let exerciseName = ExerciseCatalog.find(id: draft.exercises[exIdx].exerciseID)?.name ?? "训练动作"
                    return .merge(
                        .run { _ in
                            await restTimerClient.scheduleRestCompletion(seconds: rest, exerciseName: exerciseName)
                        },
                        .run { send in
                            for await _ in clock.timer(interval: .seconds(1)) {
                                await send(.restTimerTick)
                            }
                        }
                        .cancellable(id: CancelID.restTimer, cancelInFlight: true)
                    )
                }
                state.activeWorkout = draft
                return .none

            case let .activeWorkoutAddSetTapped(exIdx):
                guard var draft = state.activeWorkout,
                      draft.exercises.indices.contains(exIdx) else { return .none }
                let previous = draft.exercises[exIdx].sets.last
                let nextIndex = draft.exercises[exIdx].sets.count + 1
                draft.exercises[exIdx].sets.append(
                    LoggedSetEntry(
                        id: uuid(),
                        setIndex: nextIndex,
                        weightKg: previous?.weightKg ?? 20,
                        reps: previous?.reps ?? 10,
                        isCompleted: false
                    )
                )
                state.activeWorkout = draft
                return .none

            case let .activeWorkoutAddExercisePresented(presented):
                state.isExercisePickerPresented = presented
                return .none

            case let .activeWorkoutAddExerciseTapped(def):
                guard var draft = state.activeWorkout else { return .none }
                let defaultWeight: Double = def.equipment == "自重" ? 0 : 20
                let sets = (1...3).map {
                    LoggedSetEntry(id: uuid(), setIndex: $0, weightKg: defaultWeight, reps: 10, isCompleted: false)
                }
                draft.exercises.append(LoggedExerciseRecord(id: uuid(), exerciseID: def.id, sets: sets, restSeconds: 90))
                state.activeWorkout = draft
                state.isExercisePickerPresented = false
                return .none

            case let .activeWorkoutRPEChanged(rpe):
                state.activeWorkout?.rpe = max(1, min(10, rpe))
                return .none

            case .restTimerTick:
                guard var draft = state.activeWorkout,
                      let endsAt = draft.restEndsAt else {
                    return .cancel(id: CancelID.restTimer)
                }
                let remaining = Int(ceil(endsAt.timeIntervalSince(now)))
                if remaining <= 0 {
                    draft.restSecondsRemaining = nil
                    draft.restEndsAt = nil
                    state.activeWorkout = draft
                    return .cancel(id: CancelID.restTimer)
                }
                draft.restSecondsRemaining = remaining
                state.activeWorkout = draft
                return .none

            case let .adjustRestTimerTapped(delta):
                guard var draft = state.activeWorkout,
                      let current = draft.restSecondsRemaining else { return .none }
                let updated = max(10, current + delta)
                draft.restSecondsRemaining = updated
                draft.restEndsAt = now.addingTimeInterval(TimeInterval(updated))
                state.activeWorkout = draft
                let draftTitle = draft.title
                return .run { _ in
                    await restTimerClient.scheduleRestCompletion(seconds: updated, exerciseName: draftTitle)
                }

            case .skipRestTimerTapped:
                state.activeWorkout?.restSecondsRemaining = nil
                state.activeWorkout?.restEndsAt = nil
                return .merge(
                    .cancel(id: CancelID.restTimer),
                    .run { _ in await restTimerClient.cancelPending() }
                )

            case .discardActiveWorkoutTapped:
                state.activeWorkout = nil
                state.isExercisePickerPresented = false
                return .merge(
                    .cancel(id: CancelID.restTimer),
                    .run { _ in await restTimerClient.cancelPending() }
                )

            case .completeActiveWorkoutTapped:
                guard let draft = state.activeWorkout, !state.isSavingWorkout else { return .none }
                state.isSavingWorkout = true
                state.lastError = nil
                let completedAt = now
                let durationMin = max(1, Int(completedAt.timeIntervalSince(draft.startedAt) / 60))
                let volume = draft.totalCompletedVolumeKg
                let estimatedKcal = max(45, Double(durationMin) * Double(max(3, draft.rpe)) * 0.85 + volume * 0.015)

                let baseSession = LoggedWorkoutSession(
                    id: draft.id,
                    title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "力量训练" : draft.title,
                    startedAt: draft.startedAt,
                    completedAt: completedAt,
                    exercises: draft.exercises,
                    rpe: draft.rpe,
                    estimatedCalories: estimatedKcal,
                    syncedHealthKitUUID: nil,
                    notes: ""
                )

                return .merge(
                    .cancel(id: CancelID.restTimer),
                    .run { send in
                        await restTimerClient.cancelPending()
                        var finalSession = baseSession
                        var hkWarning: String?
                        do {
                            let hkUUID = try await healthKitClient.saveWorkout(baseSession)
                            finalSession.syncedHealthKitUUID = hkUUID
                        } catch {
                            hkWarning = "Apple 健康写回未完成（\(error.localizedDescription)）"
                        }

                        do {
                            try await fitnessStoreClient.saveSession(finalSession)
                            await send(.workoutPersisted(finalSession, hkWarning: hkWarning))
                        } catch {
                            await send(.workoutPersistFailed(error.localizedDescription))
                        }
                    }
                )

            case let .workoutPersisted(session, hkWarning):
                state.isSavingWorkout = false
                state.activeWorkout = nil
                state.isExercisePickerPresented = false
                state.sessions.insert(session, at: 0)
                state.recomputeRecoverySnapshot()
                if let hkWarning {
                    state.statusMessage = "训练已保存到 BodySeek；\(hkWarning)"
                } else {
                    state.statusMessage = "已完成「\(session.title)」并同步至 Apple 健康"
                }
                return .send(.delegate(.sessionSaved(session)))

            case let .workoutPersistFailed(reason):
                state.isSavingWorkout = false
                state.lastError = "保存训练失败：\(reason)"
                return .none

            case let .templatePersistFailed(reason):
                state.lastError = "保存训练模板失败：\(reason)"
                return .none

            case let .askCoachForMuscleTapped(muscle):
                if let muscle {
                    return .send(.delegate(.askCoach("结合我今天的恢复状态和 ACWR 负荷比，帮我安排一组针对「\(muscle.title)」的训练")))
                }
                return .send(.delegate(.askCoach("根据我今天的恢复评分、最近肌肉负荷和 ACWR 负荷比，帮我安排今日训练")))

            case .openTrendsTapped:
                return .send(.delegate(.openTrends))

            case .clearStatusBanner:
                state.statusMessage = nil
                state.lastError = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }

    private func syncWatchWorkoutsEffect(
        historyDays: [DailyComputedDay],
        asOf: Date,
        dominantHand: DominantHand
    ) -> Effect<Action> {
        let seedRecords = State.storedRecords(from: historyDays)
        var symbolMap: [String: String] = [:]
        for day in historyDays.suffix(30) {
            for w in day.raw.workouts {
                let uuid = (w.healthKitUUID ?? w.id).uuidString
                symbolMap[uuid] = w.symbolName
            }
        }
        let immutableSymbols = symbolMap
        let sinceDate = asOf.addingTimeInterval(-14 * 86_400)
        return .run { send in
            do {
                if !seedRecords.isEmpty {
                    try await bodySeekStoreClient.upsertStoredWorkouts(seedRecords, immutableSymbols)
                }
                let existing = try await bodySeekStoreClient.loadStoredWorkouts(120)
                for workout in existing where workout.end >= sinceDate {
                    if workout.reviewState == .unreviewed || workout.reviewState == .autoAttributed,
                       let auto = WorkoutAutoAttributor.autoAttribute(workout: workout, dominantHand: dominantHand)
                    {
                        _ = try await bodySeekStoreClient.applyAutoWorkoutAttribution(workout.hkUUID, auto.loads)
                    }
                }
                let finalWorkouts = try await bodySeekStoreClient.loadStoredWorkouts(120)
                let annotations = try await bodySeekStoreClient.loadWorkoutAnnotations(nil)
                let loads = try await bodySeekStoreClient.loadAllMuscleLoads(sinceDate)
                await send(.watchWorkoutsLoaded(
                    workouts: finalWorkouts,
                    annotations: annotations,
                    loads: loads
                ))
            } catch {
                await send(.watchSyncFailed("同步 Watch 训练与肌群归因失败：\(error.localizedDescription)"))
            }
        }
    }
}
