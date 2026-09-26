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
            let descriptor = FetchDescriptor<DailyHealthSummaryRecord>(
                predicate: #Predicate { $0.dayIdentifier == dayIdentifier }
            )

            if let existing = try modelContext.fetch(descriptor).first {
                existing.apply(snapshot: snapshot, calendar: calendar)
                if scoreEvidence != nil {
                    try existing.apply(scoreEvidence: scoreEvidence)
                }
            } else {
                let record = DailyHealthSummaryRecord(snapshot: snapshot, calendar: calendar)
                try record.apply(scoreEvidence: scoreEvidence)
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
}
