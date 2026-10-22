import SwiftUI
import SwiftData
import Combine

struct StrengthWorkoutLogSheetView: View {
    var trainingDecisionKind: String?
    var onRefresh: (() async -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var appState = VelaAppState.shared
    @State private var workoutHistory: [StrengthWorkoutRecord] = []
    @State private var persistedTemplates: [WorkoutTemplateRecord] = []
    @State private var deletedWorkouts: [DeletedWorkoutRecord] = []
    
    @State private var title = "力量训练"
    @State private var startedAt = Date()
    @State private var notes = ""
    @State private var exertionScore: Double = 7.0
    @State private var exercises: [StrengthExerciseLog] = []
    @State private var showExercisePicker = false
    @State private var showDiscardConfirmation = false
    @State private var restTimer: RestTimerState?
    @State private var saveError: String?
    @State private var completedSummary: StrengthWorkoutAnalysis?
    @State private var completedWorkout: StrengthWorkoutRecord?
    @State private var closeAfterSummary = false
    @State private var isLoaded = false
    /// Guards against a fast double-tap on "完成" creating a duplicate workout.
    @State private var isSaving = false
    @State private var showIgnoreUncompletedConfirmation = false
    @State private var showPlateCalculator = false
    @State private var showExerciseGrouping = false
    @State private var activeDraftID: UUID?
    @StateObject private var sessionViewModel = StrengthWorkoutSessionViewModel()

    private let startingTemplateID: UUID?
    private let initialDraft: TrainingSessionDraft?
    private let editingWorkout: StrengthWorkoutRecord?
    private let equipmentOptions = ["杠铃", "哑铃", "固定器械", "绳索", "壶铃", "自重", "其他"]

    init(
        startingTemplateID: UUID? = nil,
        initialDraft: TrainingSessionDraft? = nil,
        editingWorkout: StrengthWorkoutRecord? = nil,
        trainingDecisionKind: String? = nil,
        onRefresh: (() async -> Void)? = nil
    ) {
        self.startingTemplateID = startingTemplateID
        self.initialDraft = initialDraft
        self.editingWorkout = editingWorkout
        self.trainingDecisionKind = trainingDecisionKind
        self.onRefresh = onRefresh
    }

    private func durationMinutes(at date: Date = Date()) -> Int {
        // Editing an already-logged workout: its duration is a historical fact and
        // `now` is meaningless here — `startedAt` was set to the original PAST date,
        // so `now - startedAt` would inflate the duration to days and corrupt it.
        // Keep the existing recorded duration instead.
        if let editingWorkout {
            return max(1, editingWorkout.durationMinutes)
        }
        // 草稿跨天续录时 now - startedAt 可膨胀到数百上千分钟，污染时长/负荷/热量；
        // 单次训练时长封顶 4 小时（超过时按 startedAt 重算最近一次活跃的保守值）。
        return min(max(1, Int(date.timeIntervalSince(startedAt) / 60)), 240)
    }

    private var completedSetCount: Int {
        exercises.flatMap(\.sets).filter { $0.isCompleted == true }.count
    }

    private var totalSetCount: Int {
        exercises.flatMap(\.sets).count
    }

    private var setProgressText: String {
        totalSetCount == 0 ? "未添加组" : "\(completedSetCount)/\(totalSetCount) 组"
    }

    private var hasMeaningfulDraft: Bool {
        guard editingWorkout == nil else { return false }
        if !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if title.trimmingCharacters(in: .whitespacesAndNewlines) != "力量训练" { return true }
        return exercises.contains { exercise in
            !exercise.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !exercise.sets.isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sessionCard

                    if let restTimer {
                        StrengthRestTimerCard(
                            timer: restTimer,
                            onFinish: { self.restTimer = nil }
                        )
                    }

                    ForEach($exercises) { $exercise in
                        exerciseCard(exercise: $exercise)
                    }

                    Button {
                        showExercisePicker = true
                    } label: {
                        Label("添加动作", systemImage: "plus.circle.fill")
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .foregroundStyle(VelaTheme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .velaNativeCard(radius: 16)
                    }
                    .buttonStyle(.cardPress)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle(editingWorkout != nil ? "编辑力量训练" : "记录力量训练")
            .navigationBarTitleDisplayMode(.inline)
            .velaRhythmDetailChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editingWorkout == nil ? "关闭" : "取消") { requestClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { requestSave() }
                        .disabled(validExercises.isEmpty || isSaving)
                }
            }
        }
        .task {
            try? ExerciseLibraryService.seedDefaultsIfNeeded(modelContext: modelContext)
            loadTemplateLibrary()
            loadWorkoutHistory()
            loadDraftIfNeeded()
        }
        .onChange(of: appState.localDataRevision) { _, _ in
            loadTemplateLibrary()
            loadWorkoutHistory()
        }
        .onChange(of: title) { _, _ in scheduleDraftSave() }
        .onChange(of: notes) { _, _ in scheduleDraftSave() }
        .onChange(of: exercises) { _, _ in scheduleDraftSave() }
        .onReceive(NotificationCenter.default.publisher(for: .wristStrengthSetEditQueued)) { _ in
            applyPendingWatchEdits()
        }
        .sheet(isPresented: $showExercisePicker) {
            ExercisePickerSheet { definition in
                addExercise(definition)
            }
        }
        .sheet(isPresented: $showPlateCalculator) {
            BarbellPlateCalculatorSheet()
                .presentationDetents([.medium])
                .velaSheetSurface()
        }
        .sheet(isPresented: $showExerciseGrouping) {
            StrengthExerciseGroupingSheet(exercises: $exercises)
                .velaSheetSurface()
        }
        .sheet(item: $completedSummary, onDismiss: {
            if closeAfterSummary { dismiss() }
        }) { summary in
            StrengthWorkoutSummarySheet(
                summary: summary,
                workout: completedWorkout,
                onSaveTemplate: saveCompletedWorkoutAsTemplate,
                onDone: {
                    closeAfterSummary = true
                    completedSummary = nil
                }
            )
        }
        .confirmationDialog("要关闭这次训练吗？", isPresented: $showDiscardConfirmation, titleVisibility: .visible) {
            Button("保存草稿并关闭") {
                saveDraft()
                dismiss()
            }
            Button("丢弃草稿", role: .destructive) { discardWorkout() }
            Button("继续训练", role: .cancel) {}
        } message: {
            Text("已记录的动作和组次可以保留为草稿，下次打开会继续显示。")
        }
        .confirmationDialog("忽略未完成组？", isPresented: $showIgnoreUncompletedConfirmation, titleVisibility: .visible) {
            Button("忽略并保存", role: .destructive) { save(ignoringUncompletedSets: true) }
            Button("返回继续记录", role: .cancel) {}
        } message: {
            Text("未打勾的组不会计入训练总结、肌群疲劳或今日负荷。")
        }
        .alert("无法保存训练", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                WorkoutElapsedTimeLabel(
                    startedAt: startedAt,
                    fixedDurationMinutes: editingWorkout?.durationMinutes
                )
                Label(setProgressText, systemImage: "checkmark.circle")
                Spacer()
            }
            .font(.system(.caption, design: .default, weight: .semibold))
            .foregroundStyle(VelaTheme.muted)

            TextField("训练名称", text: $title)
                .font(.system(.body, design: .default, weight: .bold))
            HStack {
                Spacer()
                Button {
                    showPlateCalculator = true
                } label: {
                    Label("杠铃配片", systemImage: "scalemass")
                }
                .font(.system(.footnote, design: .default, weight: .bold))

                Button {
                    showExerciseGrouping = true
                } label: {
                    Label("组合动作", systemImage: "link")
                }
                .font(.system(.footnote, design: .default, weight: .bold))
                .disabled(exercises.count < 2)

                Menu("从模板开始") {
                    Button("空白训练") { exercises = [] }
                    ForEach(availableTemplates) { template in
                        Menu(localizedWorkoutTemplateTitle(template.title)) {
                            Button("应用模板") { applyTemplate(template) }
                            Button("删除模板", role: .destructive) { deleteTemplate(template) }
                        }
                    }
                }
                .font(.system(.footnote, design: .default, weight: .bold))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("自觉竭力程度 (RPE):")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.fg)
                    Spacer()
                    Text("\(Int(exertionScore)) / 10")
                        .font(.system(.footnote, design: .rounded, weight: .bold))
                        .foregroundStyle(VelaTheme.accent)
                }
                Slider(value: $exertionScore, in: 1...10, step: 1)
                    .tint(VelaTheme.accent)
                Text("1 = 极轻松，10 = 力竭且无任何保留组。用于重算今日负荷。")
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }
            .padding(.top, 4)

            TextField("训练备注（可选）", text: $notes, axis: .vertical)
                .font(.system(.footnote, design: .default))
                .lineLimit(2...4)
        }
        .padding(16)
        .velaNativeCard(radius: 16)
    }

    private func exerciseCard(exercise: Binding<StrengthExerciseLog>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let groupKind = exercise.wrappedValue.groupKind,
               let groupPosition = exercise.wrappedValue.groupPosition {
                Label(
                    "\(groupKind.displayName) · \(groupPosition + 1)",
                    systemImage: groupKind == .superset ? "link" : "arrow.triangle.2.circlepath"
                )
                .font(VelaTheme.caption1().weight(.bold))
                .foregroundStyle(groupKind == .superset ? VelaTheme.accent : VelaTheme.rhythmInk)
            }

            HStack {
                TextField("动作名称，例如卧推", text: exercise.name)
                    .font(.system(.callout, design: .default, weight: .bold))
                if exercises.count > 1 {
                    Button {
                        let exerciseID = exercise.wrappedValue.id
                        let groupID = exercise.wrappedValue.groupID
                        if let groupID {
                            exercises = StrengthExerciseGroupingPlanner.ungroup(exercises, groupID: groupID)
                        }
                        exercises.removeAll { $0.id == exerciseID }
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(VelaTheme.systemRed)
                    }
                    .buttonStyle(.cardPress)
                }
            }

            Picker("器械", selection: exercise.equipment) {
                ForEach(equipmentOptions, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)

            let previousSets = previousCompletedSets(for: exercise.wrappedValue.name)
            if !previousSets.isEmpty {
                Text("上次表现：\(previousPerformance(for: exercise.wrappedValue.name) ?? "")")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.muted)
            }

            ForEach(Array(exercise.wrappedValue.sets.enumerated()), id: \.element.id) { index, item in
                strengthSetRow(
                    index: index,
                    set: Binding(
                        get: { exercise.wrappedValue.sets[index] },
                        set: { exercise.wrappedValue.sets[index] = $0 }
                    ),
                    exercise: exercise,
                    previousSets: previousSets
                )
            }

            HStack(spacing: 16) {
                Button {
                    let lastWeight = exercise.wrappedValue.sets.last?.weightKilograms ?? 0
                    let lastReps = exercise.wrappedValue.sets.last?.repetitions ?? 10
                    exercise.wrappedValue.sets.append(StrengthSetLog(repetitions: lastReps, weightKilograms: lastWeight, isWarmup: false, rpe: nil, rir: nil, isCompleted: false, completedAt: nil))
                } label: {
                    Label("添加一组", systemImage: "plus")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.accent)
                }
                .buttonStyle(.cardPress)

                if let last = exercise.wrappedValue.sets.last {
                    Button {
                        var copy = last
                        copy.id = UUID()
                        copy.isCompleted = false
                        copy.completedAt = nil
                        exercise.wrappedValue.sets.append(copy)
                    } label: {
                        Label("复制上一组", systemImage: "plus.square.on.square")
                            .font(.system(.caption, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.muted)
                    }
                    .buttonStyle(.cardPress)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .velaNativeCard(radius: 20)
    }

    private func strengthSetRow(
        index: Int,
        set: Binding<StrengthSetLog>,
        exercise: Binding<StrengthExerciseLog>,
        previousSets: [StrengthSetLog]
    ) -> some View {
        let prevText: String
        if index < previousSets.count {
            let prev = previousSets[index]
            prevText = "\(prev.weightKilograms.formatted(.number.precision(.fractionLength(0...1))))×\(prev.repetitions)"
        } else {
            prevText = "—"
        }

        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(StrengthSetKind.allCases, id: \.self) { kind in
                        Button {
                            set.wrappedValue.kind = kind
                            scheduleDraftSave()
                        } label: {
                            Label(kind.displayName, systemImage: setKindIcon(kind))
                        }
                    }
                } label: {
                    Text(set.wrappedValue.kind == .working ? "\(index + 1)" : set.wrappedValue.kind.shortLabel)
                        .font(VelaTheme.caption1().weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(setKindColor(set.wrappedValue.kind)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("第 \(index + 1) 组，\(set.wrappedValue.kind.displayName)，轻点更改类型")

                VStack(alignment: .leading, spacing: 2) {
                    Text(set.wrappedValue.kind == .working ? "第 \(index + 1) 组" : set.wrappedValue.kind.displayName)
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.fg)
                    Text("上次 \(prevText)")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.muted)
                }

                Spacer()

                Button {
                    complete(set: set, in: exercise)
                } label: {
                    Label(
                        (set.wrappedValue.isCompleted ?? false) ? "已完成" : "完成",
                        systemImage: (set.wrappedValue.isCompleted ?? false) ? "checkmark.circle.fill" : "circle"
                    )
                    .font(VelaTheme.caption1().weight(.semibold))
                    .foregroundStyle((set.wrappedValue.isCompleted ?? false) ? VelaTheme.success : VelaTheme.accent)
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("重量 kg").font(VelaTheme.caption2()).foregroundStyle(VelaTheme.muted)
                    TextField("0", value: set.weightKilograms, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.center)
                        .font(VelaTheme.headline().monospacedDigit())
                        .frame(height: 38)
                        .background(VelaTheme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: set.wrappedValue.weightKilograms) { _, _ in scheduleDraftSave() }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    Text("次数").font(VelaTheme.caption2()).foregroundStyle(VelaTheme.muted)
                    TextField("0", value: set.repetitions, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(VelaTheme.headline().monospacedDigit())
                        .frame(height: 38)
                        .background(VelaTheme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                        .onChange(of: set.wrappedValue.repetitions) { _, _ in scheduleDraftSave() }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    Text("RPE").font(VelaTheme.caption2()).foregroundStyle(VelaTheme.muted)
                    Menu {
                        Button("无") { set.wrappedValue.rpe = nil; scheduleDraftSave() }
                        ForEach((5...10).reversed(), id: \.self) { val in
                            Button("RPE \(val)") { set.wrappedValue.rpe = Double(val); scheduleDraftSave() }
                        }
                    } label: {
                        Text(set.wrappedValue.rpe.map { "\(Int($0))" } ?? "—")
                            .font(VelaTheme.headline().monospacedDigit())
                            .foregroundStyle(set.wrappedValue.rpe != nil ? VelaTheme.accent : VelaTheme.muted)
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .background(VelaTheme.cardBg, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
        .background(VelaTheme.elevatedBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contextMenu {
            Menu("组类型") {
                ForEach(StrengthSetKind.allCases, id: \.self) { kind in
                    Button(kind.displayName) {
                        set.wrappedValue.kind = kind
                        scheduleDraftSave()
                    }
                }
            }
            
            if exercise.wrappedValue.sets.count > 1 {
                Button("删除此组", role: .destructive) {
                    exercise.wrappedValue.sets.removeAll { $0.id == set.wrappedValue.id }
                    scheduleDraftSave()
                }
            }
        }
    }

    private func setKindIcon(_ kind: StrengthSetKind) -> String {
        switch kind {
        case .working: "dumbbell.fill"
        case .warmup: "flame.fill"
        case .drop: "arrow.down.right"
        case .backoff: "arrow.uturn.backward"
        case .failure: "bolt.fill"
        }
    }

    private func setKindColor(_ kind: StrengthSetKind) -> Color {
        switch kind {
        case .working: VelaTheme.accent
        case .warmup: VelaTheme.warn
        case .drop: VelaTheme.rhythmInk
        case .backoff: VelaTheme.rhythmInk
        case .failure: VelaTheme.rhythmInk
        }
    }

    private var validExercises: [StrengthExerciseLog] {
        exercises.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func requestSave() {
        if hasUncompletedSets {
            showIgnoreUncompletedConfirmation = true
        } else {
            save(ignoringUncompletedSets: false)
        }
    }

    private func save(ignoringUncompletedSets: Bool) {
        // Reject a fast double-tap so the same workout isn't committed twice.
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let savedDurationMinutes = durationMinutes()
        let validation = StrengthWorkoutSaveValidator.exercisesToSave(
            from: exercises,
            ignoringUncompletedSets: ignoringUncompletedSets
        )
        let exercisesToSave: [StrengthExerciseLog]
        switch validation {
        case .success(let validatedExercises):
            exercisesToSave = validatedExercises
        case .failure(.emptyCompletedSets):
            saveError = "至少完成一组后才能保存训练。"
            return
        }
        
        if let editingWorkout {
            let previousStartDate = editingWorkout.startedAt
            editingWorkout.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "力量训练" : title
            editingWorkout.startedAt = startedAt
            editingWorkout.durationMinutes = savedDurationMinutes
            editingWorkout.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            editingWorkout.exercises = exercisesToSave
            editingWorkout.completedAt = startedAt.addingTimeInterval(TimeInterval(savedDurationMinutes * 60))
            
            do {
                // PR 历史只取早于本次训练的记录，避免编辑旧训练时与未来记录比较产生伪 PR。
                let editingStart = editingWorkout.startedAt
                let analysis = TrainingAnalyticsService().summarizeWorkout(
                    editingWorkout.dto,
                    history: workoutHistory
                        .filter { $0.id != editingWorkout.id && $0.startedAt < editingStart }
                        .map { $0.dto },
                    exerciseLibrary: ExerciseLibraryService.defaultDefinitionsDTO()
                )
                // T7 修复：停止写入只写不读的 analyticsJSON。
                
                _ = try WorkoutSaveCoordinator().commitWorkoutEdit(
                    workout: editingWorkout,
                    previousStartDate: previousStartDate,
                    sessionRPE: exertionScore,
                    modelContext: modelContext
                )
                
                VelaAppState.shared.markLocalDataChanged()
                completedWorkout = editingWorkout
                completedSummary = analysis
                if let onRefresh {
                    Task { await onRefresh() }
                }
            } catch {
                saveError = "训练更新失败，请稍后再试。\(error.localizedDescription)"
            }
        } else {
            let record = StrengthWorkoutRecord(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "力量训练" : title,
                startedAt: startedAt,
                durationMinutes: savedDurationMinutes,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                exercises: exercisesToSave
            )
            record.planDayId = initialDraft?.planDayId
            do {
                let analysis = TrainingAnalyticsService().summarizeWorkout(
                    record.dto,
                    history: workoutHistory.map { $0.dto },
                    exerciseLibrary: ExerciseLibraryService.defaultDefinitionsDTO()
                )
                // T7 修复：停止写入只写不读的 analyticsJSON。
                let workoutIdStr = record.id.uuidString
                let existingArtifacts = try? CoachArtifactRepository(modelContext: modelContext).fetchAll()
                if let existing = existingArtifacts {
                    for art in existing {
                        if art.actionsJSON.contains(workoutIdStr) {
                            modelContext.delete(art)
                        }
                    }
                }
                
                let planDayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: record.startedAt)
                let readinessDecision = (try? DailyOperatingPlanRepository(modelContext: modelContext)
                    .fetchLatest(dayIdentifier: planDayIdentifier))?.primaryActionType
                    ?? trainingDecisionKind
                let artifact = CoachArtifact.postWorkoutReview(
                    workout: record,
                    summary: analysis,
                    readinessDecision: readinessDecision,
                    sourceContextHash: ContentHash.hash(
                        "\(record.id.uuidString)-\(record.totalVolumeKilograms)-\(record.exercises.flatMap(\.sets).count)"
                    )
                )
                _ = try WorkoutSaveCoordinator().commitNewWorkout(
                    workout: record,
                    artifact: CoachArtifactRecord(artifact: artifact),
                    sessionRPE: exertionScore,
                    modelContext: modelContext
                )
                clearDraft()
                
                VelaAppState.shared.markLocalDataChanged()
                completedWorkout = record
                completedSummary = analysis
                if let onRefresh {
                    Task { await onRefresh() }
                }
            } catch {
                saveError = "训练暂时无法保存，请稍后再试。\(error.localizedDescription)"
            }
        }
    }

    private func addExercise(_ definition: ExerciseDefinitionRecord) {
        let previousSets = previousCompletedSets(for: definition.name)
        let seedSets = previousSets.isEmpty
            ? [StrengthSetLog(
                repetitions: 10,
                weightKilograms: ExerciseLoadDefaults.initialWeight(
                    equipment: definition.equipment,
                    exerciseName: definition.name,
                    previousSets: []
                ),
                isWarmup: false,
                rpe: nil,
                rir: nil,
                isCompleted: false,
                completedAt: nil
            )]
            : previousSets.prefix(3).map {
                StrengthSetLog(
                    repetitions: $0.repetitions,
                    weightKilograms: $0.weightKilograms,
                    isWarmup: false,
                    rpe: $0.rpe,
                    rir: $0.rir,
                    isCompleted: false,
                    completedAt: nil
                )
            }
        exercises.append(StrengthExerciseLog(
            exerciseDefinitionId: definition.id,
            exerciseCanonicalKey: definition.canonicalKey,
            name: definition.name,
            equipment: localizedEquipment(definition.equipment),
            primaryMuscleGroup: definition.primaryMuscleGroup,
            sets: Array(seedSets)
        ))
    }

    private func applyTemplate(_ template: WorkoutTemplateRecord) {
        title = localizedWorkoutTemplateTitle(template.title)
        template.lastUsedAt = Date()
        template.updatedAt = Date()
        exercises = template.exercises.map { item in
            var definition: ExerciseDefinitionRecord?
            if let defKey = item.exerciseCanonicalKey {
                definition = (try? ExerciseDefinitionRepository(modelContext: modelContext)
                    .fetch(canonicalKey: defKey))?.first
            }
            if definition == nil {
                definition = (try? ExerciseDefinitionRepository(modelContext: modelContext)
                    .fetch(name: item.name))?.first
            }
            
            let libDef = ExerciseLibraryService.defaultDefinitions().first {
                if let defKey = item.exerciseCanonicalKey { return $0.canonicalKey == defKey }
                return $0.name == item.name
            }
            
            let finalId = definition?.id ?? libDef?.id
            let finalKey = definition?.canonicalKey ?? libDef?.canonicalKey
            
            let reps = StrengthWorkoutTemplateParser.reps(from: item.targetReps)
            
            let previousSets = previousCompletedSets(for: item.name)
            let defaultWeight = ExerciseLoadDefaults.initialWeight(
                equipment: definition?.equipment ?? libDef?.equipment ?? "other",
                exerciseName: item.name,
                previousSets: previousSets
            )
            return StrengthExerciseLog(
                exerciseDefinitionId: finalId,
                exerciseCanonicalKey: finalKey,
                name: item.name,
                equipment: localizedEquipment(definition?.equipment ?? libDef?.equipment ?? "other"),
                primaryMuscleGroup: definition?.primaryMuscleGroup ?? libDef?.primaryMuscleGroup,
                sets: (0..<max(1, item.targetSets)).map { index in
                    let previous = index < previousSets.count ? previousSets[index] : nil
                    return StrengthSetLog(
                        repetitions: previous?.repetitions ?? reps,
                        weightKilograms: previous?.weightKilograms ?? defaultWeight,
                        isWarmup: false,
                        rpe: previous?.rpe ?? item.targetRPE,
                        rir: previous?.rir,
                        isCompleted: false,
                        completedAt: nil
                    )
                }
            )
        }
    }

    private var availableTemplates: [WorkoutTemplateRecord] {
        let deletedTemplateTitles = Set(deletedWorkouts.compactMap { rec -> String? in
            if rec.id.hasPrefix("template:") {
                return String(rec.id.dropFirst("template:".count))
            }
            return nil
        })
        let persistedTitles = Set(persistedTemplates.map(\.title))
        let filteredPersisted = persistedTemplates.filter { !deletedTemplateTitles.contains($0.title) }
        let filteredDefaults = ExerciseLibraryService.defaultTemplates().filter {
            !persistedTitles.contains($0.title) && !deletedTemplateTitles.contains($0.title)
        }
        return filteredPersisted + filteredDefaults
    }

    private func deleteTemplate(_ template: WorkoutTemplateRecord) {
        modelContext.insert(DeletedWorkoutRecord(id: "template:\(template.title)"))
        modelContext.delete(template)
        modelContext.saveOrRecordFailure("modelContext.save")
        loadTemplateLibrary()
    }

    private func localizedEquipment(_ value: String) -> String {
        switch value.lowercased() {
        case "barbell": return "杠铃"
        case "dumbbell": return "哑铃"
        case "machine": return "固定器械"
        case "cable": return "绳索"
        case "kettlebell": return "壶铃"
        case "bodyweight": return "自重"
        default: return "其他"
        }
    }

    private func previousPerformance(for exerciseName: String) -> String? {
        let sets = previousCompletedSets(for: exerciseName)
        guard !sets.isEmpty else {
            return nil
        }
        return sets.prefix(3).map {
            "\($0.weightKilograms.formatted(.number.precision(.fractionLength(0...1))))kg × \($0.repetitions)"
        }.joined(separator: "，")
    }

    private func previousCompletedSets(for exerciseName: String) -> [StrengthSetLog] {
        StrengthWorkoutSessionPrefill.previousCompletedSets(for: exerciseName, in: workoutHistory)
    }

    private func complete(set: Binding<StrengthSetLog>, in exercise: Binding<StrengthExerciseLog>) {
        set.wrappedValue.isCompleted = !(set.wrappedValue.isCompleted ?? false)
        set.wrappedValue.completedAt = (set.wrappedValue.isCompleted ?? false) ? Date() : nil
        sessionViewModel.saveImmediately { saveDraft() }
        guard set.wrappedValue.isCompleted ?? false,
              let index = exercise.wrappedValue.sets.firstIndex(where: { $0.id == set.wrappedValue.id }) else { return }
        
        var restDuration = 90
        if let plan = try? TrainingPlanRepository(modelContext: modelContext).fetchActivePlans().first {
            // 用本次训练的开始日而非「今天」（跨天补录时取错计划日）。
            let todayWeekday = Calendar.current.component(.weekday, from: startedAt)
            let dayNum = todayWeekday == 1 ? 7 : todayWeekday - 1
            if let day = plan.days.first(where: { $0.dayNumber == dayNum }),
               let data = day.plannedExercisesJSON.data(using: .utf8),
               let planned = try? JSONDecoder().decode([WorkoutTemplateExercise].self, from: data),
               let match = planned.first(where: { $0.name.caseInsensitiveCompare(exercise.wrappedValue.name) == .orderedSame }) {
                restDuration = match.restSeconds
            }
        }
        
        restTimer = RestTimerState(endsAt: Date().addingTimeInterval(TimeInterval(restDuration)), exerciseName: exercise.wrappedValue.name, setNumber: index + 1)
    }

    private func quickAdjust(_ label: String, action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .buttonStyle(.bordered)
            .controlSize(.mini)
    }

    private func saveCompletedWorkoutAsTemplate() -> Bool {
        guard let workout = completedWorkout else { return false }
        modelContext.insert(WorkoutTemplateRecord(
            title: workout.title,
            goal: "custom",
            notes: workout.notes,
            exercises: workout.exercises.map {
                WorkoutTemplateExercise(
                    exerciseDefinitionId: $0.exerciseDefinitionId,
                    exerciseCanonicalKey: $0.exerciseCanonicalKey,
                    name: $0.name,
                    targetSets: max(1, $0.sets.filter { !($0.isWarmup) }.count),
                    targetReps: $0.sets.first.map { "\($0.repetitions)" } ?? "8-12",
                    targetRPE: $0.sets.compactMap(\.rpe).first,
                    restSeconds: 90
                )
            },
            estimatedDurationMinutes: workout.durationMinutes
        ))
        do {
            try modelContext.save()
            loadTemplateLibrary()
            return true
        } catch {
            return false
        }
    }

    private func loadTemplateLibrary() {
        persistedTemplates = (try? WorkoutTemplateRepository(modelContext: modelContext).fetchAllSortedByTitle()) ?? []
        deletedWorkouts = (try? DeletedWorkoutRepository(modelContext: modelContext).fetchAll()) ?? []
    }

    // MARK: - Draft Autosave Mechanism

    private func loadWorkoutHistory() {
        workoutHistory = (try? WorkoutHistoryRepository(modelContext: modelContext)
            .fetchStrengthWorkoutsSortedByStart(newestFirst: true)) ?? []
    }

    private func loadDraftIfNeeded() {
        if let editingWorkout {
            self.title = editingWorkout.title
            self.startedAt = editingWorkout.startedAt
            self.notes = editingWorkout.notes
            self.exercises = editingWorkout.exercises
            if let eventID = editingWorkout.linkedWorkoutEventId {
                if let event = try? WorkoutHistoryRepository(modelContext: modelContext)
                    .fetchEvents(id: eventID)
                    .first {
                    self.exertionScore = event.rpe ?? 7.0
                }
            }
        } else if let initialDraft {
            self.title = initialDraft.title
            self.startedAt = initialDraft.startedAt
            self.notes = initialDraft.notes
            self.exercises = initialDraft.exercises
            self.exertionScore = initialDraft.exercises
                .flatMap(\.sets)
                .compactMap(\.rpe)
                .max() ?? 7
        } else {
            if let draft = (try? ActiveWorkoutDraftRepository(modelContext: modelContext).fetchAll())?.first {
                self.activeDraftID = draft.id
                self.title = draft.title
                self.startedAt = draft.startedAt
                self.notes = draft.notes
                self.exercises = draft.exercises
            } else if let startingTemplateID,
                      let template = availableTemplates.first(where: { $0.id == startingTemplateID }) {
                self.startedAt = Date()
                applyTemplate(template)
            }
        }
        self.isLoaded = true
        if editingWorkout == nil {
            saveDraft()
            applyPendingWatchEdits()
        }
    }

    private func saveDraft() {
        guard isLoaded && editingWorkout == nil else { return }
        let draft: ActiveWorkoutDraftRecord
        if let existing = (try? ActiveWorkoutDraftRepository(modelContext: modelContext).fetchAll())?.first {
            existing.title = title
            existing.startedAt = startedAt
            existing.notes = notes
            existing.exercises = exercises
            existing.lastUpdated = Date()
            draft = existing
        } else {
            let created = ActiveWorkoutDraftRecord(
                title: title,
                startedAt: startedAt,
                notes: notes
            )
            created.exercises = exercises
            modelContext.insert(created)
            draft = created
        }
        activeDraftID = draft.id
        modelContext.saveOrRecordFailure("modelContext.save")
        WristSnapshotBridge.shared.publishActiveWorkout(draft)
    }

    private func scheduleDraftSave() {
        guard isLoaded && editingWorkout == nil else { return }
        sessionViewModel.scheduleDraftSave { saveDraft() }
    }

    private var hasUncompletedSets: Bool {
        validExercises.flatMap(\.sets).contains { $0.isCompleted != true }
    }

    private func requestClose() {
        if editingWorkout != nil {
            dismiss()
            return
        }
        if hasMeaningfulDraft {
            showDiscardConfirmation = true
        } else {
            clearDraft()
            dismiss()
        }
    }

    private func discardWorkout() {
        clearDraft()
        dismiss()
    }

    private func clearDraft() {
        if let drafts = try? ActiveWorkoutDraftRepository(modelContext: modelContext).fetchAll() {
            for draft in drafts {
                modelContext.delete(draft)
            }
        }
        modelContext.saveOrRecordFailure("modelContext.save")
        activeDraftID = nil
        WristSnapshotBridge.shared.clearActiveWorkout()
    }

    private func applyPendingWatchEdits() {
        guard let activeDraftID else { return }
        let edits = WristSnapshotBridge.shared.drainPendingStrengthSetEdits()
        guard !edits.isEmpty else { return }
        let updated = WristStrengthEditApplier.apply(edits, draftID: activeDraftID, to: exercises)
        guard updated != exercises else { return }
        exercises = updated
        sessionViewModel.saveImmediately { saveDraft() }
    }
}

enum BarbellPlateCalculator {
    static let availablePlates = [25.0, 20.0, 15.0, 10.0, 5.0, 2.5, 1.25, 0.5, 0.25]

    static func platesPerSide(targetKilograms: Double, barKilograms: Double) -> [Double] {
        var remaining = max(0, (targetKilograms - barKilograms) / 2)
        var result: [Double] = []
        for plate in availablePlates {
            while remaining + 0.0001 >= plate {
                result.append(plate)
                remaining -= plate
            }
        }
        return result
    }

    static func achievableKilograms(targetKilograms: Double, barKilograms: Double) -> Double {
        barKilograms + platesPerSide(targetKilograms: targetKilograms, barKilograms: barKilograms).reduce(0, +) * 2
    }
}

private struct WorkoutElapsedTimeLabel: View {
    let startedAt: Date
    let fixedDurationMinutes: Int?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Label("\(duration(at: context.date)) 分钟", systemImage: "timer")
                .monospacedDigit()
                .accessibilityLabel("训练时长")
                .accessibilityValue("\(duration(at: context.date)) 分钟")
        }
    }

    private func duration(at date: Date) -> Int {
        if let fixedDurationMinutes {
            return max(1, fixedDurationMinutes)
        }
        return min(max(1, Int(date.timeIntervalSince(startedAt) / 60)), 240)
    }
}

private struct StrengthRestTimerCard: View {
    let timer: RestTimerState
    let onFinish: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack {
                Image(systemName: "timer")
                Text("\(timer.exerciseName) 第 \(timer.setNumber) 组休息")
                Spacer()
                Text("\(remainingSeconds(at: context.date))s")
                    .monospacedDigit()
                    .accessibilityLabel("剩余休息时间")
                    .accessibilityValue("\(remainingSeconds(at: context.date)) 秒")
                Button("跳过", action: onFinish)
                    .buttonStyle(.cardPress)
            }
        }
        .font(.system(.footnote, design: .default, weight: .bold))
        .foregroundStyle(VelaTheme.accent)
        .padding(14)
        .velaNativeCard(radius: 16)
        .appleIntelligenceGlow(isHighlighted: true, radius: 16)
        .task(id: timer.endsAt) {
            let delay = max(0, timer.endsAt.timeIntervalSinceNow)
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    private func remainingSeconds(at date: Date) -> Int {
        max(0, Int(timer.endsAt.timeIntervalSince(date).rounded(.up)))
    }
}

private struct BarbellPlateCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var targetKilograms = 60.0
    @State private var barKilograms = 20.0

    private var plates: [Double] {
        BarbellPlateCalculator.platesPerSide(
            targetKilograms: targetKilograms,
            barKilograms: barKilograms
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("重量") {
                    LabeledContent("目标总重量") {
                        TextField("60", value: $targetKilograms, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("杠铃杆", selection: $barKilograms) {
                        Text("20 kg").tag(20.0)
                        Text("15 kg").tag(15.0)
                        Text("10 kg").tag(10.0)
                    }
                }

                Section("每侧配片") {
                    if plates.isEmpty {
                        Text(targetKilograms <= barKilograms ? "无需加片" : "没有可用配片组合")
                            .foregroundStyle(VelaTheme.muted)
                    } else {
                        Text(plates.map { $0.formatted(.number.precision(.fractionLength(0...2))) }.joined(separator: " + ") + " kg")
                            .font(.headline.monospacedDigit())
                        LabeledContent(
                            "实际总重量",
                            value: "\(BarbellPlateCalculator.achievableKilograms(targetKilograms: targetKilograms, barKilograms: barKilograms).formatted(.number.precision(.fractionLength(0...2)))) kg"
                        )
                    }
                    Text("按当前常见公制配片向下取最接近组合；训练前请核对杠铃杆和配片标识。")
                        .font(.caption)
                        .foregroundStyle(VelaTheme.muted)
                }
            }
            .navigationTitle("杠铃配片")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
