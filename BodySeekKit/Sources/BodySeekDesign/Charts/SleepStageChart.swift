import BodySeekCore
import SleepChartKit
import SwiftUI

/// Sleep-stage summary and interactive detail sharing the same normalized segments.
public struct SleepStageChart: View {
    public let segments: [SleepStageSegment]
    public let height: CGFloat
    public let interactive: Bool

    @State private var selectedSegment: SleepStageSegment?

    private let trackOrder: [BodySeekCore.SleepStage] = [.awake, .rem, .core, .deep]

    public init(segments: [SleepStageSegment], height: CGFloat = 156, interactive: Bool = true) {
        self.segments = segments
        self.height = height
        self.interactive = interactive
    }

    public var body: some View {
        let ordered = segments.filter { $0.endDate > $0.startDate }.sorted { $0.startDate < $1.startDate }

        if ordered.isEmpty {
            ChartEmptyPlaceholder(
                title: "昨晚暂无睡眠分期片段",
                systemImage: "bed.double.fill",
                height: min(height, 110)
            )
        } else if !interactive, let samples = Self.communitySamples(for: ordered),
                  let start = ordered.first?.startDate, let end = ordered.last?.endDate {
            VStack(alignment: .leading, spacing: 8) {
                SleepTimelineGraph(samples: samples, colorProvider: CommunitySleepColors())
                    .frame(height: max(40, height - 48))
                    .clipped()

                HStack {
                    Text(ChartAxisSupport.formatHour(start))
                    Spacer()
                    Text(ChartAxisSupport.formatHour(end))
                }
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(BevelTheme.inkSecondary)

                HStack(spacing: 12) {
                    ForEach(trackOrder, id: \.self) { stage in
                        Label(stage.title, systemImage: "circle.fill")
                            .foregroundStyle(BevelTheme.sleepStageColor(stage))
                    }
                }
                .font(.footnote)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("昨夜睡眠分期图")
            .accessibilityValue(totalStageSummary(ordered))
            .accessibilityIdentifier("community-sleep-chart")
        } else if let minStart = ordered.first?.startDate, let maxEnd = ordered.map(\.endDate).max(), maxEnd > minStart {
            let totalDuration = maxEnd.timeIntervalSince(minStart)
            let midDate = minStart.addingTimeInterval(totalDuration / 2.0)

            VStack(alignment: .leading, spacing: 8) {
                if interactive {
                    ChartLockedReadoutHeader(
                        primaryText: selectedSegment.map { "\($0.stage.title) · \($0.durationMinutes) 分钟" } ?? totalStageSummary(ordered),
                        secondaryText: selectedSegment.map {
                            "\(ChartAxisSupport.formatHour($0.startDate)) – \(ChartAxisSupport.formatHour($0.endDate))"
                        } ?? "\(ChartAxisSupport.formatHour(minStart)) 入睡 · \(ChartAxisSupport.formatHour(maxEnd)) 起床",
                        tint: selectedSegment.map { BevelTheme.sleepStageColor($0.stage) } ?? BevelTheme.sleepColor,
                        isLocked: selectedSegment != nil,
                        onClear: selectedSegment == nil ? nil : { selectedSegment = nil }
                    )
                }

                GeometryReader { geo in
                    let labelColumnWidth: CGFloat = 34
                    let plotWidth = max(1, geo.size.width - labelColumnWidth - 6)
                    let axisFooterHeight: CGFloat = 18
                    let tracksHeight = max(40, geo.size.height - axisFooterHeight)
                    let rowHeight = tracksHeight / CGFloat(trackOrder.count)

                    ZStack(alignment: .topLeading) {
                        Canvas { context, size in
                            let plotStartX = labelColumnWidth + 6
                            let rowH = (size.height - axisFooterHeight) / CGFloat(trackOrder.count)

                            // Subtle horizontal track guide lines
                            for row in 0..<trackOrder.count {
                                let midY = CGFloat(row) * rowH + rowH / 2
                                var guide = Path()
                                guide.move(to: CGPoint(x: plotStartX, y: midY))
                                guide.addLine(to: CGPoint(x: size.width, y: midY))
                                context.stroke(guide, with: .color(BevelTheme.hairline.opacity(0.6)), lineWidth: 0.5)
                            }

                            // Staircase vertical connectors between consecutive segments
                            for i in 0..<(ordered.count - 1) {
                                let a = ordered[i]
                                let b = ordered[i + 1]
                                guard a.endDate == b.startDate else { continue }
                                let rowA = trackOrder.firstIndex(of: a.stage) ?? 2
                                let rowB = trackOrder.firstIndex(of: b.stage) ?? 2
                                guard rowA != rowB else { continue }
                                let x = plotStartX + CGFloat(a.endDate.timeIntervalSince(minStart) / totalDuration) * plotWidth
                                let y1 = CGFloat(rowA) * rowH + rowH * 0.5
                                let y2 = CGFloat(rowB) * rowH + rowH * 0.5
                                var connector = Path()
                                connector.move(to: CGPoint(x: x, y: y1))
                                connector.addLine(to: CGPoint(x: x, y: y2))
                                context.stroke(
                                    connector,
                                    with: .color(BevelTheme.inkSecondary.opacity(0.32)),
                                    lineWidth: 1.1
                                )
                            }

                            // Stage blocks
                            for seg in ordered {
                                let row = trackOrder.firstIndex(of: seg.stage) ?? 2
                                let x0 = plotStartX + CGFloat(seg.startDate.timeIntervalSince(minStart) / totalDuration) * plotWidth
                                let x1 = plotStartX + CGFloat(seg.endDate.timeIntervalSince(minStart) / totalDuration) * plotWidth
                                let blockWidth = max(2.5, x1 - x0)
                                let verticalPad = max(3.5, rowH * 0.22)
                                let rect = CGRect(
                                    x: x0,
                                    y: CGFloat(row) * rowH + verticalPad,
                                    width: blockWidth,
                                    height: max(6, rowH - verticalPad * 2)
                                )
                                let rounded = Path(roundedRect: rect, cornerRadius: min(6, rect.height / 2))
                                let isSelected = selectedSegment?.id == seg.id
                                let color = BevelTheme.sleepStageColor(seg.stage)
                                context.fill(rounded, with: .color(color.opacity(selectedSegment == nil || isSelected ? 0.92 : 0.35)))
                                if isSelected {
                                    context.stroke(rounded, with: .color(BevelTheme.ink), lineWidth: 1.4)
                                }
                            }
                        }

                        // Leading track labels
                        VStack(spacing: 0) {
                            ForEach(trackOrder, id: \.self) { stage in
                                Text(stage.title)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(BevelTheme.sleepStageColor(stage))
                                    .frame(width: labelColumnWidth, height: rowHeight, alignment: .leading)
                            }
                        }

                        // Explicit start / midpoint / end time ticks (never truncated)
                        HStack {
                            Text(ChartAxisSupport.formatHour(minStart))
                            Spacer()
                            Text(ChartAxisSupport.formatHour(midDate))
                            Spacer()
                            Text(ChartAxisSupport.formatHour(maxEnd))
                        }
                        .font(.caption2.monospacedDigit())
                        .fontDesign(.rounded)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .padding(.leading, labelColumnWidth + 6)
                        .offset(y: tracksHeight + 2)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard interactive else { return }
                                selectSegment(atX: value.location.x, labelOffset: labelColumnWidth + 6, plotWidth: plotWidth, start: minStart, duration: totalDuration, ordered: ordered)
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                guard interactive else { return }
                                selectSegment(atX: value.location.x, labelOffset: labelColumnWidth + 6, plotWidth: plotWidth, start: minStart, duration: totalDuration, ordered: ordered)
                            }
                    )
                }
                .frame(height: height)
                .bodyseekSelectionHaptic(trigger: selectedSegment?.id)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("昨夜睡眠分期图")
            .accessibilityValue(totalStageSummary(ordered))
        }
    }

    static func communitySamples(for ordered: [SleepStageSegment]) -> [SleepSample]? {
        // The upstream renderer connects consecutive samples even across a gap.
        // Keep incomplete or overlapping sessions on the gap-aware renderer.
        guard !ordered.isEmpty,
              ordered.allSatisfy({ $0.startDate < $0.endDate }),
              zip(ordered, ordered.dropFirst()).allSatisfy({ $0.endDate == $1.startDate })
        else { return nil }

        return ordered.map { segment in
            let stage: SleepChartKit.SleepStage = switch segment.stage {
            case .awake: .awake
            case .rem: .asleepREM
            case .core: .asleepCore
            case .deep: .asleepDeep
            }
            return SleepSample(stage: stage, startDate: segment.startDate, endDate: segment.endDate)
        }
    }

    private func selectSegment(
        atX x: CGFloat,
        labelOffset: CGFloat,
        plotWidth: CGFloat,
        start: Date,
        duration: TimeInterval,
        ordered: [SleepStageSegment]
    ) {
        let fraction = min(1, max(0, (x - labelOffset) / max(1, plotWidth)))
        let targetDate = start.addingTimeInterval(duration * Double(fraction))
        let hit = ordered.first {
            targetDate >= $0.startDate && (targetDate < $0.endDate || targetDate == ordered.last?.endDate && targetDate == $0.endDate)
        }
        if selectedSegment?.id != hit?.id {
            selectedSegment = hit
            BodySeekSignposts.shared.emitEvent(.chartScrub, detail: "sleep-stages")
        }
    }

    private func totalStageSummary(_ ordered: [SleepStageSegment]) -> String {
        let deep = ordered.filter { $0.stage == .deep }.reduce(0) { $0 + $1.durationMinutes }
        let rem = ordered.filter { $0.stage == .rem }.reduce(0) { $0 + $1.durationMinutes }
        let core = ordered.filter { $0.stage == .core }.reduce(0) { $0 + $1.durationMinutes }
        return "深睡 \(deep)分 · REM \(rem)分 · 核心 \(core)分"
    }
}


private struct CommunitySleepColors: SleepStageColorProvider {
    func color(for stage: SleepChartKit.SleepStage) -> Color {
        switch stage {
        case .awake: BevelTheme.sleepStageColor(.awake)
        case .asleepREM: BevelTheme.sleepStageColor(.rem)
        case .asleepCore: BevelTheme.sleepStageColor(.core)
        case .asleepDeep: BevelTheme.sleepStageColor(.deep)
        case .asleepUnspecified, .inBed: BevelTheme.inkSecondary
        }
    }
}
