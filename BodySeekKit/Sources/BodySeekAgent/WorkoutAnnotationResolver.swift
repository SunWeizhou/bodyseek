import BodySeekCore
import Foundation

public enum WorkoutAnnotationResolution: Hashable, Sendable {
    case unique(CoachWorkoutAnnotationCandidate)
    case multiple([CoachWorkoutAnnotationCandidate], windowDescription: String)
    case none(reason: String)
    case conflict(reason: String)
}

/// Deterministic date and candidate resolution shared by the cloud tool and the
/// Apple Foundation Models adapter. It never writes; it only produces candidates.
public enum WorkoutAnnotationResolver {
    private struct DateWindow {
        let start: Date
        let end: Date
        let description: String
    }

    public static func resolve(
        rawText: String,
        workoutUUID: String?,
        asOf: Date,
        workouts: [StoredWorkoutRecord],
        deletedWorkoutUUIDs: Set<String>,
        annotationsByWorkoutUUID: [String: WorkoutAnnotationRecord],
        calendar: Calendar = .current
    ) -> WorkoutAnnotationResolution {
        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return .none(reason: "复盘描述为空")
        }
        let timeZone = calendar.timeZone
        let today = asOf.physiologicalDayKey(cutoverHour: 4, timeZone: timeZone)
        let calendarToday = DayKey.fromCalendarDay(asOf, calendar: calendar)
        let completed = workouts
            .filter { $0.end <= asOf && !deletedWorkoutUUIDs.contains($0.hkUUID.lowercased()) }
            .sorted { $0.start < $1.start }

        let parsedWindow = parseDateWindow(
            text: cleaned,
            today: today,
            calendarToday: calendarToday,
            timeZone: timeZone
        )
        if case let .conflict(reason) = parsedWindow {
            return .conflict(reason: reason)
        }
        let window: DateWindow? = {
            if case let .window(value) = parsedWindow { return value }
            return nil
        }()

        if let rawUUID = workoutUUID?.trimmingCharacters(in: .whitespacesAndNewlines), !rawUUID.isEmpty {
            guard let workout = completed.first(where: { $0.hkUUID.caseInsensitiveCompare(rawUUID) == .orderedSame }) else {
                return .none(reason: "UUID 对应的训练不存在、已删除或尚未结束")
            }
            if let window, !(workout.start >= window.start && workout.start < window.end) {
                return .conflict(reason: "指定的训练时间和描述中的日期不一致，请确认是哪一次训练")
            }
            return .unique(makeCandidate(
                workout: workout,
                rawText: cleaned,
                annotations: annotationsByWorkoutUUID[workout.hkUUID],
                timeZone: timeZone
            ))
        }

        if let window {
            let matches = completed.filter { $0.start >= window.start && $0.start < window.end }
            return resolution(for: matches, window: window, rawText: cleaned, annotations: annotationsByWorkoutUUID, timeZone: timeZone)
        }

        // No date and no UUID: only recent unreviewed strength workouts.
        let cutoff = asOf.addingTimeInterval(-72 * 3600)
        let recent = completed.filter {
            $0.start >= cutoff
                && $0.reviewState == .unreviewed
                && WorkoutAutoAttributor.isStrengthWorkout(type: $0.type)
        }
        return resolution(
            for: recent,
            window: DateWindow(start: cutoff, end: asOf, description: "近 72 小时待复盘力量训练"),
            rawText: cleaned,
            annotations: annotationsByWorkoutUUID,
            timeZone: timeZone
        )
    }

    private enum ParsedWindow {
        case none
        case window(DateWindow)
        case conflict(reason: String)
    }

    private static func parseDateWindow(
        text: String,
        today: DayKey,
        calendarToday: DayKey,
        timeZone: TimeZone
    ) -> ParsedWindow {
        // "昨晚" and "昨天" are calendar-day phrases: at 02:00 the previous evening
        // still ends on the current calendar morning, even though the physiological
        // day is still yesterday.
        let phrases: [(String, DayKey)] = [
            ("前天", calendarToday.addingDays(-2)),
            ("前晚", calendarToday.addingDays(-1)),
            ("昨夜", calendarToday),
            ("昨晚", calendarToday),
            ("昨日", calendarToday.addingDays(-1)),
            ("昨天", calendarToday.addingDays(-1)),
            ("今日", today),
            ("今天", today),
        ]
        let matches = phrases.filter { text.contains($0.0) }
        guard !matches.isEmpty else { return .none }
        let kinds = Set(matches.map { $0.0.contains("晚") || $0.0.contains("夜") ? "night" : "day" })
        guard kinds.count == 1 else {
            return .conflict(reason: "描述里同时出现了两个日期，请只指定一次训练")
        }
        // Multiple phrases of the same kind are allowed only when they resolve to the same day.
        let days = Set(matches.map { $0.1.isoString })
        guard days.count == 1, let day = matches.first?.1 else {
            return .conflict(reason: "描述里同时出现了两个日期，请只指定一次训练")
        }
        let isNight = matches[0].0.contains("晚") || matches[0].0.contains("夜")
        if isNight {
            let start = day.startDate(cutoverHour: 4, timeZone: timeZone).addingTimeInterval(-10 * 3600)
            let end = day.startDate(cutoverHour: 4, timeZone: timeZone).addingTimeInterval(2 * 3600)
            return .window(DateWindow(
                start: start,
                end: end,
                description: "\(day.isoString) 前一晚 18:00 至当日 06:00"
            ))
        }
        let start = day.startDate(cutoverHour: 4, timeZone: timeZone)
        let end = day.addingDays(1).startDate(cutoverHour: 4, timeZone: timeZone)
        return .window(DateWindow(start: start, end: end, description: "\(day.isoString) 04:00 生理日"))
    }

    private static func resolution(
        for workouts: [StoredWorkoutRecord],
        window: DateWindow,
        rawText: String,
        annotations: [String: WorkoutAnnotationRecord],
        timeZone: TimeZone
    ) -> WorkoutAnnotationResolution {
        let unique = Dictionary(workouts.map { ($0.hkUUID.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = unique.values.sorted { $0.start < $1.start }
        if ordered.isEmpty {
            return .none(reason: "\(window.description) 没有可标注的 Watch 训练")
        }
        let candidates = ordered.prefix(12).map { workout in
            makeCandidate(
                workout: workout,
                rawText: rawText,
                annotations: annotations[workout.hkUUID],
                timeZone: timeZone
            )
        }
        if candidates.count == 1 {
            return .unique(candidates[0])
        }
        return .multiple(Array(candidates), windowDescription: window.description)
    }

    private static func makeCandidate(
        workout: StoredWorkoutRecord,
        rawText: String,
        annotations: WorkoutAnnotationRecord?,
        timeZone: TimeZone
    ) -> CoachWorkoutAnnotationCandidate {
        let parsed = ChineseWorkoutLexiconParser.parse(rawText)
        let duration = max(1, Int((workout.end.timeIntervalSince(workout.start) / 60).rounded()))
        let loads = WorkoutLoadBuilder.buildMuscleLoads(
            workoutUUID: workout.hkUUID,
            durationMinutes: duration,
            primaryMuscles: parsed.primaryMuscles,
            secondaryMuscles: parsed.secondaryMuscles,
            rpe: parsed.rpe ?? 7
        )
        let recordState = WorkoutAnnotationRecordState(
            workoutUUID: workout.hkUUID,
            start: workout.start,
            end: workout.end,
            type: workout.type,
            reviewState: workout.reviewState,
            latestAnnotationID: annotations?.id,
            latestAnnotationRawText: annotations?.rawText
        )
        let proposal = CoachWorkoutAnnotationProposal(
            workoutUUID: workout.hkUUID,
            workoutTitle: workout.type,
            rawText: rawText,
            proposal: parsed,
            muscleLoads: loads,
            recordState: recordState
        )
        return CoachWorkoutAnnotationCandidate(
            proposal: proposal,
            start: workout.start,
            end: workout.end,
            dayKey: workout.start.physiologicalDayKey(cutoverHour: 4, timeZone: timeZone).isoString,
            source: "healthkit",
            reviewState: workout.reviewState
        )
    }
}
