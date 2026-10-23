import SwiftUI
import SwiftData

struct BehaviorQuickNoteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    var onSave: (String) -> Void

    private let templates = ["火锅，吃得有点撑", "晚饭很晚", "睡前喝了咖啡", "喝了两杯啤酒", "今天喝水少", "外卖偏咸"]
    private var signals: [BehaviorSignal] {
        BehaviorSignalExtractor.extract(from: note, confidence: .aiInferred)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("随手记", systemImage: "text.bubble.fill")
                            .font(.system(.body, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Text("记录你觉得可能影响恢复、睡眠或训练的行为。这里不估算热量、克重或宏量营养，只给 Body Model 留低摩擦信号。")
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineSpacing(3)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                    )

                    VStack(alignment: .leading, spacing: 10) {
                        TextEditor(text: $note)
                            .frame(minHeight: 120)
                            .padding(10)
                            .scrollContentBackground(.hidden)
                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VelaTheme.rhythmCanvas))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(templates, id: \.self) { template in
                                    Button {
                                        VelaHaptic.selection()
                                        note = note.isEmpty ? template : "\(note)，\(template)"
                                    } label: {
                                        Text(template)
                                            .font(.system(.caption, design: .default, weight: .semibold))
                                            .foregroundStyle(VelaTheme.rhythmInk)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 7)
                                            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VelaTheme.rhythmCanvas))
                                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.5))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        if !signals.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                                ForEach(signals) { signal in
                                    Text("\(signal.tag.displayTitle) · \(signal.intensity.rawValue)")
                                        .font(.system(.caption2, design: .default, weight: .bold))
                                        .foregroundStyle(VelaTheme.rhythmDeep)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 5)
                                        .background(RoundedRectangle(cornerRadius: 10).fill(VelaTheme.rhythmDeep.opacity(0.12)))
                                }
                            }
                        } else {
                            Text("保存后仍会作为普通手记进入上下文；识别不到标签时不会强行编造。")
                                .font(.system(.caption2, design: .default))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                    )

                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onSave(note)
                        dismiss()
                    } label: {
                        Text("保存随手记")
                            .font(.system(.subheadline, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeepOn)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).fill(VelaTheme.rhythmDeep))
                    }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.plain)
                }
                .padding(16)
            }
            .background(VelaTheme.rhythmCanvas)
            .navigationTitle("随手记")
            .velaRhythmDetailChrome()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}

struct CaffeineLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Double) -> Void
    
    @State private var customAmount: Double = 80.0
    
    let quickOptions = [
        ("浓缩咖啡", "espresso", 64.0, "cup.and.saucer.fill"),
        ("美式咖啡", "americano", 120.0, "cup.and.saucer"),
        ("拿铁", "latte", 80.0, "cup.and.saucer.fill"),
        ("绿茶", "greentea", 35.0, "leaf.fill")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("记录咖啡因")
                    .font(.system(.title3, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Close", "关闭"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 24) {
                    Text("输入或选择摄入的咖啡因量。这会有助于 AI 预测它对你深度睡眠和能量水平的长期影响。")
                        .font(.system(.footnote, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(customAmount))")
                                .font(.system(.largeTitle, design: .rounded, weight: .black))
                                .foregroundStyle(VelaTheme.accent)
                            Text("mg")
                                .font(.system(.body, design: .default, weight: .bold))
                                .foregroundStyle(VelaTheme.meta)
                        }
                        
                        Slider(value: $customAmount, in: 0...400, step: 5)
                            .tint(VelaTheme.accent)
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .velaNativeCard(radius: 20)
                    .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("快捷选项")
                            .font(.system(.footnote, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.muted)
                            .padding(.leading, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(quickOptions, id: \.1) { name, key, val, icon in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        customAmount = val
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: icon)
                                                .font(.system(size: 20))
                                                .foregroundStyle(VelaTheme.accent)
                                                .frame(width: 44, height: 44)
                                                .background(Circle().fill(VelaTheme.accent.opacity(0.12)))
                                            
                                            Text(name)
                                                .font(.system(.caption, design: .default, weight: .bold))
                                                .foregroundStyle(VelaTheme.fg)
                                            
                                            Text("\(Int(val)) mg")
                                                .font(.system(.caption2, design: .default, weight: .bold))
                                                .foregroundStyle(VelaTheme.meta)
                                        }
                                        .frame(width: 90, height: 110)
                                        .velaNativeCard(radius: 16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                                                .stroke(customAmount == val ? VelaTheme.accent : Color.clear, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onSave(customAmount)
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.system(.callout, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeepOn)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.rhythmDeep))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
        }
        .background(VelaTheme.rhythmCanvas.ignoresSafeArea())
    }
}

struct WaterLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Double) -> Void
    
    @State private var customAmount: Double = 250.0
    
    let quickOptions = [
        ("小杯", 250.0, "drop.fill"),
        ("中杯", 350.0, "drop.fill"),
        ("大杯", 500.0, "drop.fill"),
        ("整瓶", 750.0, "drop.fill")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("记录补水")
                    .font(.system(.title3, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Close", "关闭"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 24) {
                    Text("记录今天摄入的水分，帮助你回顾补水习惯与后续状态。")
                        .font(.system(.footnote, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(Int(customAmount))")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .foregroundStyle(VelaTheme.accent)
                            Text("ml")
                                .font(.system(.body, design: .default, weight: .bold))
                                .foregroundStyle(VelaTheme.meta)
                        }
                        
                        Slider(value: $customAmount, in: 0...1000, step: 50)
                            .tint(VelaTheme.accent)
                            .padding(.horizontal, 20)
                    }
                    .padding(.vertical, 20)
                    .frame(maxWidth: .infinity)
                    .velaNativeCard(radius: 20)
                    .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("快捷选项")
                            .font(.system(.footnote, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.muted)
                            .padding(.leading, 20)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(quickOptions, id: \.1) { name, val, icon in
                                    Button {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        customAmount = val
                                    } label: {
                                        VStack(spacing: 8) {
                                            Image(systemName: icon)
                                                .font(.system(size: 20))
                                                .foregroundStyle(VelaTheme.accent)
                                                .frame(width: 44, height: 44)
                                                .background(Circle().fill(VelaTheme.accent.opacity(0.12)))
                                            
                                            Text(name)
                                                .font(.system(.caption, design: .default, weight: .bold))
                                                .foregroundStyle(VelaTheme.fg)
                                            
                                            Text("\(Int(val)) ml")
                                                .font(.system(.caption2, design: .default, weight: .bold))
                                                .foregroundStyle(VelaTheme.meta)
                                        }
                                        .frame(width: 90, height: 110)
                                        .velaNativeCard(radius: 16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                                                .stroke(customAmount == val ? VelaTheme.accent : Color.clear, lineWidth: 1.5)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 4)
                        }
                    }
                    
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onSave(customAmount)
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.system(.callout, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeepOn)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.rhythmDeep))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
        }
        .background(VelaTheme.rhythmCanvas.ignoresSafeArea())
    }
}

struct MoodLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Double, String) -> Void
    
    @State private var selectedScore: Double = 3.0
    @State private var noteText: String = ""
    
    let moodOptions = [
        (1.0, "😞", "糟糕"),
        (2.0, "😐", "平淡"),
        (3.0, "🙂", "还行"),
        (4.0, "😃", "开心"),
        (5.0, "🤩", "极佳")
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("记录心情")
                    .font(.system(.title3, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Close", "关闭"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 24) {
                    Text("记录今天你的整体情绪感受。AI 会基于心率变异性(HRV)等生理指标与心境波动建立深度习惯网络模型。")
                        .font(.system(.footnote, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                    
                    HStack(spacing: 10) {
                        ForEach(moodOptions, id: \.0) { score, emoji, label in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                selectedScore = score
                            } label: {
                                VStack(spacing: 6) {
                                    Text(emoji)
                                        .font(.system(size: 32))
                                    Text(label)
                                        .font(.system(.caption2, design: .default, weight: .bold))
                                        .foregroundStyle(selectedScore == score ? VelaTheme.rhythmInk : VelaTheme.rhythmInkSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 80)
                                .background(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(selectedScore == score ? VelaTheme.rhythmCanvasRaised : VelaTheme.rhythmCanvas)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(selectedScore == score ? VelaTheme.rhythmDeep : VelaTheme.rhythmMist, lineWidth: selectedScore == score ? 1.5 : 0.75)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("今日备注 (可选)")
                            .font(.system(.footnote, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .padding(.leading, 4)
                        
                        TextField("记录一些让你开心或焦虑的小事...", text: $noteText)
                            .font(.system(.footnote, design: .default))
                            .padding(14)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                            )
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onSave(selectedScore, noteText)
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.system(.callout, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeepOn)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.rhythmDeep))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                }
            }
        }
        .background(VelaTheme.rhythmCanvas.ignoresSafeArea())
    }
}

struct AlcoholLoggerView: View {
    @Environment(\.dismiss) private var dismiss
    var onSave: (Double) -> Void
    
    @State private var customDrinks: Double = 1.0
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("记录饮酒")
                    .font(.system(.title3, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.t("Close", "关闭"))
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            ScrollView {
                VStack(spacing: 24) {
                    Text("饮酒可能影响睡眠连续性、夜间心率和次日恢复。影响程度会随摄入量、饮酒时间、睡眠和个体差异而变化；记录后可结合自己的趋势回看。")
                        .font(.system(.footnote, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(4)
                        .padding(.horizontal, 20)
                    
                    VStack(spacing: 16) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(String(format: "%.1f", customDrinks))
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            Text("标准杯")
                                .font(.system(.body, design: .default, weight: .bold))
                                .foregroundStyle(VelaTheme.meta)
                        }
                        
                        HStack(spacing: 40) {
                            Button {
                                VelaHaptic.selection()
                                if customDrinks > 0 {
                                    customDrinks -= 0.5
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            }
                            .buttonStyle(.plain)
                                .accessibilityLabel(L10n.t("Decrease drink", "减少饮水量"))
                                .frame(minWidth: VelaTheme.minimumHitTarget, minHeight: VelaTheme.minimumHitTarget)
                            
                            Button {
                                VelaHaptic.selection()
                                customDrinks += 0.5
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 36))
                                    .foregroundStyle(VelaTheme.rhythmDeep)
                            }
                            .buttonStyle(.plain)
                                .accessibilityLabel(L10n.t("Increase drink", "增加饮水量"))
                                .frame(minWidth: VelaTheme.minimumHitTarget, minHeight: VelaTheme.minimumHitTarget)
                        }
                    }
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
                    .velaNativeCard(radius: 20)
                    .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Text("标准杯换算")
                            .font(.system(.footnote, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        
                        Text("本页按约 10 克纯酒精记为 1 标准杯，便于统一记录。不同地区的标准不同，实际酒精量应以饮品容量和酒精度为准：\n· 普通啤酒约 330 ml、4.5%\n· 红葡萄酒约 150 ml、12%\n· 烈性酒约 45 ml、40%")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineSpacing(5)
                    }
                    .padding(18)
                    .velaNativeCard(radius: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                            .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                    )
                    .padding(.horizontal, 20)
                    
                    Button {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        onSave(customDrinks)
                        dismiss()
                    } label: {
                        Text("保存")
                            .font(.system(.callout, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeepOn)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(VelaTheme.rhythmDeep))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                }
            }
        }
        .background(VelaTheme.rhythmCanvas.ignoresSafeArea())
    }
}
