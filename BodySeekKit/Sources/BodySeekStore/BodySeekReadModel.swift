import BodySeekCore
import CryptoKit
import Foundation
import GRDB
import os

public struct CachedDashboardState: Equatable, Sendable {
    public let snapshot: BodySeekDashboardSnapshot
    public let chartCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]
    public let contentDigest: String

    public init(
        snapshot: BodySeekDashboardSnapshot,
        chartCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]],
        contentDigest: String
    ) {
        self.snapshot = snapshot
        self.chartCache = chartCache
        self.contentDigest = contentDigest
    }

    public static func == (lhs: CachedDashboardState, rhs: CachedDashboardState) -> Bool {
        lhs.contentDigest == rhs.contentDigest
    }
}

/// Precomputed GRDB ReadModel providing cold-start snapshot hydration and
/// CryptoKit SHA256 content-hash deduplicated `ValueObservation` streams.
public final class BodySeekReadModel: Sendable {
    public let database: BodySeekDatabase
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "BodySeekReadModel")

    public init(database: BodySeekDatabase) {
        self.database = database
    }

    public func loadCachedDashboard(
        sleepGoalMinutes: Int,
        referenceDate: Date = Date(),
        sourceLabel: String = "Apple 健康",
        isAuthorized: Bool = true,
        calendar: Calendar = .current
    ) async throws -> CachedDashboardState? {
        try await database.writer.read { db in
            try Self.loadCachedDashboardSync(
                db: db,
                sleepGoalMinutes: sleepGoalMinutes,
                referenceDate: referenceDate,
                sourceLabel: sourceLabel,
                isAuthorized: isAuthorized,
                calendar: calendar
            )
        }
    }

    public func observeDashboard(
        sleepGoalMinutes: Int,
        referenceDateProvider: @escaping @Sendable () -> Date = { Date() },
        sourceLabel: String = "Apple 健康",
        isAuthorized: Bool = true,
        calendar: Calendar = .current
    ) -> AsyncThrowingStream<CachedDashboardState, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var lastDigest: String?
                let observation = ValueObservation.tracking { db in
                    try Self.loadCachedDashboardSync(
                        db: db,
                        sleepGoalMinutes: sleepGoalMinutes,
                        referenceDate: referenceDateProvider(),
                        sourceLabel: sourceLabel,
                        isAuthorized: isAuthorized,
                        calendar: calendar
                    )
                }

                do {
                    for try await state in observation.values(in: database.writer) {
                        guard let state else { continue }
                        if state.contentDigest != lastDigest {
                            lastDigest = state.contentDigest
                            continuation.yield(state)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    Self.logger.error("ReadModel ValueObservation failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    static func loadCachedDashboardSync(
        db: Database,
        sleepGoalMinutes: Int,
        referenceDate: Date,
        sourceLabel: String,
        isAuthorized: Bool,
        calendar: Calendar
    ) throws -> CachedDashboardState? {
        let rawDays = try BodySeekRepository.loadRawDaysSync(db: db, calendar: calendar)
        guard !rawDays.isEmpty else { return nil }

        let cachedDays: [DailyComputedDay]
        do {
            cachedDays = try BodySeekRepository.loadComputedDaysSync(
                db: db,
                rawDays: rawDays,
                algorithmVersion: .scoreV2
            )
        } catch {
            Self.logger.error("Failed decoding cached computed days, recomputing: \(error.localizedDescription, privacy: .public)")
            cachedDays = []
        }
        let existingByDayKey = Dictionary(
            cachedDays.map { ($0.dayKey, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        let snapshot = BevelScoringEngine.recomputeIncremental(
            existingByDayKey: existingByDayKey,
            allRawDays: rawDays,
            dirtyDayKeys: [],
            sleepGoalMinutes: sleepGoalMinutes,
            referenceDate: referenceDate,
            sourceLabel: sourceLabel,
            isAuthorized: isAuthorized,
            calendar: calendar
        )
        let chartCache = BevelScoringEngine.buildAllChartSnapshots(
            days: snapshot.historyDays,
            referenceDate: snapshot.referenceDate,
            calendar: calendar
        )
        let digest = try computeDigest(snapshot: snapshot)
        return CachedDashboardState(
            snapshot: snapshot,
            chartCache: chartCache,
            contentDigest: digest
        )
    }

    private struct DigestEnvelope: Encodable {
        let referenceDay: DayKey
        let today: DailyComputedDay
        let historyDays: [DailyComputedDay]
        let trainingLoad: TrainingLoadStatus
        let isAuthorized: Bool
    }

    public static func computeDigest(snapshot: BodySeekDashboardSnapshot) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let payload = DigestEnvelope(
            referenceDay: snapshot.referenceDate.physiologicalDayKey(),
            today: snapshot.today,
            historyDays: snapshot.historyDays,
            trainingLoad: snapshot.trainingLoad,
            isAuthorized: snapshot.isAuthorized
        )
        let data = try encoder.encode(payload)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
