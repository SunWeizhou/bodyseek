@_exported import BodySeekAgent
@_exported import BodySeekCore
@_exported import BodySeekDesign
@_exported import BodySeekFeatures
@_exported import BodySeekHealth
import ComposableArchitecture
import Spezi
import SwiftUI

final class BodySeekAppDelegate: SpeziAppDelegate {
    private let standard = BodySeekStandard()

    override var configuration: Configuration {
        let cfg = BodySeekSpeziConfiguration.makeConfiguration(standard: standard)
        BodySeekHealthBridgeModule.shared.register(standard: standard)
        return cfg
    }
}

@main
struct VelaApp: App {
    @ApplicationDelegateAdaptor(BodySeekAppDelegate.self) private var appDelegate
    private let store: StoreOf<AppFeature>?
    private let isUnitTestHost: Bool

    init() {
        let runningUnitTests = NSClassFromString("XCTestCase") != nil
        self.isUnitTestHost = runningUnitTests
        if runningUnitTests {
            self.store = nil
        } else {
            self.store = Store(initialState: AppFeature.State()) {
                AppFeature()
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            if isUnitTestHost {
                Color.clear
            } else if let store {
                RootTabView(store: store)
                    .spezi(appDelegate)
            }
        }
    }
}
