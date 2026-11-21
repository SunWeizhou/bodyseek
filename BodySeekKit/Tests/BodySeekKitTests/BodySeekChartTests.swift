import BodySeekCore
@testable import BodySeekDesign
import Foundation
import SwiftUI
import XCTest

@MainActor
final class BodySeekChartTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    private var refDate: Date {
        calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
    }

    private func renderCGImage<V: View>(_ view: V, width: CGFloat = 340, height: CGFloat = 240) -> CGImage? {
        let hosted = view
            .frame(width: width, height: height)
        let renderer = ImageRenderer(content: hosted)
        renderer.scale = 2.0
        return renderer.cgImage
    }

    func testCommunitySleepTimelinePreservesContinuity() {
        let midnight = refDate
        let start = midnight.addingTimeInterval(-900)
        let end = midnight.addingTimeInterval(1_800)
        let first = SleepStageSegment(stage: .core, startDate: start, endDate: midnight)
        let second = SleepStageSegment(stage: .deep, startDate: midnight, endDate: end)
        let continuous = [first, second]
        let gap = SleepStageSegment(stage: .deep, startDate: midnight.addingTimeInterval(60), endDate: end)
        let overlap = SleepStageSegment(stage: .deep, startDate: midnight.addingTimeInterval(-60), endDate: end)

        let samples = SleepStageChart.communitySamples(for: continuous)
        XCTAssertEqual(samples?.first?.startDate, start)
        XCTAssertEqual(samples?.last?.endDate, end)
        XCTAssertEqual(samples?.last?.duration, 1_800)
        XCTAssertNil(SleepStageChart.communitySamples(for: [first, gap]))
        XCTAssertNil(SleepStageChart.communitySamples(for: [first, overlap]))
        XCTAssertNil(SleepStageChart.communitySamples(for: []))
        XCTAssertNotNil(renderCGImage(SleepStageChart(segments: continuous, interactive: false)))
        XCTAssertNotNil(renderCGImage(SleepStageChart(segments: [first, gap], interactive: false)))
    }

    func testAllEightChartTypesRenderAcrossAllMatrixStates() {
        let now = refDate
        let raw365 = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 365, calendar: calendar)
        let snap365 = BevelScoringEngine.computeWindow(
            rawDays: raw365,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "ChartTest",
            isAuthorized: true,
            calendar: calendar
        )

        let monthNormal = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .recovery,
            horizon: .month,
            days: snap365.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        let yearCapsules = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .sleep,
            horizon: .threeYears,
            days: snap365.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        let weekCapsules = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .recovery,
            horizon: .week,
            days: snap365.historyDays,
            referenceDate: now,
            calendar: calendar
        )
        let monthCapsules = BevelScoringEngine.buildChartSeriesSnapshot(
            for: .strain,
            horizon: .month,
            days: snap365.historyDays,
            referenceDate: now,
            calendar: calendar
        )

        // Sparse + knownZero + excluded variant
        let mixedPoints: [ChartPointSnapshot] = (0..<14).map { idx in
            let date = calendar.date(byAdding: .day, value: idx - 13, to: now) ?? now
            let dayKey = DayKey.fromCalendarDay(date, calendar: calendar)
            switch idx {
            case 2, 3, 7:
                return ChartPointSnapshot(dayKey: dayKey, date: date, value: nil, availability: .missing(reason: "未佩戴"))
            case 5:
                return ChartPointSnapshot(dayKey: dayKey, date: date, value: 0, availability: .knownZero(reason: "休息日"))
            case 9:
                return ChartPointSnapshot(dayKey: dayKey, date: date, value: nil, availability: .excluded(reason: "运动排除"))
            default:
                return ChartPointSnapshot(dayKey: dayKey, date: date, value: Double(40 + idx * 4), availability: .available)
            }
        }
        let sparseSnapshot = ChartSeriesSnapshot(
            kind: .strain,
            horizon: .month,
            referenceDayKey: DayKey.fromCalendarDay(now, calendar: calendar),
            dailyPoints: mixedPoints,
            capsules: [],
            baselineBand: BaselineBand(lower: 45, upper: 72),
            medianValue: 60,
            halfDelta: 3,
            coveredDays: 10,
            totalDays: 14,
            statusSummary: "稀疏测试"
        )

        // Extreme values variant (0 / 100)
        let extremePoints: [ChartPointSnapshot] = [0, 1, 2, 3].map { idx in
            let date = calendar.date(byAdding: .day, value: idx - 3, to: now) ?? now
            let dayKey = DayKey.fromCalendarDay(date, calendar: calendar)
            return ChartPointSnapshot(
                dayKey: dayKey,
                date: date,
                value: idx.isMultiple(of: 2) ? 0.0 : 100.0,
                availability: .available
            )
        }
        let extremeSnapshot = ChartSeriesSnapshot(
            kind: .recovery,
            horizon: .week,
            referenceDayKey: DayKey.fromCalendarDay(now, calendar: calendar),
            dailyPoints: extremePoints,
            capsules: [],
            baselineBand: BaselineBand(lower: 0, upper: 100),
            medianValue: 50,
            halfDelta: 0,
            coveredDays: 4,
            totalDays: 7,
            statusSummary: "极值"
        )

        let emptySnapshot = ChartSeriesSnapshot(
            kind: .recovery,
            horizon: .month,
            referenceDayKey: DayKey.fromCalendarDay(now, calendar: calendar),
            dailyPoints: [],
            capsules: [],
            baselineBand: nil,
            medianValue: nil,
            halfDelta: nil,
            coveredDays: 0,
            totalDays: 30,
            statusSummary: "空"
        )

        let sampleSegments = snap365.today.raw.sleepSegments
        let sampleBins = snap365.today.stressTimeline
        let sampleCurve = snap365.today.energyCurve
        let sampleDays = Array(snap365.historyDays.suffix(30))
        let sampleZones = WorkoutHeartRateZones(
            zone1Minutes: 5,
            zone2Minutes: 14,
            zone3Minutes: 12,
            zone4Minutes: 8,
            zone5Minutes: 2,
            maxHeartRate: 178
        )
        let emptyZones = WorkoutHeartRateZones(zone1Minutes: 0, zone2Minutes: 0, zone3Minutes: 0, zone4Minutes: 0, zone5Minutes: 0)
        let sparkPoints: [(date: Date, value: Double?)] = mixedPoints.map { ($0.date, $0.value) }

        enum RenderVariant: String, CaseIterable {
            case normal, sparse, empty, extreme, ax5, dark
        }

        func applyVariant<V: View>(_ view: V, _ variant: RenderVariant) -> AnyView {
            switch variant {
            case .ax5:
                AnyView(view.environment(\.dynamicTypeSize, .accessibility5))
            case .dark:
                AnyView(view.environment(\.colorScheme, .dark))
            case .normal, .sparse, .empty, .extreme:
                AnyView(view.environment(\.colorScheme, .light))
            }
        }

        for variant in RenderVariant.allCases {
            // 1. TrendLineChart
            let trendInput: ChartSeriesSnapshot = switch variant {
            case .normal, .ax5, .dark: monthNormal
            case .sparse: sparseSnapshot
            case .empty: emptySnapshot
            case .extreme: extremeSnapshot
            }
            XCTAssertNotNil(
                renderCGImage(applyVariant(TrendLineChart(snapshot: trendInput, tint: BevelTheme.recoveryColor), variant)),
                "TrendLineChart failed for \(variant.rawValue)"
            )

            // 2. RangeCapsuleChart
            let capsuleInput = variant == .empty ? emptySnapshot : yearCapsules
            XCTAssertNotNil(
                renderCGImage(applyVariant(RangeCapsuleChart(snapshot: capsuleInput, tint: BevelTheme.sleepColor), variant)),
                "RangeCapsuleChart failed for \(variant.rawValue)"
            )

            // 7 天按日胶囊（单样本日柱 + 中位点）与 30 天按周胶囊（极值须 + P25–P75）。
            XCTAssertNotNil(
                renderCGImage(applyVariant(RangeCapsuleChart(snapshot: weekCapsules, tint: BevelTheme.recoveryColor), variant)),
                "RangeCapsuleChart day buckets failed for \(variant.rawValue)"
            )
            XCTAssertNotNil(
                renderCGImage(applyVariant(RangeCapsuleChart(snapshot: monthCapsules, tint: BevelTheme.strainColor), variant)),
                "RangeCapsuleChart week buckets failed for \(variant.rawValue)"
            )

            // 3. SleepStageChart
            let segs = variant == .empty ? [] : (variant == .sparse ? Array(sampleSegments.prefix(2)) : sampleSegments)
            XCTAssertNotNil(
                renderCGImage(applyVariant(SleepStageChart(segments: segs, height: 156, interactive: true), variant), height: 220),
                "SleepStageChart failed for \(variant.rawValue)"
            )

            // 4. IntradayBarChart
            let bins = variant == .empty ? [] : sampleBins
            let excluded: Set<Int> = variant == .sparse ? [18, 19] : []
            XCTAssertNotNil(
                renderCGImage(applyVariant(IntradayBarChart(bins: bins, excludedHours: excluded, height: 112, interactive: true), variant), height: 200),
                "IntradayBarChart failed for \(variant.rawValue)"
            )

            // 5. EnergyAreaChart
            let curve = variant == .empty ? [] : sampleCurve
            XCTAssertNotNil(
                renderCGImage(applyVariant(EnergyAreaChart(curve: curve, height: 112, interactive: true), variant), height: 200),
                "EnergyAreaChart failed for \(variant.rawValue)"
            )

            // 6. LoadRecoveryComboChart
            let days = variant == .empty ? [] : (variant == .sparse ? Array(sampleDays.prefix(5)) : sampleDays)
            XCTAssertNotNil(
                renderCGImage(applyVariant(LoadRecoveryComboChart(days: days, height: 200), variant), height: 260),
                "LoadRecoveryComboChart failed for \(variant.rawValue)"
            )

            // 7. ZoneBar
            let z = variant == .empty ? emptyZones : sampleZones
            XCTAssertNotNil(
                renderCGImage(applyVariant(ZoneBar(zones: z, showsTrimp: true), variant), height: 90),
                "ZoneBar failed for \(variant.rawValue)"
            )

            // 8. MiniSparkline
            let pts: [(date: Date, value: Double?)] = variant == .empty ? [] : sparkPoints
            XCTAssertNotNil(
                renderCGImage(applyVariant(MiniSparkline(points: pts, tint: BevelTheme.recoveryColor, baselineRange: 45...75), variant), height: 64),
                "MiniSparkline failed for \(variant.rawValue)"
            )
        }
    }

    func testFeatureLayerHasNoDirectChartsOrRemovedThirdPartyImportsOrPermanentLoops() throws {
        let fileURL = URL(fileURLWithPath: #filePath)
        let bodySeekKitRoot = fileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let featuresRoot = bodySeekKitRoot.appendingPathComponent("Sources/BodySeekFeatures")
        let allSourcesRoot = bodySeekKitRoot.appendingPathComponent("Sources")

        func swiftFiles(under root: URL) throws -> [URL] {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil
            ) else {
                return []
            }
            var files: [URL] = []
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                files.append(url)
            }
            return files
        }

        for file in try swiftFiles(under: featuresRoot) {
            let content = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(content.contains("import Charts"), "Feature layer must not import Charts directly: \(file.path)")
            XCTAssertFalse(content.contains("import Liveline"), "Liveline rendering must stay out of the feature layer: \(file.path)")
            XCTAssertFalse(content.contains("import SleepChartKit"), "SleepChartKit rendering belongs in BodySeekDesign: \(file.path)")
        }

        for file in try swiftFiles(under: allSourcesRoot) {
            let content = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(content.contains("repeatForever"), "Permanent repeatForever animation is disallowed: \(file.path)")
        }
    }
}
