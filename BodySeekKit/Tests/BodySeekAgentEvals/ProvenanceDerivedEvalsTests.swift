import BodySeekAgent
import XCTest

/// UI v4 §6.1 / §6.3：派生值（四舍五入、单位换算、同一指标差值）核对夹具，以及
/// `defensive_phrase_count`（门槛 0）与 `unverified_rate`（门槛 ≤ 5%）。
final class ProvenanceDerivedEvalsTests: XCTestCase {
    /// 含派生值的工具结果夹具：睡眠 432 分钟（= 7.2 小时 = 7 小时 12 分），上周 396 分钟；HRV 42.4 / 47.9 ms。
    private static let toolOutput = """
    {"tool":"get_today_context","data":{"sleepAsleepMinutes":432,"hrvMs":42.4,\
    "derived":{"sleepAsleepHours":7.2,"sleepAsleepText":"7 小时 12 分","hrvVs14dMeanMs":-5.5,"recordedDays14d":13}},\
    "evidence":[
    {"metric":"sleep_asleep","value":432,"unit":"minutes","dayKey":"2026-11-23"},
    {"metric":"sleep_asleep","value":396,"unit":"minutes","dayKey":"2026-11-16"},
    {"metric":"hrv","value":42.4,"unit":"ms","dayKey":"2026-11-23"},
    {"metric":"hrv","value":47.9,"unit":"ms","dayKey":"2026-11-16"}]}
    """

    /// 一组合格回复：每句都由工具结果直接给出、四舍五入、换算或差值得到。
    private static let groundedReplies = [
        "结论：昨晚睡了 7.2 小时，比上周同一天多睡 36 分钟。",
        "昨晚实际睡眠 7 小时 12 分，上周同一天是 6 小时 36 分。",
        "夜间 HRV 42 ms，比上周同一天低 5.5 ms，连续 3 晚低于平时。",
        "近 14 天有 13 天有记录，今天训练 2 次、吃了 3 餐。",
    ]

    func testDerivedValuesAreVerified() {
        for reply in Self.groundedReplies {
            let report = NumericProvenanceVerifier.verify(
                responseText: reply,
                toolOutputs: [Self.toolOutput],
                userQuestion: "我昨晚睡得怎么样"
            )
            XCTAssertTrue(report.unverifiedTokens.isEmpty, "\(reply) -> \(report.unverifiedTokens)")
            XCTAssertEqual(report.annotatedText, reply, "正文不得插入标记")
        }
    }

    func testCountWordsDoNotParticipateAndHallucinationsAreStillFlagged() {
        let counted = NumericProvenanceVerifier.verify(
            responseText: "睡眠 5 次、恢复 9 天、压力 4 晚、能量 2 组都只是计数。",
            toolOutputs: [Self.toolOutput]
        )
        XCTAssertTrue(counted.unverifiedTokens.isEmpty, "\(counted.unverifiedTokens)")

        let hallucinated = NumericProvenanceVerifier.verify(
            responseText: "夜间 HRV 71 ms，睡眠 9 小时。",
            toolOutputs: [Self.toolOutput]
        )
        XCTAssertEqual(hallucinated.unverifiedTokens.count, 2, "\(hallucinated.unverifiedTokens)")
        XCTAssertFalse(hallucinated.annotatedText.contains("未核实"))
    }

    func testUIv4MetricsOnDerivedFixture() {
        var verified = 0
        var unverified = 0
        var defensive = 0
        for reply in Self.groundedReplies {
            let report = NumericProvenanceVerifier.verify(responseText: reply, toolOutputs: [Self.toolOutput])
            verified += report.verifiedCount
            unverified += report.unverifiedTokens.count
            defensive += AgentEvalMetrics.defensivePhraseCount(in: reply)
        }
        let rate = AgentEvalMetrics.unverifiedRate(verified: verified, unverified: unverified)
        print(String(format: "AGENT_EVALS_UIV4_FIXTURE: defensive_phrase_count=%d unverified_rate=%.1f%% verified=%d unverified=%d", defensive, rate, verified, unverified))
        XCTAssertEqual(defensive, 0)
        XCTAssertLessThanOrEqual(rate, AgentEvalMetrics.maxUnverifiedRatePercent)
        XCTAssertGreaterThan(verified, 0)
    }

    func testDefensivePhraseCounterFindsHedges() {
        XCTAssertEqual(AgentEvalMetrics.defensivePhraseCount(in: "可能是睡得晚，仅供参考。"), 2)
        XCTAssertEqual(AgentEvalMetrics.defensivePhraseCount(in: "主要是训练加量，其次是睡得晚。"), 0)
    }
}
