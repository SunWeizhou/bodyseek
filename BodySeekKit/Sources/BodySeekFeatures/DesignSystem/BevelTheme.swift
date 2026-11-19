import BodySeekCore
import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

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
