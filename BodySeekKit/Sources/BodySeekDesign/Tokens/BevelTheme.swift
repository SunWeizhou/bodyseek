import BodySeekCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

public enum BodySeekMotion {
    public static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
}

public enum BevelTheme {
    private static func hexRGBA(_ value: String) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        switch hex.count {
        case 6:
            return (
                CGFloat((int >> 16) & 0xFF) / 255,
                CGFloat((int >> 8) & 0xFF) / 255,
                CGFloat(int & 0xFF) / 255,
                1
            )
        case 8:
            return (
                CGFloat((int >> 16) & 0xFF) / 255,
                CGFloat((int >> 8) & 0xFF) / 255,
                CGFloat(int & 0xFF) / 255,
                CGFloat((int >> 24) & 0xFF) / 255
            )
        default:
            return (0, 0, 0, 1)
        }
    }

    public static func adaptive(_ light: String, _ dark: String) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { traits in
            let rgba = hexRGBA(traits.userInterfaceStyle == .dark ? dark : light)
            return UIColor(red: rgba.r, green: rgba.g, blue: rgba.b, alpha: rgba.a)
        })
        #else
        let rgba = hexRGBA(light)
        return Color(.sRGB, red: rgba.r, green: rgba.g, blue: rgba.b, opacity: rgba.a)
        #endif
    }

    // MARK: - Canvas & Surfaces

    public static let canvas = adaptive("#F2F2F7", "#000000")
    public static let card = adaptive("#FFFFFF", "#1C1C1E")
    public static let surfaceElevated = adaptive("#F2F2F7", "#2C2C2E")
    public static let hairline = adaptive("#E5E5EA", "#2C2C2E")
    public static let scoreTrack = adaptive("#E9E9EE", "#242426")
    public static let rangeBand = adaptive("#E5E5EA", "#2C2C2E")

    // MARK: - Text & Neutral Ink

    public static let ink = adaptive("#111111", "#F5F5F7")
    public static let inkSecondary = adaptive("#5E5E63", "#98989D")
    public static let deviationInk = adaptive("#5E5E63", "#9A9A9E")

    // MARK: - Brand Accent

    public static let brand = adaptive("#0F755D", "#34D399")
    public static let onBrand = adaptive("#FFFFFF", "#052019")
    public static let brandSoft = adaptive("#E6F5F0", "#0E2922")

    // MARK: - Semantic Metric Colors

    public static let recoveryColor = adaptive("#168B70", "#34D399")
    public static let sleepColor = adaptive("#5E5CE6", "#8F8DFF")
    public static let strainColor = adaptive("#D85A20", "#FF9565")
    public static let stressColor = adaptive("#D9466E", "#FF7596")
    public static let energyColor = adaptive("#B4730A", "#F5BC47")
    public static let heartRateAverage = adaptive("#FF5252", "#FF6B6B")
    public static let infoBlue = adaptive("#30A2FF", "#5AB0FF")

    public static let dangerColor = adaptive("#D92D20", "#FF6B6B")

    // MARK: - Daily Nutrition 4-State Circle Tokens (每日营养素)

    public static let nutritionMet = adaptive("#4A9D72", "#4A9D72")
    public static let nutritionLow = adaptive("#D79939", "#D79939")
    public static let nutritionOver = adaptive("#D65C5C", "#D65C5C")
    public static let nutritionUnknown = adaptive("#8A9099", "#8A9099")

    public static func nutritionColor(for status: NutritionReadingStatus) -> Color {
        switch status {
        case .met: nutritionMet
        case .low: nutritionLow
        case .over: nutritionOver
        case .unknown: nutritionUnknown
        }
    }

    public static func nutritionInkColor(for status: NutritionReadingStatus) -> Color {
        switch status {
        case .met: adaptive("#226B46", "#6AD198")
        case .low: adaptive("#8B5A0B", "#F2B857")
        case .over: adaptive("#A42D2D", "#F28080")
        case .unknown: inkSecondary
        }
    }

    public static func color(for kind: MetricKind) -> Color {
        switch kind {
        case .recovery: recoveryColor
        case .sleep: sleepColor
        case .strain: strainColor
        case .stress: stressColor
        case .energy: energyColor
        }
    }

    public static func sleepStageColor(_ stage: SleepStage) -> Color {
        switch stage {
        case .deep: adaptive("#4F46E5", "#818CF8")
        case .core: adaptive("#0EA5E9", "#38BDF8")
        case .rem: adaptive("#14B8A6", "#2DD4BF")
        case .awake: adaptive("#F97316", "#FB923C")
        }
    }
}

public extension View {
    /// Unified BodySeek grouped card surface with subtle hairline stroke and continuous corner radius.
    func bodySeekSurface(cornerRadius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BevelTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(BevelTheme.hairline.opacity(0.6), lineWidth: 0.5)
            )
    }

    /// Liquid pill control chrome compatible with iOS 26 glass surfaces and clean grouped fallback.
    @ViewBuilder
    func bodySeekLiquidPill(isSelected: Bool, tint: Color = BevelTheme.brand) -> some View {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            self
                .background(
                    isSelected ? tint.opacity(0.20) : BevelTheme.card,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? tint.opacity(0.70) : BevelTheme.hairline.opacity(0.75),
                            lineWidth: isSelected ? 1.2 : 0.5
                        )
                )
        } else {
            self
                .background(isSelected ? tint.opacity(0.20) : BevelTheme.surfaceElevated, in: Capsule())
        }
        #else
        self
            .background(isSelected ? tint.opacity(0.16) : BevelTheme.surfaceElevated, in: Capsule())
        #endif
    }
}
