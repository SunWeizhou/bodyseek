import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct MuscleRecoveryDetailSheet: View {
    @Bindable var store: StoreOf<WorkoutFeature>
    public let muscle: BodyRegionMuscle

    public init(store: StoreOf<WorkoutFeature>, muscle: BodyRegionMuscle) {
        self.store = store
        self.muscle = muscle
    }

    public var body: some View {
        let est = store.recoverySnapshot.estimate(for: muscle)
        let matchingExercises = ExerciseCatalog.exercises(for: muscle)
        let recoveryColor: Color = est.recoveryRatio >= 0.85
            ? BevelTheme.recoveryColor
            : (est.recoveryRatio >= 0.55 ? BevelTheme.energyColor : BevelTheme.strainColor)

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BSSpace.m) {
                    BevelCard(padding: 16) {
                        VStack(alignment: .leading, spacing: BSSpace.s) {
                            HStack {
                                Text(muscle.title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(BevelTheme.ink)
                                Spacer()
                                Text("启发式估计")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, BSSpace.s)
                                    .padding(.vertical, BSSpace.xxs)
                                    .background(BevelTheme.surfaceElevated, in: Capsule())
                                    .foregroundStyle(BevelTheme.inkSecondary)
                                    .accessibilityIdentifier("muscle-recovery-heuristic-badge")
                            }

                            HStack(alignment: .firstTextBaseline, spacing: BSSpace.xs) {
                                Text("\(est.recoveryPercent)%")
                                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(recoveryColor)
                                    .contentTransition(.numericText())
                                Text("预计就绪度")
                                    .font(.subheadline)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }

                            ProgressView(value: est.recoveryRatio)
                                .tint(recoveryColor)

                            Text(est.readyETADescription)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(BevelTheme.ink)
                                .accessibilityIdentifier("muscle-recovery-eta-text")

                            Divider()

                            detailRow(
                                "上次受刺激时间",
                                value: est.lastTrainedAt.map { $0.formatted(.dateTime.month().day().hour().minute()) } ?? "近 7 天暂无记录"
                            )
                            if let title = est.lastWorkoutTitle {
                                detailRow("最近来源训练", value: title)
                            }
                            detailRow("模型参数", value: String(format: "τ = %.0fh · 有效 %.1fh (α = %.2f)", est.tauHours, est.effectiveTauHours, store.recoverySnapshot.systemicFactor.alpha))
                        }
                    }

                    BevelCard(padding: 14) {
                        VStack(alignment: .leading, spacing: BSSpace.xs) {
                            Label("全身衰减系数依据（无循环负荷依赖）", systemImage: "waveform.path.ecg")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BevelTheme.ink)
                            Text(store.recoverySnapshot.systemicFactor.summary)
                                .font(.footnote)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                    }

                    if !est.contributingEvents.isEmpty {
                        BevelCard(padding: 14) {
                            VStack(alignment: .leading, spacing: BSSpace.s) {
                                Text("近 7 天关联刺激记录")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                ForEach(est.contributingEvents) { ev in
                                    HStack {
                                        VStack(alignment: .leading, spacing: BSSpace.xxs) {
                                            Text(ev.workoutTitle)
                                                .font(.footnote.weight(.medium))
                                                .foregroundStyle(BevelTheme.ink)
                                            Text("\(ev.completedAt, format: .dateTime.month().day().hour().minute()) · \(ev.role == .primary ? "主受刺激" : "协同")\(ev.lateralNote.map { " · \($0)" } ?? "")")
                                                .font(.caption2)
                                                .foregroundStyle(BevelTheme.inkSecondary)
                                        }
                                        Spacer()
                                        Text(String(format: "负荷 %.2f", ev.load))
                                            .font(.caption.weight(.semibold).monospacedDigit())
                                            .fontDesign(.rounded)
                                            .foregroundStyle(BevelTheme.strainColor)
                                    }
                                    if ev.id != est.contributingEvents.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }

                    if !matchingExercises.isEmpty {
                        BevelCard(padding: 14) {
                            VStack(alignment: .leading, spacing: BSSpace.xs) {
                                Text("目标肌群动作参考")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                ForEach(matchingExercises.prefix(4)) { ex in
                                    HStack {
                                        Text(ex.name)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(BevelTheme.ink)
                                        Spacer()
                                        Text(ex.equipment)
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        store.send(.inspectMuscleRecovery(nil))
                        store.send(.askCoachForMuscleTapped(muscle))
                    } label: {
                        Label("让 AI 教练按该肌群状态排课", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, BSSpace.s)
                            .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: BSRadius.m, style: .continuous))
                            .foregroundStyle(BevelTheme.onBrand)
                    }
                    .buttonStyle(.bsPressable)

                    Text(est.disclaimer)
                        .font(.caption2)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .padding(.horizontal, BSSpace.xxs)
                }
                .padding(BSSpace.m)
            }
            .background(BevelTheme.canvas.ignoresSafeArea())
            .navigationTitle("\(muscle.title) · 启发式恢复")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("完成") {
                        store.send(.inspectMuscleRecovery(nil))
                    }
                    .accessibilityIdentifier("muscle-recovery-done")
                }
            }
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(BevelTheme.inkSecondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.ink)
                .multilineTextAlignment(.trailing)
        }
    }
}
