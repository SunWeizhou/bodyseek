import Foundation
import XCTest
@testable import BodySeekDomain

/// Production sleep-score behavior. These cases used to construct the unused
/// in-app `SleepScoreEngine`; they now call `BodySeekDomain.SleepScoreEngine`.
final class SleepScoreEngineBehaviorTests: XCTestCase {

    func testSleepScoreEngineProducesValidRange() {
        let engine = SleepScoreEngine()
        let input = SleepScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            totalSleepMinutes: 420,
            sleepTargetMinutes: 480,
            awakeMinutes: 15,
            awakeEpisodeCount: 2,
            remMinutes: 90,
            deepMinutes: 90
        )
        let result = engine.calculate(from: input)
        XCTAssertGreaterThanOrEqual(result.value ?? 0, 0)
        XCTAssertLessThanOrEqual(result.value ?? 0, 100)
    }
    func testSleepScoreEngineAwakeCountDistinguishesMeasuredFactFromEstimate() {
        let engine = SleepScoreEngine()

        // 1. Measured awakeEpisodeCount should report as detected fact (no "估算")
        let measuredInput = SleepScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            totalSleepMinutes: 420,
            sleepTargetMinutes: 480,
            awakeMinutes: 20,
            awakeEpisodeCount: 3
        )
        let measuredResult = engine.calculate(from: measuredInput)
        let measuredInterruptionReason = measuredResult.reasons.first { $0.contains("睡眠中断") } ?? ""
        XCTAssertTrue(measuredInterruptionReason.contains("醒来频率 3次"))
        XCTAssertFalse(measuredInterruptionReason.contains("估算"))

        // 2. Missing awakeEpisodeCount with awakeMinutes > 0 must explicitly declare "估算"
        let estimatedInput = SleepScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            totalSleepMinutes: 420,
            sleepTargetMinutes: 480,
            awakeMinutes: 24,
            awakeEpisodeCount: nil
        )
        let estimatedResult = engine.calculate(from: estimatedInput)
        let estimatedInterruptionReason = estimatedResult.reasons.first { $0.contains("睡眠中断") } ?? ""
        XCTAssertTrue(estimatedInterruptionReason.contains("醒来频率约 3次 · 估算"))
    }
    func testSleepTargetCompletionReasonUsesExactObservedMinutes() {
        let engine = SleepScoreEngine()
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)

        func durationReason(sleepMinutes: Double?, targetMinutes: Double = 360) -> String {
            let result = engine.calculate(from: SleepScoreInput(
                asOf: asOf,
                totalSleepMinutes: sleepMinutes,
                sleepTargetMinutes: targetMinutes,
                awakeMinutes: 0
            ))
            return result.reasons.first { $0.hasPrefix("睡眠时长") } ?? ""
        }

        let adequacyNote = "；注：依据 AASM 成人共识，成人健康睡眠建议为 7–9 小时，达成个人作息目标不代表生理充分满足"
        XCTAssertEqual(durationReason(sleepMinutes: 240), "睡眠时长 4小时0分钟（未达成个人作息目标 6小时\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: 360), "睡眠时长 6小时0分钟（已达成个人作息目标 6小时\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: 390), "睡眠时长 6小时30分钟（已达成个人作息目标 6小时；超过目标30分钟\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: 359), "睡眠时长 5小时59分钟（未达成个人作息目标 6小时\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: 390, targetMinutes: 390), "睡眠时长 6小时30分钟（已达成个人作息目标 6小时30分钟\(adequacyNote)）")
        XCTAssertEqual(durationReason(sleepMinutes: nil), "")
    }
    func testSleepEvidenceTreatsMissingStagesAsUnknownInsteadOfZero() {
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let result = SleepScoreEngine().calculate(from: SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: 450,
            awakeMinutes: 12,
            awakeEpisodeCount: nil
        ))

        XCTAssertNotNil(result.value)
        XCTAssertEqual(result.components["sleep_efficiency"] ?? -1, 450.0 / 462.0 * 100.0, accuracy: 0.001)
        XCTAssertNil(result.components["rem_pct"])
        XCTAssertNil(result.components["deep_pct"])
        XCTAssertFalse(result.missingInputs.contains("inBedMinutes"))
        XCTAssertTrue(result.missingInputs.contains("remMinutes"))
        XCTAssertTrue(result.missingInputs.contains("deepMinutes"))
        XCTAssertTrue(result.reasons.contains { $0.contains("估算") })
        XCTAssertEqual(result.algorithmVersion, "sleep.v2.2.0")
    }
    func testSleepEvidenceDoesNotPublishArchitectureWhenOneStageIsMissing() {
        let result = SleepScoreEngine().calculate(from: SleepScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            totalSleepMinutes: 450,
            remMinutes: 90,
            deepMinutes: nil
        ))

        XCTAssertNil(result.components["deep_pct"])
        XCTAssertNil(result.components["buysse_architecture"])
        XCTAssertTrue(result.missingInputs.contains("deepMinutes"))
    }
    func testSleepZeroDurationIsUnknownEvenWhenOtherSignalsExist() {
        let result = SleepScoreEngine().calculate(from: SleepScoreInput(
            asOf: Date(timeIntervalSince1970: 1_700_000_000),
            totalSleepMinutes: 0,
            awakeMinutes: 0
        ))

        XCTAssertNil(result.value)
        XCTAssertEqual(result.dataCoverage, .unavailable)
        XCTAssertTrue(result.missingInputs.contains("totalSleepMinutes"))
        XCTAssertFalse(result.reasons.contains { $0.contains("0小时") })
    }
    func testSleepStaleEvidenceRetainsValueButLowersConfidence() {
        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let range = DateInterval(start: asOf.addingTimeInterval(-86_400), end: asOf)
        let observed = SleepComponentObservation(value: 450, availability: .observed, observedWindow: range)
        let staleEvidence = SleepEvidenceContext(
            queryOutcome: .transient,
            freshness: .stale,
            totalSleep: observed,
            bedtime: .missing("查询失败"),
            wakeTime: .missing("查询失败"),
            inBed: .missing("查询失败"),
            awake: .missing("查询失败"),
            rem: .missing("查询失败"),
            deep: .missing("查询失败"),
            episodeCount: .missing("查询失败")
        )
        let result = SleepScoreEngine().calculate(from: SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: 450,
            sleepTargetMinutes: 450,
            evidence: staleEvidence
        ))

        XCTAssertNotNil(result.value)
        XCTAssertEqual(result.confidence, .low)
        XCTAssertTrue(result.reasons.contains { $0.contains("陈旧") })
        XCTAssertTrue(result.reasons.contains { $0.contains("transient") })
    }
    func testS4SleepTargetBehavioralGoalDoesNotClaimAASMPhysiologicalAdequacy() {
        let asOf = Date()
        let engine = SleepScoreEngine()

        // User sets target to 5h (300 min) and sleeps exactly 5h (300 min)
        let inputShortTarget = SleepScoreInput(
            asOf: asOf,
            totalSleepMinutes: 300,
            sleepTargetMinutes: 300,
            awakeMinutes: 15,
            awakeEpisodeCount: nil // missing awake episode count
        )
        let result = engine.calculate(from: inputShortTarget)
        
        // Check reasons for behavioral qualification vs physiological adequacy
        let hasBehavioralNotice = result.reasons.contains { $0.contains("AASM") || $0.contains("生理充分满足") }
        XCTAssertTrue(hasBehavioralNotice, "Short sleep target completion must explicitly clarify behavioral vs physiological adequacy")

        let hasAwakeEstimateNotice = result.reasons.contains { $0.contains("估算") }
        XCTAssertTrue(hasAwakeEstimateNotice, "Missing awake count must be flagged as estimated")
    }
    func testGenerateSleepSemanticsReplayContract() throws {
        struct ComponentDTO: Codable {
            var value: Double?
            var availability: String
            var reason: String?
        }

        struct ScenarioDTO: Codable {
            var scenario: String
            var oldValue: Double?
            var newValue: Double?
            var queryOutcome: String?
            var freshness: String?
            var components: [String: ComponentDTO]
            var dataCoverage: String
            var confidence: String
            var missingInputs: [String]
            var reasons: [String]
            var algorithmVersion: String
        }

        let asOf = Date(timeIntervalSince1970: 1_700_000_000)
        let range = DateInterval(start: asOf.addingTimeInterval(-86_400), end: asOf)
        func observed(_ value: Double) -> SleepComponentObservation {
            SleepComponentObservation(value: value, availability: .observed, observedWindow: range)
        }
        func missing(_ reason: String) -> SleepComponentObservation {
            SleepComponentObservation(value: nil, availability: .missing, reason: reason, observedWindow: range)
        }
        func context(
            outcome: HealthQueryOutcomeKind,
            freshness: DataFreshness,
            total: SleepComponentObservation,
            bedtime: SleepComponentObservation,
            wake: SleepComponentObservation,
            inBed: SleepComponentObservation,
            awake: SleepComponentObservation,
            rem: SleepComponentObservation,
            deep: SleepComponentObservation,
            episodeCount: SleepComponentObservation
        ) -> SleepEvidenceContext {
            SleepEvidenceContext(
                queryOutcome: outcome,
                freshness: freshness,
                totalSleep: total,
                bedtime: bedtime,
                wakeTime: wake,
                inBed: inBed,
                awake: awake,
                rem: rem,
                deep: deep,
                episodeCount: episodeCount
            )
        }

        let scenarios: [(String, Double?, SleepEvidenceContext)] = [
            (
                "observed_complete",
                78,
                context(
                    outcome: .data,
                    freshness: .today,
                    total: observed(450),
                    bedtime: observed(asOf.timeIntervalSinceReferenceDate - 8 * 3_600),
                    wake: observed(asOf.timeIntervalSinceReferenceDate),
                    inBed: observed(480),
                    awake: observed(30),
                    rem: observed(90),
                    deep: observed(80),
                    episodeCount: SleepComponentObservation(value: 2, availability: .estimated, reason: "由清醒片段估算醒来次数", observedWindow: range)
                )
            ),
            (
                "estimated_efficiency",
                70,
                context(
                    outcome: .data,
                    freshness: .today,
                    total: observed(450),
                    bedtime: observed(asOf.timeIntervalSinceReferenceDate - 8 * 3_600),
                    wake: observed(asOf.timeIntervalSinceReferenceDate),
                    inBed: SleepComponentObservation(value: 480, availability: .estimated, reason: "由睡眠时长与清醒时长推导卧床时长", observedWindow: range),
                    awake: observed(30),
                    rem: missing("HealthKit 未提供 REM 阶段"),
                    deep: missing("HealthKit 未提供 Deep 阶段"),
                    episodeCount: missing("缺少清醒次数数据")
                )
            ),
            (
                "stale_retained",
                75,
                context(
                    outcome: .transient,
                    freshness: .stale,
                    total: observed(450),
                    bedtime: missing("查询失败"),
                    wake: missing("查询失败"),
                    inBed: missing("查询失败"),
                    awake: missing("查询失败"),
                    rem: missing("查询失败"),
                    deep: missing("查询失败"),
                    episodeCount: missing("查询失败")
                )
            ),
            (
                "no_valid_sleep",
                nil,
                context(
                    outcome: .noData,
                    freshness: .stale,
                    total: missing("没有有效睡眠片段"),
                    bedtime: missing("没有入睡时间"),
                    wake: missing("没有起床时间"),
                    inBed: missing("没有卧床阶段"),
                    awake: missing("没有清醒阶段"),
                    rem: missing("没有 REM 阶段"),
                    deep: missing("没有 Deep 阶段"),
                    episodeCount: missing("没有清醒次数")
                )
            )
        ]

        func dto(_ observation: SleepComponentObservation) -> ComponentDTO {
            ComponentDTO(value: observation.value, availability: observation.availability.rawValue, reason: observation.reason)
        }

        let reports = scenarios.map { name, oldValue, evidence in
            let result = SleepScoreEngine().calculate(from: SleepScoreInput(
                asOf: asOf,
                totalSleepMinutes: evidence.totalSleep.value,
                sleepTargetMinutes: 450,
                evidence: evidence
            ))
            return ScenarioDTO(
                scenario: name,
                oldValue: oldValue,
                newValue: result.value,
                queryOutcome: evidence.queryOutcome?.rawValue,
                freshness: evidence.freshness?.rawValue,
                components: [
                    "totalSleep": dto(evidence.totalSleep),
                    "inBed": dto(evidence.inBed),
                    "awake": dto(evidence.awake),
                    "rem": dto(evidence.rem),
                    "deep": dto(evidence.deep),
                    "episodeCount": dto(evidence.episodeCount)
                ],
                dataCoverage: result.dataCoverage.rawValue,
                confidence: result.confidence.rawValue,
                missingInputs: result.missingInputs,
                reasons: result.reasons,
                algorithmVersion: result.algorithmVersion
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(reports)
        let outputDirectory = ProcessInfo.processInfo.environment["BODYSEEK_REPLAY_OUTPUT_DIR"]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        let url = outputDirectory.appendingPathComponent("sleep_semantics_replay.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        XCTAssertEqual(reports.count, 4)
    }
}
