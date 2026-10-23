import Foundation
import SwiftData

/// Full local training history. Windowed queries stay at their call sites;
/// the unfiltered table reads share this pair so they cannot drift apart.
final class WorkoutHistoryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchStrengthWorkouts() throws -> [StrengthWorkoutRecord] {
        try modelContext.fetch(FetchDescriptor<StrengthWorkoutRecord>())
    }

    /// Every strength workout, ordered by start time. `limit` keeps the newest or oldest rows.
    func fetchStrengthWorkoutsSortedByStart(newestFirst: Bool = false, limit: Int? = nil) throws -> [StrengthWorkoutRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        var descriptor = FetchDescriptor<StrengthWorkoutRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: order)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }

    func fetchWorkoutEvents() throws -> [WorkoutEventRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>())
    }

    func fetchWorkoutEventsSortedByStart(newestFirst: Bool = true) throws -> [WorkoutEventRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            sortBy: [SortDescriptor(\.startedAt, order: order)]
        ))
    }

    /// Inclusive on both ends, newest start first.
    func fetchStrengthWorkouts(from start: Date, through end: Date) throws -> [StrengthWorkoutRecord] {
        try modelContext.fetch(FetchDescriptor<StrengthWorkoutRecord>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt <= end },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
    }

    /// Inclusive on both ends, newest start first. `limit` keeps the recent-event cap.
    func fetchWorkoutEvents(from start: Date, through end: Date, limit: Int? = nil) throws -> [WorkoutEventRecord] {
        var descriptor = FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt <= end },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }

    /// Half-open `[start, end)`. Oldest start first unless `newestFirst` is set.
    func fetchWorkoutEvents(from start: Date, until end: Date, newestFirst: Bool = false) throws -> [WorkoutEventRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate { $0.startedAt >= start && $0.startedAt < end },
            sortBy: [SortDescriptor(\.startedAt, order: order)]
        ))
    }

    /// Events that started at or after `start`, newest first. There is no end bound.
    func fetchWorkoutEvents(onOrAfter start: Date) throws -> [WorkoutEventRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate { $0.startedAt >= start },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
    }

    func fetchEvents(id: UUID) throws -> [WorkoutEventRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate { $0.id == id }
        ))
    }

    func fetchEvents(linkedHealthKitWorkoutId: UUID) throws -> [WorkoutEventRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate { $0.linkedHealthKitWorkoutId == linkedHealthKitWorkoutId }
        ))
    }

    func fetchEvents(linkedStrengthWorkoutId: UUID) throws -> [WorkoutEventRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate { $0.linkedStrengthWorkoutId == linkedStrengthWorkoutId }
        ))
    }

    /// Half-open day window of events that are still free to merge with a strength log.
    func fetchEventsWithoutStrengthLink(from start: Date, until end: Date) throws -> [WorkoutEventRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate {
                $0.startedAt >= start && $0.startedAt < end && $0.linkedStrengthWorkoutId == nil
            }
        ))
    }

    /// Event row, HealthKit link, or strength link.
    func fetchEvents(relatedTo id: UUID) throws -> [WorkoutEventRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate {
                $0.id == id || $0.linkedHealthKitWorkoutId == id || $0.linkedStrengthWorkoutId == id
            }
        ))
    }

    /// Event row or HealthKit link. A strength-only link stays out.
    func fetchEvents(idOrHealthKitWorkoutId id: UUID) throws -> [WorkoutEventRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate { $0.id == id || $0.linkedHealthKitWorkoutId == id }
        ))
    }

    func fetchStrengthWorkouts(id: UUID) throws -> [StrengthWorkoutRecord] {
        try modelContext.fetch(FetchDescriptor<StrengthWorkoutRecord>(
            predicate: #Predicate { $0.id == id }
        ))
    }
}

/// Post-workout response rows. Windowed reads share one inclusive date query.
final class TrainingResponseRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [TrainingResponseRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingResponseRecord>())
    }

    func fetchAllSortedByDate(newestFirst: Bool = true) throws -> [TrainingResponseRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<TrainingResponseRecord>(
            sortBy: [SortDescriptor(\.date, order: order)]
        ))
    }

    /// Inclusive on both ends, newest response first.
    func fetchResponses(from start: Date, through end: Date) throws -> [TrainingResponseRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingResponseRecord>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
    }

    /// Responses on or after `start`, newest first.
    func fetchResponses(onOrAfter start: Date) throws -> [TrainingResponseRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingResponseRecord>(
            predicate: #Predicate { $0.date >= start },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))
    }

    func fetchResponses(workoutId: UUID) throws -> [TrainingResponseRecord] {
        try modelContext.fetch(FetchDescriptor<TrainingResponseRecord>(
            predicate: #Predicate { $0.workoutId == workoutId }
        ))
    }
}

/// Saved workout templates. Seeding only needs the titles; the training page
/// shows them in title order.
final class WorkoutTemplateRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [WorkoutTemplateRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutTemplateRecord>())
    }

    func fetchAllSortedByTitle() throws -> [WorkoutTemplateRecord] {
        try modelContext.fetch(FetchDescriptor<WorkoutTemplateRecord>(
            sortBy: [SortDescriptor(\.title, order: .forward)]
        ))
    }
}

/// Workouts the user removed. Every blacklist filter reads this full set;
/// a single-id lookup stays at the write that checks for duplicates.
final class DeletedWorkoutRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [DeletedWorkoutRecord] {
        try modelContext.fetch(FetchDescriptor<DeletedWorkoutRecord>())
    }
}

/// Exercise library rows. Seeding reads the whole table; the picker shows names
/// in ascending order. Key and name lookups stay unsorted.
final class ExerciseDefinitionRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [ExerciseDefinitionRecord] {
        try modelContext.fetch(FetchDescriptor<ExerciseDefinitionRecord>())
    }

    func fetchAllSortedByName() throws -> [ExerciseDefinitionRecord] {
        try modelContext.fetch(FetchDescriptor<ExerciseDefinitionRecord>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        ))
    }

    func fetch(canonicalKey: String) throws -> [ExerciseDefinitionRecord] {
        try modelContext.fetch(FetchDescriptor<ExerciseDefinitionRecord>(
            predicate: #Predicate { $0.canonicalKey == canonicalKey }
        ))
    }

    func fetch(name: String) throws -> [ExerciseDefinitionRecord] {
        try modelContext.fetch(FetchDescriptor<ExerciseDefinitionRecord>(
            predicate: #Predicate { $0.name == name }
        ))
    }
}

/// The in-progress strength log. Callers that resume a session still take the
/// first stored row; clearing a session deletes every row.
final class ActiveWorkoutDraftRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [ActiveWorkoutDraftRecord] {
        try modelContext.fetch(FetchDescriptor<ActiveWorkoutDraftRecord>())
    }
}

/// Imported Xunji workouts. A full read is for dedupe; deletion looks up the
/// mirror attached to one strength workout.
final class XunjiWorkoutMirrorRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [XunjiWorkoutMirrorRecord] {
        try modelContext.fetch(FetchDescriptor<XunjiWorkoutMirrorRecord>())
    }

    func fetch(linkedStrengthWorkoutId: UUID) throws -> [XunjiWorkoutMirrorRecord] {
        try modelContext.fetch(FetchDescriptor<XunjiWorkoutMirrorRecord>(
            predicate: #Predicate { $0.linkedStrengthWorkoutID == linkedStrengthWorkoutId }
        ))
    }
}
