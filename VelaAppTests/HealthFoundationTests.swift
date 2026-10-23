import XCTest
import HealthKit
import SwiftData
@testable import Vela

final class HealthFoundationTests: XCTestCase {
    @MainActor
    func testHealthPermissionTiersRequestCumulativeReadTypes() async throws {
        let store = FakeHealthStore()
        let service = HealthAuthorizationService(healthStore: store)

        try await service.requestAuthorization(tier: .core)
        XCTAssertEqual(store.requestedReadTypes, Set(HealthDataTypeCatalog.coreTypes))

        try await service.requestAuthorization(tier: .enhanced)
        XCTAssertEqual(store.requestedReadTypes, Set(HealthDataTypeCatalog.coreTypes + HealthDataTypeCatalog.enhancedTypes))

        try await service.requestAuthorization(tier: .advanced)
        XCTAssertEqual(store.requestedReadTypes, Set(HealthDataTypeCatalog.readTypes))
    }

    @MainActor
    func testHealthSyncDefersUntilInitialAuthorizationRequest() async {
        let store = FakeHealthStore()
        let service = HealthAuthorizationService(healthStore: store)

        store.requestStatus = .shouldRequest
        let shouldDefer = await service.shouldDeferBackgroundSync()
        XCTAssertTrue(shouldDefer)

        store.requestStatus = .unnecessary
        let shouldSync = await service.shouldDeferBackgroundSync()
        XCTAssertFalse(shouldSync)
    }

    @MainActor
    func testSnapshotOmitsUncomputedScoresInsteadOfPersistingZeroes() {
        let date = Date()
        let context = DailyHealthContext(
            date: date,
            sleepSummary: nil,
            recoveryMetrics: RecoveryMetricSummary(),
            recoveryBaseline: RecoveryMetricSummary(),
            strainToday: StrainActivitySummary(workouts: []),
            strainBaselineDaily: StrainActivitySummary(workouts: []),
            bodyMetrics: BodyMetricsSummary()
        )

        let snapshot = DailySummaryUseCase().makeSnapshot(
            from: .empty(date: date),
            context: context,
            date: date
        )

        XCTAssertNil(snapshot.recoveryScore)
        XCTAssertNil(snapshot.sleepScore)
        XCTAssertNil(snapshot.strainScore)
        XCTAssertNil(snapshot.stressIndex)
        XCTAssertNil(snapshot.currentEnergy)
    }

    @MainActor
    func testMakeSnapshotPersistsEnergyBankMatchingEngineValue() throws {
        // F3 回归：makeSnapshot 之前硬编码 energyBank: nil，
        // 前台重存会抹掉引擎 applying(to:) 写入的能量银行字段。
        let date = Date()
        let dashboard = PreviewDataFactory.makeDashboard(date: date)
        let context = DailyHealthContext(
            date: date,
            sleepSummary: nil,
            recoveryMetrics: RecoveryMetricSummary(),
            recoveryBaseline: RecoveryMetricSummary(),
            strainToday: StrainActivitySummary(workouts: []),
            strainBaselineDaily: StrainActivitySummary(workouts: []),
            bodyMetrics: BodyMetricsSummary()
        )

        let snapshot = DailySummaryUseCase().makeSnapshot(
            from: dashboard,
            context: context,
            date: date
        )

        XCTAssertEqual(
            snapshot.energyBank,
            dashboard.energy.hasData ? dashboard.energy.value : nil,
            "energyBank 必须与引擎写入值一致，不得恒为 nil"
        )
        XCTAssertEqual(
            snapshot.currentEnergy,
            dashboard.energy.hasData ? dashboard.energy.value : nil
        )
    }

    func testDataCoverageSummaryBuildsDomainScoresAndTopBlockers() {
        let groups = [
            CoverageGroup(
                id: "recovery",
                title: "恢复",
                icon: "heart.fill",
                signals: [
                    coverage(.hrvSDNN, usable: true),
                    coverage(.restingHR, usable: true),
                    coverage(.respiratoryRate, usable: false)
                ],
                affectedJudgments: ["Recovery Score"]
            ),
            CoverageGroup(
                id: "training",
                title: "训练",
                icon: "figure.run",
                signals: [
                    coverage(.workouts, usable: true),
                    coverage(.activeEnergy, usable: false),
                    coverage(.workoutHR, usable: false)
                ],
                affectedJudgments: ["Training Load"]
            )
        ]

        let summary = DataCoverageSummaryModel.build(groups: groups)

        XCTAssertEqual(summary.scorePercent, 50)
        XCTAssertEqual(summary.status, .moderate)
        XCTAssertEqual(summary.domainSummaries.map(\.id), ["recovery", "training"])
        XCTAssertEqual(summary.domainSummaries.map(\.scorePercent), [67, 33])
        XCTAssertEqual(summary.topBlockers.count, 3)
        XCTAssertTrue(summary.coachContextLine.contains("Data coverage 50%"))
    }

    func testDataCoverageSummaryStaysConservativeWhenCriticalSignalsAreMissing() {
        let groups = [
            CoverageGroup(
                id: "recovery",
                title: "恢复",
                icon: "heart.fill",
                signals: [
                    coverage(.hrvSDNN, usable: false),
                    coverage(.restingHR, usable: false),
                    coverage(.respiratoryRate, usable: false)
                ],
                affectedJudgments: ["Recovery Score", "Autonomic Fatigue"]
            )
        ]

        let summary = DataCoverageSummaryModel.build(groups: groups)

        XCTAssertEqual(summary.scorePercent, 0)
        XCTAssertEqual(summary.status, .low)
        XCTAssertTrue(summary.subtitle.contains("保守"))
        XCTAssertTrue(summary.actionTitle.contains("数据"))
    }

    func testCoverageDoesNotClaimAvailabilityWithoutReadableSamples() {
        let coverage = HealthSignalCoverage(
            signal: .hrvSDNN,
            authorizationState: .noReadableSamples,
            sampleCount7d: 0,
            sampleCount30d: 0,
            latestSampleAt: nil,
            freshness: .missing,
            quality: .insufficient
        )

        XCTAssertFalse(coverage.isAvailable)
        XCTAssertFalse(coverage.analyticallyUsable)
        XCTAssertTrue(
            coverage.confidenceImpact.contains("读取") ||
            coverage.confidenceImpact.contains("readable")
        )
    }

    @MainActor
    func testCoverageStoreSeamPreservesTypedOutcomesAndDiagnostics() async {
        let fake = FakeHealthCoverageStore()
        fake.isHealthDataAvailable = false
        let unavailableService = HealthSignalCoverageService(coverageStore: fake)
        let unavailable = await unavailableService.fetchCoverage(for: .hrvSDNN)
        XCTAssertEqual(unavailable.queryOutcome, .unavailable)
        XCTAssertEqual(unavailable.authorizationState, .unavailable)

        fake.isHealthDataAvailable = true
        fake.errorsByIdentifier[HealthSignal.restingHR.objectType!.identifier] = NSError(
            domain: HKErrorDomain,
            code: HKError.Code.errorAuthorizationDenied.rawValue
        )
        fake.errorsByIdentifier[HealthSignal.respiratoryRate.objectType!.identifier] = NSError(
            domain: HKErrorDomain,
            code: HKError.Code.errorDatabaseInaccessible.rawValue
        )
        fake.errorsByIdentifier[HealthSignal.sleepAnalysis.objectType!.identifier] = NSError(
            domain: "CoverageTest",
            code: 42
        )

        let stats = HealthCoverageSampleStats(sampleCount7d: 0, sampleCount30d: 0, latestSampleAt: nil)
        fake.statsByIdentifier[HealthSignal.activeEnergy.objectType!.identifier] = stats
        let service = HealthSignalCoverageService(coverageStore: fake)

        let denied = await service.fetchCoverage(for: .restingHR)
        let transient = await service.fetchCoverage(for: .respiratoryRate)
        let failed = await service.fetchCoverage(for: .sleepAnalysis)
        let noData = await service.fetchCoverage(for: .activeEnergy)

        XCTAssertEqual(denied.queryOutcome, .denied)
        XCTAssertEqual(denied.authorizationState, .denied)
        XCTAssertEqual(transient.queryOutcome, .transient)
        XCTAssertEqual(failed.queryOutcome, .failed)
        XCTAssertEqual(noData.queryOutcome, .noData)
        XCTAssertEqual(noData.authorizationState, .noReadableSamples)
        XCTAssertFalse(noData.analyticallyUsable)
        XCTAssertNil(noData.latestSampleAt)

        // HealthKit may return an empty sample set instead of throwing when
        // read access is denied; authorization state must still win over the
        // no-data inference.
        fake.sharingStatus = .sharingDenied
        let deniedWithoutSamples = await service.fetchCoverage(for: .activeEnergy)
        XCTAssertEqual(deniedWithoutSamples.queryOutcome, .denied)
        XCTAssertEqual(deniedWithoutSamples.authorizationState, .denied)

        let diagnostics = service.consumeDiagnostics()
        let outcomeCounts = Dictionary(grouping: diagnostics, by: \.outcome)
            .mapValues(\.count)
        XCTAssertEqual(outcomeCounts[.denied], 2)
        XCTAssertEqual(outcomeCounts[.transient], 1)
        XCTAssertEqual(outcomeCounts[.failed], 1)
        XCTAssertEqual(outcomeCounts[.noData], 1)
        XCTAssertTrue(service.consumeDiagnostics().isEmpty)
    }

    @MainActor
    func testCoverageStoreSeamComputesFreshUsableCoverageWithoutInventingZero() async {
        let fake = FakeHealthCoverageStore()
        fake.statsByIdentifier[HealthSignal.hrvSDNN.objectType!.identifier] = HealthCoverageSampleStats(
            sampleCount7d: 7,
            sampleCount30d: 14,
            latestSampleAt: Date()
        )
        let service = HealthSignalCoverageService(coverageStore: fake)

        let coverage = await service.fetchCoverage(for: .hrvSDNN)

        XCTAssertEqual(coverage.queryOutcome, .data)
        XCTAssertEqual(coverage.authorizationState, .readableSamples)
        XCTAssertEqual(coverage.sampleCount7d, 7)
        XCTAssertEqual(coverage.sampleCount30d, 14)
        XCTAssertTrue(coverage.analyticallyUsable)
        XCTAssertNotEqual(coverage.sampleCount30d, 0)
    }

    func testHealthSignalCatalogCoversEveryQueriedSignalAndSeparatesAudioSources() {
        XCTAssertTrue(HealthSignal.allCases.allSatisfy { $0.objectType != nil })
        XCTAssertNotEqual(
            HealthSignal.envNoise.objectType?.identifier,
            HealthSignal.headphoneNoise.objectType?.identifier
        )

        let advancedIdentifiers = Set(
            HealthSignalCatalog.readTypes(for: .advanced).map(\.identifier)
        )
        XCTAssertTrue(advancedIdentifiers.contains(HealthSignal.height.objectType!.identifier))
        XCTAssertTrue(advancedIdentifiers.contains(HealthSignal.workoutRoute.objectType!.identifier))
        XCTAssertTrue(advancedIdentifiers.contains(HealthSignal.daylight.objectType!.identifier))
    }

    func testHeartRateRecoveryUnitMatchesAppleHealthSampleUnit() throws {
        // Apple 的 heartRateRecoveryOneMinute 样本单位是 count/min。
        // 若 unit 表写错(如 .count()),doubleValue(for:) 会在真机上抛
        // NSInvalidArgumentException,App 启动即崩溃。
        // 复现崩溃路径:用真实 Apple 单位创建一个样本,再用 unit 表单位取值,必须不抛异常。
        let unit = try XCTUnwrap(
            HealthSignalCatalog.unit(for: .heartRateRecoveryOneMinute)?.healthKitUnit
        )
        let sampleUnit = HKUnit.count().unitDivided(by: .minute())
        let sample = HKQuantitySample(
            type: try XCTUnwrap(HealthSignalCatalog.objectType(for: .heartRateRecoveryOneMinute) as? HKQuantityType),
            quantity: HKQuantity(unit: sampleUnit, doubleValue: 12.0),
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 60)
        )
        XCTAssertNoThrow(sample.quantity.doubleValue(for: unit))
    }

    func testReadStateResolverNeverInfersReadDenialFromMissingSamples() {
        // 缺失样本 + 已授权 → 仍判「暂无样本」，denied 只来自显式的 sharingStatus
        XCTAssertEqual(
            HealthReadStateResolver.resolve(
                requestStatus: .unnecessary,
                sharingStatus: .sharingAuthorized,
                sampleCount7d: 0,
                sampleCount30d: 0
            ),
            .noReadableSamples
        )
        XCTAssertEqual(
            HealthReadStateResolver.resolve(
                requestStatus: .shouldRequest,
                sharingStatus: .sharingAuthorized,
                sampleCount7d: 0,
                sampleCount30d: 0
            ),
            .notRequested
        )
        XCTAssertEqual(
            HealthReadStateResolver.resolve(
                requestStatus: .unnecessary,
                sharingStatus: .sharingAuthorized,
                sampleCount7d: 0,
                sampleCount30d: 12
            ),
            .readableSamplesStale
        )
    }

    func testHealthSyncPlannerBootstrapsBaselinesButScoresRequestedWindow() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = Date(timeIntervalSince1970: 1_785_369_600)

        let plan = HealthSyncPlanner.plan(
            requestedDays: 3,
            endingAt: end,
            cachedDays: [],
            state: HealthSyncCursorState(),
            forceRefreshRecentDays: 3,
            calendar: calendar
        )

        XCTAssertEqual(plan.rawRefreshDays.count, 45)
        XCTAssertEqual(plan.scoreRecomputeDays.count, 3)
    }

    func testHealthSyncPlannerRecomputesForwardFromDirtyDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_785_369_600))
        let allDays = Set((0..<45).compactMap {
            calendar.date(byAdding: .day, value: -$0, to: end)
        })
        let dirty = calendar.date(byAdding: .day, value: -10, to: end)!
        let dirtyID = DailyHealthSummaryRecord.dayIdentifier(for: dirty, calendar: calendar)
        let state = HealthSyncCursorState(
            lastSuccessfulSyncAt: end.addingTimeInterval(-3_600),
            pendingDirtyDayIdentifiers: [dirtyID]
        )

        let plan = HealthSyncPlanner.plan(
            requestedDays: 3,
            endingAt: end,
            cachedDays: allDays,
            state: state,
            forceRefreshRecentDays: 2,
            calendar: calendar
        )

        XCTAssertTrue(plan.rawRefreshDays.contains(dirty))
        XCTAssertEqual(plan.scoreRecomputeDays.first, dirty)
        XCTAssertEqual(plan.scoreRecomputeDays.last, end)
        XCTAssertEqual(plan.scoreRecomputeDays.count, 11)
    }

    func testHealthSyncCursorStorePersistsDirtyDays() {
        let suiteName = "HealthSyncCursor-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = HealthSyncCursorStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_785_369_600)

        store.markDirty(date)

        XCTAssertEqual(store.load().pendingDirtyDayIdentifiers.count, 1)
    }

    func testHealthReadStateResolverDistinguishesDeniedPermission() {
        // 用户拒绝权限后不得被归入「暂无样本」——必须有独立的 denied 状态，
        // 供 Onboarding/今日页给出「去系统设置开启」的恢复路径。
        XCTAssertEqual(
            HealthReadStateResolver.resolve(
                requestStatus: .unnecessary,
                sharingStatus: .sharingDenied,
                sampleCount7d: 0,
                sampleCount30d: 0
            ),
            .denied
        )
        XCTAssertEqual(
            HealthReadStateResolver.resolve(
                requestStatus: .unnecessary,
                sharingStatus: .sharingAuthorized,
                sampleCount7d: 0,
                sampleCount30d: 0
            ),
            .noReadableSamples
        )
        XCTAssertEqual(
            HealthReadStateResolver.resolve(
                requestStatus: .unnecessary,
                sharingStatus: .sharingAuthorized,
                sampleCount7d: 5,
                sampleCount30d: 10
            ),
            .readableSamples
        )
    }

    func testHealthDayBoundaryAssignsAfterMidnightSamplesToPreviousHealthDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let boundary = HealthDayBoundary(calendar: calendar, boundaryMinutes: 4 * 60)
        let twoAM = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 31, hour: 2
        )))
        let fiveAM = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 31, hour: 5
        )))

        XCTAssertEqual(
            DailyHealthSummaryRecord.dayIdentifier(
                for: boundary.labelDate(containing: twoAM),
                calendar: calendar
            ),
            "2026-07-30"
        )
        XCTAssertEqual(
            DailyHealthSummaryRecord.dayIdentifier(
                for: boundary.labelDate(containing: fiveAM),
                calendar: calendar
            ),
            "2026-07-31"
        )
    }

    func testMainNightSummaryAttributesFullNightCrossingHealthDayBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 13
        )))
        // 目标健康日窗口 [04:00 D, 04:00 D+1)
        let range = DateRangeQuery.singleDay(day, calendar: calendar)

        // 昨夜 23:00 D-1 入睡、07:00 D 醒，跨 04:00 边界的两个睡眠阶段段。
        // 查询调用方会把窗口向前扩展以捕获前夜入睡段（段按 startDate 匹配），
        // 归属必须按“主睡眠段结束时刻”落在目标窗口内 → 完整 8 小时夜晚。
        let segments = [
            SleepStageSegment(
                stage: .deep,
                start: day.addingTimeInterval(-1 * 3_600),
                end: day.addingTimeInterval(2 * 3_600)
            ),
            SleepStageSegment(
                stage: .rem,
                start: day.addingTimeInterval(2 * 3_600),
                end: day.addingTimeInterval(7 * 3_600)
            )
        ]

        let summary = SleepSampleNormalizer.mainNightSummary(in: range, segments: segments)

        XCTAssertEqual(summary?.totalSleepMinutes ?? -1, 480)
        XCTAssertEqual(summary?.bedtime, day.addingTimeInterval(-1 * 3_600))
        XCTAssertEqual(summary?.wakeTime, day.addingTimeInterval(7 * 3_600))
    }

    func testMainNightSummaryIgnoresNapsWhenNightEndsInWindow() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2026, month: 8, day: 13
        )))
        let range = DateRangeQuery.singleDay(day, calendar: calendar)

        // 主睡眠 23:00→06:00（7h）+ 午后小睡 13:00→14:30（1.5h，也结束在窗口内）
        let night = [
            SleepStageSegment(stage: .deep, start: day.addingTimeInterval(-1 * 3_600), end: day.addingTimeInterval(6 * 3_600))
        ]
        let nap = [
            SleepStageSegment(stage: .core, start: day.addingTimeInterval(13 * 3_600), end: day.addingTimeInterval(14.5 * 3_600))
        ]

        let summary = SleepSampleNormalizer.mainNightSummary(in: range, segments: night + nap)

        XCTAssertEqual(summary?.totalSleepMinutes ?? -1, 420)
        XCTAssertEqual(summary?.wakeTime, day.addingTimeInterval(6 * 3_600))
    }

    func testHealthDayBoundaryUsesCalendarDaysAcrossDSTAndTravelTimeZones() throws {
        var losAngeles = Calendar(identifier: .gregorian)
        losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let boundary = HealthDayBoundary(calendar: losAngeles, boundaryMinutes: 4 * 60)
        let springForward = try XCTUnwrap(losAngeles.date(from: DateComponents(
            year: 2026, month: 3, day: 8, hour: 12
        )))
        let range = boundary.range(containing: springForward)
        XCTAssertEqual(
            losAngeles.dateComponents([.day], from: range.start, to: range.end).day,
            1
        )

        let instant = Date(timeIntervalSince1970: 1_785_369_600)
        var shanghai = Calendar(identifier: .gregorian)
        shanghai.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let shanghaiLabel = HealthDayBoundary(
            calendar: shanghai,
            boundaryMinutes: 4 * 60
        ).labelDate(containing: instant)
        let losAngelesLabel = HealthDayBoundary(
            calendar: losAngeles,
            boundaryMinutes: 4 * 60
        ).labelDate(containing: instant)
        XCTAssertNotEqual(
            DailyHealthSummaryRecord.dayIdentifier(for: shanghaiLabel, calendar: shanghai),
            DailyHealthSummaryRecord.dayIdentifier(for: losAngelesLabel, calendar: losAngeles)
        )
    }

    private func coverage(_ signal: HealthSignal, usable: Bool) -> HealthSignalCoverage {
        HealthSignalCoverage(
            signal: signal,
            authorizationState: usable ? .readableSamples : .noReadableSamples,
            sampleCount7d: usable ? 7 : 0,
            sampleCount30d: usable ? 21 : 0,
            latestSampleAt: usable ? Date() : nil,
            freshness: usable ? .today : .missing,
            quality: usable ? .enough : .insufficient
        )
    }
}

@MainActor
private final class FakeHealthStore: HealthStoreProviding {
    var isHealthDataAvailable = true
    var requestedReadTypes = Set<HKObjectType>()
    var requestStatus: HKAuthorizationRequestStatus = .unnecessary

    func requestAuthorization(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws {
        requestedReadTypes = typesToRead
    }

    func authorizationRequestStatus(toShare typesToShare: Set<HKSampleType>, read typesToRead: Set<HKObjectType>) async throws -> HKAuthorizationRequestStatus {
        requestStatus
    }

    func authorizationStatus(for type: HKObjectType) -> HKAuthorizationStatus {
        .notDetermined
    }
}

@MainActor
private final class FakeHealthCoverageStore: HealthCoverageStore {
    var isHealthDataAvailable = true
    var requestStatus: HKAuthorizationRequestStatus = .unnecessary
    var sharingStatus: HKAuthorizationStatus = .sharingAuthorized
    var statsByIdentifier: [String: HealthCoverageSampleStats] = [:]
    var errorsByIdentifier: [String: Error] = [:]

    func authorizationStatus(for objectType: HKObjectType) -> HKAuthorizationStatus {
        sharingStatus
    }

    func authorizationRequestStatus(for objectType: HKObjectType) async throws -> HKAuthorizationRequestStatus {
        requestStatus
    }

    func sampleStats(
        for sampleType: HKSampleType,
        start7d: Date,
        start30d: Date,
        now: Date
    ) async throws -> HealthCoverageSampleStats {
        if let error = errorsByIdentifier[sampleType.identifier] {
            throw error
        }
        return statsByIdentifier[sampleType.identifier]
            ?? HealthCoverageSampleStats(sampleCount7d: 0, sampleCount30d: 0, latestSampleAt: nil)
    }
}

// MARK: - BodyStateKernel & TrainingDecisionKernel Tests

final class BodyStateKernelTests: XCTestCase {
    func testBodyStateKernelBuildBasic() {
        let kernel = BodyStateKernel()
        let input = BodyStateInput(
            dashboard: .empty(date: Date()),
            activeStatus: "active",
            generatedAt: Date()
        )
        
        let state = kernel.build(input: input)
        XCTAssertEqual(state.activeStatus, "active")
        XCTAssertEqual(state.readiness, .unknown)
        XCTAssertEqual(state.drivers.count, 1)
        XCTAssertEqual(state.drivers.first?.kind, .dataCoverage)
        XCTAssertTrue(state.drivers.first?.detail.contains("保守训练窗口") == true)
    }

    func testBodyStateKernelSickStatusAddsDriver() {
        let kernel = BodyStateKernel()
        let input = BodyStateInput(
            dashboard: .empty(date: Date()),
            activeStatus: "sick",
            generatedAt: Date()
        )
        
        let state = kernel.build(input: input)
        XCTAssertEqual(state.activeStatus, "sick")
        XCTAssertFalse(state.drivers.isEmpty)
        XCTAssertTrue(state.drivers.contains(where: { $0.kind == .activeStatus }))
    }

    func testBodyStateKernelNutritionAddsDriver() {
        let kernel = BodyStateKernel()
        let food = FoodLogRecord(
            mealName: "Lunch",
            foods: [FoodLogItem(name: "Chicken Salad", portion: "1 bowl", calories: 350)],
            totalCalories: 350,
            proteinGrams: 30,
            carbsGrams: 10,
            fatGrams: 20,
            fiberGrams: 5,
            healthScore: "85",
            suggestions: ["Good protein source."],
            source: .manual,
            rawAnalysis: "",
            createdAt: Date()
        )
        let input = BodyStateInput(
            dashboard: .empty(date: Date()),
            foodLogs: [food.dto],
            generatedAt: Date()
        )
        
        let state = kernel.build(input: input)
        XCTAssertTrue(state.drivers.contains(where: { $0.kind == BodyStateDriver.Kind.nutrition }))
    }
}

final class TrainingDecisionKernelTests: XCTestCase {
    func testTrainingDecisionKernelSickStatusForcesRest() {
        let kernel = TrainingDecisionKernel()
        let dashboard = DashboardSummary.empty(date: Date())
        
        // Mock bodyState with sick activeStatus
        var state = dashboard.bodyState
        state.activeStatus = "sick"
        state.readiness = .recovering
        
        let input = TrainingDecisionInput(
            bodyState: state,
            activePlan: nil,

            trainingResponses: []
        )
        
        let decision = kernel.decide(input: input)
        XCTAssertEqual(decision.decision, .rest)
        XCTAssertEqual(decision.volumeMultiplier, 0.0)
    }
}

final class ProactiveIntelligenceOrchestratorTests: XCTestCase {
    @MainActor
    func testProactiveIntelligenceOrchestratorRunAsyncCheck() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext

        // 主动洞察是 opt-in 开关（默认关）；开关必须被尊重（此前无效的 bug 已修）。
        AutoAgentConfig.shared.proactiveInsights = true
        // 日级去重 key 会跨测试进程残留，先清除确保本次检查执行。
        UserDefaults.standard.removeObject(forKey: "vela.proactive.last_async_check_day")

        let orchestrator = ProactiveIntelligenceOrchestrator()
        let insights = await orchestrator.runAsyncCheck(modelContext: context)
        
        XCTAssertFalse(insights.isEmpty)

        // D3 修复：ProactiveInsightRecord 不再落库（UI 实时重算为唯一事实来源）。
        let records = (try? context.fetch(FetchDescriptor<ProactiveInsightRecord>())) ?? []
        XCTAssertTrue(records.isEmpty, "主动洞察不再持久化，落库记录此前只写不读")

        let events = (try? context.fetch(FetchDescriptor<VelaEventRecord>())) ?? []
        XCTAssertTrue(events.contains(where: { $0.eventType == VelaProductEventType.proactiveInsightGenerated }))
    }
}

final class WorkoutAdaptationServiceTests: XCTestCase {
    func testPostWorkoutAIGenerationGateRequiresBackgroundHealthAndTrainingConsent() {
        let fullyAuthorized = AgentOutboundConsentPolicy(
            backgroundNetworkAIConsent: true,
            categoryPolicy: .all
        )
        XCTAssertTrue(PostWorkoutAIGenerationGate.allows(policy: fullyAuthorized))

        let noBackgroundConsent = AgentOutboundConsentPolicy(
            backgroundNetworkAIConsent: false,
            categoryPolicy: .all
        )
        XCTAssertFalse(PostWorkoutAIGenerationGate.allows(policy: noBackgroundConsent))

        let healthOnly = AgentOutboundConsentPolicy(
            backgroundNetworkAIConsent: true,
            health: true,
            training: false,
            nutrition: false,
            journal: false,
            wiki: false,
            reports: false,
            conversationHistory: false,
            webSearch: false,
            files: false
        )
        XCTAssertFalse(PostWorkoutAIGenerationGate.allows(policy: healthOnly))

        let trainingOnly = AgentOutboundConsentPolicy(
            backgroundNetworkAIConsent: true,
            health: false,
            training: true,
            nutrition: false,
            journal: false,
            wiki: false,
            reports: false,
            conversationHistory: false,
            webSearch: false,
            files: false
        )
        XCTAssertFalse(PostWorkoutAIGenerationGate.allows(policy: trainingOnly))

        let noCategoryConsent = AgentOutboundConsentPolicy(
            backgroundNetworkAIConsent: true,
            categoryPolicy: .none
        )
        XCTAssertFalse(PostWorkoutAIGenerationGate.allows(policy: noCategoryConsent))
    }

    @MainActor
    func testWorkoutAdaptationServiceProcessWorkoutCompletion() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext
        
        let plan = TrainingPlanRecord(
            title: "Hypothalamic Adaptation Plan",
            goalDescription: "Strength Development",
            days: [
                TrainingDay(
                    weekNumber: 1,
                    dayNumber: 1,
                    title: "Lower Body Heavy",
                    description: "Squat 4x5",
                    focus: "strength",
                    durationMinutes: 45,
                    intensity: "high"
                )
            ]
        )
        context.insert(plan)
        try context.save()
        
        let service = WorkoutAdaptationService()
        let workoutID = UUID()
        _ = try await service.processWorkoutCompletion(workoutID: workoutID, modelContext: context)
        
        let events = (try? context.fetch(FetchDescriptor<VelaEventRecord>())) ?? []
        XCTAssertTrue(events.contains(where: { $0.eventType == VelaProductEventType.workoutCompleted }))
    }

    @MainActor
    func testWorkoutAdaptationServiceSkipsDeniedPostWorkoutProviderAfterLocalMutation() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext
        let plan = TrainingPlanRecord(
            title: "Consent Gate Plan",
            goalDescription: "Strength Development",
            days: [
                TrainingDay(
                    weekNumber: 1,
                    dayNumber: 1,
                    title: "Full Body",
                    description: "Squat 3x5",
                    focus: "strength",
                    durationMinutes: 30,
                    intensity: "moderate"
                )
            ]
        )
        context.insert(plan)
        try context.save()

        let deniedPolicy = AgentOutboundConsentPolicy(
            backgroundNetworkAIConsent: true,
            health: true,
            training: false,
            nutrition: false,
            journal: false,
            wiki: false,
            reports: false,
            conversationHistory: false,
            webSearch: false,
            files: false
        )
        let probe = PostWorkoutAIGeneratorProbe()
        let service = WorkoutAdaptationService(
            postWorkoutAIGenerator: { _, _ in
                await probe.recordInvocation()
                return PostWorkoutAIBoundary(
                    observation: "should not be requested",
                    nextVolumeMultiplier: 0.7,
                    nextIntensityCap: 7,
                    nextSuggestedFocus: nil,
                    rationale: "should not be requested"
                )
            },
            outboundPolicyProvider: { deniedPolicy }
        )

        _ = try await service.processWorkoutCompletion(
            workoutID: UUID(),
            modelContext: context
        )

        let invocationCount = await probe.invocationCount()
        XCTAssertEqual(invocationCount, 0)
        let events = (try? context.fetch(FetchDescriptor<VelaEventRecord>())) ?? []
        XCTAssertTrue(
            events.contains(where: { $0.eventType == VelaProductEventType.workoutCompleted }),
            "Denied network consent must not discard the local workout completion fact."
        )
    }
}

private actor PostWorkoutAIGeneratorProbe {
    private var count = 0

    func recordInvocation() {
        count += 1
    }

    func invocationCount() -> Int {
        count
    }
}

final class CircadianAlignmentKernelTests: XCTestCase {
    func testCircadianAlignmentKernelEvaluation() {
        let kernel = CircadianAlignmentKernel()
        let input = CircadianInput(
            sleepStartHour: 23.5,
            sleepEndHour: 7.5,
            targetBedtimeHour: 23.0,
            hrvLowestPointHour: 3.5
        )
        let result = kernel.evaluate(input: input)

        XCTAssertEqual(result.phaseOffsetMinutes, 30)
        XCTAssertEqual(result.estimatedCortisolPeak, "08:00")
        XCTAssertEqual(result.caffeineCutoffTime, "13:30")
        XCTAssertFalse(result.recommendations.isEmpty)
    }
}

final class PipelineDiagnosticsLoggerTests: XCTestCase {
    @MainActor
    func testPipelineDiagnosticsSelfCheck() throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext

        PipelineDiagnosticsLogger.log(
            modelContext: context,
            stage: "health_kit_sync",
            isSuccess: true,
            summary: "Sync completed successfully."
        )

        let report = PipelineDiagnosticsLogger.performSelfCheck(modelContext: context)

        XCTAssertTrue(report.isHealthy)
        XCTAssertEqual(report.recentErrorsCount, 0)
    }
}

final class ArtifactGeneratorToolTests: XCTestCase {
    @MainActor
    func testArtifactGeneratorToolCreatesAndPersistsArtifactRecord() throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext

        let artifact = ArtifactGeneratorTool.createArtifact(
            type: .morningBrief,
            title: "Today's Briefing",
            summary: "Optimal recovery state.",
            modelContext: context
        )

        XCTAssertEqual(artifact.title, "Today's Briefing")

        let records = (try? context.fetch(FetchDescriptor<AgentArtifactRecord>())) ?? []
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.title, "Today's Briefing")
    }
}

final class BiologicalAgeEngineTests: XCTestCase {
    func testBiologicalAgeEngineEvaluatesHeartRateRecoveryFactor() {
        let engine = BiologicalAgeEngine()
        let input = BiologicalAgeInput(
            chronologicalAge: 28.0,
            restingHR: 58.0,
            vo2Max: 48.0,
            heartRateRecovery: 28.0
        )
        let result = engine.calculate(input: input)

        XCTAssertTrue(result.factors.contains(where: { $0.name.contains("心率恢复") || $0.name.contains("Heart Rate Recovery") }))
        XCTAssertEqual(result.healthAgeTrend, "improving")
    }

    private static func biomarker(_ name: String, _ value: Double, _ unit: String) -> BiomarkerRecord {
        BiomarkerRecord(name: name, value: value, unit: unit, referenceMin: 0, referenceMax: 100)
    }

    private static var healthyBiomarkers: [BiomarkerRecord] {
        [
            biomarker("Albumin", 4.5, "g/dL"),
            biomarker("Creatinine", 0.9, "mg/dL"),
            biomarker("Glucose", 85, "mg/dL"),
            biomarker("C-Reactive Protein", 0.5, "mg/L"),
            biomarker("Lymphocyte", 35, "%"),
            biomarker("MCV", 90, "fL"),
            biomarker("RDW", 12.5, "%"),
            biomarker("Alkaline Phosphatase", 60, "U/L"),
            biomarker("WBC", 5.5, "10^3/uL")
        ]
    }

    private static var abnormalBiomarkers: [BiomarkerRecord] {
        [
            biomarker("Albumin", 3.8, "g/dL"),
            biomarker("Creatinine", 1.3, "mg/dL"),
            biomarker("Glucose", 110, "mg/dL"),
            biomarker("C-Reactive Protein", 3.0, "mg/L"),
            biomarker("Lymphocyte", 25, "%"),
            biomarker("MCV", 88, "fL"),
            biomarker("RDW", 14.5, "%"),
            biomarker("Alkaline Phosphatase", 90, "U/L"),
            biomarker("WBC", 7.0, "10^3/uL")
        ]
    }

    func testBiologicalAgeEnginePhenoAgeCanonicalFormulaForHealthy30() {
        // Levine 2018 规范公式（BioAge 包确认常数）实算 ≈ 22.9 岁；
        // 旧实现 hazard 缩小 25,637 倍，同输入输出约 −64 岁。
        let result = BiologicalAgeEngine().calculate(input: BiologicalAgeInput(
            chronologicalAge: 30.0,
            biomarkers: Self.healthyBiomarkers
        ))
        XCTAssertEqual(result.biologicalAge, 22.9, accuracy: 3.0)
    }

    func testBiologicalAgeEnginePhenoAgeCanonicalFormulaForNormal50() {
        let result = BiologicalAgeEngine().calculate(input: BiologicalAgeInput(
            chronologicalAge: 50.0,
            biomarkers: Self.healthyBiomarkers
        ))
        XCTAssertEqual(result.biologicalAge, 40.7, accuracy: 3.0)
    }

    func testBiologicalAgeEnginePhenoAgeCanonicalFormulaForAbnormal50() {
        let result = BiologicalAgeEngine().calculate(input: BiologicalAgeInput(
            chronologicalAge: 50.0,
            biomarkers: Self.abnormalBiomarkers
        ))
        XCTAssertEqual(result.biologicalAge, 59.9, accuracy: 3.0)
    }

    func testBiologicalAgeEngineClampsPhenoAgeToPlausibleRange() {
        // 高龄 + 极差化验：M→1 时 log 发散，必须有下界护栏且输出钳制在 0...150
        let extreme = BiologicalAgeInput(
            chronologicalAge: 90.0,
            biomarkers: [
                Self.biomarker("Albumin", 2.5, "g/dL"),
                Self.biomarker("Creatinine", 5.0, "mg/dL"),
                Self.biomarker("Glucose", 300, "mg/dL"),
                Self.biomarker("C-Reactive Protein", 50, "mg/L"),
                Self.biomarker("Lymphocyte", 8, "%"),
                Self.biomarker("MCV", 70, "fL"),
                Self.biomarker("RDW", 25, "%"),
                Self.biomarker("Alkaline Phosphatase", 500, "U/L"),
                Self.biomarker("WBC", 25, "10^3/uL")
            ]
        )
        let result = BiologicalAgeEngine().calculate(input: extreme)
        XCTAssertGreaterThanOrEqual(result.biologicalAge, 0)
        XCTAssertLessThanOrEqual(result.biologicalAge, 150)
    }
}

final class AutonomousHealthDigitalTwinTests: XCTestCase {
    @MainActor
    func testAutonomousHealthDigitalTwinSimulation() {
        let twin = AutonomousHealthDigitalTwin()
        let dashboard = DashboardSummary.empty(date: Date())
        let scenario = SimulationScenarioInput(
            plannedWorkoutStrain: 15.0,
            plannedWorkoutHour: 21.0,
            targetSleepDurationHours: 6.5
        )

        let result = twin.simulateNextDay(dashboard: dashboard, scenario: scenario)

        XCTAssertEqual(result.scenarioTag, "suboptimal_timing")
        XCTAssertLessThan(result.sleepQualityMultiplier, 1.0)
        XCTAssertFalse(result.recommendation.isEmpty)
    }
}

final class FoodVisionIntelligenceEngineTests: XCTestCase {
    func testFoodVisionIntelligenceEngineMealAnalysis() {
        let engine = FoodVisionIntelligenceEngine()
        let result = engine.analyzeMealText("香煎鸡胸肉配紫米饭和西兰花沙拉")

        XCTAssertEqual(result.metabolicTag, "protein_rich")
        XCTAssertGreaterThan(result.proteinGrams, 30)
        XCTAssertGreaterThan(result.estimatedCalories, 300)
        XCTAssertFalse(result.recommendations.isEmpty)
    }
}

final class PersonalBaselineEngineHuberTests: XCTestCase {
    func testHuberMeanRejectsExtremeSingleDayOutliers() {
        let sampleHRVs = [48.0, 52.0, 49.0, 51.0, 50.0, 47.0, 53.0, 250.0]

        let huber = PersonalBaselineEngine.huberMean(sampleHRVs)
        XCTAssertNotNil(huber)
        if let huber {
            XCTAssertLessThan(huber, 60.0)
            XCTAssertGreaterThan(huber, 45.0)
        }
    }
}

final class JournalCrossLaggedCorrelationTests: XCTestCase {
    func testJournalCrossLaggedCorrelationCalculation() {
        let engine = JournalCorrelationEngine()
        let seriesA = [15.0, 16.0, 14.0, 18.0, 12.0, 17.0, 15.0, 19.0]
        let seriesB = [75.0, 50.0, 48.0, 65.0, 35.0, 70.0, 55.0, 30.0]

        let results = engine.calculateCrossLaggedCorrelation(seriesA: seriesA, seriesB: seriesB, maxLagDays: 2)

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.contains(where: \.isOptimalLag))
    }
}

final class WorkoutHeartRateRecoveryMatcherTests: XCTestCase {
    func testMatchesNearestPositiveRecoverySampleToEachWorkoutOnlyOnce() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let first = WorkoutSummary(
            id: UUID(),
            start: base,
            end: base.addingTimeInterval(3_600),
            activityName: "Outdoor Run"
        )
        let second = WorkoutSummary(
            id: UUID(),
            start: base.addingTimeInterval(5 * 3_600),
            end: base.addingTimeInterval(6 * 3_600),
            activityName: "Cycling"
        )
        let samples = [
            HeartRateRecoverySample(date: first.end.addingTimeInterval(120), bpm: 27),
            HeartRateRecoverySample(date: second.end.addingTimeInterval(180), bpm: 31)
        ]

        let result = WorkoutHeartRateRecoveryMatcher.match(samples: samples, workouts: [first, second])

        XCTAssertEqual(result[first.id], 27)
        XCTAssertEqual(result[second.id], 31)
        XCTAssertEqual(result.count, 2)
    }

    func testDoesNotAttachStaleOrNegativeRecoverySamples() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let workout = WorkoutSummary(
            id: UUID(),
            start: base,
            end: base.addingTimeInterval(3_600),
            activityName: "Outdoor Run"
        )
        let samples = [
            HeartRateRecoverySample(date: workout.end.addingTimeInterval(7 * 3_600), bpm: 25),
            HeartRateRecoverySample(date: workout.end.addingTimeInterval(60), bpm: -5)
        ]

        XCTAssertTrue(WorkoutHeartRateRecoveryMatcher.match(samples: samples, workouts: [workout]).isEmpty)
    }
}

@MainActor
final class HistoricalScoreRepairTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 23))! }

    private func fixture(future: Bool = false, savedScore: Double? = nil) throws -> ModelContainer {
        let container = try VelaModelContainer.make(inMemory: true)
        for offset in -15 ... -1 {
            var snapshot = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: offset, to: today)!)
            snapshot.hrvAverage = 48 + Double(offset % 3)
            snapshot.restingHeartRate = 57
            snapshot.sleepHours = 7.5
            snapshot.steps = 0 // a real zero is evidence
            if offset == -1 { snapshot.recoveryScore = savedScore }
            container.mainContext.insert(DailyHealthSummaryRecord(snapshot: snapshot, calendar: calendar))
        }
        if future {
            var snapshot = DailyHealthSnapshot(date: calendar.date(byAdding: .day, value: 1, to: today)!)
            snapshot.hrvAverage = 100_000
            snapshot.restingHeartRate = 200
            container.mainContext.insert(DailyHealthSummaryRecord(snapshot: snapshot, calendar: calendar))
        }
        try container.mainContext.save()
        return container
    }

    private func record(_ container: ModelContainer) throws -> DailyHealthSummaryRecord {
        let context = ModelContext(container)
        return try XCTUnwrap(SwiftDataDailyHealthSummaryRepository(modelContext: context).fetchRecord(
            dayIdentifier: DailyHealthSummaryRecord.dayIdentifier(for: calendar.date(byAdding: .day, value: -1, to: today)!, calendar: calendar)))
    }

    func testRepairPersistsCanonicalEvidenceWithoutChangingRawDataAndIsIdempotent() async throws {
        let container = try fixture()
        let service = HistoricalScoreBackfillService(modelContext: ModelContext(container), calendar: calendar)
        let result = try await service.repair(days: 1, endingAt: today, profile: DailyHealthComputationProfile(sleepTargetMinutes: 450, maxHeartRate: 190, biologicalSex: nil))
        XCTAssertEqual(result.completed, 1)
        let saved = try record(container)
        XCTAssertNotNil(saved.decodedScoreEvidence())
        XCTAssertEqual(saved.hrvAverage, 47)
        XCTAssertEqual(saved.sleepHours, 7.5)
        XCTAssertEqual(saved.steps, 0)
        let rerun = try await HistoricalScoreBackfillService(modelContext: ModelContext(container), calendar: calendar).repair(days: 1, endingAt: today, profile: DailyHealthComputationProfile(sleepTargetMinutes: 450, maxHeartRate: 190, biologicalSex: nil))
        XCTAssertEqual(rerun.total, 0)
    }

    func testConcurrentScoreUpdateIsNotOverwritten() async throws {
        let container = try fixture()
        let service = HistoricalScoreBackfillService(modelContext: ModelContext(container), calendar: calendar)
        do {
            _ = try await service.repair(days: 1, endingAt: today, onProgress: { progress in
                if progress.completed == 0 {
                    let date = self.calendar.date(byAdding: .day, value: -1, to: self.today)!
                    let id = DailyHealthSummaryRecord.dayIdentifier(for: date, calendar: self.calendar)
                    let record = try! SwiftDataDailyHealthSummaryRepository(modelContext: container.mainContext).fetchRecord(dayIdentifier: id)!
                    record.recoveryScore = 88
                    try! container.mainContext.save()
                }
            })
            XCTFail("Concurrent update must stop this stale repair")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("更新"))
        }
        XCTAssertEqual(try record(container).recoveryScore, 88)
        XCTAssertNil(try record(container).decodedScoreEvidence())
    }

    func testRepairPreservesExistingPartialScores() async throws {
        let container = try fixture(savedScore: 42)
        let result = try await HistoricalScoreBackfillService(modelContext: ModelContext(container), calendar: calendar).repair(days: 1, endingAt: today, profile: DailyHealthComputationProfile(sleepTargetMinutes: 450, maxHeartRate: 190, biologicalSex: nil))
        XCTAssertEqual(result.total, 0)
        XCTAssertEqual(try record(container).recoveryScore, 42)
        XCTAssertNil(try record(container).decodedScoreEvidence())
    }

    func testBatchRepairMatchesChronologicalOneDayRepairs() async throws {
        let batch = try fixture()
        let sequential = try fixture()
        let profile = DailyHealthComputationProfile(sleepTargetMinutes: 450, maxHeartRate: 190, biologicalSex: nil)
        _ = try await HistoricalScoreBackfillService(modelContext: ModelContext(batch), calendar: calendar).repair(days: 7, endingAt: today, profile: profile)
        for offset in -6...0 {
            let end = calendar.date(byAdding: .day, value: offset, to: today)!
            _ = try await HistoricalScoreBackfillService(modelContext: ModelContext(sequential), calendar: calendar).repair(days: 1, endingAt: end, profile: profile)
        }
        let first = try XCTUnwrap(record(batch).decodedScoreEvidence())
        let second = try XCTUnwrap(record(sequential).decodedScoreEvidence())
        XCTAssertEqual(first.sleep, second.sleep)
        XCTAssertEqual(first.recovery, second.recovery)
        XCTAssertEqual(first.strain, second.strain)
        XCTAssertEqual(first.stress, second.stress)
        XCTAssertEqual(first.energy, second.energy)
    }

    func testFutureHealthRecordsCannotChangeHistoricalRepair() async throws {
        let first = try fixture()
        let second = try fixture(future: true)
        for container in [first, second] {
            _ = try await HistoricalScoreBackfillService(modelContext: ModelContext(container), calendar: calendar).repair(days: 1, endingAt: today, profile: DailyHealthComputationProfile(sleepTargetMinutes: 450, maxHeartRate: 190, biologicalSex: nil))
        }
        XCTAssertEqual(try record(first).decodedScoreEvidence(), try record(second).decodedScoreEvidence())
    }

    func testCoverageDistinguishesZeroRawEvidenceFromEmptyAndScoredDays() {
        var raw = DailyHealthSnapshot(date: today)
        raw.steps = 0
        var scored = DailyHealthSnapshot(date: today.addingTimeInterval(-86400))
        scored.recoveryScore = 0
        let empty = DailyHealthSnapshot(date: today.addingTimeInterval(-2 * 86400))
        let coverage = HistoricalCoverageSummary(snapshots: [raw, scored, empty], calendar: calendar)
        XCTAssertEqual(coverage.rawDays, 1)
        XCTAssertEqual(coverage.rawDaysWithoutScores, 1)
        XCTAssertEqual(coverage.emptyDays, 1)
    }
}
