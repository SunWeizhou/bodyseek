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

        let targetVersion = AlgorithmVersion.scoreV2.description
        let scoreRows = try Row.fetchAll(
            db,
            sql: """
            SELECT day_key, kind, value, state, reason, baseline_delta, badge, subtitle, contributors_json
            FROM score_snapshot
            WHERE algorithm_version = ?
            """,
            arguments: [targetVersion]
        )

        let artifactRows = try Row.fetchAll(
            db,
            sql: """
            SELECT day_key, date, energy_curve_json, stress_timeline_json, factual_summary, evidence_summary
            FROM day_computed_artifact
            WHERE algorithm_version = ?
            """,
            arguments: [targetVersion]
        )

        let decoder = JSONDecoder()
        var scoresByDayAndKind: [String: [MetricKind: MetricScore]] = [:]
        for row in scoreRows {
            let dayKeyStr: String = row["day_key"]
            let kindStr: String = row["kind"]
            guard let kind = MetricKind(rawValue: kindStr) else { continue }

            let valueInt: Int? = row["value"]
            let stateStr: String = row["state"]
            let reasonStr: String = (row["reason"] as String?) ?? ""
            let availability: MetricAvailability
            switch stateStr {
            case ObservationStateTag.available.rawValue:
                availability = .available
            case ObservationStateTag.knownZero.rawValue:
                availability = .knownZero(reason: reasonStr)
            case ObservationStateTag.excluded.rawValue:
                availability = .excluded(reason: reasonStr)
            default:
                availability = .missing(reason: reasonStr)
            }

            let contribJSON: String = row["contributors_json"]
            let contributors = try decoder.decode([MetricContributor].self, from: Data(contribJSON.utf8))
            scoresByDayAndKind[dayKeyStr, default: [:]][kind] = MetricScore(
                kind: kind,
                value: valueInt,
                availability: availability,
                badge: row["badge"],
                subtitle: row["subtitle"],
                baselineDelta: row["baseline_delta"],
                algorithmVersion: .scoreV2,
                contributors: contributors
            )
        }

        struct ArtifactRecord {
            let date: Date
            let energyCurve: [EnergyCurvePoint]
            let stressTimeline: [StressTimelineBin]
            let factualSummary: String
            let evidenceSummary: String
        }
        var artifactsByDay: [String: ArtifactRecord] = [:]
        for row in artifactRows {
            let dayKeyStr: String = row["day_key"]
            let curve = try decoder.decode([EnergyCurvePoint].self, from: Data((row["energy_curve_json"] as String).utf8))
            let stress = try decoder.decode([StressTimelineBin].self, from: Data((row["stress_timeline_json"] as String).utf8))
            artifactsByDay[dayKeyStr] = ArtifactRecord(
                date: Date(timeIntervalSince1970: row["date"]),
                energyCurve: curve,
                stressTimeline: stress,
                factualSummary: row["factual_summary"],
                evidenceSummary: row["evidence_summary"]
            )
        }

        var existingByDayKey: [DayKey: DailyComputedDay] = [:]
        for raw in rawDays {
            let key = raw.dayKey ?? raw.date.physiologicalDayKey(cutoverHour: 4, timeZone: calendar.timeZone)
            let keyStr = key.isoString
            if let scores = scoresByDayAndKind[keyStr],
               scores.count == MetricKind.allCases.count,
               let rec = scores[.recovery],
               let slp = scores[.sleep],
               let str = scores[.strain],
               let sts = scores[.stress],
               let eng = scores[.energy],
               let artifact = artifactsByDay[keyStr]
            {
                existingByDayKey[key] = DailyComputedDay(
                    date: artifact.date,
                    dayKey: key,
                    raw: raw,
                    recovery: rec,
                    sleep: slp,
                    strain: str,
                    stress: sts,
                    energy: eng,
                    energyCurve: artifact.energyCurve,
                    stressTimeline: artifact.stressTimeline,
                    factualSummary: artifact.factualSummary,
                    evidenceSummary: artifact.evidenceSummary,
                    algorithmVersion: .scoreV2
                )
            }
        }

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
