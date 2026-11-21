import BodySeekStore
import Foundation
import GRDB
import XCTest

final class MigrationV6Tests: XCTestCase {
    func testV5ArtifactsGetLegacySleepGoalSentinelAndKindIndex() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bodyseek-v6-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = try DatabaseQueue(path: url.path)
        try BodySeekDatabase.migrator.migrate(queue, upTo: "v5_action_audit_undo_snapshots")

        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO day_computed_artifact (
                    day_key, date, energy_curve_json, stress_timeline_json,
                    factual_summary, evidence_summary, algorithm_version, computed_at
                )
                VALUES ('2026-11-20', 100, '[]', '[]', '', '', 'score-v2@2.0.0', 100)
                """
            )
        }

        try BodySeekDatabase.migrator.migrate(queue)

        try queue.read { db in
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT sleep_goal_minutes FROM day_computed_artifact"),
                -1
            )
            let indexNames = try String.fetchAll(
                db,
                sql: "SELECT name FROM pragma_index_list('action_audit')"
            )
            XCTAssertTrue(indexNames.contains("idx_action_audit_kind"))
        }
    }
}
