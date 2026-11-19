import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct ActiveWorkoutSheetView: View {
    @Bindable var store: StoreOf<WorkoutFeature>

    public init(store: StoreOf<WorkoutFeature>) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let draft = store.activeWorkout {
                    ScrollView {
                        VStack(spacing: 14) {
                            summaryStrip(draft)

                            if let restRemaining = draft.restSecondsRemaining {
                                restBanner(seconds: restRemaining)
                            }

                            ForEach(Array(draft.exercises.enumerated()), id: \.element.id) { exIdx, record in
                                exerciseCard(record, exIdx: exIdx)
                            }

                            Button {
                                store.send(.activeWorkoutAddExercisePresented(true))
                            } label: {
                                Label("从动作库新增动作", systemImage: "plus.circle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(BevelTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                    .foregroundStyle(BevelTheme.brand)
                            }
                            .buttonStyle(.plain)

                            rpeCard(current: draft.rpe)
                        }
                        .padding(16)
                    }
                    .background(BevelTheme.canvas)
                    .navigationTitle(draft.title)
                    .bodyseekNavigationBarInline()
                    .toolbar {
                        ToolbarItem(placement: .bodyseekLeading) {
                            Button("放弃") {
                                store.send(.discardActiveWorkoutTapped)
                            }
                            .foregroundStyle(BevelTheme.dangerColor)
                        }
                        ToolbarItem(placement: .bodyseekTrailing) {
                            Button {
                                store.send(.completeActiveWorkoutTapped)
                            } label: {
                                if store.isSavingWorkout {
                                    ProgressView()
                                } else {
                                    Text("完成并写回健康")
                                        .fontWeight(.semibold)
                                }
                            }
                            .disabled(store.isSavingWorkout)
                            .accessibilityIdentifier("workout.finishSession")
                        }
                    }
                    .sheet(
                        isPresented: Binding(
                            get: { store.isExercisePickerPresented },
                            set: { store.send(.activeWorkoutAddExercisePresented($0)) }
                        )
                    ) {
                        exercisePickerSheet
                    }
                }
            }
        }
    }

    private func summaryStrip(_ draft: ActiveWorkoutDraft) -> some View {
        BevelCard(padding: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("已完成组次")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                    Text("\(draft.completedSetCount) / \(draft.totalSetCount) 组")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(BevelTheme.ink)
                        .contentTransition(.numericText())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("累计容量")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                    Text("\(Int(draft.totalCompletedVolumeKg.rounded())) kg")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(BevelTheme.brand)
                        .contentTransition(.numericText())
                }
            }
        }
    }

    private func restBanner(seconds: Int) -> some View {
        BevelCard(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "timer")
                    .font(.title3)
                    .foregroundStyle(BevelTheme.brand)
                VStack(alignment: .leading, spacing: 1) {
                    Text("组间休息倒计时")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                    Text("\(seconds) 秒（结束将同步手表通知）")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(BevelTheme.ink)
                        .contentTransition(.numericText())
                }
                Spacer()
                Button("+15s") {
                    store.send(.adjustRestTimerTapped(15))
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)

                Button("跳过") {
                    store.send(.skipRestTimerTapped)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.plain)
                .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
    }

    private func exerciseCard(_ record: LoggedExerciseRecord, exIdx: Int) -> some View {
        let def = ExerciseCatalog.find(id: record.exerciseID)
        return BevelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(def?.name ?? record.exerciseID)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.ink)
                        if let def {
                            Text("\(def.equipment) · \(def.primaryMuscles.map(\.title).joined(separator: "、"))")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                    }
                    Spacer()
                    Text("休息 \(record.restSeconds)s")
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                HStack {
                    Text("组次").frame(width: 34, alignment: .leading)
                    Text("重量 (kg)").frame(maxWidth: .infinity, alignment: .center)
                    Text("次数").frame(maxWidth: .infinity, alignment: .center)
                    Text("完成").frame(width: 44, alignment: .trailing)
                }
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)

                ForEach(Array(record.sets.enumerated()), id: \.element.id) { setIdx, entry in
                    HStack(spacing: 8) {
                        Text("#\(entry.setIndex)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .frame(width: 34, alignment: .leading)

                        Stepper(
                            value: Binding(
                                get: { entry.weightKg },
                                set: { store.send(.activeWorkoutWeightChanged(exerciseIndex: exIdx, setIndex: setIdx, weightKg: $0)) }
                            ),
                            in: 0...400,
                            step: 2.5
                        ) {
                            Text(String(format: "%.1f", entry.weightKg))
                                .font(.subheadline.monospacedDigit())
                                .frame(minWidth: 42)
                        }
                        .frame(maxWidth: .infinity)

                        Stepper(
                            value: Binding(
                                get: { entry.reps },
                                set: { store.send(.activeWorkoutRepsChanged(exerciseIndex: exIdx, setIndex: setIdx, reps: $0)) }
                            ),
                            in: 1...60,
                            step: 1
                        ) {
                            Text("\(entry.reps)")
                                .font(.subheadline.monospacedDigit())
                                .frame(minWidth: 26)
                        }
                        .frame(maxWidth: .infinity)

                        Button {
                            store.send(.activeWorkoutToggleSetCompleted(exerciseIndex: exIdx, setIndex: setIdx))
                        } label: {
                            Image(systemName: entry.isCompleted ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(entry.isCompleted ? BevelTheme.recoveryColor : BevelTheme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .frame(width: 44, alignment: .trailing)
                        .accessibilityIdentifier("workout.completeSet.\(exIdx).\(setIdx)")
                    }
                }

                Button {
                    store.send(.activeWorkoutAddSetTapped(exerciseIndex: exIdx))
                } label: {
                    Label("新增一组", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func rpeCard(current: Int) -> some View {
        BevelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("主观疲劳度 (Session RPE)")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("RPE \(current) / 10")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(BevelTheme.brand)
                }
                HStack(spacing: 6) {
                    ForEach(5...10, id: \.self) { level in
                        Button {
                            store.send(.activeWorkoutRPEChanged(level))
                        } label: {
                            Text("\(level)")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    level == current ? BevelTheme.brand : BevelTheme.surfaceElevated,
                                    in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                )
                                .foregroundStyle(level == current ? BevelTheme.onBrand : BevelTheme.ink)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var exercisePickerSheet: some View {
        NavigationStack {
            List(ExerciseCatalog.all) { ex in
                Button {
                    store.send(.activeWorkoutAddExerciseTapped(ex))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(BevelTheme.ink)
                            Text("\(ex.equipment) · \(ex.primaryMuscles.map(\.title).joined(separator: "、"))")
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                        Spacer()
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(BevelTheme.brand)
                    }
                }
            }
            .navigationTitle("选择动作")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekLeading) {
                    Button("关闭") {
                        store.send(.activeWorkoutAddExercisePresented(false))
                    }
                }
            }
        }
    }
}
