import SwiftUI
import UIKit

enum VelaFeatureFlags {
    static let bevelParityInterfaceKey = "vela.feature.bevelParityInterface"

    /// Product scope switches: hide secondary entries while keeping the code.
    /// Nutrition is off to keep the train–recover loop. Biological age stays
    /// compiled but is not a default Fact / Today instrument readout (PRD
    /// non-goal). Flip `biologicalAgeEnabled` after re-validation.
    static let nutritionEnabled = false
    static let biologicalAgeEnabled = false

    /// Compact Fact snapshot, Today instrument, and equivalent primary readouts.
    static var showsBiologicalAgeInPrimaryFact: Bool { biologicalAgeEnabled }

    static func bevelParityInterfaceEnabled(
        defaults: UserDefaults = .standard,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if arguments.contains("-velaLegacyInterface") { return false }
        if arguments.contains("-velaBevelParityInterface") { return true }
        // Rhythm is now the production information architecture. The former
        // Bevel-parity shell remains available for visual regression work, but
        // it must be opted into explicitly instead of defining the product.
        guard defaults.object(forKey: bevelParityInterfaceKey) != nil else {
            return false
        }
        return defaults.bool(forKey: bevelParityInterfaceKey)
    }
}

struct VelaRootView: View {
    var body: some View {
        VelaShell()
    }
}
