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

@Reducer
public struct WorkoutFeature: Sendable {
    @ObservableState
    public struct State: Equatable, Sendable {
        public var snapshot: BodySeekDashboardSnapshot
        public var templates: [WorkoutTemplate] = []
        public var sessions: [LoggedWorkoutSession] = []
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
            sessions: [LoggedWorkoutSession] = []
        ) {
            self.snapshot = snapshot
            self.templates = templates
            self.sessions = sessions
        }

        public var muscleLoadLast72h: [BodyRegionMuscle: Double] {
            let cutoff = snapshot.referenceDate.addingTimeInterval(-72 * 3600)
            var combined: [BodyRegionMuscle: Double] = [:]
            for session in sessions where session.completedAt >= cutoff {
                let elapsedHours = max(0, snapshot.referenceDate.timeIntervalSince(session.completedAt) / 3600)
                let decay = max(0.35, 1.0 - (elapsedHours / 96.0))
                for (muscle, intensity) in session.muscleLoadIntensities {
                    combined[muscle, default: 0] += intensity * decay
                }
            }
            return combined.mapValues { min(1.0, $0) }
        }

        public var loadedMusclesRanked: [(muscle: BodyRegionMuscle, load: Double)] {
            muscleLoadLast72h
                .filter { $0.value >= 0.08 }
                .sorted { $0.value > $1.value }
                .map { ($0.key, $0.value) }
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
            case askCoach(String)
            case openTrends
        }
    }

    private enum CancelID {
        case restTimer
    }

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
}
