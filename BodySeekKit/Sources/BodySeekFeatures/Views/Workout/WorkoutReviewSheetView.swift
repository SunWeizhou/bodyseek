import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct WorkoutReviewSheetView: View {
    @Bindable var store: StoreOf<WorkoutFeature>

    public init(store: StoreOf<WorkoutFeature>) {
        self.store = store
    }

    private let quickSamples = [
        "今天练胸和三头，平板卧推 5 组加双杠臂屈伸，RPE 8，右肩前束略紧",
        "拉力日，引体向上 5 组、高位下拉和坐姿划船，RPE 8",
        "腿日深蹲配罗马尼亚硬拉，RPE 9，右膝有点紧",
    ]

    public var body: some View {
        NavigationStack {
            Group {
                if let draft = store.reviewDraft {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            workoutMetaHeader(draft.workout)
                            inputSection(draft)
                            confirmationCard(draft)
                        }
                        .padding(16)
                    }
                }
            }
            .background(BevelTheme.canvas.ignoresSafeArea())
            .navigationTitle("一句话训练复盘")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekLeading) {
                    Button("关闭") {
                        store.send(.dismissReviewSheet)
                    }
                    .accessibilityIdentifier("workout-review-close")
                }
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button(draftSavingTitle) {
                        store.send(.confirmReviewTapped)
                    }
                    .fontWeight(.semibold)
                    .disabled(!canConfirmDraft(store.reviewDraft))
                    .accessibilityIdentifier("workout-review-confirm-top")
                }
            }
        }
    }

    private func canConfirmDraft(_ draft: WorkoutReviewDraft?) -> Bool {
        guard let draft else { return false }
        return !draft.isSaving && (!draft.primaryMuscles.isEmpty || !draft.secondaryMuscles.isEmpty)
    }

    private var draftSavingTitle: String {
        store.reviewDraft?.isSaving == true ? "保存中..." : "确认"
    }

    private func workoutMetaHeader(_ w: StoredWorkoutRecord) -> some View {
        let durationMin = max(1, Int((w.end.timeIntervalSince(w.start) / 60).rounded()))
        return BevelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(w.type, systemImage: "applewatch.radiowaves.left.and.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    Text(w.start, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                HStack(spacing: 12) {
                    Text("\(durationMin) 分钟")
                    Text("\(Int(w.energy.rounded())) kcal")
                    if let avgHR = w.avgHR {
                        Text("均心率 \(Int(avgHR.rounded())) bpm")
                    }
                    if let userEffort = w.effortUser {
                        Text(String(format: "手打用力 %.1f", userEffort))
                            .foregroundStyle(BevelTheme.strainColor)
                    } else if let est = w.effortEstimated {
                        Text(String(format: "Apple估算 %.1f", est))
                    }
                }
                .font(.caption.monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
    }

    private func inputSection(_ draft: WorkoutReviewDraft) -> some View {
        BevelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("练完后打字或听写一句话")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    if draft.isParsing {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }

                TextField(
                    "例如：今天推力日，上斜卧推 4 组加侧平举 RPE 8，右肩有点紧",
                    text: Binding(
                        get: { store.reviewDraft?.inputText ?? "" },
                        set: { store.send(.reviewTextChanged($0)) }
                    ),
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textFieldStyle(.plain)
                .padding(12)
                .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityIdentifier("workout-review-input")

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(quickSamples.enumerated()), id: \.offset) { idx, sample in
                            Button {
                                store.send(.reviewTextChanged(sample))
                                store.send(.parseReviewTapped)
                            } label: {
                                Text(sample)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(BevelTheme.surfaceElevated, in: Capsule())
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workout-review-chip-\(idx)")
                        }
                    }
                }

                Button {
                    store.send(.parseReviewTapped)
                } label: {
                    Label("智能解析肌群与身体信号", systemImage: "wand.and.stars")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(BevelTheme.brandSoft, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(BevelTheme.brand)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("workout-review-parse")
            }
        }
    }

    private func confirmationCard(_ draft: WorkoutReviewDraft) -> some View {
        let unusedMuscles = BodyRegionMuscle.allCases.filter {
            !draft.primaryMuscles.contains($0) && !draft.secondaryMuscles.contains($0)
        }
        return BevelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("确认卡（可点按切换/增删）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    if let source = draft.proposal?.parserSource {
                        Text(source.badgeTitle)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(BevelTheme.brandSoft, in: Capsule())
                            .foregroundStyle(BevelTheme.brand)
                    }
                }

                if let reason = draft.proposal?.degradationReason {
                    Text(reason)
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("主受刺激肌群（深色实心 · 点按降为次要）")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                    if draft.primaryMuscles.isEmpty && draft.secondaryMuscles.isEmpty {
                        Text("尚未指定肌群：请先输入并点击「智能解析」，或点击下方「增补肌群」选择本次训练肌群。")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.strainColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    muscleChipFlow(
                        muscles: draft.primaryMuscles,
                        isPrimary: true
                    )

                    if !draft.secondaryMuscles.isEmpty {
                        Text("辅助协同肌群（点按升为主受刺激）")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .padding(.top, 4)
                        muscleChipFlow(
                            muscles: draft.secondaryMuscles,
                            isPrimary: false
                        )
                    }

                    if !unusedMuscles.isEmpty {
                        HStack {
                            Menu {
                                Section("为主受刺激肌群添加") {
                                    ForEach(unusedMuscles) { m in
                                        Button("+ 主肌群：\(m.title)") {
                                            store.send(.addMuscleToDraft(m, asPrimary: true))
                                        }
                                    }
                                }
                                Section("为协同肌群添加") {
                                    ForEach(unusedMuscles) { m in
                                        Button("+ 次肌群：\(m.title)") {
                                            store.send(.addMuscleToDraft(m, asPrimary: false))
                                        }
                                    }
                                }
                            } label: {
                                Label("增补肌群", systemImage: "plus.circle")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(BevelTheme.brand)
                            }
                            .accessibilityIdentifier("workout-review-add-muscle")
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }

                Divider()

                Stepper(
                    value: Binding(
                        get: { store.reviewDraft?.rpe ?? 7 },
                        set: { store.send(.reviewRPEChanged($0)) }
                    ),
                    in: 1...10
                ) {
                    HStack {
                        Text("主观疲劳度 RPE")
                            .font(.subheadline)
                            .foregroundStyle(BevelTheme.ink)
                        Spacer()
                        Text("\(draft.rpe) / 10")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundStyle(BevelTheme.strainColor)
                    }
                }

                if !draft.exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("识别动作")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Text(draft.exercises.joined(separator: " · "))
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(BevelTheme.ink)
                    }
                }

                if !draft.bodySignals.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 8) {
                        Label("身体信号 → 自动创建 14 天约束记忆", systemImage: "exclamationmark.shield")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.energyColor)
                        ForEach(draft.bodySignals) { signal in
                            Toggle(
                                isOn: Binding(
                                    get: { signal.includeAsMemory },
                                    set: { _ in store.send(.toggleBodySignalMemory(signal.id)) }
                                )
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(signal.region)\(signal.symptom)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(BevelTheme.ink)
                                    Text(signal.suggestedConstraint)
                                        .font(.caption2)
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                            }
                            .tint(BevelTheme.brand)
                        }
                    }
                }

                if let errorMessage = draft.errorMessage {
                    Text(errorMessage)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BevelTheme.dangerColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("workout-review-error")
                }

                let confirmEnabled = canConfirmDraft(draft)
                Button {
                    store.send(.confirmReviewTapped)
                } label: {
                    Text(draft.isSaving ? "正在保存并重算恢复..." : "确认并更新肌群恢复")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(confirmEnabled ? BevelTheme.brand : BevelTheme.scoreTrack, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(confirmEnabled ? BevelTheme.onBrand : BevelTheme.inkSecondary)
                }
                .buttonStyle(.plain)
                .disabled(!confirmEnabled)
                .accessibilityIdentifier("workout-review-confirm")
            }
        }
    }

    private func muscleChipFlow(muscles: [BodyRegionMuscle], isPrimary: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(muscles) { muscle in
                    HStack(spacing: 4) {
                        Button {
                            store.send(.toggleMuscleInDraft(muscle))
                        } label: {
                            Text(muscle.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isPrimary ? BevelTheme.onBrand : BevelTheme.ink)
                        }
                        .buttonStyle(.plain)

                        Button {
                            store.send(.removeMuscleFromDraft(muscle))
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                                .foregroundStyle(isPrimary ? BevelTheme.onBrand.opacity(0.85) : BevelTheme.inkSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        isPrimary ? BevelTheme.brand : BevelTheme.surfaceElevated,
                        in: Capsule()
                    )
                }
            }
        }
    }
}
