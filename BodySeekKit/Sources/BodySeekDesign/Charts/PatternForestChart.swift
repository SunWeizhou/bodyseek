import BodySeekCore
import Charts
import SwiftUI

/// Standard Apple Swift Charts forest plot displaying M4a statistical pattern effects and 95% confidence intervals relative to zero.
public struct PatternForestChart: View {
    public let findings: [PatternFindingRecord]
    public let height: CGFloat

    private struct ForestRow: Identifiable {
        let id: UUID
        let label: String
        let lowNorm: Double
        let midNorm: Double
        let highNorm: Double
        let effectText: String
        let isPositive: Bool
        let isConfirmed: Bool
    }

    public init(
        findings: [PatternFindingRecord],
        height: CGFloat = 176
    ) {
        self.findings = findings
        self.height = height
    }

    public var body: some View {
        let rows = Array(findings.filter { $0.status != .dismissed }.prefix(4)).map(makeRow)

        if rows.isEmpty {
            Text("暂无足够的规律置信区间可绘制。")
                .font(.caption)
                .foregroundStyle(BevelTheme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Chart {
                    RuleMark(x: .value("零效应", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(BevelTheme.inkSecondary.opacity(0.55))

                    ForEach(rows) { row in
                        let tint = row.isPositive ? BevelTheme.recoveryColor : BevelTheme.strainColor

                        RuleMark(
                            xStart: .value("95% CI 下界", row.lowNorm),
                            xEnd: .value("95% CI 上界", row.highNorm),
                            y: .value("规律", row.label)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .foregroundStyle(tint.opacity(0.55))

                        PointMark(
                            x: .value("均值效应", row.midNorm),
                            y: .value("规律", row.label)
                        )
                        .symbol {
                            Circle()
                                .fill(tint)
                                .overlay(
                                    Circle()
                                        .strokeBorder(row.isConfirmed ? BevelTheme.brand : BevelTheme.card, lineWidth: 1.6)
                                )
                                .frame(width: 9, height: 9)
                        }
                        .annotation(
                            position: row.midNorm >= 0 ? .trailing : .leading,
                            spacing: 6
                        ) {
                            Text(row.effectText)
                                .font(.caption2.weight(.semibold).monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(tint)
                        }
                    }
                }
                .chartXScale(domain: -3.2...3.2)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label)
                                    .font(.caption2)
                                    .foregroundStyle(BevelTheme.ink)
                            }
                        }
                    }
                }
                .frame(height: max(108, min(height, CGFloat(rows.count) * 40 + 16)))

                Text("虚线为零效应基线，横线为 95% 置信区间（已按各自尺度对齐，标注为原始均值变化）")
                    .font(.caption2)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
        }
    }

    private func makeRow(_ finding: PatternFindingRecord) -> ForestRow {
        let low = min(finding.ciLow, finding.ciHigh)
        let high = max(finding.ciLow, finding.ciHigh)
        let maxAbs = max(abs(low), abs(high), abs(finding.effect), 1e-6)
        let scale = maxAbs / 2.0

        let shortLabel = conciseTitle(from: finding.statement)
        let sign = finding.effect >= 0 ? "+" : ""
        let effectText = String(format: "%@%.1f%@", sign, finding.effect, inferUnit(from: finding.statement))

        return ForestRow(
            id: finding.id,
            label: shortLabel,
            lowNorm: low / scale,
            midNorm: finding.effect / scale,
            highNorm: high / scale,
            effectText: effectText,
            isPositive: finding.effect >= 0,
            isConfirmed: finding.status == .confirmed
        )
    }

    private func conciseTitle(from statement: String) -> String {
        let head = statement.components(separatedBy: "（").first ?? statement
        let cleaned = head
            .replacingOccurrences(of: "，次日", with: "→次日")
            .replacingOccurrences(of: "后，", with: "→")
            .replacingOccurrences(of: "平均变化 ", with: "")
            .replacingOccurrences(of: "平均高 ", with: "")
            .replacingOccurrences(of: "平均偏高 ", with: "")
            .replacingOccurrences(of: "平均低 ", with: "")
        if cleaned.count <= 14 {
            return cleaned
        }
        return String(cleaned.prefix(13)) + "…"
    }

    private func inferUnit(from statement: String) -> String {
        if statement.contains("分钟") { return "分" }
        if statement.contains("ms") { return "ms" }
        if statement.contains("bpm") { return "bpm" }
        return ""
    }
}
