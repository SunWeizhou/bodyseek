import XCTest
@testable import Vela

final class HealthPresentationCopyTests: XCTestCase {
    func testSleepEngineKeysGetDistinctChineseLabels() {
        let keys = [
            "todayBedtime",
            "recentBedtimesHistory",
            "awakeMinutes",
            "remMinutes",
            "deepMinutes",
            "inBedMinutes",
            "totalSleepMinutes",
            "awakeEpisodeCount"
        ]
        let labels = keys.map(MissingInputLabel.chineseLabel(for:))
        XCTAssertEqual(labels, [
            "当日入睡时间",
            "近期入睡时间历史",
            "夜间清醒时长",
            "REM 时长",
            "深睡时长",
            "在床时长",
            "睡眠总时长",
            "醒来次数"
        ])
        XCTAssertEqual(Set(labels).count, labels.count, "sleep missing keys must not share a display label")
    }

    func testSleepDetailSummaryDoesNotRepeatFullSleep() {
        let summary = MissingInputLabel.summary(
            for: ["todayBedtime", "recentBedtimesHistory", "awakeMinutes"],
            hasValue: true,
            suffix: "当前结果已降低证据覆盖度。"
        )
        XCTAssertEqual(
            summary,
            "仍缺少：当日入睡时间、近期入睡时间历史、夜间清醒时长。当前结果已降低证据覆盖度。"
        )
        XCTAssertFalse(summary?.contains("完整睡眠、完整睡眠") == true)
    }

    func testSummaryDeduplicatesIdenticalLabelsAndFillsFromLaterKeys() {
        let summary = MissingInputLabel.summary(
            for: ["hrvToday", "HRVToday", "sleepScore", "priorStrainYesterday"],
            hasValue: true
        )
        XCTAssertEqual(summary, "仍缺少：今日 HRV、睡眠分、昨日负荷。")
    }

    func testRecoveryAndStressKeysStayDistinctFromSubstringCollisions() {
        XCTAssertEqual(MissingInputLabel.chineseLabel(for: "hrvToday"), "今日 HRV")
        XCTAssertEqual(MissingInputLabel.chineseLabel(for: "hrvHistory"), "HRV 历史")
        XCTAssertEqual(MissingInputLabel.chineseLabel(for: "hrvBaseline"), "HRV 基线")
        XCTAssertEqual(MissingInputLabel.chineseLabel(for: "restingHeartRateToday"), "今日静息心率")
        XCTAssertEqual(MissingInputLabel.chineseLabel(for: "rhrHistory"), "静息心率历史")
        XCTAssertEqual(MissingInputLabel.chineseLabel(for: "sleepScore"), "睡眠分")
        XCTAssertNotEqual(
            MissingInputLabel.chineseLabel(for: "wakeTime"),
            MissingInputLabel.chineseLabel(for: "awakeMinutes")
        )
    }

    func testUnknownKeysStayDistinctInsteadOfSharingPartialInput() {
        let labels = MissingInputLabel.uniqueLabels(for: ["alphaSignal", "betaSignal"])
        XCTAssertEqual(labels.count, 2)
        XCTAssertNotEqual(labels[0], labels[1])
        XCTAssertFalse(labels.contains("部分输入"))
    }

    func testBaselineDeviationCopyIsDirectionalAndNeutral() {
        XCTAssertEqual(BaselineDeviationCopy.relativeToUsual(percent: -12), "低于平时")
        XCTAssertEqual(BaselineDeviationCopy.relativeToUsual(percent: 8), "高于平时")
        XCTAssertNil(BaselineDeviationCopy.relativeToUsual(percent: 0))
        XCTAssertEqual(
            BaselineDeviationCopy.relativeToUsual(current: 48, baseline: 60),
            "低于平时"
        )
        XCTAssertEqual(
            BaselineDeviationCopy.relativeToUsual(current: 70, baseline: 60),
            "高于平时"
        )
        XCTAssertEqual(BaselineDeviationCopy.unusualFallback, "偏离个人基线")

        let below = HealthTrendFinding(
            metric: .recovery,
            horizon: .thirtyDays,
            direction: .declining,
            currentValue: 48,
            currentValueFormatted: "48",
            baselineValue: 62,
            currentDeviationPercent: -22.5,
            summary: "test",
            isNotable: true
        )
        XCTAssertEqual(BaselineDeviationCopy.label(for: below), "低于平时")
    }

    func testConfidenceBadgeCopyIsPlainChineseWithoutEnglishCodes() {
        XCTAssertEqual(ConfidenceBadgeCopy.label(confidence: .high), "置信度 高")
        XCTAssertEqual(ConfidenceBadgeCopy.label(confidence: .medium), "置信度 中")
        XCTAssertEqual(ConfidenceBadgeCopy.label(confidence: .low), "置信度 低")
        XCTAssertEqual(ConfidenceBadgeCopy.label(confidence: .unavailable), "置信度 未知")
        XCTAssertEqual(ConfidenceBadgeCopy.label(score: 0.9), "置信度 高")
        XCTAssertEqual(ConfidenceBadgeCopy.label(score: 0.6), "置信度 中")
        XCTAssertEqual(ConfidenceBadgeCopy.label(score: 0.2), "置信度 低")
        XCTAssertFalse(ConfidenceBadgeCopy.label(confidence: .low).contains("LOW"))
        XCTAssertFalse(ConfidenceBadgeCopy.label(score: 0.2).contains("%"))
    }
}
