import BodySeekCore
import XCTest

/// UI v4 §5.3：平时范围逐日滚动（前 28 天有效观测的 P25–P75，不含当天，< 7 天不给区间）。
final class RollingBaselineTests: XCTestCase {
    func testWindowExcludesCurrentDay() throws {
        // 前 28 天都是 40...67（每天 +1），第 29 天出现 1000 的异常值。
        var values: [Double?] = (0..<28).map { Double(40 + $0) }
        values.append(1000)
        values.append(50)
        let bands = BevelScoringEngine.rollingBands(values: values)

        // 异常值当天的区间只来自它之前的 28 天，不含它自己。
        let spikeDay = try XCTUnwrap(bands[28])
        XCTAssertEqual(spikeDay.sampleCount, 28)
        XCTAssertLessThan(spikeDay.upper, 100)
        // 第二天窗口才包含异常值，上沿被抬高。
        let nextDay = try XCTUnwrap(bands[29])
        XCTAssertGreaterThanOrEqual(nextDay.upper, spikeDay.upper)
        XCTAssertEqual(nextDay.sampleCount, 28)
    }

    func testWindowIsLimitedToPrior28Days() throws {
        // 第 0 天是 500，之后 30 天都是 50；第 29、30 天的窗口已经不含第 0 天。
        var values: [Double?] = [500]
        values.append(contentsOf: Array(repeating: 50.0, count: 30))
        let bands = BevelScoringEngine.rollingBands(values: values)
        let inside = try XCTUnwrap(bands[28])  // 窗口 0..<28，含 500
        XCTAssertEqual(inside.sampleCount, 28)
        let outside = try XCTUnwrap(bands[29])  // 窗口 1..<29，不含 500
        XCTAssertEqual(outside.lower, 50, accuracy: 0.0001)
        XCTAssertEqual(outside.upper, 50, accuracy: 0.0001)
    }

    func testMissingValuesAreSkippedNotZero() throws {
        // 10 个有效值 60...69，穿插 10 个缺失。缺失不得被当成 0 拉低分位。
        var values: [Double?] = []
        for index in 0..<10 {
            values.append(Double(60 + index))
            values.append(nil)
        }
        values.append(65)
        let bands = BevelScoringEngine.rollingBands(values: values)
        let last = try XCTUnwrap(bands[values.count - 1])
        XCTAssertEqual(last.sampleCount, 10)
        XCTAssertGreaterThanOrEqual(last.lower, 60)
        XCTAssertLessThanOrEqual(last.upper, 69)
    }

    func testFewerThanSevenObservationsGivesNoBand() throws {
        let six: [Double?] = [60, nil, 61, 62, nil, 63, 64, 65, 70]
        let sixBands = BevelScoringEngine.rollingBands(values: six)
        // 最后一天之前恰好 6 个有效观测。
        XCTAssertNil(sixBands[six.count - 1])

        let seven: [Double?] = [60, nil, 61, 62, nil, 63, 64, 65, 66, 70]
        let sevenBands = BevelScoringEngine.rollingBands(values: seven)
        let band = try XCTUnwrap(sevenBands[seven.count - 1])
        XCTAssertEqual(band.sampleCount, 7)
    }

    func testFirstDaysHaveNoBand() {
        let values: [Double?] = Array(repeating: 55.0, count: 10)
        let bands = BevelScoringEngine.rollingBands(values: values)
        XCTAssertTrue(bands[0..<7].allSatisfy { $0 == nil })
        XCTAssertNotNil(bands[7])
    }

    func testChartSnapshotCarriesPerPointBandAndKeepsLegacyBand() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let raw = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 200, calendar: calendar)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: raw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Rolling",
            isAuthorized: true,
            calendar: calendar
        )
        let chart = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .recovery,
            horizon: .month,
            days: snapshot.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        XCTAssertNotNil(chart.baselineBand, "旧的固定区间字段必须保留")
        XCTAssertEqual(chart.dailyPoints.count, 30)
        let withBand = chart.dailyPoints.compactMap(\.rollingBand)
        XCTAssertFalse(withBand.isEmpty)
        for band in withBand {
            XCTAssertGreaterThanOrEqual(band.sampleCount, BevelScoringEngine.rollingMinimumSamples)
            XCTAssertLessThanOrEqual(band.sampleCount, BevelScoringEngine.rollingWindowDays)
            XCTAssertLessThanOrEqual(band.lower, band.upper)
        }
    }

    func testCapsuleUsesRollingBandOfLastDayInBucket() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let now = Date(timeIntervalSince1970: 1_795_000_000)
        let raw = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 220, calendar: calendar)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: raw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Rolling",
            isAuthorized: true,
            calendar: calendar
        )
        let chart = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .sleep,
            horizon: .sixMonths,
            days: snapshot.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        let capsule = try XCTUnwrap(chart.capsules.last)
        let lastPoint = try XCTUnwrap(chart.dailyPoints.last { $0.dayKey == capsule.endDayKey })
        XCTAssertEqual(capsule.rollingLow, lastPoint.rollingLow)
        XCTAssertEqual(capsule.rollingHigh, lastPoint.rollingHigh)
        XCTAssertEqual(capsule.rollingSampleCount, lastPoint.rollingSampleCount)
    }
}
