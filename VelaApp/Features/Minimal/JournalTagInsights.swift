import SwiftUI
import SwiftData

struct JournalTagInsights: View {
    let state: BodyModelState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(VelaTheme.accentOn)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: VelaTheme.radiusSm).fill(bodyModelMaturityColor(state.maturity.overall)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("模型成熟度：\(bodyModelMaturityTitle(state.maturity.overall))")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text("\(state.maturity.baselineDays) 天基线 · \(state.maturity.behaviorPairs) 条行为信号 · \(state.maturity.trainingSessions) 次训练事实")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                Spacer()
            }

            if let claim = state.claims.first {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(confidenceColor(claim.confidence))
                        .padding(.top, 2)
                    Text("\(claim.title)：\(claim.summary)")
                        .font(.system(.caption2, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .lineLimit(2)
                }
            } else if !state.uncertainAreas.isEmpty {
                Text("仍有 \(state.uncertainAreas.count) 类证据不足，积累更多记录后再形成结论。")
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
    }

    private func bodyModelMaturityTitle(_ level: BodyModelMaturityLevel) -> String {
        switch level {
        case .seed: return "种子期"
        case .learning: return "学习期"
        case .stable: return "稳定期"
        }
    }

    private func bodyModelMaturityColor(_ level: BodyModelMaturityLevel) -> Color {
        switch level {
        case .seed: return VelaTheme.systemOrange
        case .learning: return VelaTheme.accent
        case .stable: return VelaTheme.success
        }
    }

    private func confidenceColor(_ confidence: DataConfidence) -> Color {
        switch confidence {
        case .high: return VelaTheme.success
        case .medium: return VelaTheme.accent
        case .low: return VelaTheme.systemOrange
        case .unavailable: return VelaTheme.muted
        }
    }

    private func displayConfidence(_ conf: String) -> String {
        switch conf.lowercased() {
        case "high": return L10n.t("High", "高")
        case "medium": return L10n.t("Medium", "中")
        case "low": return L10n.t("Low", "低")
        case "unavailable": return L10n.t("Unavailable", "不可用")
        default: return conf
        }
    }
}
