@testable import BodySeekAgent
@testable import BodySeekCore
import Foundation
import XCTest

private struct GoldenFixtureFile: Decodable {
    struct GoldenVector: Decodable {
        let caseId: String
        let features: [Double]
        let expectedNumpy: [Double]
        let expectedCoreML: [Double]

        private enum CodingKeys: String, CodingKey {
            case caseId = "case_id"
            case features
            case expectedNumpy = "expected_numpy"
            case expectedCoreML = "expected_coreml"
        }
    }

    let modelVersion: String
    let featureColumns: [String]
    let targetNames: [String]
    let vectors: [GoldenVector]

    private enum CodingKeys: String, CodingKey {
        case modelVersion = "model_version"
        case featureColumns = "feature_columns"
        case targetNames = "target_names"
        case vectors
    }
}

final class PersonalForecasterParityTests: XCTestCase {
    func testCoreMLAndSwiftSpecMatchAll24GoldenVectorsWithinTolerance() throws {
        let spec = try PersonalForecasterEngine.loadBundledSpec()
        XCTAssertEqual(spec.featureColumns.count, 31)
        XCTAssertEqual(spec.targets.count, 3)

        let fixtureURL = Bundle.module.url(
            forResource: "personal_forecaster_v1_golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "personal_forecaster_v1_golden", withExtension: "json")
        let resolvedURL = try XCTUnwrap(fixtureURL, "personal_forecaster_v1_golden.json should be bundled in BodySeekKitTests")
        let fixtureData = try Data(contentsOf: resolvedURL)
        let fixture = try JSONDecoder().decode(GoldenFixtureFile.self, from: fixtureData)

        XCTAssertEqual(fixture.modelVersion, spec.modelVersion)
        XCTAssertEqual(fixture.vectors.count, 24)
        XCTAssertEqual(fixture.featureColumns, spec.featureColumns)

        var maxSwiftRelErr = 0.0
        var maxCoreMLRelErr = 0.0

        for vector in fixture.vectors {
            let swiftPred = try PersonalForecasterEngine.predictRawLinear(features: vector.features, spec: spec)
            XCTAssertEqual(swiftPred.count, 3, "Swift prediction count mismatch on \(vector.caseId)")

            #if canImport(CoreML)
            let coreMLRaw = try CoreMLPersonalForecaster.shared.predictRaw(features: vector.features)
            XCTAssertEqual(coreMLRaw.count, 3, "CoreML prediction count mismatch on \(vector.caseId)")
            #endif

            for i in 0..<3 {
                let refNumpy = vector.expectedNumpy[i]
                let refCoreML = vector.expectedCoreML[i]
                let swiftRel = abs(swiftPred[i] - refNumpy) / max(1e-6, abs(refNumpy))
                maxSwiftRelErr = max(maxSwiftRelErr, swiftRel)
                XCTAssertLessThanOrEqual(
                    swiftRel,
                    1e-3,
                    "Swift vs numpy parity exceeded on \(vector.caseId) target[\(i)]"
                )

                #if canImport(CoreML)
                let clippedCoreML = min(spec.targets[i].clipMax, max(spec.targets[i].clipMin, coreMLRaw[i]))
                let coreMLRel = abs(clippedCoreML - refCoreML) / max(1e-6, abs(refCoreML))
                maxCoreMLRelErr = max(maxCoreMLRelErr, coreMLRel)
                XCTAssertLessThanOrEqual(
                    coreMLRel,
                    1e-3,
                    "CoreML vs python CoreML parity exceeded on \(vector.caseId) target[\(i)]"
                )
                #endif
            }
        }

        print(String(
            format: "COREML_PARITY_M4D: vectors=%d swift_max_rel_err=%.2e coreml_max_rel_err=%.2e",
            fixture.vectors.count,
            maxSwiftRelErr,
            maxCoreMLRelErr
        ))
    }

    func testCausalFeatureVectorHasZeroFutureLeakage() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 10)) ?? Date()
        let refDayKey = refDate.physiologicalDayKey(timeZone: calendar.timeZone)

        // Insufficient data path (< 7 observed days)
        let shortRaw = PreviewSeedFactory.makeRawWindow(endingAt: refDate, days: 4, calendar: calendar)
        let shortSnap = BevelScoringEngine.computeWindow(
            rawDays: shortRaw,
            sleepGoalMinutes: 450,
            referenceDate: refDate,
            sourceLabel: "Test",
            isAuthorized: true,
            calendar: calendar
        )
        let insufficient = PersonalForecasterEngine.forecast(
            historyDays: shortSnap.historyDays,
            referenceDate: refDate
        )
        if case let .insufficientData(observed, minReq, _) = insufficient {
            XCTAssertEqual(minReq, 7)
            XCTAssertLessThan(observed, 7)
        } else {
            XCTFail("Expected .insufficientData when < 7 days")
        }

        // Future leakage test: append mutated future days after refDate
        let futureRef = calendar.date(byAdding: .day, value: 3, to: refDate) ?? refDate
        let fullRaw = PreviewSeedFactory.makeRawWindow(endingAt: futureRef, days: 45, calendar: calendar)
        let fullSnap = BevelScoringEngine.computeWindow(
            rawDays: fullRaw,
            sleepGoalMinutes: 450,
            referenceDate: futureRef,
            sourceLabel: "Test",
            isAuthorized: true,
            calendar: calendar
        )
        let baselineDays = fullSnap.historyDays.filter { $0.dayKey <= refDayKey }
        let vecBefore = PersonalForecasterEngine.buildFeatureVector(
            from: baselineDays,
            referenceDayKey: refDayKey
        )

        var alteredFutureDays = fullSnap.historyDays
        for idx in alteredFutureDays.indices where alteredFutureDays[idx].dayKey > refDayKey {
            var mutRaw = alteredFutureDays[idx].raw
            mutRaw.hrvMs = 150.0
            mutRaw.restingHeartRateBpm = 35.0
            mutRaw.activeEnergyKcal = 2500.0
            alteredFutureDays[idx] = DailyComputedDay(
                date: alteredFutureDays[idx].date,
                dayKey: alteredFutureDays[idx].dayKey,
                raw: mutRaw,
                recovery: alteredFutureDays[idx].recovery,
                sleep: alteredFutureDays[idx].sleep,
                strain: alteredFutureDays[idx].strain,
                stress: alteredFutureDays[idx].stress,
                energy: alteredFutureDays[idx].energy,
                energyCurve: alteredFutureDays[idx].energyCurve,
                stressTimeline: alteredFutureDays[idx].stressTimeline,
                factualSummary: alteredFutureDays[idx].factualSummary,
                evidenceSummary: alteredFutureDays[idx].evidenceSummary
            )
        }
        let vecAfter = PersonalForecasterEngine.buildFeatureVector(
            from: alteredFutureDays,
            referenceDayKey: refDayKey
        )
        XCTAssertEqual(vecBefore, vecAfter, "Modifying future days (> referenceDayKey) must never alter causal features at t")
    }

    func testNOfOneExperimentEvaluatorExcludesMissingDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = DayKey(year: 2026, month: 11, day: 1)

        func makeDay(offset: Int, steps: Int?, hrv: Double?, authorized: Bool = true) -> DailyComputedDay {
            let dk = start.addingDays(offset)
            let d = dk.calendarDayStart(calendar: calendar)
            let raw = DailyRawMetrics(
                date: d,
                hrvMs: hrv,
                steps: steps,
                hasAuthorizedHealthData: authorized,
                dayKey: dk
            )
            let missingScore: (MetricKind) -> MetricScore = { kind in
                MetricScore(
                    kind: kind,
                    value: nil,
                    availability: .missing(reason: "无观测样本"),
                    badge: "缺失",
                    subtitle: ""
                )
            }
            return DailyComputedDay(
                date: d,
                dayKey: dk,
                raw: raw,
                recovery: missingScore(.recovery),
                sleep: missingScore(.sleep),
                strain: missingScore(.strain),
                stress: missingScore(.stress),
                energy: missingScore(.energy),
                energyCurve: [],
                stressTimeline: [],
                factualSummary: "",
                evidenceSummary: ""
            )
        }

        // Adherent days (>=10k steps): 0,1,2 -> next-day HRV 52,54,56 (mean = 54)
        // Non-adherent days (<10k steps): 3,4,5 -> next-day HRV 40,42 (day 6 HRV is nil -> excluded!)
        let history = [
            makeDay(offset: 0, steps: 12000, hrv: 45),
            makeDay(offset: 1, steps: 11000, hrv: 52),
            makeDay(offset: 2, steps: 10500, hrv: 54),
            makeDay(offset: 3, steps: 4000, hrv: 56),
            makeDay(offset: 4, steps: 4500, hrv: 40),
            makeDay(offset: 5, steps: 3000, hrv: 42),
            makeDay(offset: 6, steps: 5000, hrv: nil),
        ]
        let stepsTemplate = try XCTUnwrap(NOfOneExperimentTemplate.presets.first { $0.id == "daily_steps_10k" })
        let rec = NOfOneExperimentRecord(template: stepsTemplate, startDayKey: start)
        let eval = NOfOneExperimentEvaluator.evaluate(
            record: rec,
            historyDays: history,
            referenceDayKey: start.addingDays(6)
        )
        XCTAssertTrue(eval.isSufficientSample)
        XCTAssertEqual(eval.adherentDays, 3)
        XCTAssertEqual(eval.nonAdherentDays, 2)
        XCTAssertEqual(eval.excludedMissingDays, 2) // offset 5->nil & offset 6->no next day
        XCTAssertEqual(eval.adherentMean ?? -1, 54.0, accuracy: 0.01)
        XCTAssertEqual(eval.nonAdherentMean ?? -1, 41.0, accuracy: 0.01)
        XCTAssertEqual(eval.delta ?? -1, 13.0, accuracy: 0.01)
    }

    func testCoachToolGetPersonalForecastReturnsFourStateEnvelopeAndDisclaimer() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let refDate = calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 9)) ?? Date()
        let raw40 = PreviewSeedFactory.makeRawWindow(endingAt: refDate, days: 40, calendar: calendar)
        let snap40 = BevelScoringEngine.computeWindow(
            rawDays: raw40,
            sleepGoalMinutes: 450,
            referenceDate: refDate,
            sourceLabel: "Test",
            isAuthorized: true,
            calendar: calendar
        )
        let ctx = AgentExecutionContext(snapshot: snap40)
        let json = await CoachToolRegistry.execute(
            name: "get_personal_forecast",
            argumentsJSON: "{}",
            context: ctx
        )
        XCTAssertTrue(json.contains(#""state":"available""#))
        XCTAssertTrue(json.contains("个人统计预测，非医学诊断"))
        XCTAssertTrue(json.contains("hrv_sdnn_ms"))
        XCTAssertTrue(json.contains("resting_hr_bpm"))
        XCTAssertTrue(json.contains("sleep_efficiency"))

        // Missing path (< 7 days)
        let emptySnap = BevelScoringEngine.computeWindow(
            rawDays: [],
            sleepGoalMinutes: 450,
            referenceDate: refDate,
            sourceLabel: "Test",
            isAuthorized: false,
            calendar: calendar
        )
        let missingCtx = AgentExecutionContext(snapshot: emptySnap)
        let missingJSON = await CoachToolRegistry.execute(
            name: "get_personal_forecast",
            argumentsJSON: "{}",
            context: missingCtx
        )
        XCTAssertTrue(missingJSON.contains(#""state":"missing""#))
        XCTAssertTrue(missingJSON.contains("非医学诊断"))
    }

    func testFeatureDriversSumMatchesLinearDeltaFromBias() throws {
        let spec = try PersonalForecasterEngine.loadBundledSpec()
        let fixtureURL = Bundle.module.url(
            forResource: "personal_forecaster_v1_golden",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) ?? Bundle.module.url(forResource: "personal_forecaster_v1_golden", withExtension: "json")
        let resolvedURL = try XCTUnwrap(fixtureURL)
        let fixture = try JSONDecoder().decode(GoldenFixtureFile.self, from: try Data(contentsOf: resolvedURL))

        for vector in fixture.vectors {
            let swiftPred = try PersonalForecasterEngine.predictRawLinear(features: vector.features, spec: spec)
            for (idx, target) in spec.targets.enumerated() {
                let drivers = try PersonalForecasterEngine.computeDrivers(
                    features: vector.features,
                    spec: spec,
                    target: target
                )
                XCTAssertEqual(drivers.count, 7)
                let rawTotal = target.bias + drivers.reduce(0.0) { $0 + $1.contribution }
                let clipped = min(target.clipMax, max(target.clipMin, rawTotal))
                XCTAssertEqual(clipped, swiftPred[idx], accuracy: 1e-9)
            }
        }

        let calendar = Calendar(identifier: .gregorian)
        let refDate = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let raw30 = PreviewSeedFactory.makeRawWindow(endingAt: refDate, days: 30, calendar: calendar)
        let snap30 = BevelScoringEngine.computeWindow(
            rawDays: raw30,
            sleepGoalMinutes: 450,
            referenceDate: refDate,
            sourceLabel: "Test",
            isAuthorized: true,
            calendar: calendar
        )
        let state = PersonalForecasterEngine.forecast(historyDays: snap30.historyDays, referenceDate: refDate)
        guard case let .available(summary) = state else {
            return XCTFail("Expected .available forecast summary for 30d window")
        }
        for target in summary.targets {
            XCTAssertFalse(target.drivers.isEmpty)
            XCTAssertLessThanOrEqual(target.drivers.count, 4)
        }
    }
}
