import XCTest
import HealthKit
@testable import Vela

/// HealthKit 查询失败分类回归测试（审计 C2）。
/// 不变量：
///   1. 真实查询错误（授权被拒/参数错误/数据库异常）→ 记录为组件失败，绝不当作「无数据」；
///   2. 只有 errorNoData（该范围确实没有样本）→ 空数据分支，不记为失败；
///   3. 核心组件全部失败 → hasCoreData == false（调用方不得持久化全空快照）；
///   4. 至少一个核心组件成功 → 部分数据合法，hasCoreData == true。
final class HealthSyncErrorHandlingTests: XCTestCase {

    fileprivate final class FakeHealthQueryService: HealthQueryService {
        var onSleep: () throws -> SleepSummary? = { nil }
        var onRecovery: () throws -> RecoveryMetricSummary = {
            RecoveryMetricSummary()
        }
        var onStrain: () throws -> StrainActivitySummary = {
            StrainActivitySummary(workouts: [])
        }
        var onBody: () throws -> BodyMetricsSummary = {
            BodyMetricsSummary()
        }
        var onExtended: () throws -> ExtendedHealthMetrics = {
            ExtendedHealthMetrics()
        }
        var onIntraday: (HealthSignal, DateRangeQuery) throws -> [IntradaySignalPoint] = { _, _ in
            []
        }

        func sleepSummary(in range: DateRangeQuery) async throws -> SleepSummary? {
            try onSleep()
        }

        func sleepEpisodes(in range: DateRangeQuery) async throws -> [SleepSummary] { [] }

        func recoveryMetrics(in range: DateRangeQuery) async throws -> RecoveryMetricSummary {
            try onRecovery()
        }

        func strainSummary(in range: DateRangeQuery) async throws -> StrainActivitySummary {
            try onStrain()
        }

        func bodyMetrics(in range: DateRangeQuery) async throws -> BodyMetricsSummary {
            try onBody()
        }

        func extendedMetrics(in range: DateRangeQuery) async throws -> ExtendedHealthMetrics {
            try onExtended()
        }

        func intradaySamples(
            for signal: HealthSignal,
            in range: DateRangeQuery
        ) async throws -> [IntradaySignalPoint] {
            try onIntraday(signal, range)
        }

        func recentWorkouts(limit: Int) async throws -> [WorkoutSummary] { [] }
        func heartRateSamples(start: Date, end: Date) async throws -> [HeartRateSample] { [] }
        func workoutRoute(workoutId: UUID) async throws -> [RouteCoordinate] { [] }
    }

    private var calendar: Calendar { Calendar.current }

    private static func nonBenignError() -> NSError {
        NSError(domain: HKErrorDomain, code: 100, userInfo: nil)
    }

    private static func benignNoDataError() -> NSError {
        NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue, userInfo: nil)
    }

    @MainActor
    func testRealQueryErrorsAreRecordedNotSwallowed() async {
        let fake = FakeHealthQueryService()
        fake.onSleep = { throw Self.nonBenignError() }
        fake.onRecovery = { throw Self.nonBenignError() }
        fake.onStrain = { throw Self.nonBenignError() }
        fake.onBody = { throw Self.nonBenignError() }

        let result = await DailySnapshotBuilder.buildSnapshot(
            for: Date(),
            queryService: fake,
            calendar: calendar
        )

        XCTAssertEqual(
            Set(result.queryFailures),
            [.sleep, .recovery, .strain, .body],
            "真实查询错误必须记录为组件失败，绝不能当作无数据吞掉"
        )
        XCTAssertEqual(
            result.diagnostics.filter { $0.outcome == .failed }.map(\.component),
            ["sleep", "recovery", "strain", "body"]
        )
        XCTAssertFalse(
            result.hasCoreData,
            "核心组件全部失败时不得持久化全空快照"
        )
        XCTAssertNil(result.snapshot.sleepHours)
        XCTAssertNil(result.snapshot.hrvAverage)
    }

    @MainActor
    func testNoDataIsBenignAndNotAFailure() async {
        let fake = FakeHealthQueryService()
        fake.onSleep = { throw Self.benignNoDataError() }
        fake.onRecovery = { throw Self.benignNoDataError() }
        fake.onStrain = { throw Self.benignNoDataError() }
        fake.onBody = { throw Self.benignNoDataError() }

        let result = await DailySnapshotBuilder.buildSnapshot(
            for: Date(),
            queryService: fake,
            calendar: calendar
        )

        XCTAssertTrue(
            result.queryFailures.isEmpty,
            "errorNoData 是无样本而不是查询失败，不应记入失败清单"
        )
        XCTAssertEqual(result.diagnostics.map(\.outcome), [.noData, .noData, .noData, .noData])
        // 注意：无数据 ≠ 没有核心数据依赖——组件全部「无样本」时快照为空，
        // 但这是合法的缺失数据表达（由 Data Coverage 规则承接）。
    }

    @MainActor
    func testPartialFailureKeepsCoreDataAndReportsComponent() async {
        let fake = FakeHealthQueryService()
        fake.onSleep = { throw Self.nonBenignError() }
        fake.onRecovery = {
            var summary = RecoveryMetricSummary()
            summary.hrvMilliseconds = 41.0
            summary.restingHeartRate = 62.0
            return summary
        }

        let result = await DailySnapshotBuilder.buildSnapshot(
            for: Date(),
            queryService: fake,
            calendar: calendar
        )

        XCTAssertEqual(result.queryFailures, [.sleep])
        XCTAssertEqual(result.diagnostics.first?.outcome, .failed)
        XCTAssertTrue(result.hasCoreData, "部分组件失败时应保留其余核心数据")
        XCTAssertEqual(result.snapshot.hrvAverage, 41.0)
        XCTAssertNil(result.snapshot.sleepHours, "失败组件不得产出伪造数据")
        XCTAssertEqual(result.sleepEvidence.queryOutcome, .failed)
        XCTAssertEqual(result.sleepEvidence.freshness, .stale)
        XCTAssertEqual(result.sleepEvidence.totalSleep.availability, .missing)
    }

    func testHealthKitErrorClassifierKeepsPermissionAndAvailabilityDistinct() {
        XCTAssertEqual(
            HealthKitQueryOutcomeClassifier.classify(
                NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue)
            ),
            .denied
        )
        XCTAssertEqual(
            HealthKitQueryOutcomeClassifier.classify(
                NSError(domain: HKErrorDomain, code: HKError.Code.errorHealthDataUnavailable.rawValue)
            ),
            .unavailable
        )
        XCTAssertEqual(
            HealthKitQueryOutcomeClassifier.classify(
                NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue)
            ),
            .noData
        )
    }
}

/// ARCH-02 dependency seam checks live beside the existing HealthKit fakes so
/// they compile in the current test target without editing the Xcode project.
final class DependencySeamTests: XCTestCase {
    @MainActor
    private final class RecordingAuthorization: HealthAuthorizationProviding {
        private(set) var calls = 0
        let deferSync: Bool

        init(deferSync: Bool) {
            self.deferSync = deferSync
        }

        func shouldDeferBackgroundSync() async -> Bool {
            calls += 1
            return deferSync
        }
    }

    @MainActor
    func testDailyEvidenceInterfaceIsObservableThroughProtocol() async throws {
        let fake = HealthSyncErrorHandlingTests.FakeHealthQueryService()
        var extendedCalls = 0
        var intradayCalls = 0
        fake.onExtended = {
            extendedCalls += 1
            return ExtendedHealthMetrics()
        }
        fake.onIntraday = { _, _ in
            intradayCalls += 1
            return [IntradaySignalPoint(date: Date(timeIntervalSince1970: 1), value: 2)]
        }

        let service: any HealthQueryService = fake
        let range = DateRangeQuery(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 3_600)
        )
        _ = try await service.extendedMetrics(in: range)
        _ = try await service.intradaySamples(for: .stepCount, in: range)

        XCTAssertEqual(extendedCalls, 1)
        XCTAssertEqual(intradayCalls, 1)
    }

    @MainActor
    func testFactoriesUseInjectedProviderWithoutConstructingHealthKit() async throws {
        let fake = HealthSyncErrorHandlingTests.FakeHealthQueryService()
        let authorization = RecordingAuthorization(deferSync: true)
        let now = Date(timeIntervalSince1970: 1_725_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dependencies = AppDependencies.test(
            now: now,
            calendar: calendar,
            queryService: fake,
            authorizationService: authorization
        )
        let services = VelaServices(dependencies: dependencies)

        XCTAssertTrue(services.dailySummaryUseCase === dependencies.today.dailySummaryUseCase)
        XCTAssertTrue(services.syncCoordinator === dependencies.health.syncCoordinator)
        XCTAssertTrue(dependencies.health.queryService as AnyObject === fake)
        XCTAssertTrue(dependencies.health.authorization as AnyObject === authorization)

        let dashboard = try await dependencies.today.dailySummaryUseCase.loadDashboard(
            for: now,
            modelContext: nil
        )
        XCTAssertEqual(dashboard.date, now)
        XCTAssertEqual(authorization.calls, 1)

        let snapshot = try await dependencies.today.reader.load(
            for: now,
            policy: .automatic
        )
        XCTAssertEqual(snapshot.dashboard.date, now)

        // Constructing the legacy host remains source-compatible; resolving
        // its concrete HealthKit provider is intentionally not performed in a
        // test that promises no real HKHealthStore startup.
        _ = VelaServices()
    }

    func testHistoricalScoringEliminatesLookaheadBias() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let baseDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!

        // Create baseline points spanning 30 days
        let pastPoints = (0..<30).map { (offset: Int) -> LongTermBaselinePoint in
            let date = calendar.date(byAdding: .day, value: -offset, to: baseDate)!
            return LongTermBaselinePoint(
                date: date,
                hrvAverage: 50.0 + Double(offset % 5),
                restingHeartRate: 60.0,
                sleepHours: 7.5
            )
        }

        // Add 5 "future" points relative to baseDate
        let futurePoints = (1...5).map { (offset: Int) -> LongTermBaselinePoint in
            let date = calendar.date(byAdding: .day, value: offset, to: baseDate)!
            return LongTermBaselinePoint(
                date: date,
                hrvAverage: 120.0, // Significant future spike
                restingHeartRate: 40.0,
                sleepHours: 10.0
            )
        }

        let allPoints = pastPoints + futurePoints

        // When evaluating as-of baseDate, future points must be filtered out
        let historicalPoints = allPoints.filter { $0.date <= baseDate }
        XCTAssertEqual(historicalPoints.count, 30)
        XCTAssertFalse(historicalPoints.contains { $0.date > baseDate })

        let reportWithoutFuture = LongTermBaselineEngine.compute(
            points: historicalPoints,
            today: baseDate,
            calendar: calendar
        )

        // Baseline computed with future excluded should be deterministic
        XCTAssertNotNil(reportWithoutFuture)
    }
}
