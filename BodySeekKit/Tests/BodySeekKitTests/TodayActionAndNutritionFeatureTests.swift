import BodySeekCore
import BodySeekFeatures
import BodySeekHealth
import BodySeekStore
import ComposableArchitecture
import Foundation
import XCTest

@MainActor
final class TodayActionAndNutritionFeatureTests: XCTestCase {
    func testClosingHistoricalNutritionDoesNotBorrowTodayOrInventZero() async throws {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let date = now.physiologicalDayKey()
        let prior = date.addingDays(-10)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: [DailyRawMetrics(date: now, activeEnergyKcal: 425, steps: 6_000, dayKey: date)],
            sleepGoalMinutes: 450, referenceDate: now, sourceLabel: "测试", isAuthorized: true
        )
        let database = try BodySeekDatabase.inMemory()
        let executor = ActionExecutor(database: database)
        let repository = BodySeekRepository(database: database)
        var dependency = BodySeekStoreClient.previewValue
        dependency.executeProposal = { try await executor.execute($0) }
        dependency.loadNutritionLogs = { try await repository.loadNutritionLogs(from: $0, to: $1) }
        let client = dependency
        let store = TestStore(initialState: NutritionFeature.State(snapshot: snapshot, isPreviewMode: false)) {
            NutritionFeature()
        } withDependencies: {
            $0.bodySeekStoreClient = client
        }
        store.exhaustivity = .off
        await store.send(.daySelected(prior))
        await store.send(.closeSelectedDayTapped(reviewSummary: nil))
        await store.finish()
        let logs = try await client.loadNutritionLogs(prior, prior)
        XCTAssertEqual(logs.first?.dayKey, prior)
        XCTAssertNil(logs.first?.steps)
        XCTAssertNil(logs.first?.sportKcal)
    }

    func testTodayActionAdoptionPersistsAndWritesAuditTrail() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 20),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )
        let dayKey = snapshot.referenceDate.physiologicalDayKey()
        let defaults = TodayActionGenerator.generateDefaultPlanItems(for: snapshot, dayKey: dayKey)
        XCTAssertFalse(defaults.isEmpty)

        actor AuditCounter {
            var count = 0
            func record() { count += 1 }
        }
        let counter = AuditCounter()
        var customStoreClient = BodySeekStoreClient.testValue
        let innerExec = customStoreClient.executeProposal
        customStoreClient.executeProposal = { proposal in
            if proposal.kind == .adjustPlan {
                await counter.record()
            }
            return try await innerExec(proposal)
        }

        let store = TestStore(
            initialState: AppFeature.State(
                hasCompletedOnboarding: true,
                snapshot: snapshot,
                arguments: ["-velaPreviewDashboard"]
            )
        ) {
            AppFeature()
        } withDependencies: {
            $0.healthKitClient = .previewValue
            $0.preferencesClient = .previewValue
            $0.fitnessStoreClient = .previewValue
            $0.coachAIClient = .previewValue
            $0.bodySeekStoreClient = customStoreClient
            $0.continuousClock = ImmediateClock()
            $0.date.now = now
        }
        store.exhaustivity = .off

        let firstID = try XCTUnwrap(store.state.today.planItems.first?.id)
        await store.send(.today(.adoptPlanItem(firstID)))
        await store.receive(\.today.delegate.adoptPlanItem)
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.state.today.planItems.first?.state, .adopted)
        let auditCount = await counter.count
        XCTAssertEqual(auditCount, 1)

        if defaults.count > 1 {
            let secondID = defaults[1].id
            await store.send(.today(.dismissPlanItem(secondID)))
            await store.receive(\.today.delegate.dismissPlanItem)
            XCTAssertEqual(store.state.today.planItems[1].state, .dismissed)
        }
    }

    func testNutritionFeatureLifecycleLogMealCloseDayAndDRIsActivation() async throws {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 14),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )
        let todayKey = snapshot.referenceDate.physiologicalDayKey()
        let isolatedClient = BodySeekStoreClient.testValue

        let store = TestStore(
            initialState: NutritionFeature.State(
                snapshot: snapshot,
                todayKey: todayKey,
                isPreviewMode: false
            )
        ) {
            NutritionFeature()
        } withDependencies: {
            $0.bodySeekStoreClient = isolatedClient
            $0.date.now = now
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.loaded)

        // Initially honest unknown / unconfigured targets
        XCTAssertFalse(store.state.periodSummary.validatedPlan.isActive)
        XCTAssertNil(store.state.selectedDayLog)

        // 1. Save profile + activate validated DRIs 2023 targets
        let profile = NutritionPlanFactory.makePreviewProfile()
        await store.send(.saveProfileTapped(profile, generateAndActivateDRIs: true))
        await store.receive(\.mutationSucceeded)
        await store.receive(\.loaded)

        XCTAssertTrue(store.state.periodSummary.validatedPlan.isActive)
        XCTAssertTrue(store.state.periodSummary.validatedPlan.errors.isEmpty)
        XCTAssertGreaterThan(store.state.periodSummary.validatedPlan.validAdoptedItems.count, 10)

        // 2. Log meal -> day remains incomplete -> calorieSurplusKcal stays nil
        let chicken = try XCTUnwrap(NutritionCatalog.starterFoodItems.first(where: { $0.foodID == "chicken_breast_boiled" }))
        let scaled = chicken.makeMealEntry(dayKey: todayKey, mealType: .lunch, portionAmount: 200)
        await store.send(.logMealSubmitted(
            mealType: .lunch,
            foodName: chicken.name,
            foodID: chicken.foodID,
            portionAmount: 200,
            portionUnit: "g",
            kcal: scaled.kcal,
            carbsG: scaled.carbsG,
            proteinG: scaled.proteinG,
            fatG: scaled.fatG,
            fiberG: scaled.fiberG,
            waterMl: nil,
            vitamins: scaled.vitamins,
            minerals: scaled.minerals,
            isEstimated: false,
            isPartial: false,
            note: "午间训练加餐"
        ))
        await store.receive(\.mutationSucceeded)
        await store.receive(\.loaded)

        XCTAssertEqual(store.state.selectedDayLog?.entries.count, 1)
        XCTAssertNil(store.state.selectedDayLog?.calorieSurplusKcal)

        // 3. Close day -> calorieSurplusKcal computed cleanly
        await store.send(.closeSelectedDayTapped(reviewSummary: "收尾测试"))
        await store.receive(\.mutationSucceeded)
        await store.receive(\.loaded)

        XCTAssertEqual(store.state.selectedDayLog?.dietDayComplete, true)
        XCTAssertNotNil(store.state.selectedDayLog?.calorieSurplusKcal)

        // 4. Obsidian Markdown export contains YAML frontmatter
        await store.send(.exportDailyMarkdownTapped)
        let md = try XCTUnwrap(store.state.exportedMarkdown)
        XCTAssertTrue(md.contains("diet_day_complete: true"))
        XCTAssertTrue(md.contains(chicken.name))
    }

    func testStaleTrendAndNutritionAIInsightsAreDiscardedAfterScopeSwitch() async {
        let now = Date(timeIntervalSince1970: 1_760_000_000)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: PreviewSeedFactory.makeRawWindow(endingAt: now, days: 30),
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "Test",
            isAuthorized: true
        )

        let trendsState = TrendsFeature.State(snapshot: snapshot, isPreviewMode: false)
        let monthScope = trendsState.currentInsightScopeKey
        let trendsStore = TestStore(initialState: trendsState) {
            TrendsFeature()
        }
        trendsStore.exhaustivity = .off

        await trendsStore.send(.aiInsightLoaded(monthScope, .generated(text: "30天分析", engineName: "DeepSeek")))
        XCTAssertEqual(trendsStore.state.aiInsightStatus, .generated(text: "30天分析", engineName: "DeepSeek"))

        await trendsStore.send(.horizonChanged(.week))
        XCTAssertEqual(trendsStore.state.aiInsightStatus, .idle)

        // Late arrival for the old 30d scope must be ignored once switched to 7d
        await trendsStore.send(.aiInsightLoaded(monthScope, .generated(text: "迟到的30天", engineName: "DeepSeek")))
        XCTAssertEqual(trendsStore.state.aiInsightStatus, .idle)

        // Switching back to 30d restores the 30d insight cleanly
        await trendsStore.send(.horizonChanged(.month))
        XCTAssertEqual(trendsStore.state.aiInsightStatus, .generated(text: "30天分析", engineName: "DeepSeek"))

        // Same isolation & stale guard on NutritionFeature
        let nutState = NutritionFeature.State(snapshot: snapshot, todayKey: snapshot.referenceDate.physiologicalDayKey(), isPreviewMode: false)
        let weekScope = nutState.currentAdviceScopeKey
        let nutStore = TestStore(initialState: nutState) {
            NutritionFeature()
        }
        nutStore.exhaustivity = .off

        await nutStore.send(.nutritionAdviceLoaded(weekScope, .generated(text: "7天饮食建议", engineName: "DeepSeek")))
        XCTAssertEqual(nutStore.state.coachAdviceStatus, .generated(text: "7天饮食建议", engineName: "DeepSeek"))
        await nutStore.send(.periodModeChanged(.month))
        XCTAssertEqual(nutStore.state.coachAdviceStatus, .idle)
        await nutStore.send(.nutritionAdviceLoaded(weekScope, .generated(text: "迟到7天建议", engineName: "DeepSeek")))
        XCTAssertEqual(nutStore.state.coachAdviceStatus, .idle)
    }
}
