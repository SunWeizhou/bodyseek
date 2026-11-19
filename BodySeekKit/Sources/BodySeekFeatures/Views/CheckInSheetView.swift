import BodySeekCore
import SwiftUI

public struct CheckInSheetView: View {
    public let dayKey: DayKey
    public let initialCheckIn: DailyCheckIn?
    public let onSave: (DailyCheckIn) -> Void
    public let onDismiss: () -> Void

    @State private var energy: Int
    @State private var mood: Int
    @State private var stress: Int
    @State private var soreness: [BodyRegionMuscle: Int]
    @State private var note: String

    private let energyLabels = ["极疲", "发沉", "平稳", "良好", "充沛"]
    private let moodLabels = ["低落", "烦躁", "平和", "愉快", "极佳"]
    private let stressLabels = ["轻松", "轻微", "适中", "紧张", "高压"]

    private let quickSorenessMuscles: [BodyRegionMuscle] = [
        .upperBack, .chest, .deltoids, .quadriceps, .hamstring, .gluteal, .lowerBack, .forearm,
    ]

    public init(
        dayKey: DayKey,
        initialCheckIn: DailyCheckIn?,
        fallbackEnergy: Int? = nil,
        onSave: @escaping (DailyCheckIn) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.dayKey = dayKey
        self.initialCheckIn = initialCheckIn
        self.onSave = onSave
        self.onDismiss = onDismiss
        _energy = State(initialValue: initialCheckIn?.energy ?? fallbackEnergy ?? 3)
        _mood = State(initialValue: initialCheckIn?.mood ?? 3)
        _stress = State(initialValue: initialCheckIn?.stress ?? 2)
        _soreness = State(initialValue: initialCheckIn?.soreness ?? [:])
        _note = State(initialValue: initialCheckIn?.note ?? "")
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    ratingRow(title: "主观精力", value: $energy, labels: energyLabels, tint: BevelTheme.recoveryColor, identifierPrefix: "checkin-energy")
                    ratingRow(title: "情绪状态", value: $mood, labels: moodLabels, tint: BevelTheme.sleepColor, identifierPrefix: "checkin-mood")
                    ratingRow(title: "主观压力", value: $stress, labels: stressLabels, tint: BevelTheme.stressColor, identifierPrefix: "checkin-stress")
                } header: {
                    Text("10 秒今日体感（生理日 \(dayKey.isoString)）")
                } footer: {
                    Text("每日体感标签将与 Apple 健康客观体征共同参与个人身体模型校准；未记录保持未知，绝不当作零。")
                }

                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 8)], spacing: 8) {
                        ForEach(quickSorenessMuscles) { muscle in
                            let level = soreness[muscle] ?? 0
                            Button {
                                cycleSoreness(for: muscle)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(muscle.title)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    if level > 0 {
                                        Text(levelLabel(level))
                                            .font(.caption2.weight(.bold))
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 8)
                                .background(
                                    level > 0 ? BevelTheme.strainColor.opacity(0.18) : BevelTheme.surfaceElevated,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(level > 0 ? BevelTheme.strainColor.opacity(0.6) : Color.clear, lineWidth: 1)
                                )
                                .foregroundStyle(level > 0 ? BevelTheme.strainColor : BevelTheme.inkSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("checkin-soreness-\(muscle.rawValue)")
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("部位酸痛 / 紧绷（可选，轻点切换 轻 → 中 → 重）")
                }

                Section("今日补充备注（可选）") {
                    TextField("例如：昨晚熬夜加班、羽球后右肩略紧…", text: $note)
                        .accessibilityIdentifier("checkin-note-field")
                }
            }
            .navigationTitle("每日体感打卡")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekLeading) {
                    Button("取消", action: onDismiss)
                        .accessibilityIdentifier("checkin-cancel-button")
                }
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button(initialCheckIn == nil ? "保存" : "更新", action: saveCheckIn)
                        .fontWeight(.semibold)
                        .foregroundStyle(BevelTheme.brand)
                        .accessibilityIdentifier("checkin-save-button")
                }
            }
        }
    }

    private func saveCheckIn() {
        let entry = DailyCheckIn(
            id: initialCheckIn?.id ?? UUID(),
            dayKey: dayKey,
            recordedAt: Date(),
            energy: energy,
            mood: mood,
            stress: stress,
            soreness: soreness,
            note: note
        )
        onSave(entry)
    }

    private func ratingRow(
        title: String,
        value: Binding<Int>,
        labels: [String],
        tint: Color,
        identifierPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)
                Spacer()
                Text("\(value.wrappedValue)/5 · \(labels[min(max(0, value.wrappedValue - 1), labels.count - 1)])")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
            }

            HStack(spacing: 8) {
                ForEach(1...5, id: \.self) { score in
                    let isSelected = value.wrappedValue == score
                    Button {
                        value.wrappedValue = score
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(score)")
                                .font(.subheadline.weight(.bold).monospacedDigit())
                            Text(labels[score - 1])
                                .font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(
                            isSelected ? tint.opacity(0.20) : BevelTheme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(isSelected ? tint : Color.clear, lineWidth: 1.2)
                        )
                        .foregroundStyle(isSelected ? tint : BevelTheme.inkSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifierPrefix)-\(score)")
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func cycleSoreness(for muscle: BodyRegionMuscle) {
        let next = ((soreness[muscle] ?? 0) + 1) % 4
        if next == 0 {
            soreness.removeValue(forKey: muscle)
        } else {
            soreness[muscle] = next
        }
    }

    private func levelLabel(_ level: Int) -> String {
        switch level {
        case 1: "轻"
        case 2: "中"
        default: "重"
        }
    }
}
