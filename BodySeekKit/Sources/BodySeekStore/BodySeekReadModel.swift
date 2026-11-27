import BodySeekCore
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
/// content-hash deduplicated `ValueObservation` streams.
public final class BodySeekReadModel: Sendable {
    public let database: BodySeekDatabase
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "BodySeekReadModel")

    public init(database: BodySeekDatabase) {
        self.database = database
    }
    private typealias ChartCache = [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]

    private struct ChartCacheStore {
        var values: [String: ChartCache] = [:]
        var order: [String] = []
    }

    private static let chartCacheStore = OSAllocatedUnfairLock(
        initialState: ChartCacheStore()
    )



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
        let digest = computeDigest(snapshot: snapshot)
        let chartCache: ChartCache
        if let cached = Self.chartCacheStore.withLock({ $0.values[digest] }) {
            chartCache = cached
        } else {
            let built = BevelScoringEngine.buildAllChartSnapshots(
                days: snapshot.historyDays,
                referenceDate: snapshot.referenceDate,
                calendar: calendar
            )
            Self.chartCacheStore.withLock { state in
                state.values[digest] = built
                state.order.append(digest)
                while state.order.count > 8 {
                    let evicted = state.order.removeFirst()
                    state.values[evicted] = nil
                }
            }
            chartCache = built
        }
        return CachedDashboardState(
            snapshot: snapshot,
            chartCache: chartCache,
            contentDigest: digest
        )
    }

    /// 管线里有哪些内容要参与去重：参考生理日、今天、全部历史日、训练负荷、是否已授权。
    ///
    /// 不含 `referenceDate` 的时刻、`lastUpdatedAt` 和 `sourceLabel`——同一份内容在刷新或换来源时不应被当作新数据。
    private enum DigestFields {
        static func hash(_ snapshot: BodySeekDashboardSnapshot, into hasher: inout Hasher) {
            hasher.combine(snapshot.referenceDate.physiologicalDayKey())
            hasher.combine(snapshot.today)
            hasher.combine(snapshot.historyDays.count)
            for day in snapshot.historyDays {
                hasher.combine(day)
            }
            hasher.combine(snapshot.trainingLoad)
            hasher.combine(snapshot.isAuthorized)
        }
    }

    /// 整份快照的内容摘要，用于去重和缓存键。
    ///
    /// 只在进程内使用，不落盘。逐个字段喂给 `Hasher`，比把三年数据（约 5–6 MB）编码成 JSON 再算 SHA256 快一个数量级；
    /// 参与的字段与 `DigestFields` 一致，内容相同则摘要相同，任何一天的数据变化都会改变摘要。
    public static func computeDigest(snapshot: BodySeekDashboardSnapshot) -> String {
        var hasher = Hasher()
        DigestFields.hash(snapshot, into: &hasher)
        return String(hasher.finalize(), radix: 16)
    }
}
