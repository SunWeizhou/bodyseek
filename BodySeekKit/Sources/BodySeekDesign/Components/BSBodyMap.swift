import MuscleMap
import SwiftUI

/// 人体肌群图的朝向。
public enum BSBodySide: Sendable, Hashable, CaseIterable {
    /// 正面。
    case front
    /// 背面。
    case back
}

/// 肌群热力图：包装 `MuscleMap`，只暴露字符串键，页面不需要直接依赖第三方类型。
///
/// 颜色全部来自令牌：充分恢复 = 轨道色，随疲劳加深依次为强调色、能量色、负荷色。
public struct BSBodyMap: View {
    private let side: BSBodySide
    private let intensities: [String: Double]
    private let selected: String?
    private let onSelect: ((String) -> Void)?

    /// 创建肌群图。
    /// - Parameters:
    ///   - side: 正面或背面。
    ///   - intensities: 肌群原始值（`Muscle.rawValue`）到 0–1 疲劳强度的字典；不认识的键被忽略。
    ///   - selected: 当前选中的肌群原始值。
    ///   - onSelect: 点击某个肌群时的回调。
    public init(
        side: BSBodySide,
        intensities: [String: Double],
        selected: String? = nil,
        onSelect: ((String) -> Void)? = nil
    ) {
        self.side = side
        self.intensities = intensities
        self.selected = selected
        self.onSelect = onSelect
    }

    public var body: some View {
        BodyView(gender: .male, side: mapSide, style: mapStyle)
            .heatmap(heat, colorScale: colorScale)
            .selected(selectedMuscle)
            .onMuscleSelected { muscle, _ in
                onSelect?(muscle.rawValue)
            }
            .bodyseekSelectionHaptic(trigger: selected)
            .frame(width: BSSize.bodyMapWidth, height: BSSize.bodyMapHeight)
    }

    private var mapSide: BodySide {
        switch side {
        case .front: .front
        case .back: .back
        }
    }

    private var heat: [MuscleIntensity] {
        intensities.compactMap { key, value in
            guard let muscle = Muscle(rawValue: key) else { return nil }
            return MuscleIntensity(muscle: muscle, intensity: value)
        }
    }

    private var selectedMuscle: Muscle? {
        selected.flatMap { Muscle(rawValue: $0) }
    }

    /// 肌群疲劳的四段色标：0 = 充分恢复（轨道色），随疲劳加深依次为轻度残留、能量色、负荷色。
    /// 人体图和肌群列表的疲劳条共用这一条色标，同一个数值在两处才是同一种颜色。
    private static let fatigueScale = HeatmapColorScale(colors: [
        BSColor.surfaceInset,
        BSColor.tint.opacity(BSOpacity.disabled),
        BSColor.energy,
        BSColor.strain,
    ])

    /// 疲劳强度（0–1）对应的颜色；超出范围按端点取。
    public static func fatigueColor(intensity: Double) -> Color {
        let clamped = Swift.min(1, Swift.max(0, intensity.isFinite ? intensity : 0))
        return fatigueScale.color(for: clamped)
    }

    private var colorScale: HeatmapColorScale {
        Self.fatigueScale
    }

    private var mapStyle: BodyViewStyle {
        BodyViewStyle(
            defaultFillColor: BSColor.surfaceInset,
            strokeColor: BSColor.separator,
            strokeWidth: BSChartStroke.rule,
            selectionColor: BSColor.tint.opacity(BSOpacity.muted),
            selectionStrokeColor: BSColor.tint,
            selectionStrokeWidth: BSChartStroke.data,
            headColor: BSColor.surfaceInset,
            hairColor: Color.secondary
        )
    }
}
