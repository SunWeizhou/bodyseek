import Charts
import Foundation
import SwiftData
import SwiftUI

struct CorrelationArtifactPoint: Identifiable, Hashable {
    var id: String
    var date: Date
    var x: Double
    var y: Double
}

struct CorrelationArtifactAnalysis: Hashable {
    var points: [CorrelationArtifactPoint]
    var correlation: Double
    var lagDays: Int
    var predictedY: Double?
    var isBinaryX: Bool
    var isBinaryY: Bool
}

struct CorrelationArtifactOutcome: Hashable {
    var analysis: CorrelationArtifactAnalysis?
    var reason: String
}

enum CorrelationArtifactAnalyzer {
    private static let knownHealthMetrics: Set<String> = [
        "hrv", "resting_hr", "rhr", "sleep", "sleep_score", "sleep_hours",
        "recovery", "recovery_score", "strain", "strain_score", "stress",
        "stress_index", "energy", "energy_bank", "steps", "active_calories"
    ]

    static func analyze(
        metricX: String,
        metricY: String,
        snapshots: [DailyHealthSnapshot],
        journalEntries: [JournalEntryRecord],
        endingAt endDate: Date = Date(),
        calendar: Calendar = .current
    ) -> CorrelationArtifactOutcome {
        let xKey = normalize(metricX)
        let yKey = normalize(metricY)
        let isBinaryX = !knownHealthMetrics.contains(xKey)
        let isBinaryY = !knownHealthMetrics.contains(yKey)
        let startDate = calendar.date(byAdding: .day, value: -90, to: calendar.startOfDay(for: endDate)) ?? endDate.addingTimeInterval(-90 * 86_400)
        let recentSnapshots = snapshots.filter { $0.date >= startDate && $0.date <= endDate }
        var snapshotsByDay: [String: DailyHealthSnapshot] = [:]
        for snapshot in recentSnapshots.sorted(by: { $0.date < $1.date }) {
            snapshotsByDay[dayKey(snapshot.date, calendar: calendar)] = snapshot
        }
        let tagsByDay = Dictionary(grouping: journalEntries.filter { $0.createdAt >= startDate }) {
            dayKey($0.createdAt, calendar: calendar)
        }.mapValues { Set($0.flatMap(\.tags).map(normalize)) }

        var candidates: [CorrelationArtifactAnalysis] = []
        for lag in 0...1 {
            var points: [CorrelationArtifactPoint] = []
            for source in recentSnapshots.sorted(by: { $0.date < $1.date }) {
                let sourceDate = calendar.startOfDay(for: source.date)
                guard let targetDate = calendar.date(byAdding: .day, value: lag, to: sourceDate),
                      let target = snapshotsByDay[dayKey(targetDate, calendar: calendar)] else { continue }
                let sourceTags = tagsByDay[dayKey(sourceDate, calendar: calendar)] ?? []
                let targetTags = tagsByDay[dayKey(targetDate, calendar: calendar)] ?? []
                guard let x = value(for: xKey, snapshot: source, tags: sourceTags),
                      let y = value(for: yKey, snapshot: target, tags: targetTags) else { continue }
                points.append(CorrelationArtifactPoint(
                    id: "\(dayKey(sourceDate, calendar: calendar))-lag\(lag)",
                    date: sourceDate,
                    x: x,
                    y: y
                ))
            }

            let minimum = (isBinaryX || isBinaryY) ? 28 : 14
            guard points.count >= minimum else { continue }
            if isBinaryX {
                let exposed = points.filter { $0.x == 1 }.count
                guard exposed >= 8, points.count - exposed >= 8 else { continue }
            }
            if isBinaryY {
                let exposed = points.filter { $0.y == 1 }.count
                guard exposed >= 8, points.count - exposed >= 8 else { continue }
            }

            let correlation = JournalCorrelationEngine().spearmanCorrelation(
                points.map(\.x),
                points.map(\.y)
            )
            let prediction = (!isBinaryX && !isBinaryY && points.count >= 28 && abs(correlation) >= 0.35)
                ? linearPrediction(points: points)
                : nil
            candidates.append(CorrelationArtifactAnalysis(
                points: points,
                correlation: correlation,
                lagDays: lag,
                predictedY: prediction,
                isBinaryX: isBinaryX,
                isBinaryY: isBinaryY
            ))
        }

        guard let best = candidates.max(by: {
            let lhsMagnitude = abs($0.correlation)
            let rhsMagnitude = abs($1.correlation)
            if abs(lhsMagnitude - rhsMagnitude) < 0.000_001 {
                return $0.points.count < $1.points.count
            }
            return lhsMagnitude < rhsMagnitude
        }) else {
            let reason = (isBinaryX || isBinaryY)
                ? "行为关联至少需要 28 天配对数据，且记录日与对照日各至少 8 天。"
                : "双指标图至少需要 14 对同时可用的真实样本。"
            return CorrelationArtifactOutcome(analysis: nil, reason: reason)
        }
        return CorrelationArtifactOutcome(
            analysis: best,
            reason: "这是探索性相关分析，不代表因果关系或医学预测。"
        )
    }

    private static func value(
        for metric: String,
        snapshot: DailyHealthSnapshot,
        tags: Set<String>
    ) -> Double? {
        switch metric {
        case "hrv": snapshot.hrvAverage
        case "resting_hr", "rhr": snapshot.restingHeartRate
        case "sleep", "sleep_score": hasSleepSource(snapshot) ? snapshot.sleepScore : nil
        case "sleep_hours": (snapshot.sleepHours ?? 0) > 0 ? snapshot.sleepHours : nil
        case "recovery", "recovery_score": hasRecoverySource(snapshot) ? snapshot.recoveryScore : nil
        case "strain", "strain_score": hasActivitySource(snapshot) ? snapshot.strainScore : nil
        case "stress", "stress_index": (snapshot.hrvAverage != nil || snapshot.restingHeartRate != nil) ? snapshot.stressIndex : nil
        case "energy", "energy_bank": hasRecoverySource(snapshot) ? snapshot.energyBank : nil
        case "steps": snapshot.steps
        case "active_calories": snapshot.activeCalories
        default: tags.contains(metric) ? 1 : 0
        }
    }

    private static func hasSleepSource(_ snapshot: DailyHealthSnapshot) -> Bool {
        (snapshot.sleepHours ?? 0) > 0 || (snapshot.deepSleepMinutes ?? 0) > 0 || (snapshot.remSleepMinutes ?? 0) > 0
    }

    private static func hasRecoverySource(_ snapshot: DailyHealthSnapshot) -> Bool {
        snapshot.hrvAverage != nil || snapshot.restingHeartRate != nil || hasSleepSource(snapshot)
    }

    private static func hasActivitySource(_ snapshot: DailyHealthSnapshot) -> Bool {
        (snapshot.steps ?? 0) > 0 || (snapshot.activeCalories ?? 0) > 0 || (snapshot.workoutCount ?? 0) > 0
    }

    private static func linearPrediction(points: [CorrelationArtifactPoint]) -> Double? {
        guard let latestX = points.last?.x else { return nil }
        let meanX = points.map(\.x).reduce(0, +) / Double(points.count)
        let meanY = points.map(\.y).reduce(0, +) / Double(points.count)
        let denominator = points.reduce(0) { $0 + pow($1.x - meanX, 2) }
        guard denominator > 0 else { return nil }
        let numerator = points.reduce(0) { $0 + ($1.x - meanX) * ($1.y - meanY) }
        return meanY + (numerator / denominator) * (latestX - meanX)
    }

    private static func normalize(_ value: String) -> String {
        value.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "_")
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

struct CorrelationArtifactView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let key: String

    @Environment(\.modelContext) private var modelContext
    @State private var summaries: [DailyHealthSummaryRecord] = []
    @State private var journalEntries: [JournalEntryRecord] = []

    private var parsedMetrics: (x: String, y: String) {
        let parts = key.lowercased().components(separatedBy: "_vs_")
        guard parts.count == 2 else { return ("health_signal", "journal_tag") }
        return (parts[0], parts[1])
    }

    private var outcome: CorrelationArtifactOutcome {
        let metrics = parsedMetrics
        return CorrelationArtifactAnalyzer.analyze(
            metricX: metrics.x,
            metricY: metrics.y,
            snapshots: summaries.prefix(90).map { $0.toSnapshot() },
            journalEntries: Array(journalEntries.prefix(500))
        )
    }

    var body: some View {
        let metrics = parsedMetrics
        let result = outcome
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(VelaTheme.accent)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(VelaTheme.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("自定义关联图")
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                    Text(result.analysis.map { "n=\($0.points.count) · \($0.lagDays == 0 ? "当天" : "次日")" } ?? "样本门槛未满足")
                        .font(.system(.caption, design: .default))
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(VelaTheme.muted)
                }
                Spacer()
            }

            (dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))) {
                metricPill(displayName(metrics.x), color: color(metrics.x))
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(VelaTheme.muted)
                metricPill(displayName(metrics.y), color: color(metrics.y))
            }

            if let analysis = result.analysis {
                Chart(analysis.points) { point in
                    PointMark(x: .value(displayName(metrics.x), point.x), y: .value(displayName(metrics.y), point.y))
                        .foregroundStyle(color(metrics.x).opacity(0.72))
                }
                .frame(height: 150)
                .chartXAxisLabel(displayName(metrics.x))
                .chartYAxisLabel(displayName(metrics.y))

                HStack {
                    metricValue("Spearman ρ", String(format: "%+.2f", analysis.correlation))
                    metricValue("样本", "\(analysis.points.count)")
                    metricValue("滞后", analysis.lagDays == 0 ? "当天" : "+1 天")
                }
                if let predicted = analysis.predictedY {
                    Label("按当前 X 的探索性线性估计：Y ≈ \(String(format: "%.1f", predicted))。这不是临床预测。", systemImage: "waveform.path.ecg.rectangle")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.fg2)
                }
            } else {
                VelaStateCard(state: .partial, title: "暂不绘制趋势", message: result.reason)
            }

            Label("相关不等于因果；应结合样本量、时间滞后、同期生活变化和身体感受解读。", systemImage: "info.circle")
                .font(.system(.caption, design: .default))
                .foregroundStyle(VelaTheme.muted)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge).fill(VelaTheme.cardBg.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge).stroke(VelaTheme.hairline, lineWidth: VelaTheme.hairlineWidth))
        .accessibilityElement(children: .contain)
        .task {
            summaries = (try? SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
                .fetchAllSortedByDate(newestFirst: true)) ?? []
            journalEntries = (try? SwiftDataJournalRepository(modelContext: modelContext)
                .fetchAllSortedByCreatedAt(newestFirst: true)) ?? []
        }
    }

    private func metricValue(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(.subheadline, design: .rounded, weight: .bold))
            Text(title).font(.system(.caption2, design: .default)).foregroundStyle(VelaTheme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricPill(_ title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(title).font(VelaTheme.caption1().weight(.semibold)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Capsule().fill(color.opacity(0.10)))
    }

    private func color(_ metric: String) -> Color {
        switch metric {
        case "hrv", "recovery", "recovery_score": VelaTheme.rhythmInk
        case "sleep", "sleep_score", "sleep_hours": VelaTheme.rhythmInk
        case "strain", "strain_score", "steps": VelaTheme.rhythmInk
        case "stress", "stress_index", "alcohol", "late_meal": VelaTheme.rhythmInk
        case "energy", "energy_bank", "caffeine": VelaTheme.rhythmInk
        default: VelaTheme.accent
        }
    }

    private func displayName(_ metric: String) -> String {
        switch metric {
        case "hrv": "HRV"
        case "caffeine": "咖啡因"
        case "sleep", "sleep_score": "睡眠分"
        case "sleep_hours": "睡眠时长"
        case "meditation": "正念冥想"
        case "alcohol": "酒精摄入"
        case "steps": "步数"
        case "resting_hr", "rhr": "静息心率"
        case "stress", "stress_index": "压力指数"
        case "recovery", "recovery_score": "恢复分"
        case "strain", "strain_score": "负荷分"
        case "energy", "energy_bank": "能量"
        default: metric.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
