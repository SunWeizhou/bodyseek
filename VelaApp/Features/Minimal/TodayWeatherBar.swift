import SwiftUI

struct TodayWeatherBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let weatherTemp: String
    let weatherStatusText: String
    let requestWeatherUpdate: () -> Void

    var body: some View {
        Button {
            requestWeatherUpdate()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "cloud.sun")
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                Text(weatherTemp == "--" ? "天气" : weatherTemp)
                    .font(VelaTheme.subheadline())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(minHeight: VelaTheme.minimumHitTarget)
            .background(VelaTheme.cardBg, in: weatherShape)
            .overlay(weatherShape.stroke(VelaTheme.borderSoft, lineWidth: 0.5))
            .contentShape(weatherShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("天气：\(weatherStatusText)")
        .accessibilityHint("点按更新本地天气")
    }

    private var weatherShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: dynamicTypeSize.isAccessibilitySize ? 16 : VelaTheme.radiusPill,
            style: .continuous
        )
    }
}
