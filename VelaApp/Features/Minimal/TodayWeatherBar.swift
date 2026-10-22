import SwiftUI

struct TodayWeatherBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var colorScheme

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
                    .foregroundStyle(weatherTemp == "--" ? VelaTheme.rhythmInkSecondary : Color(hex: "#38BDF8"))
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
                        colorScheme == .dark
                            ? Color.white.opacity(0.10)
                            : VelaTheme.rhythmMist.opacity(0.70),
                        lineWidth: 0.75
                    )
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.cardPress)
        .accessibilityLabel("天气：\(weatherStatusText)")
        .accessibilityHint("点按更新本地天气")
    }
}
