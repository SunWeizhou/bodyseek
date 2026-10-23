import SwiftUI

struct DataFreshnessIndicator: View {
    let freshness: DataFreshness
    var showText: Bool = true

    var body: some View {
        HStack(spacing: 4) {
            indicatorIcon
            if showText {
                Text(localizedText)
                    .font(VelaTheme.caption2())
                    .foregroundStyle(textColor)
            }
        }
    }

    @ViewBuilder
    private var indicatorIcon: some View {
        switch freshness {
        case .live, .today:
            Circle()
                .fill(VelaTheme.rhythmInk)
                .frame(width: 6, height: 6)
        case .recent:
            Circle()
                .fill(VelaTheme.fg2)
                .frame(width: 6, height: 6)
        case .stale:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 8))
                .foregroundStyle(VelaTheme.warn)
        case .missing:
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 8))
                .foregroundStyle(VelaTheme.danger)
        }
    }

    private var localizedText: String {
        switch freshness {
        case .live: return "实时"
        case .today: return "今日"
        case .recent: return "近期"
        case .stale: return "数据较旧"
        case .missing: return "未同步"
        }
    }

    private var textColor: Color {
        switch freshness {
        case .live, .today: return VelaTheme.rhythmInk
        case .recent: return VelaTheme.fg2
        case .stale: return VelaTheme.warn
        case .missing: return VelaTheme.danger
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        DataFreshnessIndicator(freshness: .live)
        DataFreshnessIndicator(freshness: .today)
        DataFreshnessIndicator(freshness: .recent)
        DataFreshnessIndicator(freshness: .stale)
        DataFreshnessIndicator(freshness: .missing)
    }
    .padding()
    .background(VelaTheme.bg)
}
