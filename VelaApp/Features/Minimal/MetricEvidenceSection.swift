import SwiftUI

struct EvidenceItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
}

struct MetricEvidenceSection: View {
    let isSleep: Bool
    let items: [EvidenceItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("数据依据")
                .font(VelaTheme.footnote().weight(.bold))
                .foregroundStyle(VelaTheme.rhythmInk)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    VelaEvidenceRow(
                        title: item.title,
                        detail: item.detail,
                        value: item.value,
                        tint: isSleep ? VelaTheme.rhythmInk : VelaTheme.rhythmDeep
                    )

                    if index < items.count - 1 {
                        Divider().padding(.leading, 58)
                    }
                }
            }
            .background(VelaTheme.rhythmCanvasRaised, in: RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusCard, style: .continuous)
                    .stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth)
            )
        }
        .accessibilityIdentifier("metric-detail-evidence")
    }
}
