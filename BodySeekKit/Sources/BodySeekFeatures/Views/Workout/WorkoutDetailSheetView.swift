import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct WorkoutDetailSheetView: View {
    @Bindable var store: StoreOf<WorkoutFeature>
    public let workout: StoredWorkoutRecord

    public init(store: StoreOf<WorkoutFeature>, workout: StoredWorkoutRecord) {
        self.store = store
        self.workout = workout
    }

    public var body: some View {
        let durationMin = max(1, Int((workout.end.timeIntervalSince(workout.start) / 60).rounded()))
        let annotation = store.annotationsByWorkoutUUID[workout.hkUUID]
        let loads = store.muscleLoads
            .filter { $0.workoutUUID == workout.hkUUID }
            .sorted { $0.load > $1.load }

        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BevelCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(workout.type)
                                    .font(.headline)
                                    .foregroundStyle(BevelTheme.ink)
                                Spacer()
                                reviewBadge(workout.reviewState)
                            }

                            Text("\(workout.start, format: .dateTime.year().month().day().hour().minute()) – \(workout.end, format: .dateTime.hour().minute())")
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)

                            HStack(spacing: 16) {
                                statItem("时长", value: "\(durationMin) 分钟")
                                statItem("活动消耗", value: "\(Int(workout.energy.rounded())) kcal")
                                if let avgHR = workout.avgHR {
                                    statItem("平均心率", value: "\(Int(avgHR.rounded())) bpm")
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    if let zones = workout.zones, zones.totalZoneMinutes > 0 {
                        BevelCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("心率分区与 TRIMP")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                ZoneBar(zones: zones, showsTrimp: true)
                            }
                        }
                    }

                    BevelCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("用力评分溯源（手打与估算分存）")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BevelTheme.ink)
                            HStack(spacing: 12) {
                                effortBox(
                                    title: "用户主观用力 (EffortUser)",
                                    value: workout.effortUser.map { String(format: "%.1f / 10", $0) } ?? "未填写",
                                    tint: BevelTheme.strainColor
                                )
                                effortBox(
                                    title: "Apple 系统估算 (Estimated)",
                                    value: workout.effortEstimated.map { String(format: "%.1f / 10", $0) } ?? "无估算",
                                    tint: BevelTheme.inkSecondary
                                )
                            }
                        }
                    }

                    BevelCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("肌群归因与复盘标注")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Spacer()
                                Text("启发式估计")
                                    .font(.caption2)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }

                            if let annotation {
                                Text("“\(annotation.rawText)”")
                                    .font(.footnote)
                                    .foregroundStyle(BevelTheme.ink)
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }

                            if loads.isEmpty {
                                Text("尚无已保存的肌群负荷归因。")
                                    .font(.footnote)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            } else {
                                ForEach(loads, id: \.muscle) { rec in
                                    HStack {
                                        Text(rec.muscle.title)
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(BevelTheme.ink)
                                        Text(rec.role == .primary ? "主受刺激" : (rec.role == .secondary ? "协同" : "稳定"))
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                        Spacer()
                                        Text(String(format: "%.2f", rec.load))
                                            .font(.caption.weight(.semibold).monospacedDigit())
                                            .fontDesign(.rounded)
                                            .foregroundStyle(BevelTheme.brand)
                                    }
                                }
                            }
                        }
                    }

                    Button {
                        store.send(.inspectWorkoutDetail(nil))
                        store.send(.openReviewTapped(workout))
                    } label: {
                        Label(annotation == nil ? "补充一句话复盘" : "修改训练复盘", systemImage: "square.and.pencil")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(BevelTheme.brand, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(BevelTheme.onBrand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("workout-detail-edit-review")
                }
                .padding(16)
            }
            .background(BevelTheme.canvas.ignoresSafeArea())
            .navigationTitle("训练详情")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("完成") {
                        store.send(.inspectWorkoutDetail(nil))
                    }
                    .accessibilityIdentifier("workout-detail-done")
                }
            }
        }
    }

    private func statItem(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(BevelTheme.ink)
        }
    }

    private func effortBox(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(BevelTheme.inkSecondary)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .fontDesign(.rounded)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
