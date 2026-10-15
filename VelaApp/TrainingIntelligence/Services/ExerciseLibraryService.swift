import Foundation
import SwiftData

enum ExerciseLibraryService {

    // Shared tabular source of truth for the default exercise library. Both the
    // SwiftData backing `defaultDefinitions()` and the Sendable value-type
    // `defaultDefinitionsDTO()` (used off the main actor by the training kernels)
    // are derived from the same spec so the two can never drift apart.
    private static let exerciseSpecs: [(key: String, name: String, aliases: [String], primary: String, secondary: [String], equipment: String, pattern: String)] = [
        ("barbell_bench_press", "杠铃卧推", ["bench press", "卧推"], "chest", ["triceps", "shoulders"], "barbell", "push"),
        ("dumbbell_bench_press", "哑铃卧推", ["dumbbell bench press"], "chest", ["triceps"], "dumbbell", "push"),
        ("incline_bench_press", "上斜卧推", ["incline press"], "chest", ["shoulders", "triceps"], "barbell", "push"),
        ("dips", "双杠臂屈伸", ["dip"], "chest", ["triceps"], "bodyweight", "push"),
        ("cable_fly", "绳索夹胸", ["cable fly"], "chest", [], "cable", "isolation"),
        ("chest_press", "器械推胸", ["chest press"], "chest", ["triceps"], "machine", "push"),
        ("pull_ups", "引体向上", ["pull up", "pullup"], "back", ["biceps"], "bodyweight", "pull"),
        ("lat_pulldown", "高位下拉", ["lat pulldown"], "back", ["biceps"], "cable", "pull"),
        ("barbell_row", "杠铃划船", ["barbell row"], "back", ["biceps"], "barbell", "pull"),
        ("seated_row", "坐姿划船", ["seated row"], "back", ["biceps"], "cable", "pull"),
        ("one_arm_dumbbell_row", "单臂哑铃划船", ["one arm dumbbell row"], "back", ["biceps"], "dumbbell", "pull"),
        ("deadlift", "硬拉", ["deadlift"], "back", ["glutes", "hamstrings"], "barbell", "hinge"),
        ("squat", "深蹲", ["squat"], "quads", ["glutes", "hamstrings"], "barbell", "squat"),
        ("leg_press", "腿举", ["leg press"], "quads", ["glutes"], "machine", "squat"),
        ("romanian_deadlift", "罗马尼亚硬拉", ["romanian deadlift", "rdl"], "hamstrings", ["glutes"], "barbell", "hinge"),
        ("leg_extension", "腿屈伸", ["leg extension"], "quads", [], "machine", "isolation"),
        ("leg_curl", "腿弯举", ["leg curl"], "hamstrings", [], "machine", "isolation"),
        ("bulgarian_split_squat", "保加利亚分腿蹲", ["bulgarian split squat"], "quads", ["glutes"], "dumbbell", "lunge"),
        ("hip_thrust", "臀推", ["hip thrust", "臀桥"], "glutes", ["hamstrings"], "barbell", "hinge"),
        ("overhead_press", "推举", ["overhead press", "shoulder press"], "shoulders", ["triceps"], "barbell", "push"),
        ("lateral_raise", "哑铃侧平举", ["lateral raise"], "shoulders", [], "dumbbell", "isolation"),
        ("rear_delt_fly", "俯身飞鸟", ["rear delt fly"], "shoulders", [], "dumbbell", "isolation"),
        ("face_pull", "面拉", ["face pull"], "shoulders", ["back"], "cable", "pull"),
        ("arnold_press", "阿诺德推举", ["arnold press"], "shoulders", ["triceps"], "dumbbell", "push"),
        ("barbell_curl", "杠铃弯举", ["barbell curl"], "biceps", [], "barbell", "isolation"),
        ("dumbbell_curl", "哑铃弯举", ["dumbbell curl"], "biceps", [], "dumbbell", "isolation"),
        ("triceps_pushdown", "绳索下压", ["triceps pushdown"], "triceps", [], "cable", "isolation"),
        ("close_grip_bench_press", "窄距卧推", ["close grip bench press"], "triceps", ["chest"], "barbell", "push"),
        ("triceps_extension", "臂屈伸", ["triceps extension"], "triceps", [], "bodyweight", "isolation"),
        ("crunch", "卷腹", ["crunch"], "core", [], "bodyweight", "core"),
        ("hanging_leg_raise", "悬垂举腿", ["hanging leg raise"], "core", [], "bodyweight", "core"),
        ("plank", "平板支撑", ["plank"], "core", [], "bodyweight", "core"),
        ("pallof_press", "Pallof Press", ["pallof"], "core", [], "cable", "core")
    ]

    static func defaultDefinitions() -> [ExerciseDefinitionRecord] {
        exerciseSpecs.map(exercise)
    }

    private static let cachedDefaultDTOs: [ExerciseDefinition] = exerciseSpecs.map { spec in
        ExerciseDefinition(
            id: stableID(for: spec.key),
            canonicalKey: spec.key,
            name: spec.name,
            aliases: spec.aliases,
            primaryMuscleGroup: spec.primary,
            secondaryMuscleGroups: spec.secondary,
            equipment: spec.equipment,
            movementPattern: spec.pattern
        )
    }

    static func defaultDefinitionsDTO() -> [ExerciseDefinition] {
        cachedDefaultDTOs
    }

    // Stable deterministic UUID for a canonical key, so a given exercise always
    // maps to the same DTO identity across calls.
    private static func stableID(for canonicalKey: String) -> UUID {
        var bytes = Array(canonicalKey.utf8)
        while bytes.count < 16 { bytes.append(0) }
        bytes[6] = (bytes[6] & 0x0f) | 0x30  // version 3 (name-based)
        bytes[8] = (bytes[8] & 0x3f) | 0x80  // RFC 4122 variant
        let raw = (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                   bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15])
        return UUID(uuid: raw)
    }

    static func search(_ query: String, in library: [ExerciseDefinitionRecord]) -> [ExerciseDefinitionRecord] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return library }
        return library.filter { definition in
            definition.name.lowercased().contains(needle)
                || definition.aliases.contains { $0.lowercased().contains(needle) }
                || definition.primaryMuscleGroup.lowercased().contains(needle)
                || definition.canonicalKey.lowercased().contains(needle)
        }
    }

    static func defaultTemplates() -> [WorkoutTemplateRecord] {
        [
            template("推力训练", [
                ("barbell_bench_press", "杠铃卧推"),
                ("overhead_press", "推举"),
                ("triceps_pushdown", "绳索下压")
            ]),
            template("拉力训练", [
                ("lat_pulldown", "高位下拉"),
                ("barbell_row", "杠铃划船"),
                ("barbell_curl", "杠铃弯举")
            ]),
            template("腿部训练", [
                ("squat", "深蹲"),
                ("romanian_deadlift", "罗马尼亚硬拉"),
                ("leg_curl", "腿弯举")
            ]),
            template("上肢训练", [
                ("barbell_bench_press", "杠铃卧推"),
                ("lat_pulldown", "高位下拉"),
                ("overhead_press", "推举"),
                ("seated_row", "坐姿划船")
            ]),
            template("下肢训练", [
                ("squat", "深蹲"),
                ("romanian_deadlift", "罗马尼亚硬拉"),
                ("leg_curl", "腿弯举")
            ]),
            template("全身训练", [
                ("squat", "深蹲"),
                ("barbell_bench_press", "杠铃卧推"),
                ("barbell_row", "杠铃划船")
            ])
        ]
    }

    @MainActor
    static func seedDefaultsIfNeeded(modelContext: ModelContext) throws {
        let existingDefinitions = try ExerciseDefinitionRepository(modelContext: modelContext).fetchAll()
        let existingKeys = Set(existingDefinitions.map(\.canonicalKey))
        let existingNames = Set(existingDefinitions.map(\.name))
        
        for definition in defaultDefinitions() {
            if !existingKeys.contains(definition.canonicalKey) && !existingNames.contains(definition.name) {
                modelContext.insert(definition)
            }
        }

        let deletedRecords = try? DeletedWorkoutRepository(modelContext: modelContext).fetchAll()
        let deletedTemplateTitles = Set(deletedRecords?.compactMap { rec -> String? in
            if rec.id.hasPrefix("template:") {
                return String(rec.id.dropFirst("template:".count))
            }
            return nil
        } ?? [])

        let existingTemplates = try WorkoutTemplateRepository(modelContext: modelContext).fetchAll()
        let existingTitles = Set(existingTemplates.map(\.title))
        for template in defaultTemplates() where !existingTitles.contains(template.title) && !deletedTemplateTitles.contains(template.title) {
            modelContext.insert(template)
        }
        try modelContext.save()
    }

    private static func exercise(
        _ key: String,
        _ name: String,
        _ aliases: [String],
        _ primary: String,
        _ secondary: [String],
        _ equipment: String,
        _ pattern: String
    ) -> ExerciseDefinitionRecord {
        ExerciseDefinitionRecord(
            canonicalKey: key,
            name: name,
            aliases: aliases,
            primaryMuscleGroup: primary,
            secondaryMuscleGroups: secondary,
            equipment: equipment,
            movementPattern: pattern
        )
    }

    private static func template(_ title: String, _ exercises: [(String, String)]) -> WorkoutTemplateRecord {
        WorkoutTemplateRecord(
            title: title,
            goal: "hypertrophy",
            exercises: exercises.map { (key, name) in
                WorkoutTemplateExercise(
                    exerciseCanonicalKey: key,
                    name: name,
                    targetSets: 3,
                    targetReps: "8-12",
                    targetRPE: 8,
                    restSeconds: 90
                )
            }
        )
    }
}
