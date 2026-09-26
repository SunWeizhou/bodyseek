import Foundation

enum SleepSampleNormalizer {
    /// Total minutes in an episode that count toward sleep duration (excludes
    /// awake / in-bed). Used to pick the main night sleep over a short nap.
    static func sleepDuration(_ segments: [SleepStageSegment]) -> TimeInterval {
        segments.reduce(0) { $0 + (($1.stage.countsTowardSleepDuration && $1.end > $1.start) ? $1.end.timeIntervalSince($1.start) : 0) }
    }

    static func summary(
        for date: Date,
        segments: [SleepStageSegment],
        sleepScore: Double? = nil
    ) -> SleepSummary {
        let sortedSegments = segments.sorted { $0.start < $1.start }
        let stageMinutes = Dictionary(grouping: sortedSegments, by: \.stage)
            .mapValues { segments in
                segments.reduce(0) { $0 + $1.durationMinutes }
            }

        let totalSleepMinutes = sortedSegments.reduce(0) { partial, segment in
            guard segment.stage.countsTowardSleepDuration else { return partial }
            return partial + segment.durationMinutes
        }

        return SleepSummary(
            date: date,
            totalSleepMinutes: totalSleepMinutes,
            bedtime: sortedSegments.first?.start,
            wakeTime: sortedSegments.last?.end,
            stageMinutes: stageMinutes,
            segments: sortedSegments,
            sleepScore: sleepScore
        )
    }

    static func mostRecentEpisodeSummary(
        for date: Date,
        segments: [SleepStageSegment],
        sleepScore: Double? = nil,
        maximumGapMinutes: Int = 120,
        calendar: Calendar = .current
    ) -> SleepSummary? {
        let allSummaries = allNightlyEpisodes(
            segments: segments,
            maximumGapMinutes: maximumGapMinutes,
            calendar: calendar
        )
        guard !allSummaries.isEmpty else { return nil }

        let targetDay = calendar.startOfDay(for: date)

        // 1. Look for an episode assigned to the target health day
        if let match = allSummaries.filter({ calendar.isDate($0.date, inSameDayAs: targetDay) }).max(by: { $0.totalSleepMinutes < $1.totalSleepMinutes }) {
            return match
        }

        // 2. Otherwise pick the most recent episode on or before targetDay
        if let priorMatch = allSummaries.filter({ $0.date <= targetDay }).max(by: { $0.date < $1.date }) {
            return priorMatch
        }

        // 3. Fallback to the latest available episode
        return allSummaries.last
    }

    /// 主睡眠段归属：返回「结束时刻落在查询窗内」且时长 ≥ minimumNightMinutes 的主睡眠段。
    /// 查询调用方负责把窗口向前扩展（主睡眠段按 startDate 匹配），否则跨 04:00 健康日
    /// 边界的夜晚会被截断拆进两天。多个候选（如夜晚 + 午后小睡）取总时长最大者。
    static func mainNightSummary(
        in range: DateRangeQuery,
        segments: [SleepStageSegment],
        sleepScore: Double? = nil,
        maximumGapMinutes: Int = 120,
        minimumNightMinutes: Int = 60,
        calendar: Calendar = .current
    ) -> SleepSummary? {
        let episodes = allNightlyEpisodes(
            segments: segments,
            maximumGapMinutes: maximumGapMinutes,
            calendar: calendar
        )
        return episodes
            .filter { episode in
                guard let wake = episode.wakeTime else { return false }
                return wake >= range.start
                    && wake < range.end
                    && episode.totalSleepMinutes >= minimumNightMinutes
            }
            .max { $0.totalSleepMinutes < $1.totalSleepMinutes }
    }

    static func allNightlyEpisodes(
        segments: [SleepStageSegment],
        maximumGapMinutes: Int = 120,
        calendar: Calendar = .current
    ) -> [SleepSummary] {
        let sortedSegments = segments
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !sortedSegments.isEmpty else { return [] }

        let boundary = HealthDayBoundary(calendar: calendar)
        let maximumGap = TimeInterval(maximumGapMinutes * 60)
        var episodes: [[SleepStageSegment]] = []
        var currentEpisode: [SleepStageSegment] = []

        for segment in sortedSegments {
            if let previous = currentEpisode.last,
               segment.start.timeIntervalSince(previous.end) > maximumGap {
                episodes.append(currentEpisode)
                currentEpisode = [segment]
            } else {
                currentEpisode.append(segment)
            }
        }
        if !currentEpisode.isEmpty {
            episodes.append(currentEpisode)
        }

        return episodes.compactMap { episode in
            guard episode.contains(where: { $0.stage.countsTowardSleepDuration }),
                  let lastSegment = episode.last else { return nil }
            let date = boundary.labelDate(containing: lastSegment.end)
            return summary(for: date, segments: episode)
        }
    }
}
