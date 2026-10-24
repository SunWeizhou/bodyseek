import SwiftUI

struct MetricHighlightsSection: View {
    let isSleep: Bool
    let metricColor: Color
    let leftTitle: String
    let leftIcon: String
    let leftValue: String
    let leftSubtitle: String?
    let rightTitle: String
    let rightIcon: String
    let rightValue: String
    let rightSubtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        Text(leftTitle)
                            .font(VelaTheme.caption1())
                            .fontWeight(.bold)
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Spacer()
                        Image(systemName: leftIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(metricColor)
                    }
                    
                    Text(leftValue)
                        .font(.system(.title2, design: .default, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(.vertical, 2)
                    
                    if let leftSub = leftSubtitle {
                        Text(leftSub)
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineLimit(1)
                    } else {
                        Spacer().frame(height: 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 68).padding(.horizontal, 14)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        Text(rightTitle)
                            .font(VelaTheme.caption1())
                            .fontWeight(.bold)
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        Spacer()
                        Image(systemName: rightIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(metricColor)
                    }
                    
                    Text(rightValue)
                        .font(.system(.title2, design: .default, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(.vertical, 2)
                    
                    if let rightSub = rightSubtitle {
                        Text(rightSub)
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .lineLimit(1)
                    } else {
                        Spacer().frame(height: 10)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        )
    }
}

struct MetricInterpretationSection: View {
    let title: String
    let detail: String
    let evidence: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text("今日建议")
                        .font(VelaTheme.caption1().weight(.bold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    Text(title)
                        .font(VelaTheme.headline())
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text(detail)
                        .font(VelaTheme.subheadline())
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Label(evidence, systemImage: "checkmark.seal")
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(VelaTheme.rhythmMist.opacity(0.4), in: Capsule(style: .continuous))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        )
        .accessibilityElement(children: .combine)
    }
}

struct MetricTrustSection: View {
    let direction: String
    let confidence: String
    let coverage: String
    let updatedAt: String
    let missingSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("如何解读")
                .font(VelaTheme.footnote().weight(.bold))
                .foregroundStyle(VelaTheme.rhythmInk)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    trustItem(title: "方向", value: direction)
                    trustItem(title: "置信度", value: confidence)
                    trustItem(title: "覆盖度", value: coverage)
                }
                VStack(spacing: 8) {
                    trustItem(title: "方向", value: direction)
                    trustItem(title: "置信度", value: confidence)
                    trustItem(title: "覆盖度", value: coverage)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text(updatedAt)
            }
            .font(VelaTheme.caption2())
            .foregroundStyle(VelaTheme.rhythmInkSecondary)

            if let missingSummary {
                Label(missingSummary, systemImage: "exclamationmark.circle")
                    .font(VelaTheme.caption1())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
        )
    }

    private func trustItem(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(VelaTheme.caption2())
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Text(value)
                .font(VelaTheme.caption1().weight(.semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.rhythmCanvas)
        .clipShape(RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous))
    }
}
