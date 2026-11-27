import BodySeekStore
import Foundation
import GRDB
import XCTest

final class MigrationV5Tests: XCTestCase {
    func testV4DatabaseWithLegacyAuditAndDeletionMigratesToV5() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bodyseek-v5-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let queue = try DatabaseQueue(path: url.path)
        try BodySeekDatabase.migrator.migrate(queue, upTo: "v4_healthkit_workout_deletions")

        try queue.write { db in
            try db.execute(
                sql: """
                INSERT INTO workout (hk_uuid, day_key, type, start, end, energy, review_state)
                VALUES ('W-V4', '2026-11-19', '传统力量训练', 100, 200, 300, 'unreviewed')
                """
            )
            try db.execute(
                sql: """
                INSERT INTO deleted_healthkit_workout (uuid, day_key)
                VALUES ('W-DELETED', '2026-11-18')
                """
            )
            try db.execute(
                sql: """
                INSERT INTO action_audit (id, proposal_json, origin, decision, decided_at, affected_ids_json)
                VALUES ('00000000-0000-4000-8000-000000000888', '{}', 'agent', 'applied', 123.0, '[]')
                """
            )
        }

        try BodySeekDatabase.migrator.migrate(queue)

        try queue.read { db in
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT snapshot_version FROM action_audit"),
                1
            )
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT snapshot_json FROM action_audit"))
            XCTAssertEqual(
                try Double.fetchOne(db, sql: "SELECT decided_at FROM action_audit"),
                123.0
            )
            XCTAssertEqual(
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM deleted_healthkit_workout"),
                1
            )
            let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(action_audit)")
            let names = Set(columns.map { $0["name"] as String })
            XCTAssertTrue(names.isSuperset(of: ["snapshot_version", "snapshot_json", "undo_of", "undone_by"]))
        }
    }
}
