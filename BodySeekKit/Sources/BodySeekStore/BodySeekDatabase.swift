import BodySeekCore
import Foundation
import GRDB
import os

public enum BodySeekDatabaseError: Error, LocalizedError, Sendable {
    case invalidJSONEncoding(context: String)
    case foreignKeyTargetMissing(table: String, key: String)
    case invalidProposalPayload(kind: ActionProposal.Kind)

    public var errorDescription: String? {
        switch self {
        case let .invalidJSONEncoding(context):
            "无法序列化数据库字段：\(context)"
        case let .foreignKeyTargetMissing(table, key):
            "缺少关联记录（\(table): \(key)）"
        case let .invalidProposalPayload(kind):
            "无效的操作提案载荷（\(kind.rawValue)）"
        }
    }
}

/// Manages SQLite connections (WAL `DatabasePool` on disk, `DatabaseQueue` in memory)
/// and versioned `DatabaseMigrator` schema transitions for BodySeek.
public final class BodySeekDatabase: Sendable {
    public let writer: any DatabaseWriter
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "BodySeekDatabase")

    private init(writer: any DatabaseWriter) {
        self.writer = writer
    }

    public static func inMemory() throws -> BodySeekDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        try migrator.migrate(queue)
        return BodySeekDatabase(writer: queue)
    }

    public static func openOnDisk(url: URL? = nil) throws -> BodySeekDatabase {
        let targetURL: URL
        if let url {
            targetURL = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            targetURL = base
                .appendingPathComponent("BodySeek", isDirectory: true)
                .appendingPathComponent("bodyseek_v5.sqlite")
        }

        let directory = targetURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        var config = Configuration()
        config.foreignKeysEnabled = true

        do {
            // DatabasePool automatically enables SQLite WAL mode on disk.
            let pool = try DatabasePool(path: targetURL.path, configuration: config)
            try migrator.migrate(pool)
            return BodySeekDatabase(writer: pool)
        } catch {
            logger.error("Failed opening GRDB DatabasePool at \(targetURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            // 1. sync_anchor
            try db.create(table: "sync_anchor") { t in
                t.column("type", .text).primaryKey()
                t.column("anchor", .blob)
                t.column("backfill_cursor", .text)
                t.column("updated_at", .double).notNull()
            }

            // 2. day_metric
            try db.create(table: "day_metric") { t in
                t.column("day_key", .text).notNull()
                t.column("metric", .text).notNull()
                t.column("value", .double)
                t.column("state", .text).notNull()
                t.column("reason", .text)
                t.column("coverage", .double).notNull().defaults(to: 1.0)
                t.column("sources_json", .text).notNull().defaults(to: "[]")
                t.primaryKey(["day_key", "metric"])
            }
            try db.create(index: "idx_day_metric_day", on: "day_metric", columns: ["day_key"])

            // 3. hourly_metric
            try db.create(table: "hourly_metric") { t in
                t.column("hour_start", .double).notNull()
                t.column("metric", .text).notNull()
                t.column("value", .double)
                t.column("coverage", .double).notNull().defaults(to: 1.0)
                t.primaryKey(["hour_start", "metric"])
            }
            try db.create(index: "idx_hourly_metric_start", on: "hourly_metric", columns: ["hour_start"])

            // 4. sleep_episode
            try db.create(table: "sleep_episode") { t in
                t.column("id", .text).primaryKey()
                t.column("day_key", .text).notNull()
                t.column("start", .double).notNull()
                t.column("end", .double).notNull()
                t.column("is_primary", .boolean).notNull().defaults(to: true)
                t.column("source", .text).notNull()
                t.column("sources_json", .text).notNull().defaults(to: "[]")
                t.column("merge_policy_version", .text).notNull()
                t.column("stages_json", .text).notNull()
                t.column("asleep_minutes", .integer).notNull().defaults(to: 0)
                t.column("in_bed_minutes", .integer).notNull().defaults(to: 0)
                t.column("deep_minutes", .integer).notNull().defaults(to: 0)
                t.column("rem_minutes", .integer).notNull().defaults(to: 0)
                t.column("core_minutes", .integer).notNull().defaults(to: 0)
                t.column("awake_minutes", .integer).notNull().defaults(to: 0)
                t.column("efficiency", .double)
            }
            try db.create(index: "idx_sleep_episode_day", on: "sleep_episode", columns: ["day_key", "start"])

            // 5. workout
            try db.create(table: "workout") { t in
                t.column("hk_uuid", .text).primaryKey()
                t.column("day_key", .text).notNull()
                t.column("type", .text).notNull()
                t.column("symbol_name", .text).notNull().defaults(to: "figure.mixed.cardio")
                t.column("start", .double).notNull()
                t.column("end", .double).notNull()
                t.column("energy", .double).notNull()
                t.column("avg_hr", .double)
                t.column("zones_json", .text)
                t.column("effort_user", .double)
                t.column("effort_estimated", .double)
                t.column("review_state", .text).notNull().defaults(to: WorkoutReviewState.unreviewed.rawValue)
            }
            try db.create(index: "idx_workout_day_start", on: "workout", columns: ["day_key", "start"])

            // 6. workout_annotation
            try db.create(table: "workout_annotation") { t in
                t.column("id", .text).primaryKey()
                t.column("workout_uuid", .text)
                    .notNull()
                    .references("workout", column: "hk_uuid", onDelete: .cascade)
                t.column("raw_text", .text).notNull()
                t.column("parser_version", .text).notNull()
                t.column("confirmed_at", .double)
            }
            try db.create(index: "idx_workout_annotation_uuid", on: "workout_annotation", columns: ["workout_uuid"])

            // 7. workout_muscle_load
            try db.create(table: "workout_muscle_load") { t in
                t.column("workout_uuid", .text)
                    .notNull()
                    .references("workout", column: "hk_uuid", onDelete: .cascade)
                t.column("muscle_id", .text).notNull()
                t.column("role", .text).notNull()
                t.column("load", .double).notNull()
                t.column("algorithm_version", .text).notNull()
                t.primaryKey(["workout_uuid", "muscle_id"])
            }

            // 8. score_snapshot (+ day_computed_artifact companion for precomputed timelines)
            try db.create(table: "score_snapshot") { t in
                t.column("day_key", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("value", .integer)
                t.column("state", .text).notNull()
                t.column("reason", .text)
                t.column("baseline_delta", .integer)
                t.column("badge", .text).notNull().defaults(to: "")
                t.column("subtitle", .text).notNull().defaults(to: "")
                t.column("contributors_json", .text).notNull().defaults(to: "[]")
                t.column("algorithm_version", .text).notNull()
                t.column("computed_at", .double).notNull()
                t.primaryKey(["day_key", "kind", "algorithm_version"])
            }
            try db.create(index: "idx_score_snapshot_day", on: "score_snapshot", columns: ["day_key"])

            try db.create(table: "day_computed_artifact") { t in
                t.column("day_key", .text).primaryKey()
                t.column("date", .double).notNull()
                t.column("energy_curve_json", .text).notNull()
                t.column("stress_timeline_json", .text).notNull()
                t.column("factual_summary", .text).notNull()
                t.column("evidence_summary", .text).notNull()
                t.column("algorithm_version", .text).notNull()
                t.column("computed_at", .double).notNull()
            }

            // 9. muscle_recovery
            try db.create(table: "muscle_recovery") { t in
                t.column("as_of", .double).notNull()
                t.column("muscle_id", .text).notNull()
                t.column("recovery", .double).notNull()
                t.column("algorithm_version", .text).notNull()
                t.primaryKey(["as_of", "muscle_id", "algorithm_version"])
            }

            // 10. check_in
            try db.create(table: "check_in") { t in
                t.column("id", .text).primaryKey()
                t.column("day_key", .text).notNull().unique()
                t.column("at", .double).notNull()
                t.column("energy", .integer).notNull()
                t.column("mood", .integer).notNull()
                t.column("stress", .integer).notNull()
                t.column("soreness_json", .text).notNull()
                t.column("note", .text)
            }
            try db.create(index: "idx_check_in_day", on: "check_in", columns: ["day_key"])

            // 11. plan_item
            try db.create(table: "plan_item") { t in
                t.column("id", .text).primaryKey()
                t.column("day_key", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("payload_json", .text).notNull()
                t.column("state", .text).notNull()
                t.column("origin", .text).notNull()
            }
            try db.create(index: "idx_plan_item_day", on: "plan_item", columns: ["day_key"])

            // 12. memory
            try db.create(table: "memory") { t in
                t.column("id", .text).primaryKey()
                t.column("tier", .text).notNull()
                t.column("content", .text).notNull()
                t.column("scope_json", .text).notNull().defaults(to: "{}")
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("expires_at", .double)
                t.column("confirmed_at", .double)
                t.column("retired_at", .double)
            }
            try db.create(index: "idx_memory_tier", on: "memory", columns: ["tier", "retired_at"])

            // 13. action_audit
            try db.create(table: "action_audit") { t in
                t.column("id", .text).primaryKey()
                t.column("proposal_json", .text).notNull()
                t.column("origin", .text).notNull()
                t.column("decision", .text).notNull()
                t.column("decided_at", .double).notNull()
                t.column("affected_ids_json", .text).notNull()
            }
            try db.create(index: "idx_action_audit_at", on: "action_audit", columns: ["decided_at"])

            // 14. coach_message
            try db.create(table: "coach_message") { t in
                t.column("id", .text).primaryKey()
                t.column("thread_id", .text).notNull().defaults(to: "default")
                t.column("role", .text).notNull()
                t.column("content", .text).notNull()
                t.column("engine_label", .text)
                t.column("evidence_metric", .text)
                t.column("proposal_json", .text)
                t.column("memory_note", .text)
                t.column("tool_trace_json", .text)
                t.column("at", .double).notNull()
            }
            try db.create(index: "idx_coach_message_thread_at", on: "coach_message", columns: ["thread_id", "at"])

            // 15. pattern_finding
            try db.create(table: "pattern_finding") { t in
                t.column("id", .text).primaryKey()
                t.column("statement", .text).notNull()
                t.column("effect", .double).notNull()
                t.column("ci_low", .double).notNull()
                t.column("ci_high", .double).notNull()
                t.column("n", .integer).notNull()
                t.column("method", .text).notNull()
                t.column("model_version", .text).notNull()
                t.column("status", .text).notNull()
            }

            // Auxiliary workout template & strength session continuity tables
            try db.create(table: "workout_template") { t in
                t.column("id", .text).primaryKey()
                t.column("sort_order", .integer).notNull()
                t.column("updated_at", .double).notNull()
                t.column("payload", .blob).notNull()
            }

            try db.create(table: "logged_workout_session") { t in
                t.column("id", .text).primaryKey()
                t.column("completed_at", .double).notNull()
                t.column("payload", .blob).notNull()
            }

            // FTS5 search indexes with synchronized triggers
            try db.execute(sql: """
                CREATE VIRTUAL TABLE memory_fts USING fts5(
                    content,
                    content='memory',
                    content_rowid='rowid',
                    tokenize='trigram'
                );
                CREATE TRIGGER memory_fts_ai AFTER INSERT ON memory BEGIN
                    INSERT INTO memory_fts(rowid, content) VALUES (new.rowid, new.content);
                END;
                CREATE TRIGGER memory_fts_ad AFTER DELETE ON memory BEGIN
                    INSERT INTO memory_fts(memory_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
                END;
                CREATE TRIGGER memory_fts_au AFTER UPDATE ON memory BEGIN
                    INSERT INTO memory_fts(memory_fts, rowid, content) VALUES ('delete', old.rowid, old.content);
                    INSERT INTO memory_fts(rowid, content) VALUES (new.rowid, new.content);
                END;

                CREATE VIRTUAL TABLE workout_annotation_fts USING fts5(
                    raw_text,
                    content='workout_annotation',
                    content_rowid='rowid',
                    tokenize='trigram'
                );
                CREATE TRIGGER workout_annotation_fts_ai AFTER INSERT ON workout_annotation BEGIN
                    INSERT INTO workout_annotation_fts(rowid, raw_text) VALUES (new.rowid, new.raw_text);
                END;
                CREATE TRIGGER workout_annotation_fts_ad AFTER DELETE ON workout_annotation BEGIN
                    INSERT INTO workout_annotation_fts(workout_annotation_fts, rowid, raw_text) VALUES ('delete', old.rowid, old.raw_text);
                END;
                CREATE TRIGGER workout_annotation_fts_au AFTER UPDATE ON workout_annotation BEGIN
                    INSERT INTO workout_annotation_fts(workout_annotation_fts, rowid, raw_text) VALUES ('delete', old.rowid, old.raw_text);
                    INSERT INTO workout_annotation_fts(rowid, raw_text) VALUES (new.rowid, new.raw_text);
                END;
            """)
        }

        migrator.registerMigration("v2_nutrition_schema") { db in
            try db.create(table: "nutrition_profile") { t in
                t.column("id", .text).primaryKey()
                t.column("payload_json", .text).notNull()
                t.column("updated_at", .double).notNull()
            }

            try db.create(table: "nutrition_target_plan") { t in
                t.column("id", .text).primaryKey()
                t.column("version", .text).notNull()
                t.column("status", .text).notNull()
                t.column("effective_from", .text)
                t.column("payload_json", .text).notNull()
                t.column("updated_at", .double).notNull()
            }

            try db.create(table: "food_library_item") { t in
                t.column("food_id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("aliases_text", .text).notNull().defaults(to: "")
                t.column("category", .text).notNull()
                t.column("state", .text).notNull()
                t.column("usable", .boolean).notNull().defaults(to: true)
                t.column("payload_json", .text).notNull()
                t.column("updated_at", .double).notNull()
            }

            try db.create(table: "daily_nutrition_log") { t in
                t.column("day_key", .text).primaryKey()
                t.column("diet_kcal", .double)
                t.column("sport_kcal", .double)
                t.column("surplus_kcal", .double)
                t.column("day_complete", .boolean)
                t.column("payload_json", .text).notNull()
                t.column("updated_at", .double).notNull()
            }

            try db.create(table: "meal_entry") { t in
                t.column("id", .text).primaryKey()
                t.column("day_key", .text)
                    .notNull()
                    .references("daily_nutrition_log", column: "day_key", onDelete: .cascade)
                t.column("meal_type", .text).notNull()
                t.column("food_id", .text)
                t.column("food_name", .text).notNull()
                t.column("portion_amount", .double).notNull()
                t.column("portion_unit", .text).notNull()
                t.column("kcal", .double)
                t.column("payload_json", .text).notNull()
                t.column("recorded_at", .double).notNull()
            }
            try db.create(index: "idx_meal_entry_day", on: "meal_entry", columns: ["day_key", "recorded_at"])

            try db.execute(sql: """
                CREATE VIRTUAL TABLE food_library_fts USING fts5(
                    name,
                    aliases_text,
                    content='food_library_item',
                    content_rowid='rowid',
                    tokenize='trigram'
                );
                CREATE TRIGGER food_library_fts_ai AFTER INSERT ON food_library_item BEGIN
                    INSERT INTO food_library_fts(rowid, name, aliases_text) VALUES (new.rowid, new.name, new.aliases_text);
                END;
                CREATE TRIGGER food_library_fts_ad AFTER DELETE ON food_library_item BEGIN
                    INSERT INTO food_library_fts(food_library_fts, rowid, name, aliases_text) VALUES ('delete', old.rowid, old.name, old.aliases_text);
                END;
                CREATE TRIGGER food_library_fts_au AFTER UPDATE ON food_library_item BEGIN
                    INSERT INTO food_library_fts(food_library_fts, rowid, name, aliases_text) VALUES ('delete', old.rowid, old.name, old.aliases_text);
                    INSERT INTO food_library_fts(rowid, name, aliases_text) VALUES (new.rowid, new.name, new.aliases_text);
                END;
            """)
        }

        migrator.registerMigration("v3_allow_unknown_meal_portions") { db in
            try db.rename(table: "meal_entry", to: "meal_entry_required_portion")
            try db.execute(sql: """
                CREATE TABLE meal_entry (
                    id TEXT PRIMARY KEY,
                    day_key TEXT NOT NULL REFERENCES daily_nutrition_log(day_key) ON DELETE CASCADE,
                    meal_type TEXT NOT NULL,
                    food_id TEXT,
                    food_name TEXT NOT NULL,
                    portion_amount DOUBLE,
                    portion_unit TEXT NOT NULL,
                    kcal DOUBLE,
                    payload_json TEXT NOT NULL,
                    recorded_at DOUBLE NOT NULL
                )
                """)
            try db.execute(sql: """
                INSERT INTO meal_entry
                SELECT id, day_key, meal_type, food_id, food_name, portion_amount, portion_unit, kcal, payload_json, recorded_at
                FROM meal_entry_required_portion
                """)
            try db.drop(table: "meal_entry_required_portion")
            try db.create(index: "idx_meal_entry_day", on: "meal_entry", columns: ["day_key", "recorded_at"])
            let existingIDs = try Set(String.fetchAll(db, sql: "SELECT food_id FROM food_library_item"))
            if !existingIDs.isEmpty {
                for item in NutritionCatalog.commonMealFoodItems where !existingIDs.contains(item.foodID) {
                    try BodySeekRepository.saveFoodLibraryItemSync(db: db, item: item, updatedAt: Date().timeIntervalSince1970)
                }
            }
        }

        migrator.registerMigration("v4_healthkit_workout_deletions") { db in
            try db.create(table: "deleted_healthkit_workout") { table in
                table.column("uuid", .text).primaryKey()
                table.column("day_key", .text)
            }
        }

        return migrator
    }
}
