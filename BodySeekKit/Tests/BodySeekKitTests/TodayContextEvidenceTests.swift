import BodySeekAgent
import BodySeekCore
import XCTest

/// `get_today_context` 带类型化证据：同值不同指标的写反会被判未核实，
/// 正确引用、单位换算和差值（含五项分数较昨天 / 较 7 天均值）仍然通过。
final class TodayContextEvidenceTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    private func date(_ key: DayKey) -> Date {
        key.startDate(cutoverHour: 4, timeZone: calendar.timeZone)
    }

    private func day(_ key: DayKey, recovery: Int, sleep: Int, hrv: Double, asleep: Int) -> DailyComputedDay {
        let raw = DailyRawMetrics(
            date: date(key),
            hrvMs: hrv,
            restingHeartRateBpm: 58,
            sleepAsleepMinutes: asleep,
            sleepInBedMinutes: asleep + 18,
            hasAuthorizedHealthData: true,
            sourceNames: ["fixture"],
            dayKey: key
        )
        return DailyComputedDay(
            date: date(key),
            dayKey: key,
            raw: raw,
            recovery: MetricScore(kind: .recovery, value: recovery, availability: .available, badge: "", subtitle: ""),
            sleep: MetricScore(kind: .sleep, value: sleep, availability: .available, badge: "", subtitle: ""),
            strain: MetricScore(kind: .strain, value: 54, availability: .available, badge: "", subtitle: ""),
            stress: MetricScore(kind: .stress, value: 49, availability: .available, badge: "", subtitle: ""),
            energy: MetricScore(kind: .energy, value: 46, availability: .available, badge: "", subtitle: ""),
            energyCurve: [],
            stressTimeline: [],
            factualSummary: "",
            evidenceSummary: ""
        )
    }

    private let endKey = DayKey(year: 2026, month: 11, day: 23)

    /// 今天之前的 7 天里 6 天恢复 64 分、昨天 67 分 → 近 7 天均值 64.4；今天 71 分 → 较昨天 +4、较均值 +6.6。
    private func makeContext() -> AgentExecutionContext {
        let asOf = date(endKey).addingTimeInterval(12 * 3600)
        var history: [DailyComputedDay] = []
        for offset in -7..<0 {
            let key = endKey.addingDays(offset)
            history.append(day(key, recovery: offset == -1 ? 67 : 64, sleep: 80, hrv: 50, asleep: 400))
        }
        let today = day(endKey, recovery: 71, sleep: 87, hrv: 54, asleep: 412)
        history.append(today)
        let snapshot = BodySeekDashboardSnapshot(
            referenceDate: asOf,
            today: today,
            historyDays: history,
            trainingLoad: TrainingLoadStatus(acute7dLoad: 300, chronic28dWeeklyAvg: 280, acwrRatio: 1.07, zone: .sweetSpot),
            sourceLabel: "fixture",
            lastUpdatedAt: asOf,
            isAuthorized: true
        )
        return AgentExecutionContext(snapshot: snapshot, asOf: asOf)
    }

    private func todayContextJSON() async throws -> [String: Any] {
        let context = makeContext()
        let output = await CoachToolRegistry.execute(
            name: "get_today_context", argumentsJSON: "{}", context: context
        )
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }

    func testTodayContextCarriesTypedEvidenceAndScoreDeltas() async throws {
        let object = try await todayContextJSON()
        let evidence = try XCTUnwrap(object["evidence"] as? [[String: Any]])
        func fact(_ metric: String, scope: String) -> [String: Any]? {
            evidence.first { ($0["metric"] as? String) == metric && ($0["scope"] as? String) == scope }
        }

        let recovery = try XCTUnwrap(fact("recovery", scope: "day"))
        XCTAssertEqual(recovery["value"] as? Double, 71)
        XCTAssertEqual(recovery["unit"] as? String, "score_0_100")
        XCTAssertEqual(recovery["dayKey"] as? String, "2026-11-23")
        XCTAssertEqual(fact("hrv", scope: "day")?["unit"] as? String, "ms")
        XCTAssertEqual(fact("resting_heart_rate", scope: "day")?["value"] as? Double, 58)
        XCTAssertEqual(fact("sleep_asleep", scope: "day")?["unit"] as? String, "minutes")
        // 五项分数都有"近 7 天均值"证据；均值不含今天。
        XCTAssertEqual(fact("recovery", scope: "avg7d")?["value"] as? Double, 64.4)
        for kind in ["sleep", "strain", "stress", "energy"] {
            XCTAssertNotNil(fact(kind, scope: "avg7d"), "\(kind) 缺少近 7 天均值证据")
        }

        let data = try XCTUnwrap(object["data"] as? [String: Any])
        let derived = try XCTUnwrap(data["derived"] as? [String: Any])
        let scores = try XCTUnwrap(derived["scores"] as? [[String: Any]])
        let recoveryDerived = try XCTUnwrap(scores.first { ($0["kind"] as? String) == "recovery" })
        XCTAssertEqual(recoveryDerived["yesterday"] as? Int, 67)
        XCTAssertEqual(recoveryDerived["mean7d"] as? Double, 64.4)
        XCTAssertEqual(recoveryDerived["vsYesterday"] as? Double, 4)
        XCTAssertEqual(recoveryDerived["vs7dMean"] as? Double, 6.6)
    }

    func testSwappedMetricNumbersAreFlaggedWhileGroundedRepliesPass() async throws {
        let object = try await todayContextJSON()
        let toolOutput = String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8) ?? "{}"
        func unverified(_ text: String) -> [String] {
            NumericProvenanceVerifier.verify(responseText: text, toolOutputs: [toolOutput]).unverifiedTokens
        }

        // 如实引用：全部通过。
        XCTAssertTrue(unverified("今天恢复 71 分，睡眠 87 分，HRV 54 ms。").isEmpty)
        // 单位换算：412 分钟 = 6 小时 52 分。
        XCTAssertTrue(unverified("昨晚睡了 6 小时 52 分。").isEmpty)
        // 工具预先算好的差值：较昨天 +4 分、较近 7 天均值 +6.6 分。
        XCTAssertTrue(unverified("恢复较昨天高 4 分，比近 7 天均值高 6.6 分。").isEmpty)

        // HRV 与恢复分写反：两个数字都在工具结果里，但指标与单位对不上，必须判未核实。
        let swapped = unverified("今天 HRV 71 ms，恢复 54 分。")
        XCTAssertEqual(swapped.count, 2, "\(swapped)")
        // 编造的分数。
        XCTAssertTrue(unverified("今天恢复 92 分。").contains { $0.contains("92") })
    }
}
