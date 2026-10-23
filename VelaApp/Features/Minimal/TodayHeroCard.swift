import SwiftUI

struct DailyDecisionFeedbackValues: Sendable {
    var adoptionStatus: String
    var accuracyRating: String
    var actualAction: String
    var energyRating: Int?
    var fatigueRating: Int?
    var painRating: Int?
    var satisfactionRating: Int?
    var note: String
}

struct DailyDecisionFeedbackCard: View {
    let record: DailyDecisionFeedbackRecord?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: record?.isCompleted == true ? "checkmark.circle.fill" : "scope")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(record?.isCompleted == true ? VelaTheme.success : VelaTheme.accent)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(VelaTheme.secondaryGroupedBackground))

                VStack(alignment: .leading, spacing: 3) {
                    Text(record?.isCompleted == true ? "今日反馈已记录" : "这个建议适合你吗？")
                        .font(VelaTheme.subheadline().weight(.semibold))
                        .foregroundStyle(VelaTheme.fg)
                    Text(record?.isCompleted == true ? "可随时更新，Vela 会用它校准后续建议" : "记录实际行动与体感，约 20 秒")
                        .font(VelaTheme.caption2())
                        .foregroundStyle(VelaTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(VelaTheme.muted)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).fill(VelaTheme.cardBg))
            .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).stroke(VelaTheme.borderSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(record?.isCompleted == true ? "更新今日建议反馈" : "记录今日建议反馈")
    }
}

struct DailyDecisionFeedbackSheet: View {
    @Environment(\.dismiss) private var dismiss
    let record: DailyDecisionFeedbackRecord
    let onSave: (DailyDecisionFeedbackValues) -> Void

    @State private var adoptionStatus: String
    @State private var accuracyRating: String
    @State private var actualAction: String
    @State private var energyRating: Int?
    @State private var fatigueRating: Int?
    @State private var painRating: Int?
    @State private var satisfactionRating: Int?
    @State private var note: String

    init(record: DailyDecisionFeedbackRecord, onSave: @escaping (DailyDecisionFeedbackValues) -> Void) {
        self.record = record
        self.onSave = onSave
        _adoptionStatus = State(initialValue: record.adoptionStatus ?? "")
        _accuracyRating = State(initialValue: record.accuracyRating ?? "")
        _actualAction = State(initialValue: record.actualAction ?? "")
        _energyRating = State(initialValue: record.energyRating)
        _fatigueRating = State(initialValue: record.fatigueRating)
        _painRating = State(initialValue: record.painRating)
        _satisfactionRating = State(initialValue: record.satisfactionRating)
        _note = State(initialValue: record.note)
    }

    private var canSave: Bool {
        !adoptionStatus.isEmpty && !accuracyRating.isEmpty && !actualAction.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("校准 Vela 的判断")
                            .font(VelaTheme.title2())
                            .foregroundStyle(VelaTheme.fg)
                        Text(record.decisionTitle)
                            .font(VelaTheme.subheadline())
                            .foregroundStyle(VelaTheme.muted)
                    }

                    feedbackChoiceSection(
                        title: "你采纳建议了吗？",
                        options: [("followed", "完全采纳"), ("modified", "调整后采纳"), ("not_followed", "没有采纳")],
                        selection: $adoptionStatus
                    )
                    feedbackChoiceSection(
                        title: "建议符合当时状态吗？",
                        options: [("accurate", "准确"), ("partly", "部分准确"), ("inaccurate", "不准确")],
                        selection: $accuracyRating
                    )
                    feedbackChoiceSection(
                        title: "你实际做了什么？",
                        options: [("as_planned", "按计划训练"), ("lighter", "降低强度"), ("harder", "提高强度"), ("recovery", "主动恢复"), ("rest", "休息")],
                        selection: $actualAction
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("完成后的体感（可选）")
                            .font(VelaTheme.headline())
                        DecisionRatingRow(title: "精力", lowLabel: "低", highLabel: "高", value: $energyRating)
                        DecisionRatingRow(title: "疲劳", lowLabel: "低", highLabel: "高", value: $fatigueRating)
                        DecisionRatingRow(title: "疼痛", lowLabel: "无", highLabel: "明显", value: $painRating)
                        DecisionRatingRow(title: "满意度", lowLabel: "低", highLabel: "高", value: $satisfactionRating)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("补充说明（可选）")
                            .font(VelaTheme.headline())
                        TextField("例如：腿部仍然酸痛，所以改成低强度", text: $note, axis: .vertical)
                            .lineLimit(2...5)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).fill(VelaTheme.secondaryGroupedBackground))
                    }
                }
                .padding(20)
            }
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle("今日反馈")
            .velaRhythmDetailChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        onSave(DailyDecisionFeedbackValues(
                            adoptionStatus: adoptionStatus,
                            accuracyRating: accuracyRating,
                            actualAction: actualAction,
                            energyRating: energyRating,
                            fatigueRating: fatigueRating,
                            painRating: painRating,
                            satisfactionRating: satisfactionRating,
                            note: note
                        ))
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
    }

    @ViewBuilder
    private func feedbackChoiceSection(
        title: String,
        options: [(String, String)],
        selection: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(VelaTheme.headline())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(options, id: \.0) { option in
                    Button {
                        selection.wrappedValue = option.0
                    } label: {
                        Text(option.1)
                            .font(VelaTheme.subheadline().weight(.semibold))
                            .foregroundStyle(selection.wrappedValue == option.0 ? Color.white : VelaTheme.fg)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 9)
                            .background(Capsule().fill(selection.wrappedValue == option.0 ? VelaTheme.accent : VelaTheme.secondaryGroupedBackground))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct DecisionRatingRow: View {
    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(VelaTheme.subheadline().weight(.semibold))
                Spacer()
                Text("1 \(lowLabel) · 5 \(highLabel)")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.muted)
            }

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { rating in
                    Button {
                        value = value == rating ? nil : rating
                    } label: {
                        Text("\(rating)")
                            .font(VelaTheme.subheadline().weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(value == rating ? Color.white : VelaTheme.fg2)
                            .background(
                                RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                                    .fill(value == rating ? VelaTheme.accent : VelaTheme.secondaryGroupedBackground)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title) \(rating)，\(rating == 1 ? lowLabel : rating == 5 ? highLabel : "")")
                    .accessibilityAddTraits(value == rating ? .isSelected : [])
                }
            }
        }
    }
}

// MARK: - Rhythm secondary surfaces

struct VelaRhythmActionSequence: View {
    let actions: [TodayExperienceAction]
    let onAction: (TodayExperienceAction) -> Void
    let onEvidence: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VelaRhythmSectionHeader(
                eyebrow: "",
                title: "今天的重点",
                actionTitle: nil,
                action: {}
            )
            .padding(.bottom, 12)

            ForEach(Array(actions.prefix(3).enumerated()), id: \.element.id) { index, action in
                Button { onAction(action) } label: {
                    HStack(alignment: .center, spacing: 14) {
                        Text(String(format: "%02d", index + 1))
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(index == 0 ? VelaTheme.rhythmDeep : VelaTheme.rhythmInkSecondary)
                            .padding(.top, 4)

                        Text(action.title)
                            .font(.system(.callout, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInk)

                        Spacer(minLength: 8)

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.cardPress)

                if index < min(actions.count, 3) - 1 {
                    Divider()
                        .overlay(VelaTheme.rhythmMist)
                        .padding(.leading, 35)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct VelaRhythmSectionHeader: View {
    let eyebrow: String
    let title: String
    let actionTitle: String?
    let action: () -> Void

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                if !eyebrow.isEmpty {
                    Text(eyebrow)
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                Text(title)
                    .font(.system(.title2, design: .default, weight: .semibold))
                    .tracking(-0.35)
                    .foregroundStyle(VelaTheme.rhythmInk)
            }

            Spacer(minLength: 12)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
            }
        }
    }
}
