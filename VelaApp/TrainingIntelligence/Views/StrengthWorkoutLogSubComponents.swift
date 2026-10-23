import SwiftUI
import SwiftData

enum StrengthProgressionStatus: String, Equatable {
    case ready
    case hold
    case collecting
}

struct StrengthProgressionAdvice: Identifiable, Equatable {
    let exerciseName: String
    let status: StrengthProgressionStatus
    let evidence: String
    let action: String
    var id: String { exerciseName }
}

enum StrengthProgressionAdvisor {
    static func advise(
        current: StrengthWorkoutRecord,
        history: [StrengthWorkoutRecord]
    ) -> [StrengthProgressionAdvice] {
        current.exercises.map { exercise in
            let priorExercises = history
                .filter { $0.startedAt < current.startedAt }
                .sorted { $0.startedAt > $1.startedAt }
                .compactMap { workout in
                    workout.exercises.first(where: { matches($0, exercise) })
                }
                .prefix(2)
            let sessions = [exercise] + Array(priorExercises)

            guard sessions.count == 3 else {
                return StrengthProgressionAdvice(
                    exerciseName: exercise.name,
                    status: .collecting,
                    evidence: "需要当前训练和至少 2 次同动作历史。",
                    action: "先保持熟悉的重量与动作质量，继续记录完成组和 RPE/RIR。"
                )
            }

            let summaries = sessions.map(sessionSummary)
            guard summaries.allSatisfy({ $0.completedWorkingSets >= 2 }),
                  summaries.allSatisfy({ $0.averageEffort != nil }) else {
                return StrengthProgressionAdvice(
                    exerciseName: exercise.name,
                    status: .collecting,
                    evidence: "最近 3 次训练的完成组或 RPE/RIR 记录不完整。",
                    action: "补全主训练组和主观用力记录后再判断是否加量。"
                )
            }

            let currentSummary = summaries[0]
            let efforts = summaries.compactMap(\.averageEffort)
            if currentSummary.hasFailureOrIncomplete || (currentSummary.averageEffort ?? 0) >= 9 {
                return StrengthProgressionAdvice(
                    exerciseName: exercise.name,
                    status: .hold,
                    evidence: "本次出现未完成/力竭组，或平均 RPE 已达到 9。",
                    action: "下次先维持或小幅降低重量，完成目标次数且动作稳定后再考虑加量。"
                )
            }

            let priorMaxWeight = summaries.dropFirst().map(\.maxWeight).max() ?? 0
            let priorAverageReps = summaries.dropFirst().map(\.averageReps).min() ?? 0
            if efforts.allSatisfy({ $0 <= 8 }),
               currentSummary.maxWeight >= priorMaxWeight,
               currentSummary.averageReps >= priorAverageReps {
                return StrengthProgressionAdvice(
                    exerciseName: exercise.name,
                    status: .ready,
                    evidence: "连续 3 次完成至少 2 个主训练组，平均 RPE ≤ 8，重量和平均次数未回退。",
                    action: minimumIncrementAction(equipment: exercise.equipment)
                )
            }

            return StrengthProgressionAdvice(
                exerciseName: exercise.name,
                status: .hold,
                evidence: "最近 3 次的用力程度、重量或平均次数尚未同时稳定。",
                action: "下次保持当前重量，优先让完成次数和动作质量稳定。"
            )
        }
    }

    private struct SessionSummary {
        var completedWorkingSets: Int
        var averageEffort: Double?
        var maxWeight: Double
        var averageReps: Double
        var hasFailureOrIncomplete: Bool
    }

    private static func sessionSummary(_ exercise: StrengthExerciseLog) -> SessionSummary {
        let working = exercise.sets.filter { $0.kind != .warmup }
        let completed = working.filter { $0.isCompleted ?? true }
        let efforts = completed.compactMap { set -> Double? in
            if let rpe = set.rpe { return rpe }
            if let rir = set.rir { return min(10, max(0, 10 - rir)) }
            return nil
        }
        return SessionSummary(
            completedWorkingSets: completed.count,
            averageEffort: efforts.count == completed.count && !efforts.isEmpty
                ? efforts.reduce(0, +) / Double(efforts.count)
                : nil,
            maxWeight: completed.map(\.weightKilograms).max() ?? 0,
            averageReps: completed.isEmpty
                ? 0
                : Double(completed.map(\.repetitions).reduce(0, +)) / Double(completed.count),
            hasFailureOrIncomplete: working.contains {
                $0.kind == .failure || $0.isCompleted == false
            }
        )
    }

    private static func matches(_ lhs: StrengthExerciseLog, _ rhs: StrengthExerciseLog) -> Bool {
        if let lhsKey = lhs.exerciseCanonicalKey,
           let rhsKey = rhs.exerciseCanonicalKey,
           !lhsKey.isEmpty, !rhsKey.isEmpty {
            return lhsKey == rhsKey
        }
        return lhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            == rhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func minimumIncrementAction(equipment: String) -> String {
        let normalized = equipment.lowercased()
        if normalized.contains("dumbbell") || normalized.contains("哑铃") {
            return "若当天恢复和热身正常，下次可尝试每只哑铃增加最小可用档位；任何一组动作变形或 RPE > 9 即停止加量。"
        }
        if normalized.contains("bodyweight") || normalized.contains("自重") {
            return "若当天恢复和热身正常，下次只增加 1–2 次或一个更难的小进阶；动作质量下降即回到当前版本。"
        }
        return "若当天恢复和热身正常，下次可尝试器械最小可用增量（杠铃通常总计 2.5 kg）；动作变形或 RPE > 9 即停止加量。"
    }
}

// MARK: - RestTimerState

struct RestTimerState {
    var endsAt: Date
    var exerciseName: String
    var setNumber: Int
}

enum StrengthExerciseGroupingPlanner {
    static func group(
        _ exercises: [StrengthExerciseLog],
        selectedIDs: Set<UUID>,
        kind: StrengthExerciseGroupKind,
        groupID: UUID = UUID()
    ) -> [StrengthExerciseLog] {
        let selected = exercises.filter { selectedIDs.contains($0.id) }
        guard selected.count >= 2, kind == .circuit || selected.count == 2 else { return exercises }

        let replacedGroupIDs = Set(selected.compactMap(\.groupID))
        var cleared = exercises.map { exercise in
            var copy = exercise
            if selectedIDs.contains(copy.id) || copy.groupID.map(replacedGroupIDs.contains) == true {
                copy.groupID = nil
                copy.groupKind = nil
                copy.groupPosition = nil
            }
            return copy
        }
        let firstSelectedIndex = exercises.firstIndex { selectedIDs.contains($0.id) } ?? exercises.endIndex
        let insertionIndex = exercises[..<firstSelectedIndex].filter { !selectedIDs.contains($0.id) }.count
        let grouped = selected.enumerated().map { position, exercise in
            var copy = exercise
            copy.groupID = groupID
            copy.groupKind = kind
            copy.groupPosition = position
            return copy
        }
        cleared.removeAll { selectedIDs.contains($0.id) }
        cleared.insert(contentsOf: grouped, at: min(insertionIndex, cleared.count))
        return normalize(cleared)
    }

    static func ungroup(_ exercises: [StrengthExerciseLog], groupID: UUID) -> [StrengthExerciseLog] {
        exercises.map { exercise in
            guard exercise.groupID == groupID else { return exercise }
            var copy = exercise
            copy.groupID = nil
            copy.groupKind = nil
            copy.groupPosition = nil
            return copy
        }
    }

    private static func normalize(_ exercises: [StrengthExerciseLog]) -> [StrengthExerciseLog] {
        let counts = Dictionary(grouping: exercises.compactMap(\.groupID), by: { $0 }).mapValues(\.count)
        return exercises.map { exercise in
            guard let groupID = exercise.groupID, (counts[groupID] ?? 0) < 2 else { return exercise }
            var copy = exercise
            copy.groupID = nil
            copy.groupKind = nil
            copy.groupPosition = nil
            return copy
        }
    }
}

enum WristStrengthEditApplier {
    static func apply(
        _ edits: [WristStrengthSetEdit],
        draftID: UUID,
        to exercises: [StrengthExerciseLog]
    ) -> [StrengthExerciseLog] {
        let relevant = edits.filter { $0.draftID == draftID }
        guard !relevant.isEmpty else { return exercises }
        return exercises.map { exercise in
            var copy = exercise
            copy.sets = exercise.sets.map { set in
                guard let edit = relevant.last(where: {
                    $0.exerciseID == exercise.id && $0.setID == set.id
                }) else { return set }
                var updated = set
                updated.repetitions = min(999, max(0, edit.repetitions))
                updated.weightKilograms = min(999.9, max(0, edit.weightKilograms))
                updated.isCompleted = edit.isCompleted
                updated.completedAt = edit.isCompleted ? (set.completedAt ?? Date()) : nil
                return updated
            }
            return copy
        }
    }
}

struct StrengthExerciseGroupingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var exercises: [StrengthExerciseLog]
    @State private var selectedIDs: Set<UUID> = []
    @State private var kind: StrengthExerciseGroupKind = .superset

    private var existingGroups: [(id: UUID, kind: StrengthExerciseGroupKind, names: String)] {
        Dictionary(grouping: exercises.compactMap { exercise -> (UUID, StrengthExerciseLog)? in
            exercise.groupID.map { ($0, exercise) }
        }, by: { $0.0 })
        .compactMap { id, values in
            guard let groupKind = values.first?.1.groupKind else { return nil }
            return (id, groupKind, values.map { $0.1.name }.joined(separator: " → "))
        }
        .sorted { $0.names < $1.names }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("组合类型") {
                    Picker("类型", selection: $kind) {
                        ForEach(StrengthExerciseGroupKind.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(kind == .superset ? "超级组需要恰好 2 个动作，动作间连续切换。" : "循环组需要至少 2 个动作，按顺序循环完成。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("选择动作") {
                    ForEach(exercises) { exercise in
                        Button {
                            if selectedIDs.contains(exercise.id) {
                                selectedIDs.remove(exercise.id)
                            } else if kind == .circuit || selectedIDs.count < 2 {
                                selectedIDs.insert(exercise.id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                        .foregroundStyle(VelaTheme.fg)
                                    if let groupKind = exercise.groupKind {
                                        Text("当前属于 \(groupKind.displayName)")
                                            .font(.caption2)
                                            .foregroundStyle(VelaTheme.muted)
                                    }
                                }
                                Spacer()
                                Image(systemName: selectedIDs.contains(exercise.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIDs.contains(exercise.id) ? VelaTheme.accent : VelaTheme.muted)
                            }
                        }
                    }
                }

                if !existingGroups.isEmpty {
                    Section("已有组合") {
                        ForEach(existingGroups, id: \.id) { group in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.kind.displayName)
                                    Text(group.names)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("解散", role: .destructive) {
                                    exercises = StrengthExerciseGroupingPlanner.ungroup(exercises, groupID: group.id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Superset / Circuit")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: kind) { _, newKind in
                if newKind == .superset, selectedIDs.count > 2 {
                    selectedIDs = Set(exercises.filter { selectedIDs.contains($0.id) }.prefix(2).map(\.id))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        exercises = StrengthExerciseGroupingPlanner.group(
                            exercises,
                            selectedIDs: selectedIDs,
                            kind: kind
                        )
                        dismiss()
                    }
                    .disabled(selectedIDs.count < 2 || (kind == .superset && selectedIDs.count != 2))
                }
            }
        }
    }
}

// MARK: - StrengthWorkoutSessionViewModel

@MainActor
final class StrengthWorkoutSessionViewModel: ObservableObject {
    private var draftSaveTask: Task<Void, Never>?

    func scheduleDraftSave(_ action: @escaping @MainActor () -> Void) {
        draftSaveTask?.cancel()
        draftSaveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func saveImmediately(_ action: @escaping @MainActor () -> Void) {
        draftSaveTask?.cancel()
        action()
    }

    deinit {
        draftSaveTask?.cancel()
    }
}

// MARK: - StrengthWorkoutSessionPrefill

enum StrengthWorkoutSessionPrefill {
    static func previousCompletedSets(
        for exerciseName: String,
        in workoutHistory: [StrengthWorkoutRecord]
    ) -> [StrengthSetLog] {
        let normalizedName = exerciseName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedName.isEmpty,
              let previous = workoutHistory.lazy
                .flatMap(\.exercises)
                .first(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName }) else {
            return []
        }
        return previous.sets.filter { !$0.isWarmup && $0.isCompleted == true }
    }
}

// MARK: - Exercise Picker Sheet

struct ExercisePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var customDefinitions: [ExerciseDefinitionRecord] = []
    @State private var query = ""
    @State private var saveError: String?
    let onSelect: (ExerciseDefinitionRecord) -> Void

    private var definitions: [ExerciseDefinitionRecord] {
        let defaults = ExerciseLibraryService.defaultDefinitions()
        let names = Set(customDefinitions.map(\.name))
        return ExerciseLibraryService.search(query, in: customDefinitions + defaults.filter { !names.contains($0.name) })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(definitions) { definition in
                    Button {
                        onSelect(definition)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(definition.name)
                            Text("\(localizedMuscle(definition.primaryMuscleGroup)) · \(localizedEquipment(definition.equipment))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !definitions.contains(where: { $0.name == query }) {
                    Button("新增自定义动作「\(query)」") {
                        let definition = ExerciseDefinitionRecord(
                            name: query,
                            primaryMuscleGroup: "other",
                            equipment: "other",
                            movementPattern: "other",
                            isCustom: true
                        )
                        modelContext.insert(definition)
                        do {
                            try modelContext.save()
                            VelaAppState.shared.markLocalDataChanged()
                            onSelect(definition)
                            dismiss()
                        } catch {
                            modelContext.rollback()
                            saveError = "自定义动作未保存。请稍后重试。"
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "搜索动作或肌群")
            .navigationTitle("添加动作")
        }
        .task {
            try? ExerciseLibraryService.seedDefaultsIfNeeded(modelContext: modelContext)
            customDefinitions = (try? ExerciseDefinitionRepository(modelContext: modelContext).fetchAllSortedByName()) ?? []
        }
        .alert("无法保存动作", isPresented: Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )) {
            Button("好", role: .cancel) { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    private func localizedMuscle(_ muscle: String) -> String {
        [
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

    private func localizedEquipment(_ equipment: String) -> String {
        [
            "barbell": "杠铃",
            "dumbbell": "哑铃",
            "machine": "器械",
            "cable": "绳索",
            "bodyweight": "自重",
            "kettlebell": "壶铃",
            "other": "其他"
        ][equipment] ?? equipment
    }
}

// MARK: - Strength Workout Summary Sheet

struct StrengthWorkoutSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let summary: StrengthWorkoutAnalysis
    let workout: StrengthWorkoutRecord?
    let onSaveTemplate: () -> Bool
    let onDone: () -> Void
    @State private var isTemplateSaved = false

    private var muscleSetSummary: String {
        let lines = summary.muscleGroupSets
            .sorted { $0.value > $1.value }
            .map { "\(localizedMuscle($0.key))：\($0.value) 组" }
        return lines.isEmpty ? "本次没有形成可计入分析的有效组。" : lines.joined(separator: "\n")
    }

    private var recoveryRecommendation: String {
        guard summary.effectiveSets > 0 else {
            return "本次没有形成足够的有效训练量。下一次训练前，优先根据动作完成度、主观疲劳和当天恢复信号重新安排。"
        }
        let muscles = summary.muscleGroupSets
            .sorted { $0.value > $1.value }
            .prefix(2)
            .map { localizedMuscle($0.key) }
            .joined(separator: "、")
        let loadText = summary.effectiveSets >= 12 ? "本次有效训练量较高" : "本次训练量处于可跟踪范围"
        let focusText = muscles.isEmpty ? "涉及肌群" : "\(muscles)等涉及肌群"
        return "\(loadText)。接下来 24–48 小时留意\(focusText)的酸痛、动作稳定性和精神状态；如这些信号明显变差，下一次同部位训练应减量或改做低强度活动。"
    }

    private var nutritionRecommendation: String {
        "训练后的进食以全天总能量、蛋白质与碳水安排为先。选择你方便的下一餐补充蛋白质、主食与水分即可；无需为了固定的时间窗口强行进食。"
    }

    private var nextSessionRecommendation: String {
        if summary.uncompletedSets > 0 {
            return "本次仍有 \(summary.uncompletedSets) 组未完成。下次优先复盘重量、次数或休息时间，而不是直接加量。"
        }
        if summary.effectiveSets >= 12 {
            return "下一次同部位训练前先查看今日恢复和局部疲劳；恢复不足时可保留动作，但降低组数或强度。"
        }
        return "下一次训练可从本次已完成的动作和重量开始，再根据动作质量与主观用力程度小幅调整。"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("训练已保存", systemImage: "checkmark.circle.fill")
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text(workout?.title ?? "力量训练")
                            .font(.system(.title2, design: .default, weight: .bold))
                        Text("基于本次已完成的训练组生成")
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(VelaTheme.muted)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        metric("时长", "\(workout?.durationMinutes ?? 0) 分钟")
                        metric("总容量", "\(Int(summary.totalVolumeKg.rounded())) kg")
                        metric("计划组", "\(summary.plannedSets)")
                        metric("完成组", "\(summary.completedSets)")
                        metric("有效组", "\(summary.effectiveSets)")
                        metric("未完成", "\(summary.uncompletedSets)")
                        metric("总次数", "\(summary.totalReps)")
                        metric("训练密度", "\(Int(summary.densityKgPerMinute.rounded())) kg/min")
                    }
                    summaryCard("肌群组数", muscleSetSummary)
                    summaryCard("e1RM", summary.estimatedOneRepMaxByExercise.sorted { $0.key < $1.key }.map { "\($0.key): \(Int($0.value.rounded())) kg" }.joined(separator: "\n"))
                    summaryCard("PR", summary.personalRecords.isEmpty ? "历史数据不足，完成更多训练后会自动识别 PR。" : summary.personalRecords.map(\.summary).joined(separator: "\n"))
                    summaryCard("恢复建议", recoveryRecommendation)
                    summaryCard("次日恢复观察提示", "由于你今天完成了力量训练，Vela 将在明天特别关注你的睡眠质量、HRV 和静息心率 (RHR)，以评估本次训练对你身体产生的生理恢复代价与适应反馈。")
                    summaryCard("饮食与补水", nutritionRecommendation)
                    summaryCard("下次训练", nextSessionRecommendation)
                    Button {
                        isTemplateSaved = onSaveTemplate()
                    } label: {
                        Label(isTemplateSaved ? "已保存到模板库" : "保存为训练模板", systemImage: isTemplateSaved ? "checkmark" : "bookmark")
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isTemplateSaved)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(VelaTheme.systemGroupedBackground)
            .navigationTitle("训练完成")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onDone()
                        dismiss()
                    }
                }
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(.subheadline, design: .rounded, weight: .bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .velaNativeCard(radius: 14)
    }

    private func summaryCard(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(.footnote, design: .rounded, weight: .bold))
            Text(body.isEmpty ? "暂无数据" : body).font(.system(.footnote, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .velaNativeCard(radius: 16)
    }

    private func localizedMuscle(_ muscle: String) -> String {
        [
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
}

extension StrengthWorkoutAnalysis: Identifiable {
    public var id: String { summaryText + "\(totalSets)" }
}
