import Foundation
import SwiftData

protocol JournalRepository {
    func add(tags: [String], note: String, createdAt: Date) throws
    func recent(limit: Int) throws -> [JournalEntryRecord]
}

final class SwiftDataJournalRepository: JournalRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func add(tags: [String], note: String, createdAt: Date = Date()) throws {
        try PersistenceWriteGate.shared.assertWritable(operation: "JournalRepository: add", modelContext: modelContext)
        modelContext.insert(JournalEntryRecord(createdAt: createdAt, tags: tags, note: note))
        try modelContext.save()
    }

    func recent(limit: Int = 20) throws -> [JournalEntryRecord] {
        var descriptor = FetchDescriptor<JournalEntryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor)
    }

    func fetchAll() throws -> [JournalEntryRecord] {
        try modelContext.fetch(FetchDescriptor<JournalEntryRecord>())
    }

    /// Every journal row, ordered by when it was written.
    func fetchAllSortedByCreatedAt(newestFirst: Bool = false) throws -> [JournalEntryRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<JournalEntryRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }

    /// Inclusive on both ends, newest entry first.
    func fetchEntries(from start: Date, through end: Date) throws -> [JournalEntryRecord] {
        try modelContext.fetch(FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate { $0.createdAt >= start && $0.createdAt <= end },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    /// Entries written in `[start, end)`, newest first.
    func fetchEntries(from start: Date, until end: Date) throws -> [JournalEntryRecord] {
        try modelContext.fetch(FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate { $0.createdAt >= start && $0.createdAt < end },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    /// Entries written at or before `end`, newest first.
    func fetchEntries(through end: Date, limit: Int? = nil) throws -> [JournalEntryRecord] {
        var descriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate { $0.createdAt <= end },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }

    /// Entries written at or after `start`. Newest first unless requested otherwise.
    func fetchEntries(onOrAfter start: Date, newestFirst: Bool = true) throws -> [JournalEntryRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate { $0.createdAt >= start },
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }
}

final class FoodLogRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [FoodLogRecord] {
        try modelContext.fetch(FetchDescriptor<FoodLogRecord>())
    }

    /// Inclusive on both ends, newest log first.
    func fetchLogs(from start: Date, through end: Date) throws -> [FoodLogRecord] {
        try modelContext.fetch(FetchDescriptor<FoodLogRecord>(
            predicate: #Predicate { $0.createdAt >= start && $0.createdAt <= end },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    /// Logs written in `[start, end)`, newest first. A log exactly at `end` stays out.
    func fetchLogs(from start: Date, until end: Date) throws -> [FoodLogRecord] {
        try modelContext.fetch(FetchDescriptor<FoodLogRecord>(
            predicate: #Predicate { $0.createdAt >= start && $0.createdAt < end },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))
    }

    func fetchAllSortedByCreatedAt(newestFirst: Bool = true) throws -> [FoodLogRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<FoodLogRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }
}

/// Personal experiments, newest creation first. Starting a new experiment
/// cancels every row that is still active.
final class PersonalExperimentRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAllSortedByCreatedAt(newestFirst: Bool = true) throws -> [PersonalExperimentRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<PersonalExperimentRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: order)]
        ))
    }

    func fetchActive() throws -> [PersonalExperimentRecord] {
        try modelContext.fetch(FetchDescriptor<PersonalExperimentRecord>(
            predicate: #Predicate { $0.status == "active" }
        ))
    }
}

/// Daily experiment check-ins. The journal shows them newest first. A day's
/// check-in is addressed by its stable id.
final class ExperimentCheckInRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAllSortedByDate(newestFirst: Bool = true) throws -> [ExperimentCheckInRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<ExperimentCheckInRecord>(
            sortBy: [SortDescriptor(\.date, order: order)]
        ))
    }

    func fetch(id: String) throws -> [ExperimentCheckInRecord] {
        try modelContext.fetch(FetchDescriptor<ExperimentCheckInRecord>(
            predicate: #Predicate { $0.id == id }
        ))
    }
}

/// The daily Lived State seam. The underlying V3 store remains
/// `JournalEntryRecord`, while callers work with the two distinct domain facts:
/// score alignment and a structured subjective check-in. Each fact is upserted
/// once per calendar day so repeated edits do not inflate journal correlations.
struct LivedStateDailySnapshot: Hashable, Sendable {
    var alignment: LivedStateAlignment? = nil
    var checkIn: LivedStateCheckIn? = nil
    var alignmentRecordedAt: Date? = nil
    var checkInRecordedAt: Date? = nil

    static let empty = LivedStateDailySnapshot()
}

@MainActor
final class LivedStateJournalAdapter {
    private let modelContext: ModelContext
    private let calendar: Calendar

    init(modelContext: ModelContext, calendar: Calendar = .current) {
        self.modelContext = modelContext
        self.calendar = calendar
    }

    func snapshot(for day: Date) throws -> LivedStateDailySnapshot {
        let entries = try entries(on: day)
        let alignmentEntry = entries
            .filter { LivedStateAlignment(tags: $0.tags) != nil }
            .max(by: { $0.createdAt < $1.createdAt })
        let checkInEntry = entries
            .filter { LivedStateCheckIn(tags: $0.tags, note: $0.note) != nil }
            .max(by: { $0.createdAt < $1.createdAt })

        return LivedStateDailySnapshot(
            alignment: alignmentEntry.flatMap { LivedStateAlignment(tags: $0.tags) },
            checkIn: checkInEntry.flatMap { LivedStateCheckIn(tags: $0.tags, note: $0.note) },
            alignmentRecordedAt: alignmentEntry?.createdAt,
            checkInRecordedAt: checkInEntry?.createdAt
        )
    }

    func saveAlignment(
        _ alignment: LivedStateAlignment,
        for day: Date,
        recordedAt: Date = Date()
    ) throws {
        let timestamp = timestamp(on: day, recordedAt: recordedAt)
        try upsert(
            operation: "LivedStateJournalAdapter: save alignment",
            on: day,
            matching: { LivedStateAlignment(tags: $0.tags) != nil },
            createdAt: timestamp,
            tags: alignment.journalTags,
            note: alignment.journalNote,
            value: 1 - alignment.conservativeSeverity,
            unit: "lived_state_alignment_0_1"
        )
    }

    func saveCheckIn(
        _ checkIn: LivedStateCheckIn,
        for day: Date,
        recordedAt: Date = Date()
    ) throws {
        let timestamp = timestamp(on: day, recordedAt: recordedAt)
        try upsert(
            operation: "LivedStateJournalAdapter: save check-in",
            on: day,
            matching: { LivedStateCheckIn(tags: $0.tags, note: $0.note) != nil },
            createdAt: timestamp,
            tags: checkIn.journalTags,
            note: checkIn.journalNote,
            value: 1 - checkIn.conservativeSeverity,
            unit: "lived_state_0_1"
        )
    }

    private func upsert(
        operation: String,
        on day: Date,
        matching predicate: (JournalEntryRecord) -> Bool,
        createdAt: Date,
        tags: [String],
        note: String,
        value: Double,
        unit: String
    ) throws {
        try PersistenceWriteGate.shared.withSerializedWrite(
            operation: operation,
            modelContext: modelContext
        ) {
            let matches = try entries(on: day)
                .filter(predicate)
                .sorted(by: { $0.createdAt > $1.createdAt })

            let record: JournalEntryRecord
            if let existing = matches.first {
                record = existing
                record.createdAt = createdAt
                record.tags = tags
                record.note = note
                record.value = value
                record.unit = unit
                for duplicate in matches.dropFirst() {
                    modelContext.delete(duplicate)
                }
            } else {
                record = JournalEntryRecord(
                    createdAt: createdAt,
                    tags: tags,
                    note: note,
                    value: value,
                    unit: unit
                )
                modelContext.insert(record)
            }
            try modelContext.save()
        }
    }

    private func entries(on day: Date) throws -> [JournalEntryRecord] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return []
        }
        return try SwiftDataJournalRepository(modelContext: modelContext).fetchEntries(from: start, until: end)
    }

    /// Historical check-ins belong to the selected day, not the wall-clock day
    /// on which they were edited. Preserve the current time of day when possible.
    private func timestamp(on day: Date, recordedAt: Date) -> Date {
        if calendar.isDate(day, inSameDayAs: recordedAt) {
            return recordedAt
        }
        let time = calendar.dateComponents([.hour, .minute, .second], from: recordedAt)
        return calendar.date(
            bySettingHour: time.hour ?? 12,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? calendar.startOfDay(for: day)
    }
}
