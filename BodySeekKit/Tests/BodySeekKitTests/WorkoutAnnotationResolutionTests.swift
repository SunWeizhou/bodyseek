import BodySeekAgent
import BodySeekCore
import XCTest

final class WorkoutAnnotationResolutionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar
    }

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func workout(_ uuid: String, start: Date, minutes: Int = 60, type: String = "传统力量训练", review: WorkoutReviewState = .unreviewed) -> StoredWorkoutRecord {
        StoredWorkoutRecord(
            hkUUID: uuid,
            type: type,
            start: start,
            end: start.addingTimeInterval(Double(minutes * 60)),
            energy: 200,
            reviewState: review
        )
    }

    private func resolve(
        _ text: String,
        asOf: Date,
        workouts: [StoredWorkoutRecord],
        deleted: Set<String> = [],
        uuid: String? = nil
    ) -> WorkoutAnnotationResolution {
        WorkoutAnnotationResolver.resolve(
            rawText: text,
            workoutUUID: uuid,
            asOf: asOf,
            workouts: workouts,
            deletedWorkoutUUIDs: deleted,
            annotationsByWorkoutUUID: [:],
            calendar: calendar
        )
    }

    func testLastNightIncludesAfterMidnightWorkoutAtTwoAM() {
        let asOf = at(2026, 11, 20, 2)
        let afterMidnight = workout("W-0100", start: at(2026, 11, 20, 1))
        let result = resolve("昨晚那次练腿，补上腿训", asOf: asOf, workouts: [afterMidnight])
        guard case let .unique(candidate) = result else {
            return XCTFail("expected unique, got \(result)")
        }
        XCTAssertEqual(candidate.proposal.workoutUUID, "W-0100")
        XCTAssertEqual(candidate.dayKey, "2026-11-19")
        XCTAssertTrue(candidate.proposal.proposal.primaryMuscles.contains(.quadriceps))
    }

    func testYesterdayUsesPhysiologicalDay() {
        let asOf = at(2026, 11, 20, 10)
        let yesterday = workout("W-0900", start: at(2026, 11, 19, 9))
        let today = workout("W-TODAY", start: at(2026, 11, 20, 9))
        let result = resolve("昨天那次力量训练是腿", asOf: asOf, workouts: [yesterday, today])
        guard case let .unique(candidate) = result else {
            return XCTFail("expected unique, got \(result)")
        }
        XCTAssertEqual(candidate.proposal.workoutUUID, "W-0900")
    }

    func testNoDateUsesRecentUnreviewedStrengthCandidates() {
        let asOf = at(2026, 11, 20, 20)
        let recent = workout("W-RECENT", start: asOf.addingTimeInterval(-3600))
        let reviewed = workout("W-REVIEWED", start: asOf.addingTimeInterval(-7200), review: .annotated)
        let result = resolve("补一下训练标注", asOf: asOf, workouts: [recent, reviewed])
        guard case let .unique(candidate) = result else {
            return XCTFail("expected unique, got \(result)")
        }
        XCTAssertEqual(candidate.proposal.workoutUUID, "W-RECENT")
    }

    func testMultipleCandidatesNeedSelection() {
        let asOf = at(2026, 11, 20, 22)
        let first = workout("W-0900", start: at(2026, 11, 20, 9))
        let second = workout("W-2000", start: at(2026, 11, 20, 20), type: "羽毛球")
        let result = resolve("今天练得不错", asOf: asOf, workouts: [first, second])
        guard case let .multiple(candidates, _) = result else {
            return XCTFail("expected multiple, got \(result)")
        }
        XCTAssertEqual(candidates.map(\.proposal.workoutUUID), ["W-0900", "W-2000"])
    }

    func testDeletedAndMissingCandidatesAreReported() {
        let asOf = at(2026, 11, 20, 22)
        let deleted = workout("W-DELETED", start: at(2026, 11, 19, 9))
        let result = resolve("昨天练腿", asOf: asOf, workouts: [deleted], deleted: ["w-deleted"])
        guard case let .none(reason) = result else {
            return XCTFail("expected none, got \(result)")
        }
        XCTAssertTrue(reason.contains("没有"))
    }

    func testUUIDAndDateConflictRequestsClarification() {
        let asOf = at(2026, 11, 20, 22)
        let old = workout("W-OLD", start: at(2026, 11, 17, 9))
        let result = resolve("昨天那次", asOf: asOf, workouts: [old], uuid: "W-OLD")
        guard case let .conflict(reason) = result else {
            return XCTFail("expected conflict, got \(result)")
        }
        XCTAssertTrue(reason.contains("不一致"))
    }

    func testDatePhraseConflictRequestsClarification() {
        let asOf = at(2026, 11, 20, 22)
        let result = resolve("昨天和前天都练了", asOf: asOf, workouts: [])
        guard case .conflict = result else {
            return XCTFail("expected conflict, got \(result)")
        }
    }
}
