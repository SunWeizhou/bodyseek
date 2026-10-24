import SwiftUI

// MARK: - HeartRateRangeBin

struct HeartRateRangeBin: Identifiable {
    let id = UUID()
    let date: Date
    let minBPM: Double
    let maxBPM: Double
}

// MARK: - HeartRateZoneSegment

struct HeartRateZoneSegment: Identifiable {
    let id = UUID()
    let label: String
    let count: Int
    let color: Color
}

// MARK: - HeartRateZoneRibbonView

struct HeartRateZoneRibbonView: View {
    let segments: [HeartRateZoneSegment]

    var body: some View {
        GeometryReader { proxy in
            let visibleSegments = segments.filter { $0.count > 0 }
            let total = max(1, visibleSegments.reduce(0) { $0 + $1.count })
            let spacing = CGFloat(max(visibleSegments.count - 1, 0)) * 3
            let availableWidth = max(0, proxy.size.width - spacing)

            HStack(spacing: 3) {
                if visibleSegments.isEmpty {
                    RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                        .fill(VelaTheme.hairline)
                } else {
                    ForEach(visibleSegments) { segment in
                        RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                            .fill(segment.color)
                            .frame(width: max(12, availableWidth * CGFloat(segment.count) / CGFloat(total)))
                    }
                }
            }
        }
        .accessibilityLabel(AppLanguage.stored.isChinese ? "心率区间分布" : "Heart rate zone distribution")
    }
}

// MARK: - WorkoutHeartRateInsightSheet

struct WorkoutHeartRateInsightSheet: View {
    let averageText: String
    let peakText: String
    let rangeText: String
    let intensityText: String
    let segments: [HeartRateZoneSegment]

    private var totalCount: Int {
        max(1, segments.reduce(0) { $0 + $1.count })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("心率区间")
                    .font(.system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(intensityText)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            HStack(spacing: 10) {
                insightTile(title: "平均", value: averageText)
                insightTile(title: "峰值", value: peakText)
                insightTile(title: "范围", value: rangeText)
            }

            HeartRateZoneRibbonView(segments: segments)
                .frame(height: 34)

            VStack(spacing: 10) {
                ForEach(segments) { segment in
                    HStack(spacing: 10) {
                        Circle()
                            .fill(segment.color)
                            .frame(width: 9, height: 9)
                        Text(segment.label)
                            .font(.system(.footnote, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Spacer()
                        Text("\(Int((Double(segment.count) / Double(totalCount) * 100).rounded()))%")
                            .font(.system(.footnote, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private func insightTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.subheadline, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(.system(.caption2, design: .default, weight: .medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
    }
}

// MARK: - StrengthSetDetail

struct StrengthSetDetail: Identifiable {
    let id = UUID()
    var exerciseName: String
    var setIndex: Int
    var set: StrengthSetLog
}

// MARK: - StrengthSetDetailSheet

struct StrengthSetDetailSheet: View {
    let detail: StrengthSetDetail

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text(detail.exerciseName)
                    .font(VelaTheme.title2())
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text("第 \(detail.setIndex) 组")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    metric("重量", "\(detail.set.weightKilograms.formatted(.number.precision(.fractionLength(0...1)))) kg")
                    metric("次数", "\(detail.set.repetitions)")
                    metric("容量", "\(Int(detail.set.volumeKilograms.rounded())) kg")
                    metric("RPE", detail.set.rpe.map { "\(Int($0))" } ?? "--")
                    metric("RIR", detail.set.rir.map { "\(Int($0))" } ?? "--")
                    metric("状态", (detail.set.isCompleted ?? true) ? "已完成" : "未完成")
                }
                Spacer()
            }
            .padding(18)
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle("组详情")
            .velaRhythmDetailChrome()
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(.body, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInk)
            Text(title)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
    }
}

// MARK: - WorkoutExerciseListView

struct WorkoutExerciseListView: View {
    let strength: StrengthWorkoutRecord
    let strengthWorkouts: [StrengthWorkoutRecord]
    @Binding var selectedSet: StrengthSetDetail?

    private var bodyTextColor: Color { VelaTheme.rhythmInk }
    private var mutedColor: Color { VelaTheme.rhythmInkSecondary }
    private var accentColor: Color { VelaTheme.rhythmDeep }

    var body: some View {
        let analysis = TrainingAnalyticsService().summarizeWorkout(
            strength.dto,
            history: strengthWorkouts.filter { $0.startedAt < strength.startedAt }.map { $0.dto },
            exerciseLibrary: ExerciseLibraryService.defaultDefinitionsDTO()
        )
        return VStack(alignment: .leading, spacing: 12) {
            Text("动作与组次")
                .font(.system(.subheadline, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInk)

            ForEach(strength.exercises) { exercise in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exercise.name)
                                .font(.system(.callout, design: .default, weight: .bold))
                                .foregroundStyle(bodyTextColor)
                            Text("\(exercise.equipment) · \(Int(exercise.volumeKilograms.rounded())) kg")
                                .font(.system(.caption2, design: .default, weight: .medium))
                                .foregroundStyle(mutedColor)
                        }
                        Spacer()
                        if let e1RM = analysis.estimatedOneRepMaxByExercise[exercise.name] {
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(Int(e1RM.rounded())) kg")
                                    .font(.system(.subheadline, design: .default, weight: .bold))
                                    .foregroundStyle(accentColor)
                                Text("e1RM")
                                    .font(.system(.caption2, design: .default, weight: .bold))
                                    .foregroundStyle(mutedColor)
                            }
                        }
                    }

                    if !exercise.sets.isEmpty {
                        HStack(spacing: 12) {
                            Text("组")
                                .frame(width: 32, alignment: .leading)
                            Text("重量")
                                .frame(width: 70, alignment: .center)
                            Spacer()
                            Text("次数")
                                .frame(width: 50, alignment: .center)
                            Text("RPE")
                                .frame(width: 44, alignment: .center)
                            Text("状态")
                                .frame(width: 32, alignment: .trailing)
                        }
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundStyle(mutedColor)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)
                    }

                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        Button {
                            selectedSet = StrengthSetDetail(
                                exerciseName: exercise.name,
                                setIndex: index + 1,
                                set: set
                            )
                        } label: {
                            setRow(index: index, set: set)
                        }
                        .buttonStyle(.cardPress)
                    }
                }
                .padding(16)
                .velaNativeCard()
            }
        }
    }

    private func setRow(index: Int, set: StrengthSetLog) -> some View {
        HStack(spacing: 12) {
            Text(set.isWarmup ? "热" : "\(index + 1)")
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(set.isWarmup ? VelaTheme.rhythmInk : VelaTheme.rhythmDeepOn)
                .frame(width: 24, height: 24)
                .background(Circle().fill(set.isWarmup ? VelaTheme.surfaceFloating : VelaTheme.rhythmDeep))
                .frame(width: 32, alignment: .leading)

            Text("\(set.weightKilograms.formatted(.number.precision(.fractionLength(0...1)))) kg")
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(bodyTextColor)
                .frame(width: 70, alignment: .center)

            Spacer()

            Text("\(set.repetitions) 次")
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(bodyTextColor)
                .frame(width: 50, alignment: .center)

            Text(set.rpe.map { "\(Int($0))" } ?? "—")
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(set.rpe != nil ? VelaTheme.rhythmDeep : mutedColor)
                .frame(width: 44, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusSm)
                        .fill(VelaTheme.rhythmCanvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: VelaTheme.radiusSm)
                        .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
                )

            Image(systemName: (set.isCompleted ?? true) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle((set.isCompleted ?? true) ? VelaTheme.rhythmDeep : mutedColor)
                .font(.system(.title3, design: .default))
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - WorkoutNotesCardView

struct WorkoutNotesCardView: View {
    let strength: StrengthWorkoutRecord

    var body: some View {
        if !strength.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("训练备注", systemImage: "note.text")
                    .font(.system(.footnote, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(strength.notes)
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .padding(16)
            .velaNativeCard()
        }
    }
}
