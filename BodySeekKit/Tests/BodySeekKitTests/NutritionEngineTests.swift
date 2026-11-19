import BodySeekCore
import BodySeekStore
import Foundation
import XCTest

final class NutritionEngineTests: XCTestCase {
    func testTargetValidationRejectsDuplicatesMismatchedUnitsAndRestrictedSpecialFormUL() {
        let today = DayKey(year: 2026, month: 11, day: 19)

        let planWithIssues = NutritionTargetPlan(
            nutritionSchema: 1,
            targetStatus: .active,
            targetVersion: "v2026.11",
            effectiveFrom: DayKey(year: 2026, month: 11, day: 15),
            items: [
                // Valid protein target
                NutritionTargetItem(
                    id: "diet_protein_g",
                    unit: "g",
                    mode: .range,
                    lower: 60,
                    upper: 96,
                    source: "个人力量训练支持区间",
                    referenceType: "个人执行目标",
                    adopted: true
                ),
                // Duplicate sodium entries -> both suspended
                NutritionTargetItem(id: "diet_minerals::钠", unit: "mg", mode: .max, upper: 2000, source: "DRIs PI-NCD", adopted: true),
                NutritionTargetItem(id: "diet_minerals::钠", unit: "mg", mode: .max, upper: 2200, source: "DRIs", adopted: true),
                // Unit mismatch
                NutritionTargetItem(id: "diet_fiber_g", unit: "mg", mode: .range, lower: 25, upper: 30, source: "DRIs", adopted: true),
                // %E > 100
                NutritionTargetItem(id: "diet_carbs_g", unit: "%E", mode: .range, lower: 50, upper: 110, source: "DRIs", adopted: true),
                // Restricted special form UL (A（RAE）)
                NutritionTargetItem(
                    id: "diet_vitamins::A（RAE）",
                    unit: "μg",
                    mode: .min,
                    lower: 660,
                    source: "DRIs RNI",
                    adopted: true,
                    upperLimit: 3000,
                    upperLimitSource: "UL",
                    upperLimitScope: "total"
                ),
            ]
        )

        let validated = NutritionTargetEvaluator.validate(plan: planWithIssues, on: today)
        XCTAssertTrue(validated.isActive)
        XCTAssertEqual(validated.validAdoptedItems.keys.sorted(), ["diet_protein_g"])
        XCTAssertTrue(validated.errors.contains { $0.contains("重复") })
        XCTAssertTrue(validated.errors.contains { $0.contains("单位不匹配") })
        XCTAssertTrue(validated.errors.contains { $0.contains("供能比超出 100%") })
        XCTAssertTrue(validated.errors.contains { $0.contains("特殊形态") })
    }

    func testDailyEvaluationEnergyPercentageSurplusAndDayCompleteGate() throws {
        let dayKey = DayKey(year: 2026, month: 11, day: 18)
        let plan = NutritionTargetPlan(
            nutritionSchema: 1,
            targetStatus: .active,
            targetVersion: "2026-11-15",
            effectiveFrom: DayKey(year: 2026, month: 11, day: 15),
            items: [
                NutritionTargetItem(id: "diet_carbs_g", unit: "%E", mode: .range, lower: 50, upper: 65, source: "DRIs AMDR", adopted: true),
                NutritionTargetItem(id: "diet_protein_g", unit: "g", mode: .range, lower: 60, upper: 96, source: "个人目标", adopted: true),
                NutritionTargetItem(id: "diet_fiber_g", unit: "g", mode: .range, lower: 25, upper: 30, source: "DRIs AI", adopted: true),
                NutritionTargetItem(id: "diet_vitamins::C", unit: "mg", mode: .min, lower: 100, source: "DRIs RNI", adopted: true, upperLimit: 2000, upperLimitSource: "DRIs UL", upperLimitScope: "total"),
            ]
        )
        let validated = NutritionTargetEvaluator.validate(plan: plan, on: dayKey)

        // Build meals from starter foods: 150g cooked rice + 200g boiled chicken breast + 200g broccoli
        let rice = NutritionCatalog.starterFoodItems.first { $0.foodID == "rice_cooked" }!
        let chicken = NutritionCatalog.starterFoodItems.first { $0.foodID == "chicken_breast_boiled" }!
        let broccoli = NutritionCatalog.starterFoodItems.first { $0.foodID == "broccoli_boiled" }!

        var log = DailyNutritionLog(
            dayKey: dayKey,
            entries: [
                rice.makeMealEntry(dayKey: dayKey, mealType: .lunch, portionAmount: 150),
                chicken.makeMealEntry(dayKey: dayKey, mealType: .lunch, portionAmount: 200),
                broccoli.makeMealEntry(dayKey: dayKey, mealType: .dinner, portionAmount: 200),
            ],
            dietDayComplete: nil,
            sportHours: 0.52,
            sportKcal: 290,
            steps: 3536,
            bmrKcalUsed: 1100
        )
        log.recalculateTotals()

        // Before day is closed, status must be .unknown and calorieSurplusKcal must remain nil
        XCTAssertNil(log.calorieSurplusKcal)
        let openProteinEval = NutritionTargetEvaluator.evaluate(metricID: "diet_protein_g", log: log, validatedPlan: validated)
        XCTAssertEqual(openProteinEval.status, .unknown)
        XCTAssertEqual(openProteinEval.reason, "当天未收尾")

        // Close day -> totals and surplus compute deterministically
        log.dietDayComplete = true
        log.recalculateTotals()
        XCTAssertEqual(try XCTUnwrap(log.dietKcal), 526, accuracy: 2.0)
        XCTAssertEqual(log.calorieSurplusKcal, (log.dietKcal! - (1100 + 290)).rounded())

        let proteinEval = NutritionTargetEvaluator.evaluate(metricID: "diet_protein_g", log: log, validatedPlan: validated)
        XCTAssertEqual(proteinEval.status, .met) // ~60.4g in 60-96g

        let fiberEval = NutritionTargetEvaluator.evaluate(metricID: "diet_fiber_g", log: log, validatedPlan: validated)
        XCTAssertEqual(fiberEval.status, .low) // ~9.7g < 25g

        let vitCEval = NutritionTargetEvaluator.evaluate(metricID: "diet_vitamins::C", log: log, validatedPlan: validated)
        XCTAssertEqual(vitCEval.status, .met) // 110mg >= 100mg
    }

    func testPeriodAggregatorAndMarkdownExportAndGRDBV2ActionExecutor() async throws {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let executor = ActionExecutor(database: db)

        // Search food library via alias ("水煮蛋") & 3-char FTS5 trigram ("白米饭")
        let eggHits = try await repo.searchFoodLibrary(query: "水煮蛋")
        XCTAssertEqual(eggHits.first?.foodID, "egg_boiled")
        let riceHits = try await repo.searchFoodLibrary(query: "白米饭")
        XCTAssertEqual(riceHits.first?.foodID, "rice_cooked")

        let todayKey = DayKey(year: 2026, month: 11, day: 18)
        let profile = NutritionProfile(
            age: 31,
            referenceSex: "female",
            heightCm: 151,
            referenceWeightKg: 48,
            primaryGoal: "增肌减脂、提升力量与恢复",
            bmrKcalReference: 1100
        )
        _ = try await executor.execute(
            ActionProposal(kind: .upsertNutritionProfile, origin: .user, encodablePayload: UpsertNutritionProfilePayload(profile: profile))
        )
        let loadedProfile = try await repo.loadNutritionProfile()
        XCTAssertEqual(loadedProfile?.referenceWeightKg, 48)

        let plan = NutritionTargetPlan(
            nutritionSchema: 1,
            targetStatus: .active,
            targetVersion: "dris-2023-v1",
            effectiveFrom: DayKey(year: 2026, month: 11, day: 1),
            items: [
                NutritionTargetItem(id: "diet_protein_g", unit: "g", mode: .range, lower: 60, upper: 96, source: "力量训练目标", adopted: true),
            ]
        )
        _ = try await executor.execute(
            ActionProposal(kind: .commitNutritionTargets, origin: .agent, encodablePayload: CommitNutritionTargetsPayload(plan: plan))
        )

        // Log meals across 3 completed days for rolling deficit
        for offset in 0..<3 {
            let day = DayKey(year: 2026, month: 11, day: 16 + offset)
            let meal = riceHits[0].makeMealEntry(dayKey: day, mealType: .lunch, portionAmount: 200)
            _ = try await executor.execute(
                ActionProposal(
                    kind: .logNutritionMeal,
                    origin: .user,
                    encodablePayload: LogNutritionMealPayload(dayKey: day, entry: meal)
                )
            )
            _ = try await executor.execute(
                ActionProposal(
                    kind: .closeNutritionDay,
                    origin: .agent,
                    encodablePayload: CloseNutritionDayPayload(
                        dayKey: day,
                        markComplete: true,
                        sportHours: 0.5,
                        sportKcal: 250,
                        steps: 6000,
                        bmrKcalUsed: 1100,
                        reviewSummary: "碳水基础稳定，注意补足蛋白质"
                    )
                )
            )
        }

        let logs = try await repo.loadNutritionLogs(
            from: DayKey(year: 2026, month: 11, day: 16),
            to: todayKey
        )
        XCTAssertEqual(logs.count, 3)

        let summary = NutritionBoardAggregator.summarizePeriod(
            logs: logs,
            targetPlan: try await repo.loadNutritionTargetPlan(),
            startDayKey: DayKey(year: 2026, month: 11, day: 1),
            endDayKey: DayKey(year: 2026, month: 11, day: 30),
            todayKey: todayKey
        )
        XCTAssertEqual(summary.validSurplusDays, 3)
        XCTAssertNotNil(summary.rollingDeficit7dKcal)

        let md = NutritionMarkdownExporter.exportDailyMarkdown(log: logs[2])
        XCTAssertTrue(md.contains("diet_kcal: 312"))
        XCTAssertTrue(md.contains("diet_day_complete: true"))
        XCTAssertTrue(md.contains("## 饮食记录"))
    }
}
