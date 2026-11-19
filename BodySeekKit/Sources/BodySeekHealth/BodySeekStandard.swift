import Foundation
import Spezi
import SpeziHealthKit
import SpeziLLM
import SpeziLLMOpenAI

#if os(iOS)
import HealthKit

public final actor BodySeekStandard: Standard, HealthKitConstraint {
    private var continuations: [UUID: AsyncStream<Void>.Continuation] = [:]

    public init() {}

    public func updates() -> AsyncStream<Void> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    private func broadcastChange() {
        for continuation in continuations.values {
            continuation.yield(())
        }
    }

    public func handleNewSamples<Sample>(
        _ addedSamples: some Collection<Sample> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) async {
        guard !addedSamples.isEmpty else { return }
        broadcastChange()
    }

    public func handleDeletedObjects<Sample>(
        _ deletedObjects: some Collection<HKDeletedObject> & Sendable,
        ofType sampleType: SampleType<Sample>
    ) async {
        guard !deletedObjects.isEmpty else { return }
        broadcastChange()
    }
}

public enum BodySeekSpeziConfiguration {
    @MainActor
    public static func makeConfiguration(standard: BodySeekStandard) -> Configuration {
        let defaultServer = URL(string: "https://api.deepseek.com/v1")!
        return Configuration(standard: standard) {
            HealthKit {
                CollectSamples(.heartRateVariabilitySDNN, continueInBackground: true)
                CollectSamples(.restingHeartRate, continueInBackground: true)
                CollectSamples(.sleepAnalysis, continueInBackground: true)
                CollectSamples(.workout, continueInBackground: true)
                CollectSamples(.activeEnergyBurned)
                CollectSamples(.appleExerciseTime)
                RequestReadAccess(
                    quantity: [
                        .heartRate,
                        .stepCount,
                        .respiratoryRate,
                        .bloodOxygen,
                        .appleSleepingWristTemperature,
                        .workoutEffortScore,
                        .estimatedWorkoutEffortScore,
                        .physicalEffort,
                        .walkingHeartRateAverage,
                        .vo2Max,
                        .heartRateRecoveryOneMinute,
                        .bodyMass,
                    ]
                )
                RequestWriteAccess(
                    quantity: [.activeEnergyBurned],
                    other: [SampleType.workout]
                )
            }
            LLMRunner {
                LLMOpenAIPlatform(
                    configuration: .init(
                        serverUrl: defaultServer,
                        authToken: .none,
                        middlewares: [DynamicServerURLMiddleware()]
                    )
                )
            }
            BodySeekHealthBridgeModule.shared
        }
    }
}

public final class BodySeekHealthBridgeModule: Module, @unchecked Sendable {
    public static let shared = BodySeekHealthBridgeModule()

    @Dependency(HealthKit.self) private var healthKit
    @Dependency(LLMRunner.self) private var llmRunner
    private weak var standardRef: BodySeekStandard?

    private init() {}

    @MainActor
    public func configure() {
        _ = healthKit
        _ = llmRunner
    }

    @MainActor
    public func register(standard: BodySeekStandard) {
        self.standardRef = standard
    }

    @MainActor
    public var currentHealthKit: HealthKit? {
        healthKit
    }

    @MainActor
    public var currentLLMRunner: LLMRunner? {
        llmRunner
    }

    public func updateStream() async -> AsyncStream<Void> {
        if let standardRef {
            return await standardRef.updates()
        }
        return AsyncStream { $0.finish() }
    }
}
#endif
