import Foundation

/// Priority tiers for deduplicating overlapping sleep intervals within a physiological window.
/// Note: Owner attribution relies exclusively on source metadata and time-window rules, never owner names.
public enum SleepSourceTier: Int, Codable, Hashable, Sendable, Comparable {
    case iPhoneOrInBed = 0
    case thirdPartyWearable = 1
    case autoSleep = 2
    case appleWatch = 3

    public static func < (lhs: SleepSourceTier, rhs: SleepSourceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public static func infer(from source: SourceRef, stage: RawSleepSampleStage) -> SleepSourceTier {
        let bundle = (source.bundleIdentifier ?? "").lowercased()
        let model = (source.deviceModel ?? "").lowercased()
        let name = source.name.lowercased()

        if model.contains("watch") || name.contains("apple watch") {
            return .appleWatch
        }
        if bundle.contains("autosleep") || bundle.contains("tantsissa") || name.contains("autosleep") {
            return .autoSleep
        }
        if bundle == "com.apple.health" || bundle.hasPrefix("com.apple.health.") {
            switch stage {
            case .deep, .core, .rem:
                return .appleWatch
            case .awake, .asleepUnspecified, .inBed:
                if source.priority >= 90 {
                    return .appleWatch
                }
                return .iPhoneOrInBed
            }
        }
        if model.contains("iphone") || name.contains("iphone") {
            return .iPhoneOrInBed
        }
        return .thirdPartyWearable
    }
}

public enum RawSleepSampleStage: String, CaseIterable, Hashable, Codable, Sendable {
    case deep
    case core
    case rem
    case awake
    case asleepUnspecified
    case inBed

    public var uiStage: SleepStage? {
        switch self {
        case .deep: .deep
        case .core, .asleepUnspecified: .core
        case .rem: .rem
        case .awake: .awake
        case .inBed: nil
        }
    }
}

public struct RawSleepSample: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let stage: RawSleepSampleStage
    public let source: SourceRef
    public let deviceIdentifier: String?

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        stage: RawSleepSampleStage,
        source: SourceRef,
        deviceIdentifier: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.stage = stage
        self.source = source
        self.deviceIdentifier = deviceIdentifier
    }
}

public struct MergedSleepEpisode: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let dayKey: DayKey
    public let startDate: Date
    public let endDate: Date
    public let isPrimarySleep: Bool
    public let primarySource: SourceRef
    public let sources: [SourceRef]
    public let mergePolicyVersion: AlgorithmVersion
    public let segments: [SleepStageSegment]
    public let asleepMinutes: Int
    public let inBedMinutes: Int
    public let deepMinutes: Int
    public let remMinutes: Int
    public let coreMinutes: Int
    public let awakeMinutes: Int
    public let efficiency: Double?

    public init(
        id: String,
        dayKey: DayKey,
        startDate: Date,
        endDate: Date,
        isPrimarySleep: Bool,
        primarySource: SourceRef,
        sources: [SourceRef],
        mergePolicyVersion: AlgorithmVersion = .sleepMergeV1,
        segments: [SleepStageSegment],
        asleepMinutes: Int,
        inBedMinutes: Int,
        deepMinutes: Int,
        remMinutes: Int,
        coreMinutes: Int,
        awakeMinutes: Int,
        efficiency: Double?
    ) {
        self.id = id
        self.dayKey = dayKey
        self.startDate = startDate
        self.endDate = endDate
        self.isPrimarySleep = isPrimarySleep
        self.primarySource = primarySource
        self.sources = sources
        self.mergePolicyVersion = mergePolicyVersion
        self.segments = segments
        self.asleepMinutes = asleepMinutes
        self.inBedMinutes = inBedMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.efficiency = efficiency
    }
}

public struct SleepMergeResult: Hashable, Sendable {
    public let dayKey: DayKey
    public let episodes: [MergedSleepEpisode]
    public let primaryEpisode: MergedSleepEpisode?
    public let naps: [MergedSleepEpisode]
    public let totalAsleepMinutes: Int?
    public let totalInBedMinutes: Int?
    public let deepMinutes: Int?
    public let remMinutes: Int?
    public let coreMinutes: Int?
    public let awakeMinutes: Int?
    public let mergePolicyVersion: AlgorithmVersion

    public init(
        dayKey: DayKey,
        episodes: [MergedSleepEpisode],
        primaryEpisode: MergedSleepEpisode?,
        naps: [MergedSleepEpisode],
        totalAsleepMinutes: Int?,
        totalInBedMinutes: Int?,
        deepMinutes: Int?,
        remMinutes: Int?,
        coreMinutes: Int?,
        awakeMinutes: Int?,
        mergePolicyVersion: AlgorithmVersion = .sleepMergeV1
    ) {
        self.dayKey = dayKey
        self.episodes = episodes
        self.primaryEpisode = primaryEpisode
        self.naps = naps
        self.totalAsleepMinutes = totalAsleepMinutes
        self.totalInBedMinutes = totalInBedMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.coreMinutes = coreMinutes
        self.awakeMinutes = awakeMinutes
        self.mergePolicyVersion = mergePolicyVersion
    }
}

/// Deterministic, versioned sleep overlap & episode merge policy (`sleep-merge-v1`).
/// Priority order on overlapping windows: Apple Watch stages > AutoSleep > other wearable > iPhone / generic inBed.
public enum SleepMergePolicy {
    public static let policyVersion: AlgorithmVersion = .sleepMergeV1
    public static let episodeGapSeconds: TimeInterval = 90 * 60

    public static func merge(
        samples: [RawSleepSample],
        cutoverHour: Int = 4,
        timeZone: TimeZone = .current
    ) -> [DayKey: SleepMergeResult] {
        let valid = samples
            .filter { $0.endDate > $0.startDate }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                if lhs.endDate != rhs.endDate { return lhs.endDate < rhs.endDate }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        guard !valid.isEmpty else { return [:] }

        // Cluster raw samples into candidate sleep episodes before resolving overlaps within each cluster.
        var clusters: [[RawSleepSample]] = []
        var currentCluster: [RawSleepSample] = []
        var clusterMaxEnd = Date.distantPast

        for sample in valid {
            if currentCluster.isEmpty {
                currentCluster = [sample]
                clusterMaxEnd = sample.endDate
            } else if sample.startDate.timeIntervalSince(clusterMaxEnd) <= episodeGapSeconds {
                currentCluster.append(sample)
                if sample.endDate > clusterMaxEnd {
                    clusterMaxEnd = sample.endDate
                }
            } else {
                clusters.append(currentCluster)
                currentCluster = [sample]
                clusterMaxEnd = sample.endDate
            }
        }
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        // Resolve each cluster via sweep line and group by physiological wake-up dayKey.
        struct ResolvedDraft {
            let dayKey: DayKey
            let startDate: Date
            let endDate: Date
            let primarySource: SourceRef
            let sources: [SourceRef]
            let segments: [SleepStageSegment]
            let asleepMinutes: Int
            let inBedMinutes: Int
            let deepMinutes: Int
            let remMinutes: Int
            let coreMinutes: Int
            let awakeMinutes: Int
        }

        var draftsByDay: [DayKey: [ResolvedDraft]] = [:]

        for cluster in clusters {
            let resolved = resolveOverlaps(in: cluster)
            guard let clusterStart = resolved.clusterStart, let clusterEnd = resolved.clusterEnd else {
                continue
            }

            let inBedSpanMinutes = max(
                0,
                Int((clusterEnd.timeIntervalSince(clusterStart) / 60.0).rounded())
            )
            let deepMin = Int((resolved.deepSec / 60.0).rounded())
            let remMin = Int((resolved.remSec / 60.0).rounded())
            let coreMin = Int((resolved.coreSec / 60.0).rounded())
            let awakeMin = Int((resolved.awakeSec / 60.0).rounded())
            let asleepMin = Int(((resolved.deepSec + resolved.remSec + resolved.coreSec + resolved.unspecAsleepSec) / 60.0).rounded())
            let totalInBed = max(inBedSpanMinutes, asleepMin + awakeMin)

            guard asleepMin > 0 || totalInBed > 0 else { continue }

            let dayKey = clusterEnd.physiologicalDayKey(cutoverHour: cutoverHour, timeZone: timeZone)
            let draft = ResolvedDraft(
                dayKey: dayKey,
                startDate: clusterStart,
                endDate: clusterEnd,
                primarySource: resolved.primarySource,
                sources: resolved.allSources,
                segments: resolved.segments,
                asleepMinutes: asleepMin,
                inBedMinutes: totalInBed,
                deepMinutes: deepMin,
                remMinutes: remMin,
                coreMinutes: coreMin,
                awakeMinutes: awakeMin
            )
            draftsByDay[dayKey, default: []].append(draft)
        }

        var output: [DayKey: SleepMergeResult] = [:]
        for (dayKey, drafts) in draftsByDay {
            // Identify primary overnight sleep episode (longest asleep, tie-breaking by longest inBed then earliest end).
            let sortedByDuration = drafts.sorted { lhs, rhs in
                if lhs.asleepMinutes != rhs.asleepMinutes {
                    return lhs.asleepMinutes > rhs.asleepMinutes
                }
                if lhs.inBedMinutes != rhs.inBedMinutes {
                    return lhs.inBedMinutes > rhs.inBedMinutes
                }
                return lhs.startDate < rhs.startDate
            }

            let primaryDraft = sortedByDuration.first
            var episodes: [MergedSleepEpisode] = []
            for draft in drafts.sorted(by: { $0.startDate < $1.startDate }) {
                let isPrimary = primaryDraft.map {
                    $0.startDate == draft.startDate && $0.endDate == draft.endDate
                } ?? false
                let episodeID = "\(dayKey.isoString)_\(Int(draft.startDate.timeIntervalSince1970))"
                let efficiency: Double? = draft.inBedMinutes > 0
                    ? min(1.0, max(0.0, Double(draft.asleepMinutes) / Double(draft.inBedMinutes)))
                    : nil
                episodes.append(
                    MergedSleepEpisode(
                        id: episodeID,
                        dayKey: dayKey,
                        startDate: draft.startDate,
                        endDate: draft.endDate,
                        isPrimarySleep: isPrimary,
                        primarySource: draft.primarySource,
                        sources: draft.sources,
                        mergePolicyVersion: policyVersion,
                        segments: draft.segments,
                        asleepMinutes: draft.asleepMinutes,
                        inBedMinutes: draft.inBedMinutes,
                        deepMinutes: draft.deepMinutes,
                        remMinutes: draft.remMinutes,
                        coreMinutes: draft.coreMinutes,
                        awakeMinutes: draft.awakeMinutes,
                        efficiency: efficiency
                    )
                )
            }

            let primaryEpisode = episodes.first(where: \.isPrimarySleep)
            let naps = episodes.filter { !$0.isPrimarySleep }
            let totalAsleep = episodes.reduce(0) { $0 + $1.asleepMinutes }
            let totalInBed = episodes.reduce(0) { $0 + $1.inBedMinutes }

            output[dayKey] = SleepMergeResult(
                dayKey: dayKey,
                episodes: episodes,
                primaryEpisode: primaryEpisode,
                naps: naps,
                totalAsleepMinutes: totalAsleep,
                totalInBedMinutes: totalInBed,
                deepMinutes: primaryEpisode?.deepMinutes,
                remMinutes: primaryEpisode?.remMinutes,
                coreMinutes: primaryEpisode?.coreMinutes,
                awakeMinutes: primaryEpisode?.awakeMinutes,
                mergePolicyVersion: policyVersion
            )
        }

        return output
    }

    private struct ResolvedCluster {
        let clusterStart: Date?
        let clusterEnd: Date?
        let segments: [SleepStageSegment]
        let deepSec: TimeInterval
        let remSec: TimeInterval
        let coreSec: TimeInterval
        let awakeSec: TimeInterval
        let unspecAsleepSec: TimeInterval
        let primarySource: SourceRef
        let allSources: [SourceRef]
    }

    private static func resolveOverlaps(in samples: [RawSleepSample]) -> ResolvedCluster {
        var boundarySet = Set<TimeInterval>()
        boundarySet.reserveCapacity(samples.count * 2)
        for s in samples {
            boundarySet.insert(s.startDate.timeIntervalSinceReferenceDate)
            boundarySet.insert(s.endDate.timeIntervalSinceReferenceDate)
        }
        let boundaries = boundarySet.sorted()
        guard boundaries.count >= 2 else {
            let fallbackSource = samples.first?.source ?? SourceRef(name: "Apple 健康", priority: 0)
            return ResolvedCluster(
                clusterStart: nil,
                clusterEnd: nil,
                segments: [],
                deepSec: 0,
                remSec: 0,
                coreSec: 0,
                awakeSec: 0,
                unspecAsleepSec: 0,
                primarySource: fallbackSource,
                allSources: []
            )
        }

        var mergedSegments: [SleepStageSegment] = []
        var durationBySource: [SourceRef: TimeInterval] = [:]
        var deepSec: TimeInterval = 0
        var remSec: TimeInterval = 0
        var coreSec: TimeInterval = 0
        var awakeSec: TimeInterval = 0
        var unspecAsleepSec: TimeInterval = 0
        var earliestCovered: Date?
        var latestCovered: Date?

        for idx in 0..<(boundaries.count - 1) {
            let startRef = boundaries[idx]
            let endRef = boundaries[idx + 1]
            let duration = endRef - startRef
            guard duration > 0.5 else { continue }

            let intervalStart = Date(timeIntervalSinceReferenceDate: startRef)
            let intervalEnd = Date(timeIntervalSinceReferenceDate: endRef)

            let covering = samples.filter { sample in
                sample.startDate <= intervalStart && sample.endDate >= intervalEnd
            }
            guard let winner = covering.max(by: { lhs, rhs in
                isLowerPriority(lhs, than: rhs)
            }) else {
                continue
            }

            if earliestCovered == nil { earliestCovered = intervalStart }
            latestCovered = intervalEnd
            durationBySource[winner.source, default: 0] += duration

            switch winner.stage {
            case .deep: deepSec += duration
            case .rem: remSec += duration
            case .core: coreSec += duration
            case .awake: awakeSec += duration
            case .asleepUnspecified: unspecAsleepSec += duration
            case .inBed: break
            }

            if let uiStage = winner.stage.uiStage {
                if let last = mergedSegments.last,
                   last.stage == uiStage,
                   abs(last.endDate.timeIntervalSince(intervalStart)) <= 1.0
                {
                    mergedSegments[mergedSegments.count - 1] = SleepStageSegment(
                        id: last.id,
                        stage: last.stage,
                        startDate: last.startDate,
                        endDate: intervalEnd
                    )
                } else {
                    mergedSegments.append(
                        SleepStageSegment(
                            stage: uiStage,
                            startDate: intervalStart,
                            endDate: intervalEnd
                        )
                    )
                }
            }
        }

        let orderedSources = durationBySource
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                if lhs.key.priority != rhs.key.priority { return lhs.key.priority > rhs.key.priority }
                return lhs.key.name < rhs.key.name
            }
            .map(\.key)

        let primary = orderedSources.first ?? samples[0].source
        return ResolvedCluster(
            clusterStart: earliestCovered,
            clusterEnd: latestCovered,
            segments: mergedSegments,
            deepSec: deepSec,
            remSec: remSec,
            coreSec: coreSec,
            awakeSec: awakeSec,
            unspecAsleepSec: unspecAsleepSec,
            primarySource: primary,
            allSources: orderedSources
        )
    }

    /// Returns `true` when `lhs` loses to `rhs`.
    private static func isLowerPriority(_ lhs: RawSleepSample, than rhs: RawSleepSample) -> Bool {
        let tierL = SleepSourceTier.infer(from: lhs.source, stage: lhs.stage)
        let tierR = SleepSourceTier.infer(from: rhs.source, stage: rhs.stage)
        if tierL != tierR { return tierL < tierR }

        let stageSpecificityL = stagePriority(lhs.stage)
        let stageSpecificityR = stagePriority(rhs.stage)
        if stageSpecificityL != stageSpecificityR {
            return stageSpecificityL < stageSpecificityR
        }

        if lhs.source.priority != rhs.source.priority {
            return lhs.source.priority < rhs.source.priority
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func stagePriority(_ stage: RawSleepSampleStage) -> Int {
        switch stage {
        case .deep, .core, .rem: 3
        case .awake: 2
        case .asleepUnspecified: 1
        case .inBed: 0
        }
    }
}
