import BodySeekCore
import SwiftUI

/// 领域图标底：领域色 × `BSOpacity.faint` 的圆角方块 + 领域色图标（UI v4 §1.2，v4 的 `metric-icon`）。
public struct BSIconBlock: View {
    private let systemImage: String
    private let tint: Color

    /// 创建图标底。
    public init(systemImage: String, tint: Color) {
        self.systemImage = systemImage
        self.tint = tint
    }

    /// 按五项指标取图标与领域色。
    public init(kind: MetricKind) {
        self.systemImage = BSIconBlock.symbol(for: kind)
        self.tint = BSColor.domain(kind)
    }

    /// 五项指标的 SF Symbol。
    public static func symbol(for kind: MetricKind) -> String {
        switch kind {
        case .recovery: "heart.fill"
        case .sleep: "bed.double.fill"
        case .strain: "flame.fill"
        case .stress: "waveform.path.ecg"
        case .energy: "bolt.fill"
        }
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: BSSize.avatar, height: BSSize.avatar)
            .background(
                tint.opacity(BSOpacity.faint),
                in: RoundedRectangle(cornerRadius: BSRadius.s, style: .continuous)
            )
            .accessibilityHidden(true)
    }
}
