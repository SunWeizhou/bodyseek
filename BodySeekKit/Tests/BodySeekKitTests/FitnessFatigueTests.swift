import BodySeekCore
import XCTest

final class FitnessFatigueTests: XCTestCase {
    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: Double(offset) * 86_400)
    }

    private func loads(_ values: [Double?]) -> [DatedLoad] {
        values.enumerated().map { DatedLoad(date: day($0.offset), load: $0.element) }
    }

    func testFirstLoadSeedsBothAndConstantLoadStaysConstant() {
        let series = FitnessFatigueModel.series(from: loads(Array(repeating: 50, count: 10)))
        XCTAssertEqual(series.count, 10)
        for point in series {
            XCTAssertEqual(point.fitness ?? -1, 50, accuracy: 1e-9)
            XCTAssertEqual(point.fatigue ?? -1, 50, accuracy: 1e-9)
            XCTAssertEqual(point.form ?? -1, 0, accuracy: 1e-9)
        }
    }

    func testExponentialWeightsMatchHandComputation() {
        let series = FitnessFatigueModel.series(from: loads([10, 0]))
        XCTAssertEqual(series[1].fitness ?? -1, 10 + (0 - 10) / 42.0, accuracy: 1e-9)
        XCTAssertEqual(series[1].fatigue ?? -1, 10 + (0 - 10) / 7.0, accuracy: 1e-9)
    }

    func testFatigueReactsFasterThanFitnessToAStepUp() {
        let values: [Double?] = Array(repeating: 20, count: 30) + Array(repeating: 80, count: 7)
        let last = FitnessFatigueModel.series(from: loads(values)).last
        XCTAssertNotNil(last)
        XCTAssertGreaterThan(last?.fatigue ?? 0, last?.fitness ?? 0)
        XCTAssertLessThan(last?.form ?? 0, 0)
        XCTAssertLessThan(last?.fatigue ?? 100, 80)
    }

    func testFitnessWindowIsLongerThanFatigueWindowAfterRest() {
        let values: [Double?] = Array(repeating: 60, count: 40) + Array(repeating: 0, count: 14)
        let last = FitnessFatigueModel.series(from: loads(values)).last
        XCTAssertGreaterThan(last?.form ?? -1, 0)
    }

    func testMissingDaysCarryForwardWithoutDecay() {
        let series = FitnessFatigueModel.series(from: loads([40, nil, nil, 40]))
        XCTAssertNil(series[1].load)
        XCTAssertEqual(series[1].fitness ?? -1, 40, accuracy: 1e-9)
        XCTAssertEqual(series[2].fatigue ?? -1, 40, accuracy: 1e-9)
    }

    func testLeadingMissingDaysHaveNoFitnessYet() {
        let series = FitnessFatigueModel.series(from: loads([nil, nil, 30]))
        XCTAssertNil(series[0].fitness)
        XCTAssertNil(series[1].form)
        XCTAssertEqual(series[2].fitness ?? -1, 30, accuracy: 1e-9)
    }

    func testInputIsSortedByDateAndEmptyInputIsEmpty() {
        let unsorted = [DatedLoad(date: day(2), load: 0), DatedLoad(date: day(1), load: 10)]
        let series = FitnessFatigueModel.series(from: unsorted)
        XCTAssertEqual(series.map(\.date), [day(1), day(2)])
        XCTAssertEqual(series[0].fitness ?? -1, 10, accuracy: 1e-9)
        XCTAssertTrue(FitnessFatigueModel.series(from: [DatedLoad]()).isEmpty)
    }
}
