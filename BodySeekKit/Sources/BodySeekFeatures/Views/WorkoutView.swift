import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import MuscleMap
import SwiftUI

public struct WorkoutView: View {
    @Bindable var store: StoreOf<WorkoutFeature>
    @State private var showAllExercises = false
    @Environment(\.scenePhase) private var scenePhase

    public init(store: StoreOf<WorkoutFeature>) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if let error = store.lastError {
                    bannerCard(text: error, tint: BevelTheme.dangerColor, icon: "exclamationmark.triangle.fill")
                } else if let status = store.statusMessage {
                    bannerCard(text: status, tint: BevelTheme.brand, icon: "checkmark.circle.fill")
                }

                if let proposal = store.pendingProposal {
                    proposalCard(proposal)
                }

                if !store.unreviewedWorkouts.isEmpty {
                    reviewInboxSection
                }

                acwrCard
                muscleHeatmapCard
                watchArchiveSection
                manualSupplementarySection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle("健身")
        .bodyseekNavigationBarInline()
        .toolbar {
            ToolbarItem(placement: .bodyseekTrailing) {
                Button {
                    store.send(.startQuickEmptyTapped)
                } label: {
                    Label("手动补录", systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                }
                .accessibilityIdentifier("workout.quickStart")
            }
        }
        .onAppear {
            store.send(.onAppear)
        }
        .refreshable {
            await store.send(.refreshRequested).finish()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                store.send(.recoveryTick)
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
        .sheet(
            isPresented: Binding(
                get: { store.reviewDraft != nil },
                set: { presented in
                    if !presented {
                        store.send(.dismissReviewSheet)
                    }
                }
            )
        ) {
            WorkoutReviewSheetView(store: store)
        }
        .sheet(
            item: Binding(
                get: { store.inspectedMuscleForRecovery },
                set: { store.send(.inspectMuscleRecovery($0)) }
            )
        ) { muscle in
            MuscleRecoveryDetailSheet(store: store, muscle: muscle)
        }
        .sheet(
            item: Binding(
                get: { store.inspectedWorkoutDetail },
                set: { store.send(.inspectWorkoutDetail($0)) }
            )
        ) { workout in
            WorkoutDetailSheetView(store: store, workout: workout)
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
                    Label("AI 训练建议", systemImage: "sparkles")
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
                        Text("立即开练")
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
                        Text("存为训练模板")
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

    private var reviewInboxSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("待复盘", systemImage: "tray.and.arrow.down.fill")
                    .font(.headline)
                    .foregroundStyle(BevelTheme.ink)
                Spacer()
                Text("\(store.unreviewedWorkouts.count) 条")
                    .font(.subheadline)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
            .padding(.horizontal, 4)

            ForEach(store.unreviewedWorkouts.prefix(3)) { workout in
                let durationMin = max(1, Int((workout.end.timeIntervalSince(workout.start) / 60).rounded()))
                BevelCard(padding: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.type)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Text("\(workout.start, format: .dateTime.month().day().hour().minute()) · \(durationMin) 分钟")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Button {
                                store.send(.openReviewTapped(workout))
                            } label: {
                                Label("一句话复盘", systemImage: "text.bubble.fill")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(BevelTheme.onBrand)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workout-inbox-review-\(workout.hkUUID)")

                            Button {
                                store.send(.skipReviewTapped(workout))
                            } label: {
                                Text("跳过")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 9)
                                    .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workout-inbox-skip-\(workout.hkUUID)")
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-review-inbox")
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
                    Text("训练负荷")
                        .font(.headline)
                        .foregroundStyle(BevelTheme.ink)
                    Spacer()
                    Button("查看趋势") {
                        store.send(.openTrendsTapped)
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                }

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(load.acwrRatio.map { String(format: "%.2f", $0) } ?? "—")
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(BevelTheme.ink)
                        .contentTransition(.numericText())
                    Text(loadStatusLabel(load.zone))
                        .font(.subheadline)
                        .foregroundStyle(zoneTint)
                }

                DisclosureGroup("如何理解这个数") {
                    Text(load.acwrRatio == nil
                         ? "需要更多训练记录，才能比较最近与平时的负荷。"
                         : "比较最近 7 天与近 28 天的训练负荷。接近 1 表示近期负荷和过去的水平接近。")
                        .font(.subheadline)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .padding(.top, 4)
                }
                .font(.subheadline)
            }
        }
    }

    private func loadStatusLabel(_ zone: ACWRZone) -> String {
        switch zone {
        case .sweetSpot: "负荷适中"
        case .highRisk: "近期负荷偏高"
        case .undertraining: "近期负荷偏低"
        case .insufficientData: "数据不足"
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text("肌群恢复")
                            .font(.headline)
                            .foregroundStyle(BevelTheme.ink)
                        Text("估算于 \(store.recoverySnapshot.asOf, format: .dateTime.hour().minute())")
                            .font(.footnote)
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
                            let est = store.recoverySnapshot.estimate(for: muscle)
                            Text(muscle.title)
                                .font(.headline)
                                .foregroundStyle(BevelTheme.ink)
                            Text("预计恢复 \(est.recoveryPercent)%")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(est.isReadyForPrimaryWork ? BevelTheme.recoveryColor : BevelTheme.strainColor)
                            Text(est.readyETADescription)
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)

                            Button {
                                store.send(.inspectMuscleRecovery(muscle))
                            } label: {
                                Label("查看\(muscle.title)恢复详情", systemImage: "chart.bar.doc.horizontal")
                                    .font(.caption.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .foregroundStyle(BevelTheme.onBrand)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("workout-muscle-recovery-detail")

                            Button {
                                store.send(.muscleSelected(nil))
                            } label: {
                                Text("清除筛选")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text("训练涉及的肌群")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(BevelTheme.inkSecondary)
                            let ranked = store.recoverySnapshot.rankedByFatigue
                            if ranked.isEmpty {
                                Text("近 7 天暂无肌群负荷记录。")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            } else {
                                ForEach(ranked.prefix(5)) { est in
                                    Button {
                                        store.send(.inspectMuscleRecovery(est.muscle))
                                    } label: {
                                        HStack {
                                            Text(est.muscle.title)
                                                .font(.caption)
                                                .foregroundStyle(BevelTheme.ink)
                                            Spacer()
                                            Text("\(est.recoveryPercent)%")
                                                .font(.caption.weight(.semibold).monospacedDigit())
                                                .foregroundStyle(est.isReadyForPrimaryWork ? BevelTheme.recoveryColor : BevelTheme.strainColor)
                                        }
                                        .padding(.vertical, 4)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("workout-muscle-rank-\(est.muscle.rawValue)")
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
                    legendDot(color: BevelTheme.scoreTrack, label: "已充分恢复")
                    legendDot(color: BevelTheme.brand.opacity(0.65), label: "轻度残留")
                    legendDot(color: BevelTheme.energyColor, label: "中等疲劳")
                    legendDot(color: BevelTheme.strainColor, label: "建议休整")
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

    private var watchArchiveSection: some View {
        let items = Array(store.archiveWorkouts.prefix(6))
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader("手表训练记录")

            if items.isEmpty {
                BevelCard {
                    Text("近 30 天还没有同步的手表训练。")
                        .font(.footnote)
                        .foregroundStyle(BevelTheme.inkSecondary)
                }
            } else {
                ForEach(items) { workout in
                    let durationMin = max(1, Int((workout.end.timeIntervalSince(workout.start) / 60).rounded()))
                    let workoutLoads = store.muscleLoads.filter { $0.workoutUUID == workout.hkUUID }
                    Button {
                        store.send(.inspectWorkoutDetail(workout))
                    } label: {
                        BevelCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(workout.type)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BevelTheme.ink)
                                    Spacer()
                                    reviewBadge(workout.reviewState)
                                }

                                HStack(spacing: 12) {
                                    Text(workout.start, format: .dateTime.month().day().hour().minute())
                                    Text("\(durationMin) 分钟")
                                    Text("\(Int(workout.energy.rounded())) kcal")
                                    if let hr = workout.avgHR {
                                        Text("平均心率 \(Int(hr.rounded()))")
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)

                                HStack(spacing: 8) {
                                    if let effortUser = workout.effortUser {
                                        Text(String(format: "主观用力 %.1f", effortUser))
                                            .font(.caption2.weight(.semibold))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(BevelTheme.strainColor.opacity(0.14), in: Capsule())
                                            .foregroundStyle(BevelTheme.strainColor)
                                    }
                                    if let effortEst = workout.effortEstimated {
                                        Text(String(format: "手表估算 %.1f", effortEst))
                                            .font(.caption2)
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(BevelTheme.surfaceElevated, in: Capsule())
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                    }
                                    if !workoutLoads.isEmpty {
                                        Text(workoutLoads.filter { $0.role == .primary }.map(\.muscle.title).joined(separator: "·"))
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.brand)
                                            .lineLimit(1)
                                    }
                                }

                                if let zones = workout.zones, zones.totalZoneMinutes > 0 {
                                    ZoneBar(zones: zones, showsTrimp: true)
                                }
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-archive-row-\(workout.hkUUID)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-archive-section")
    }

    private func reviewBadge(_ state: WorkoutReviewState) -> some View {
        let (title, tint): (String, Color) = switch state {
        case .unreviewed: ("待复盘", BevelTheme.strainColor)
        case .autoAttributed: ("自动归因", BevelTheme.sleepColor)
        case .annotated: ("已复盘", BevelTheme.recoveryColor)
        case .skipped: ("已跳过", BevelTheme.inkSecondary)
        }
        return Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
    }

    // MARK: - Supplemental Manual Entry (Demoted Below Watch-First Archive)

    private var manualSupplementarySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            templatesSection
            exerciseCatalogSection
            loggedSessionsSection
        }
    }

    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("辅助训练方案与手动补录入口")

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

    private var loggedSessionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader("手动补录组次历史")
                Spacer()
                Text("近7日容量 \(Int(store.weeklyVolumeKg.rounded())) kg")
                    .font(.caption2)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }

            if store.sessions.isEmpty {
                BevelCard {
                    Text("日常无需在训练中手动记组次；若需补录重量细节，可通过右上角「手动补录」或上方方案开练。")
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
