import BodySeekCore
import BodySeekFeatures
import Foundation
import XCTest

final class PerformanceBaselineTests: XCTestCase {
    func testM0ScoringAndTrendsScrubBaselineBenchmarks() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))

        func measureMs(_ block: () -> Void) -> Double {
            let t0 = CFAbsoluteTimeGetCurrent()
            block()
            return (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
        }

        let raw60 = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 60, calendar: calendar)
        let raw365 = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 365, calendar: calendar)
        let raw1095 = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 1095, calendar: calendar)

        var snap60: BodySeekDashboardSnapshot!
        var snap365: BodySeekDashboardSnapshot!
        var snap1095: BodySeekDashboardSnapshot!

        let ms60 = measureMs {
            snap60 = BevelScoringEngine.computeWindow(
                rawDays: raw60,
                sleepGoalMinutes: 450,
                referenceDate: now,
                sourceLabel: "Bench",
                isAuthorized: true,
                calendar: calendar
            )
        }
        let ms365 = measureMs {
            snap365 = BevelScoringEngine.computeWindow(
                rawDays: raw365,
                sleepGoalMinutes: 450,
                referenceDate: now,
                sourceLabel: "Bench",
                isAuthorized: true,
                calendar: calendar
            )
        }
        let ms1095 = measureMs {
            snap1095 = BevelScoringEngine.computeWindow(
                rawDays: raw1095,
                sleepGoalMinutes: 450,
                referenceDate: now,
                sourceLabel: "Bench",
                isAuthorized: true,
                calendar: calendar
            )
        }

        XCTAssertEqual(snap60.historyDays.count, raw60.count)
        XCTAssertEqual(snap365.historyDays.count, raw365.count)
        XCTAssertEqual(snap1095.historyDays.count, raw1095.count)

        // Quantify post-M1-Data cached TrendsFeature lookup + zero-recompute scrub performance
        var trendsMonth = TrendsFeature.State(snapshot: snap365)
        trendsMonth.horizon = .month
        let scrubMonthMs = measureMs {
            for idx in 0..<60 {
                trendsMonth.selectedDate = calendar.date(byAdding: .day, value: -(idx % 30), to: now)
                _ = trendsMonth.activeSeries
                _ = trendsMonth.allMetricSeries
            }
        }

        var trends3Y = TrendsFeature.State(snapshot: snap1095)
        let horizonSwitch3YMs = measureMs {
            trends3Y.horizon = .threeYears
        }
        let scrub3YMs = measureMs {
            for idx in 0..<60 {
                trends3Y.selectedDate = calendar.date(byAdding: .day, value: -(idx % 90), to: now)
                _ = trends3Y.activeSeries
                _ = trends3Y.allMetricSeries
            }
        }

        XCTAssertLessThan(horizonSwitch3YMs, 150.0)
        XCTAssertLessThan(scrub3YMs, 50.0)

        print(String(
            format: "BENCHMARK_M1_DATA: compute60d=%.2fms compute365d=%.2fms compute1095d=%.2fms horizonSwitch3Y=%.2fms trendsScrub60xMonth=%.2fms trendsScrub60x3Y=%.2fms",
            ms60, ms365, ms1095, horizonSwitch3YMs, scrubMonthMs, scrub3YMs
        ))
    }
}
