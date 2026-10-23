import XCTest
import SwiftUI
@testable import Vela

@MainActor
final class TrendsStoreTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testStorePreservesMissingDaysAsGapsAndDoesNotConnectSegments() async {
        let day = date(2026, 9, 4)
        var first = DailyHealthSnapshot(date: dateAdding(day, -3))
        first.recoveryScore = 60
        var last = DailyHealthSnapshot(date: day)
        last.recoveryScore = 72
        let provider = StaticTrendsHistoryProvider(
            payload: TrendsHistoryPayload(snapshots: [first, last])
        )
        let store = TrendsStore(
            provider: provider,
            selectedDay: day,
            calendar: calendar,
            horizon: .sevenDays,
            metric: .recovery
        )

        await store.send(.appear)

        XCTAssertEqual(store.state.phase, .ready)
        XCTAssertEqual(store.state.series?.points.count, 7)
        XCTAssertEqual(store.state.series?.points.filter { $0.value == nil }.count, 5)
        XCTAssertEqual(store.state.series?.nonMissingSegments.count, 2)
        XCTAssertEqual(store.state.series?.nonMissingSegments.map(\.count), [1, 1])
    }

    func testStoreCarriesBaselineBandAndPointProvenanceWithoutInventingValue() async {
        let day = date(2026, 9, 4)
        var snapshot = DailyHealthSnapshot(date: dateAdding(day, -1))
        snapshot.hrvAverage = 48
        let source = TrendsPointProvenance(
            source: .healthKit,
            sourceLabel: "Apple Health",
            detail: "Nightly HRV average"
        )
        let provider = StaticTrendsHistoryProvider(
            payload: TrendsHistoryPayload(
                snapshots: [snapshot],
                baselineBand: 42...58,
                provenanceByDay: [calendar.startOfDay(for: snapshot.date): source]
            )
        )
        let store = TrendsStore(
            provider: provider,
            selectedDay: day,
            calendar: calendar,
            horizon: .sevenDays,
            metric: .hrv
        )

        await store.send(.appear)

        XCTAssertEqual(store.state.series?.baselineBand, 42...58)
        let point = store.state.series?.points.first { $0.value == 48 }
        XCTAssertEqual(point?.provenance, source)
        XCTAssertNil(store.state.series?.points.first { $0.date == day }?.value)
    }

    func testSelectingPointReturnsMissingPointForExplicitGap() async {
        let day = date(2026, 9, 4)
        let provider = StaticTrendsHistoryProvider(payload: TrendsHistoryPayload())
        let store = TrendsStore(
            provider: provider,
            selectedDay: day,
            calendar: calendar,
            horizon: .sevenDays,
            metric: .sleepScore
        )
        await store.send(.appear)
        let gapDay = dateAdding(day, -2)
        await store.send(.selectPoint(gapDay))
        XCTAssertEqual(store.state.selectedPoint?.date, calendar.startOfDay(for: gapDay))
        XCTAssertNil(store.state.selectedPoint?.value)
    }

    /// Native rendering evidence for the sparse history seen on device, a true
    /// zero, and no readings. These fixtures never enter the production loader.
    func testOverviewChartSparseAndMissingVisualFixtures() throws {
        let end = date(2026, 10, 22)
        let scenarios: [(String, [Int: Double])] = [
            ("sparse", [0: 81, 1: 67, 4: 77, 8: 49, 14: 62, 29: 59]),
            ("known-zero", [0: 40, 1: 0, 2: 30, 20: 0, 29: 0]),
            ("missing", [:])
        ]
        for (name, values) in scenarios {
            let points = (0..<30).map { offset in
                TrendsChartPoint(date: dateAdding(end, offset - 29), value: values[offset], provenance: nil)
            }
            let series = TrendsMetricSeries(
                metric: .recovery, horizon: .thirtyDays, selectedDay: end,
                points: points, baselineBand: nil, finding: nil
            )
            let host = UIHostingController(rootView: TrendsOverviewChart(series: series)
                .padding(16)
                .background(VelaTheme.rhythmCanvasRaised)
                .environment(\.locale, Locale(identifier: "zh_CN")))
            host.overrideUserInterfaceStyle = .light
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 150))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            var didDraw = false
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                didDraw = host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            XCTAssertTrue(didDraw, "The \(name) chart should render through SwiftUI")
            let attachment = XCTAttachment(image: image)
            attachment.name = "trends-chart-\(name)-320pt"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateAdding(_ date: Date, _ days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }
}

final class DataPresentationCopyTests: XCTestCase {
    func testPriorBaselineAndInclusiveChartCountsAreExplicitlyDifferent() {
        let finding = HealthTrendFinding.unavailable(metric: .recovery, horizon: .thirtyDays, sampleCount: 6)
        let summary = TrendsPeriodSummary.make(horizon: .thirtyDays, findings: [finding])
        XCTAssertTrue(summary.detail?.contains("6 天") == true)
        XCTAssertTrue(summary.detail?.contains("不含所选当天") == true)
        let row = TrendsCoverageRow(id: "recovery", title: "恢复", scoredDays: 7, windowDays: 30, requiredDays: 14, isLoaded: true, baselineDays: 6)
        let chartText = TrendsCoverageRow.summaryText([row], horizon: .thirtyDays)
        XCTAssertTrue(chartText.contains("7/30"))
        XCTAssertTrue(chartText.contains("含当天"))
    }

    func testUnusualReadingNamesItsActualReferenceWindow() {
        let finding = HealthTrendFinding(metric: .energy, horizon: .sevenDays, direction: .elevated,
            valueDirection: .rising, currentValue: 63, currentValueFormatted: "63%", baselineValue: 48,
            sampleCount: 6, requiredSampleCount: 5, summary: "higher", isNotable: true)
        let reading = ScoreInstrumentReading.make(cardValues: ["energy": "63%"], deviations: ["energy": "高于平时"], findings: [finding]).last!
        XCTAssertEqual(reading.baseline, 48)
        XCTAssertTrue(reading.caption.contains("7天"))
        XCTAssertEqual(reading.valueText, "63%")
    }
}
