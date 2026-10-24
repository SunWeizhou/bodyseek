import SwiftUI

struct TodayWeatherBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let weatherTemp: String
    let weatherStatusText: String
    let requestWeatherUpdate: () -> Void

    var body: some View {
        Button {
            VelaHaptic.light()
            requestWeatherUpdate()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "cloud.sun.fill")
                    .symbolRenderingMode(.hierarchical)
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(weatherTemp == "--" ? VelaTheme.rhythmInkSecondary : VelaTheme.rhythmInk)
                Text(weatherTemp == "--" ? "天气" : weatherTemp)
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: VelaTheme.minimumHitTarget)
            .background {
                Capsule(style: .continuous)
                    .fill(VelaTheme.rhythmCanvasRaised)
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(
                        VelaTheme.hairline,
                        lineWidth: VelaTheme.hairlineWidth
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("天气：\(weatherStatusText)")
        .accessibilityHint("点按更新本地天气")
    }
}
