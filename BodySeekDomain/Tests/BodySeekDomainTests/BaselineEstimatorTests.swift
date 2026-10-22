import Foundation
import XCTest
@testable import BodySeekDomain

final class BaselineEstimatorTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private let asOf = Date(timeIntervalSince1970: 1_780_000_000)

    func testEstimateExcludesTodayAndKeepsOneSamplePerDay() {
        let today = asOf
        let duplicateMorning = calendar.date(byAdding: .day, value: -1, to: today)!
        let duplicateEvening = duplicateMorning.addingTimeInterval(2 * 3_600)
        let samples = [
            BaselineSample(date: today, value: 999),
            BaselineSample(date: calendar.date(byAdding: .day, value: 1, to: today)!, value: 999),
            BaselineSample(date: duplicateMorning, value: 10),
            BaselineSample(date: duplicateEvening, value: 20),
            BaselineSample(date: calendar.date(byAdding: .day, value: -2, to: today)!, value: 30),
            BaselineSample(date: calendar.date(byAdding: .day, value: -3, to: today)!, value: 40)
        ]

        let estimate = BaselineEstimator.estimate(
            samples: samples,
            asOf: today,
            windowDays: 7,
            minimumSamples: 3,
            calendar: calendar
        )

        XCTAssertEqual(estimate?.values, [40, 30, 20])
        XCTAssertEqual(estimate?.median, 30)
        XCTAssertEqual(estimate?.sampleCount, 3)
    }

    func testFlatHistoryMarksARealChangeAsNotable() {
        let samples = (1...6).map { offset in
            BaselineSample(
                date: calendar.date(byAdding: .day, value: -offset, to: asOf)!,
                value: 50
            )
        }
        let estimate = try! XCTUnwrap(BaselineEstimator.estimate(
            samples: samples,
            asOf: asOf,
            windowDays: 7,
            minimumSamples: 5,
            calendar: calendar
        ))
        XCTAssertNil(estimate.robustScale)
        XCTAssertEqual(
            BaselineEstimator.zScore(value: 50, median: estimate.median, robustScale: estimate.robustScale),
            0
        )
        XCTAssertGreaterThanOrEqual(
            abs(BaselineEstimator.zScore(value: 80, median: estimate.median, robustScale: estimate.robustScale)),
            BaselineEstimator.notableZ
        )
    }

    func testMissingLoadDaysDoNotLowerAcuteLoadButKnownZeroDoes() {
        let continuous = (1...7).map { offset in
            DailyLoadObservation(
                date: calendar.date(byAdding: .day, value: -offset, to: asOf)!,
                value: 80,
                availability: .observed
            )
        }
        let missing = continuous + [
            DailyLoadObservation(
                date: calendar.date(byAdding: .day, value: -8, to: asOf)!,
                value: nil,
                availability: .missing,
                reason: "未佩戴"
            )
        ]
        var knownZero = continuous
        knownZero[3] = DailyLoadObservation(
            date: knownZero[3].date,
            value: 0,
            availability: .knownZero
        )

        func atl(_ observations: [DailyLoadObservation]) -> Double {
            let result = EnergyBankEngine(calendar: calendar).calculate(from: EnergyBankInput(
                asOf: asOf,
                recoveryScore: 70,
                sleepScore: 70,
                strainScore: 40,
                stressIndex: 20,
                trainingLoadHistory: observations,
                todayLoadObservation: DailyLoadObservation(
                    date: asOf,
                    value: 80,
                    availability: .observed
                )
            ))
            return try! XCTUnwrap(result.components["atl"])
        }

        XCTAssertEqual(atl(missing), atl(continuous), accuracy: 0.0001)
        XCTAssertLessThan(atl(knownZero), atl(continuous))
        XCTAssertEqual(ScoringAlgorithmVersions.energy, "energy.v2.2.0")
        XCTAssertEqual(ScoringAlgorithmVersions.strain, "strain.v2.2.0")
    }
}
