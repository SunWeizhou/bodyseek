import Foundation
import SwiftData

protocol DailyHealthSummaryRepository {
    func upsert(_ snapshot: DailyHealthSnapshot, calendar: Calendar) throws
    func fetch(in range: DateRangeQuery) throws -> [DailyHealthSummaryRecord]
}

final class SwiftDataDailyHealthSummaryRepository: DailyHealthSummaryRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func upsert(_ snapshot: DailyHealthSnapshot, calendar: Calendar = .current) throws {
        try upsert(snapshot, scoreEvidence: nil, calendar: calendar)
    }

    func upsert(
        _ snapshot: DailyHealthSnapshot,
        scoreEvidence: DailyScoreEvidenceEnvelope?,
        calendar: Calendar = .current
    ) throws {
        try PersistenceWriteGate.shared.withSerializedWrite(
            operation: "SwiftDataDailyHealthSummaryRepository.upsert"
        ) {
            let day = calendar.startOfDay(for: snapshot.date)
            let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: day, calendar: calendar)
            if let existing = try fetchRecord(dayIdentifier: dayIdentifier) {
                existing.apply(snapshot: snapshot, calendar: calendar)
                try existing.apply(scoreEvidence: scoreEvidence, observations: snapshot)
            } else {
                let record = DailyHealthSummaryRecord(snapshot: snapshot, calendar: calendar)
                try record.apply(scoreEvidence: scoreEvidence, observations: snapshot)
                modelContext.insert(record)
            }

            try modelContext.save()
        }
    }

    func fetch(in range: DateRangeQuery) throws -> [DailyHealthSummaryRecord] {
        let start = range.start
        let end = range.end
        let descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate { record in
                record.date >= start && record.date < end
            },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    /// Inclusive on both ends. Oldest date first unless `newestFirst` is set.
    func fetchRecords(
        from start: Date,
        through end: Date,
        newestFirst: Bool = false,
        limit: Int? = nil
    ) throws -> [DailyHealthSummaryRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        var descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate { $0.date >= start && $0.date <= end },
            sortBy: [SortDescriptor(\.date, order: order)]
        )
        if let limit {
            descriptor.fetchLimit = limit
        }
        return try modelContext.fetch(descriptor)
    }

    /// Days on or after `start`, with no upper bound. Newest date first by default.
    func fetchRecords(onOrAfter start: Date, newestFirst: Bool = true) throws -> [DailyHealthSummaryRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate { $0.date >= start },
            sortBy: [SortDescriptor(\.date, order: order)]
        ))
    }

    func fetchAll() throws -> [DailyHealthSummaryRecord] {
        try modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>())
    }

    /// Every persisted day, ordered by the stored calendar date.
    func fetchAllSortedByDate(newestFirst: Bool = false) throws -> [DailyHealthSummaryRecord] {
        let order: SortOrder = newestFirst ? .reverse : .forward
        return try modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>(
            sortBy: [SortDescriptor(\.date, order: order)]
        ))
    }

    func fetchRecord(dayIdentifier: String) throws -> DailyHealthSummaryRecord? {
        try modelContext.fetch(FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate { $0.dayIdentifier == dayIdentifier }
        )).first
    }
}
