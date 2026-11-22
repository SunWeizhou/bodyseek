import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import MuscleMap
import SwiftUI

public struct WorkoutView: View {
    @Bindable var store: StoreOf<WorkoutFeature>
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

                trainingLoadCard
                muscleHeatmapCard
                watchArchiveSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(BevelTheme.canvas.ignoresSafeArea())
        .navigationTitle("健身")
        .bodyseekNavigationBarInline()
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
                        store.send(.askCoachTapped("针对 Coach 推荐的「\(proposal.template.title)」，结合我当前恢复与负荷状态帮我细化组次或调整动作"))
                    } label: {
                        Label("去 Coach 细化", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(BevelTheme.onBrand)
                    }
                    .buttonStyle(.plain)

                    Button {
                        store.send(.dismissProposalTapped)
                    } label: {
                        Text("收起")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var trainingLoadCard: some View {
        TrainingLoadDashboardCard(
            load: store.snapshot.trainingLoad,
            recentDays: Array(store.snapshot.historyDays.suffix(14)),
            coachMicroInsight: loadCoachMicroInsight,
            onOpenTrends: { store.send(.openTrendsTapped) },
            onAskCoach: {
                store.send(.askCoachTapped("结合我当前 ACWR 训练负荷、近 14 天负荷分布和肌群恢复状态，今天最适合什么训练强度和部位？"))
            }
        )
    }

    private var loadCoachMicroInsight: String {
        let load = store.snapshot.trainingLoad
        let fatigued = store.recoverySnapshot.rankedByFatigue.filter { !$0.isReadyForPrimaryWork }.prefix(2)
        let ratioPart: String = if let ratio = load.acwrRatio {
            String(format: "ACWR %.2f（%@）", ratio, load.zone.title)
        } else {
            "训练基线积累中"
        }
        let recoveryPart = store.snapshot.today.recovery.value.map { "今日恢复 \($0) 分" } ?? "恢复样本待补充"
        let musclePart: String = if !fatigued.isEmpty {
            fatigued.map { "\($0.muscle.title)约\($0.recoveryPercent)%" }.joined(separator: "、") + "仍在恢复"
        } else if !store.recoverySnapshot.rankedByFatigue.isEmpty {
            "近期主训肌群已基本恢复就绪"
        } else {
            "戴表记录训练并一句话复盘后，将自动关联负荷与肌群恢复"
        }
        return "\(ratioPart) · \(recoveryPart)；\(musclePart)。"
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
}
