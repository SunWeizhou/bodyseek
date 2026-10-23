import Foundation
import BodySeekDomain

public typealias TrainingLoadAvailability = BodySeekDomain.TrainingLoadAvailability
public typealias DailyLoadObservation = BodySeekDomain.DailyLoadObservation
public typealias WorkoutInput = BodySeekDomain.WorkoutInput
public typealias StrainScoreInput = BodySeekDomain.StrainScoreInput

struct HeartRateZoneSummary: Hashable {
    struct Zone: Identifiable, Hashable {
        let id: Int
        let title: String
        let detail: String
        let minutes: Double
    }

    let zones: [Zone]

    var totalMinutes: Double {
        zones.reduce(0.0) { $0 + $1.minutes }
    }
}

enum HeartRateZoneCalculator {
    static func summarize(
        samples: [HeartRateSample],
        restingHeartRate: Double,
        maxHeartRate: Double,
        maxSampleGap: TimeInterval = 120
    ) -> HeartRateZoneSummary? {
        summarize(
            sampleGroups: [samples],
            restingHeartRate: restingHeartRate,
            maxHeartRate: maxHeartRate,
            maxSampleGap: maxSampleGap
        )
    }

    static func summarize(
        sampleGroups: [[HeartRateSample]],
        restingHeartRate: Double,
        maxHeartRate: Double,
        maxSampleGap: TimeInterval = 120
    ) -> HeartRateZoneSummary? {
        guard maxHeartRate > restingHeartRate,
              maxSampleGap > 0 else { return nil }

        let definitions = [
            (title: "Zone 1", detail: "恢复"),
            (title: "Zone 2", detail: "有氧基础"),
            (title: "Zone 3", detail: "节奏"),
            (title: "Zone 4", detail: "阈值"),
            (title: "Zone 5", detail: "高强度")
        ]
        let heartRateRange = maxHeartRate - restingHeartRate
        var minutes = Array(repeating: 0.0, count: definitions.count)

        for samples in sampleGroups {
            let sortedSamples = samples.sorted { $0.date < $1.date }
            for index in sortedSamples.indices.dropLast() {
                let interval = sortedSamples[index + 1].date.timeIntervalSince(sortedSamples[index].date)
                guard interval > 0 else { continue }

                let boundedInterval = min(interval, maxSampleGap)
                let reserve = (sortedSamples[index].bpm - restingHeartRate) / heartRateRange
                let zoneIndex: Int
                if reserve >= 0.9 {
                    zoneIndex = 4
                } else if reserve >= 0.8 {
                    zoneIndex = 3
                } else if reserve >= 0.7 {
                    zoneIndex = 2
                } else if reserve >= 0.6 {
                    zoneIndex = 1
                } else {
                    zoneIndex = 0
                }
                minutes[zoneIndex] += boundedInterval / 60.0
            }
        }

        guard minutes.contains(where: { $0 > 0 }) else { return nil }

        return HeartRateZoneSummary(
            zones: definitions.indices.reversed().map { index in
                HeartRateZoneSummary.Zone(
                    id: index + 1,
                    title: definitions[index].title,
                    detail: definitions[index].detail,
                    minutes: minutes[index]
                )
            }
        )
    }
}


/// App-facing strain types stay stable while the formula lives in
/// `BodySeekDomain`. Heart-rate zone display still uses app `HeartRateSample`
/// and stays in this file.
public struct StrainScoreEngine: ScoreEngine {
    public typealias Input = StrainScoreInput
    public typealias Output = MetricResult

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func calculate(from input: StrainScoreInput) -> MetricResult {
        let result = BodySeekDomain.StrainScoreEngine(calendar: calendar).calculate(from: input)
        return DomainMetricAdapter.metric(result)
    }
}
