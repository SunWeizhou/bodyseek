import BodySeekCore
import Foundation
import XCTest

final class ContractsTests: XCTestCase {
    func testDayKeyCutoverAtFourAMAndMonthRollover() throws {
        let tz = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        let beforeCutover = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 3, minute: 59, second: 59))
        )
        let atCutover = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 4, minute: 0, second: 0))
        )
        let leapBeforeCutover = try XCTUnwrap(
            cal.date(from: DateComponents(year: 2024, month: 3, day: 1, hour: 2, minute: 30, second: 0))
        )

        let beforeKey = beforeCutover.physiologicalDayKey(cutoverHour: 4, timeZone: tz)
        let atKey = atCutover.physiologicalDayKey(cutoverHour: 4, timeZone: tz)
        let leapKey = leapBeforeCutover.physiologicalDayKey(cutoverHour: 4, timeZone: tz)

        XCTAssertEqual(beforeKey, DayKey(year: 2026, month: 2, day: 28))
        XCTAssertEqual(beforeKey.isoString, "2026-02-28")
        XCTAssertEqual(atKey, DayKey(year: 2026, month: 3, day: 1))
        XCTAssertEqual(leapKey, DayKey(year: 2024, month: 2, day: 29))
        XCTAssertLessThan(beforeKey, atKey)
        XCTAssertEqual(DayKey(isoString: "2026-02-28"), beforeKey)
        XCTAssertNil(DayKey(isoString: "2026-02-30"))
        XCTAssertEqual(atKey.startDate(cutoverHour: 4, timeZone: tz), atCutover)
    }

    func testHealthObservationFourStatesCodableRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_763_500_000)
        let prov = Provenance(
            sources: [SourceRef(bundleIdentifier: "com.apple.health", name: "Apple Watch", priority: 100)],
            window: DateInterval(start: start, duration: 3600),
            coverage: 0.92,
            ingestedAt: start.addingTimeInterval(60),
            timeZoneIdentifier: "Asia/Shanghai"
        )

        let cases: [HealthObservation<Int>] = [
            .available(84, prov),
            .knownZero(reason: "今日无运动训练", prov),
            .missing(reason: .insufficientBaseline),
            .excluded(reason: .postWorkoutWindow, prov),
        ]

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for original in cases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(HealthObservation<Int>.self, from: data)
            XCTAssertEqual(decoded, original)
        }

        XCTAssertEqual(cases[0].value, 84)
        XCTAssertTrue(cases[0].isAvailable)
        XCTAssertNil(cases[1].value)
        XCTAssertFalse(cases[1].isAvailable)
        XCTAssertNil(cases[2].provenance)
        XCTAssertEqual(cases[3].provenance, prov)
    }

    func testMetricAvailabilityExcludedState() {
        let excluded = MetricAvailability.excluded(reason: "运动后 90 分钟恢复期已排除")
        XCTAssertFalse(excluded.isAvailable)
        XCTAssertEqual(excluded.reasonText, "运动后 90 分钟恢复期已排除")
    }

    func testActionProposalPayloadRoundTrip() throws {
        struct NotePayload: Codable, Equatable {
            let workoutID: String
            let note: String
            let rpe: Int
        }

        let payload = NotePayload(workoutID: "W-123", note: "背+二头力量", rpe: 8)
        let proposal = try ActionProposal(
            kind: .annotateWorkout,
            origin: .agent,
            encodablePayload: payload,
            rationale: "用户语音复盘解析",
            evidenceRefs: [EvidenceRef(kind: "workout", identifier: "W-123", summary: "45m 力量训练")]
        )

        let wire = try JSONEncoder().encode(proposal)
        let decodedProposal = try JSONDecoder().decode(ActionProposal.self, from: wire)
        let decodedPayload = try decodedProposal.decodePayload(NotePayload.self)
        XCTAssertEqual(decodedProposal.kind, .annotateWorkout)
        XCTAssertEqual(decodedProposal.origin, .agent)
        XCTAssertEqual(decodedPayload, payload)
    }

    func testDailyCheckInAndLegacyPreferencesBackwardCompatibleDecode() throws {
        let dayKey = DayKey(year: 2026, month: 11, day: 19)
        let entry = DailyCheckIn(
            dayKey: dayKey,
            recordedAt: Date(timeIntervalSince1970: 1_763_540_000),
            energy: 4,
            mood: 5,
            stress: 2,
            soreness: [.deltoids: 2, .forearm: 1],
            note: "羽毛球后右肩轻微酸痛"
        )
        let encoded = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(DailyCheckIn.self, from: encoded)
        XCTAssertEqual(decoded, entry)

        // Ensure pre-M0 preferences JSON decodes without error and gets .right + empty checkInsByDay
        let legacyJSON = #"{"sleepGoalMinutes":465,"subjectiveFeelingsByDay":{"2026-11-16":4}}"#
        let legacyData = try XCTUnwrap(legacyJSON.data(using: .utf8))
        let legacyDecoded = try JSONDecoder().decode(AppPreferencesState.self, from: legacyData)
        XCTAssertEqual(legacyDecoded.sleepGoalMinutes, 465)
        XCTAssertEqual(legacyDecoded.subjectiveFeelingsByDay["2026-11-16"], 4)
        XCTAssertTrue(legacyDecoded.checkInsByDay.isEmpty)
        XCTAssertEqual(legacyDecoded.dominantHand, .right)
    }
}
