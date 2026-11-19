import Foundation
import os

public enum BodySeekSignpostMetric: String, Sendable {
    case appColdStartToFirstFrame = "AppColdStartToFirstFrame"
    case healthKitWindowFetch = "HealthKitWindowFetch"
    case scoringComputeWindow = "ScoringComputeWindow"
    case trendsSeriesCompute = "TrendsSeriesCompute"
    case tabSwitch = "TabSwitch"
    case chartScrub = "ChartScrub"

    fileprivate var staticName: StaticString {
        switch self {
        case .appColdStartToFirstFrame: "AppColdStartToFirstFrame"
        case .healthKitWindowFetch: "HealthKitWindowFetch"
        case .scoringComputeWindow: "ScoringComputeWindow"
        case .trendsSeriesCompute: "TrendsSeriesCompute"
        case .tabSwitch: "TabSwitch"
        case .chartScrub: "ChartScrub"
        }
    }
}

/// Zero-overhead `OSSignposter` bridge for Instruments Time Profiler / Points of Interest.
public final class BodySeekSignposts: @unchecked Sendable {
    public static let shared = BodySeekSignposts()

    private let signposter: OSSignposter
    private let lock = NSLock()
    private var coldStartInterval: OSSignpostIntervalState?
    private var hasFinishedFirstColdStart = false

    public init(subsystem: String = "com.sunweizhou.Vela4", category: String = "Performance") {
        let log = OSLog(subsystem: subsystem, category: category)
        self.signposter = OSSignposter(logHandle: log)
    }

    public func begin(_ metric: BodySeekSignpostMetric) -> OSSignpostIntervalState {
        let id = signposter.makeSignpostID()
        return signposter.beginInterval(metric.staticName, id: id)
    }

    public func end(_ metric: BodySeekSignpostMetric, _ state: OSSignpostIntervalState) {
        signposter.endInterval(metric.staticName, state)
    }

    public func emitEvent(_ metric: BodySeekSignpostMetric, detail: String = "") {
        signposter.emitEvent(metric.staticName, "\(detail, privacy: .public)")
    }

    @discardableResult
    public func measure<T>(_ metric: BodySeekSignpostMetric, operation: () throws -> T) rethrows -> T {
        let state = begin(metric)
        defer { end(metric, state) }
        return try operation()
    }

    @discardableResult
    public func measureAsync<T>(_ metric: BodySeekSignpostMetric, operation: () async throws -> T) async rethrows -> T {
        let state = begin(metric)
        defer { end(metric, state) }
        return try await operation()
    }

    public func beginColdStartIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard !hasFinishedFirstColdStart, coldStartInterval == nil else { return }
        coldStartInterval = begin(.appColdStartToFirstFrame)
    }

    public func endColdStartIfActive() {
        lock.lock()
        let interval = coldStartInterval
        if interval != nil {
            coldStartInterval = nil
            hasFinishedFirstColdStart = true
        }
        lock.unlock()
        if let interval {
            end(.appColdStartToFirstFrame, interval)
        }
    }
}
