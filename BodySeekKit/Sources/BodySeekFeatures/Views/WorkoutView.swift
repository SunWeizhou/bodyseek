import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import MuscleMap
import SwiftUI

public struct WorkoutView: View {
    @Bindable var store: StoreOf<WorkoutFeature>
    @State private var showAllExercises = false

    public init(store: StoreOf<WorkoutFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error = store.lastError {
                    bannerCard(text: error, tint: BevelTheme.dangerColor, icon: "exclamationmark.triangle.fill")
                } else if let status = store.statusMessage {
                    bannerCard(text: status, tint: BevelTheme.brand, icon: "checkmark.circle.fill")
                }

                if let proposal = store.pendingProposal {
                    proposalCard(proposal)
                }

                acwrCard
                muscleHeatmapCard
                templatesSection
                exerciseCatalogSection
                watchWorkoutsSection
                loggedSessionsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(BevelTheme.canvas)
        .navigationTitle("健身")
        .toolbar {
            ToolbarItem(placement: .bodyseekTrailing) {
                Button {
                    store.send(.startQuickEmptyTapped)
                } label: {
                    Label("自由记录", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityIdentifier("workout.quickStart")
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.activeWorkout != nil },
                set: { presented in
                    if !presented {
                        store.send(.discardActiveWorkoutTapped)
                    }
                }
            )
        ) {
            ActiveWorkoutSheetView(store: store)
        }
    }

    // MARK: - Subviews

    private func bannerCard(text: String, tint: Color, icon: String) -> some View {
        BevelCard(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.ink)
                Spacer(minLength: 8)
                Button {
                    store.send(.clearStatusBanner)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func proposalCard(_ proposal: WorkoutProposal) -> some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("AI 智能体建议处方", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                    Spacer()
                    Text(proposal.template.focusTag)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BevelTheme.brandSoft, in: Capsule())
                        .foregroundStyle(BevelTheme.brand)
                }

                Text(proposal.template.title)
                    .font(.headline)
                    .foregroundStyle(BevelTheme.ink)

                Text(proposal.rationale)
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.inkSecondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(proposal.template.exercises) { item in
                            let name = ExerciseCatalog.find(id: item.exerciseID)?.name ?? item.exerciseID
                            Text("\(name) \(item.targetSets)×\(item.targetReps)")
                                .font(.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(BevelTheme.surfaceElevated, in: Capsule())
                                .foregroundStyle(BevelTheme.ink)
                        }
                    }
                }

                HStack(spacing: 10) {
                    Button {
                        store.send(.acceptProposalTapped(proposal, startImmediately: true))
                    } label: {
                        Text("立即按此开练")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(BevelTheme.onBrand)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.send(.acceptProposalTapped(proposal, startImmediately: false))
                    } label: {
                        Text("仅加入模板")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(BevelTheme.ink)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.send(.dismissProposalTapped)
                    } label: {
                        Text("忽略")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var acwrCard: some View {
        let load = store.snapshot.trainingLoad
        let zoneTint: Color = switch load.zone {
        case .sweetSpot: BevelTheme.recoveryColor
        case .highRisk: BevelTheme.dangerColor
        case .undertraining: BevelTheme.energyColor
        case .insufficientData: BevelTheme.inkSecondary
        }

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("急慢性负荷比 (ACWR)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.ink)
                        Text(load.zone.note)
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                    Spacer()
                    Text(load.zone.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(zoneTint.opacity(0.14), in: Capsule())
                        .foregroundStyle(zoneTint)
                }

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ACWR")
                            .font(.caption2)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Text(load.acwrRatio.map { String(format: "%.2f", $0) } ?? "--")
                            .font(.title2.weight(.bold).monospacedDigit())
                            .foregroundStyle(zoneTint)
                            .contentTransition(.numericText())
                    }

                    Divider().frame(height: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("近7天急负荷")
                            .font(.caption2)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Text("\(Int(load.acute7dLoad.rounded()))")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(BevelTheme.ink)
                            .contentTransition(.numericText())
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("近7天力量容量")
                            .font(.caption2)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        Text("\(Int(store.weeklyVolumeKg.rounded())) kg")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(BevelTheme.ink)
                            .contentTransition(.numericText())
                    }

                    Spacer()

                    Button {
                        store.send(.openTrendsTapped)
                    } label: {
                        Text("双轴对照")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var muscleHeatmapCard: some View {
        let intensities: [MuscleIntensity] = store.muscleLoadLast72h.compactMap { pair in
            guard let muscle = Muscle(rawValue: pair.key.rawValue) else { return nil }
            return MuscleIntensity(muscle: muscle, intensity: pair.value)
        }
        let selectedMapMuscle = store.selectedMuscle.flatMap { Muscle(rawValue: $0.rawValue) }
        let colorScale = HeatmapColorScale(colors: [
            BevelTheme.scoreTrack,
            BevelTheme.brand.opacity(0.55),
            BevelTheme.energyColor,
            BevelTheme.strainColor,
        ])
        let style = BodyViewStyle(
            defaultFillColor: BevelTheme.scoreTrack,
            strokeColor: BevelTheme.hairline,
            strokeWidth: 0.8,
            selectionColor: BevelTheme.brand.opacity(0.35),
            selectionStrokeColor: BevelTheme.brand,
            selectionStrokeWidth: 1.8,
            headColor: BevelTheme.scoreTrack,
            hairColor: BevelTheme.inkSecondary.opacity(0.45)
        )

        return BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("全身肌群热图（近72h负荷）")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.ink)
                        Text("点击任意肌群可筛选动作或发起专项训练")
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                    Spacer()
                    Picker("视角", selection: Binding(
                        get: { store.selectedBodySide },
                        set: { store.send(.bodySideChanged($0)) }
                    )) {
                        Text("正面").tag(BodySideOption.front)
                        Text("背面").tag(BodySideOption.back)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 112)
                    .accessibilityIdentifier("workout.bodySidePicker")
                }

                HStack(alignment: .top, spacing: 14) {
                    BodyView(
                        gender: .male,
                        side: store.selectedBodySide == .front ? .front : .back,
                        style: style
                    )
                    .heatmap(intensities, colorScale: colorScale)
                    .selected(selectedMapMuscle)
                    .onMuscleSelected { muscle, _ in
                        let mapped = BodyRegionMuscle(rawValue: muscle.rawValue)
                        store.send(.muscleSelected(mapped))
                    }
                    .bodyseekSelectionHaptic(trigger: store.selectedMuscle)
                    .frame(width: 148, height: 245)
                    .accessibilityIdentifier("workout.muscleMap")

                    VStack(alignment: .leading, spacing: 10) {
                        if let muscle = store.selectedMuscle {
                            let loadPct = Int(((store.muscleLoadLast72h[muscle] ?? 0) * 100).rounded())
                            Text(muscle.title)
                                .font(.headline)
                                .foregroundStyle(BevelTheme.ink)
                            Text("72h 负荷指数 \(loadPct)% · 匹配 \(store.filteredExercises.count) 个动作")
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)

                            Button {
                                store.send(.startMuscleTargetedWorkoutTapped(muscle))
                            } label: {
                                Label("开始\(muscle.title)专项", systemImage: "play.fill")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(BevelTheme.onBrand)
                            }
                            .buttonStyle(.plain)

                            Button {
                                store.send(.muscleSelected(nil))
                            } label: {
                                Text("清除筛选")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("近期重点受力")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BevelTheme.inkSecondary)
                            if store.loadedMusclesRanked.isEmpty {
                                Text("近 72 小时暂无已记录的力量训练负荷，可点击任意肌肉预览动作。")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            } else {
                                ForEach(store.loadedMusclesRanked.prefix(5), id: \.muscle) { entry in
                                    Button {
                                        store.send(.muscleSelected(entry.muscle))
                                    } label: {
                                        HStack {
                                            Text(entry.muscle.title)
                                                .font(.caption)
                                                .foregroundStyle(BevelTheme.ink)
                                            Spacer()
                                            Text("\(Int((entry.load * 100).rounded()))%")
                                                .font(.caption.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(entry.load > 0.65 ? BevelTheme.strainColor : BevelTheme.brand)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        Spacer(minLength: 4)

                        Button {
                            store.send(.askCoachForMuscleTapped(store.selectedMuscle))
                        } label: {
                            Label("让 AI 教练排课", systemImage: "sparkles")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(BevelTheme.brandSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .foregroundStyle(BevelTheme.brand)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 12) {
                    legendDot(color: BevelTheme.scoreTrack, label: "待激活")
                    legendDot(color: BevelTheme.brand.opacity(0.65), label: "适度刺激")
                    legendDot(color: BevelTheme.energyColor, label: "中等负荷")
                    legendDot(color: BevelTheme.strainColor, label: "需优先恢复")
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(BevelTheme.inkSecondary)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BevelTheme.inkSecondary)
            .padding(.horizontal, 4)
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("训练方案与分化")

            ForEach(store.templates) { template in
                BevelCard(padding: 14) {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(template.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                if template.isAIGenerated {
                                    Text("AI")
                                        .font(.caption2.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(BevelTheme.brandSoft, in: Capsule())
                                        .foregroundStyle(BevelTheme.brand)
                                }
                            }
                            Text(template.subtitle)
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .lineLimit(2)

                            HStack(spacing: 8) {
                                Text("\(template.exercises.count) 个动作")
                                Text("约 \(template.estimatedMinutes) 分钟")
                                Text(template.primaryMuscles.prefix(3).map(\.title).joined(separator: "·"))
                            }
                            .font(.caption2)
                            .foregroundStyle(BevelTheme.inkSecondary)
                        }

                        Spacer(minLength: 8)

                        Button {
                            store.send(.startTemplateTapped(template))
                        } label: {
                            Label("开练", systemImage: "play.fill")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(BevelTheme.brand, in: Capsule())
                                .foregroundStyle(BevelTheme.onBrand)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("workout.startTemplate.\(template.id.uuidString)")
                    }
                }
            }
        }
    }

    private var exerciseCatalogSection: some View {
        let items = showAllExercises ? store.filteredExercises : Array(store.filteredExercises.prefix(5))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(store.selectedMuscle.map { "\($0.title)推荐动作库" } ?? "动作库（free-exercise-db）")
                Spacer()
                if store.filteredExercises.count > 5 {
                    Button {
                        showAllExercises.toggle()
                    } label: {
                        Text(showAllExercises ? "收起" : "查看全部 (\(store.filteredExercises.count))")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BevelTheme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }

            BevelCard(padding: 12) {
                VStack(spacing: 10) {
                    ForEach(items) { ex in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(ex.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(BevelTheme.ink)
                                    Text(ex.equipment)
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(BevelTheme.surfaceElevated, in: Capsule())
                                        .foregroundStyle(BevelTheme.inkSecondary)
                                }
                                Text(ex.instructions)
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Text(ex.primaryMuscles.map(\.title).joined(separator: " / "))
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.brand)
                        }
                        if ex.id != items.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var watchWorkoutsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Apple Watch 训练与心率分区")

            if store.recentHealthWorkouts.isEmpty {
                BevelCard {
                    Text("近 14 天暂无同步自 Apple Watch 的体能训练记录。在手表或本页面完成一次训练后，心率 Z1–Z5 分区、TRIMP 与 Effort 分数将在此呈现。")
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
            } else {
                ForEach(store.recentHealthWorkouts.prefix(4)) { workout in
                    BevelCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Label(workout.activityName, systemImage: workout.symbolName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Spacer()
                                if let effort = workout.effortScore {
                                    Text(String(format: "努力度 %.1f", effort))
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(BevelTheme.strainColor.opacity(0.14), in: Capsule())
                                        .foregroundStyle(BevelTheme.strainColor)
                                }
                            }

                            HStack(spacing: 12) {
                                Text(workout.startDate, format: .dateTime.month().day().hour().minute())
                                Text("\(workout.durationMinutes) 分钟")
                                Text("\(Int(workout.activeEnergyKcal.rounded())) kcal")
                                if let hr = workout.averageHeartRate {
                                    Text("均心率 \(Int(hr.rounded()))")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)

                            if let zones = workout.heartRateZones, zones.totalZoneMinutes > 0 {
                                ZoneBar(zones: zones, showsTrimp: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var loggedSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("力量训练记录")

            if store.sessions.isEmpty {
                BevelCard {
                    Text("尚未记录力量组次。点击上方任意训练方案的「开练」即可记录重量、次数并写回 Apple 健康。")
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
            } else {
                ForEach(store.sessions.prefix(5)) { session in
                    BevelCard(padding: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Text(session.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BevelTheme.ink)
                                    if session.syncedHealthKitUUID != nil {
                                        Label("健康已同步", systemImage: "heart.fill")
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.recoveryColor)
                                    }
                                }
                                Text("\(session.durationMinutes) 分钟 · 总容量 \(Int(session.totalVolumeKg.rounded())) kg · RPE \(session.rpe)")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Spacer()
                            Text(session.completedAt, format: .dateTime.month().day())
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                        }
                    }
                }
            }
        }
    }
}
