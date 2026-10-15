import SwiftData
import SwiftUI

enum TrainingTargetComparison: Equatable {
    case unavailable
    case below(Int)
    case withinTarget
    case above(Int)

    static func evaluate(strainValues: [Double], target: MetricResult) -> Self {
        guard target.hasData,
              strainValues.count >= 3,
              let lower = target.components["recommended_lower"],
              let upper = target.components["recommended_upper"],
              upper >= lower else {
            return .unavailable
        }

        let targetMidpoint = (lower + upper) / 2
        guard targetMidpoint > 0 else { return .unavailable }
        let average = strainValues.reduce(0, +) / Double(strainValues.count)
        let percent = Int(((average - targetMidpoint) / targetMidpoint * 100).rounded())

        if abs(percent) <= 5 { return .withinTarget }
        return percent < 0 ? .below(abs(percent)) : .above(percent)
    }

    var valueText: String {
        switch self {
        case .unavailable: return "--"
        case let .below(percent): return "低 \(percent)%"
        case .withinTarget: return "接近目标"
        case let .above(percent): return "高 \(percent)%"
        }
    }

    var contextText: String {
        switch self {
        case .unavailable: return "目标范围待计算"
        case .below: return "低于个人目标中值"
        case .withinTarget: return "处于个人目标范围"
        case .above: return "高于个人目标中值"
        }
    }

    var tint: Color {
        switch self {
        case .unavailable: return VelaTheme.rhythmInkSecondary
        case .below: return VelaTheme.rhythmDeep
        case .withinTarget: return VelaTheme.rhythmGlow
        case .above: return VelaTheme.rhythmWarm
        }
    }
}

enum CardioLoadStatus: String, Equatable {
    case building
    case maintaining
    case easing
    case spike

    var title: String {
        switch self {
        case .building: "逐步提升"
        case .maintaining: "维持"
        case .easing: "负荷回落"
        case .spike: "短期陡增"
        }
    }
}

struct CardioTrainingSnapshot: Equatable {
    var acuteMinutes: Int
    var baselineWeeklyMinutes: Int?
    var loadRatio: Double?
    var status: CardioLoadStatus?
    var focus: String?
    var cardioSessions: Int
    var heartRateCoverage: Int
    var heartRateRecoveryBPM: Double?
}

enum CardioTrainingAnalyzer {
    static func analyze(
        workouts: [WorkoutSummary],
        endingAt endDate: Date,
        heartRateRecoverySamples: [Double] = [],
        calendar: Calendar = .current
    ) -> CardioTrainingSnapshot {
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        let acuteStart = calendar.date(byAdding: .day, value: -7, to: end) ?? end.addingTimeInterval(-7 * 86_400)
        let baselineStart = calendar.date(byAdding: .day, value: -28, to: end) ?? end.addingTimeInterval(-28 * 86_400)
        let cardio = workouts.filter {
            $0.start >= baselineStart && $0.start < end && isCardio($0.activityName) && $0.end > $0.start
        }
        let acute = cardio.filter { $0.start >= acuteStart }
        let baseline = cardio.filter { $0.start < acuteStart }
        let acuteMinutes = Int(acute.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        let baselineMinutes = Int(baseline.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        let baselineWeekly = baseline.count >= 3 ? Int((Double(baselineMinutes) / 3).rounded()) : nil
        let ratio: Double? = {
            guard let baselineWeekly, baselineWeekly > 0, !acute.isEmpty else { return nil }
            return Double(acuteMinutes) / Double(baselineWeekly)
        }()
        let status = ratio.map { value -> CardioLoadStatus in
            switch value {
            case ..<0.75: .easing
            case 0.75..<1.15: .maintaining
            case 1.15...1.5: .building
            default: .spike
            }
        }
        let focus = Dictionary(grouping: acute, by: { focusName($0.activityName) })
            .mapValues { sessions in sessions.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } }
            .max(by: { $0.value < $1.value })?.key
        let sourcedRecovery = heartRateRecoverySamples.isEmpty
            ? acute.compactMap(\.heartRateRecoveryOneMinuteBPM)
            : heartRateRecoverySamples
        let validRecovery = sourcedRecovery.filter { $0.isFinite && $0 >= 0 && $0 <= 120 }.sorted()
        let recovery: Double? = validRecovery.count >= 3 ? median(validRecovery) : nil

        return CardioTrainingSnapshot(
            acuteMinutes: acuteMinutes,
            baselineWeeklyMinutes: baselineWeekly,
            loadRatio: ratio,
            status: status,
            focus: focus,
            cardioSessions: acute.count,
            heartRateCoverage: acute.filter { $0.averageHeartRate != nil }.count,
            heartRateRecoveryBPM: recovery
        )
    }

    private static func isCardio(_ name: String) -> Bool {
        let value = name.lowercased()
        let excluded = ["strength", "力量", "weight", "yoga", "瑜伽", "flexibility", "mobility"]
        if excluded.contains(where: value.contains) { return false }
        let included = [
            "run", "跑", "walk", "步行", "hiking", "徒步", "cycle", "cycling", "骑行",
            "swim", "游泳", "row", "划船", "elliptical", "椭圆", "cardio", "有氧",
            "soccer", "football", "basketball", "dance", "舞蹈", "stair", "爬楼",
            // [8] 修复：HIIT/Cross Training/Mixed Cardio 此前漏出有氧统计。
            "hiit", "interval", "间歇", "cross training", "crossfit", "mixed cardio",
            "mixed", "混合", "跳绳", "jump rope"
        ]
        return included.contains(where: value.contains)
    }

    private static func focusName(_ name: String) -> String {
        let value = name.lowercased()
        if value.contains("run") || value.contains("跑") { return "跑步" }
        if value.contains("walk") || value.contains("步行") || value.contains("hiking") || value.contains("徒步") { return "步行 / 徒步" }
        if value.contains("cycle") || value.contains("骑行") { return "骑行" }
        if value.contains("swim") || value.contains("游泳") { return "游泳" }
        if value.contains("row") || value.contains("划船") { return "划船" }
        return "综合有氧"
    }

    private static func median(_ values: [Double]) -> Double {
        let middle = values.count / 2
        return values.count.isMultiple(of: 2)
            ? (values[middle - 1] + values[middle]) / 2
            : values[middle]
    }
}

struct CardioStatusCard: View {
    let snapshot: CardioTrainingSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("有氧状态", systemImage: "heart.circle")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text("最近 7 天")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            HStack(spacing: 8) {
                cardioMetric("有氧负荷", snapshot.cardioSessions == 0 ? "—" : "\(snapshot.acuteMinutes) 分", detail: baselineDetail)
                cardioMetric("有氧状态", snapshot.status?.title ?? "校准中", detail: statusDetail)
            }
            HStack(spacing: 8) {
                cardioMetric("有氧重点", snapshot.focus ?? "—", detail: snapshot.focus == nil ? "暂无有氧训练" : "按训练时长最多")
                cardioMetric("心率恢复", snapshot.heartRateRecoveryBPM.map { "\(Int($0.rounded())) bpm" } ?? "—", detail: recoveryDetail)
            }

            if snapshot.loadRatio.map({ $0 > 1.5 }) == true {
                Label("短期有氧时长明显高于前三周基线；结合恢复与身体感受决定是否降量。", systemImage: "exclamationmark.triangle.fill")
                    .font(VelaTheme.caption2())
                    .foregroundStyle(VelaTheme.warn)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
    }

    private var baselineDetail: String {
        guard let baseline = snapshot.baselineWeeklyMinutes else { return "需前三周至少 3 次" }
        return "前三周均值 \(baseline) 分/周"
    }

    private var statusDetail: String {
        guard let ratio = snapshot.loadRatio else { return "基线不足，不作判断" }
        return "7 天 / 基线 \(String(format: "%.2f", ratio))×"
    }

    private var recoveryDetail: String {
        snapshot.heartRateRecoveryBPM == nil
            ? "需至少 3 次训练后心率下降样本"
            : "训练后 1 分钟下降中位数"
    }

    private func cardioMetric(_ title: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Text(value)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
            Text(detail)
                .font(.system(.caption2, design: .default))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(2)
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(VelaTheme.rhythmMist.opacity(0.62), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct TrainingStatsSection: View {
    @Binding var selectedAnalyticsTab: Int
    let targetComparison: TrainingTargetComparison
    let dynamicExertionWorkload: [Double]
    /// 与 dynamicExertionWorkload 同序的真实耗力分数与日期（标注/拖动交互显示）。
    let exertionValues: [Double]
    let exertionDates: [Date]
    let totalWorkoutDurationText: String
    let summaryWorkPathPoints: [CGPoint]
    /// 与 summaryWorkPathPoints 同序的真实耗力分数与日期（拖动交互显示）。
    let summaryWorkValues: [Double]
    let summaryWorkDates: [Date]
    let summaryPeakStrainText: String
    let selectedDate: Date
    let dashboard: DashboardSummary
    let previousMonthActiveTiers: [Int: Int]
    let currentMonthActiveTiers: [Int: Int]

    private var currentMonthStart: Date {
        monthStart(for: selectedDate)
    }

    private var previousMonthStart: Date {
        Calendar.current.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
    }

    private func monthStart(for date: Date) -> Date {
        let components = Calendar.current.dateComponents([.year, .month], from: date)
        return Calendar.current.date(from: components) ?? date
    }

    private func monthTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: date)
    }

    private func dayCount(in date: Date) -> Int {
        Calendar.current.range(of: .day, in: .month, for: date)?.count ?? 0
    }

    private func startOffset(for date: Date) -> Int {
        Calendar.current.component(.weekday, from: date) - 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: selectedAnalyticsTab == 0 ? "bolt.heart.fill" : (selectedAnalyticsTab == 1 ? "chart.bar.fill" : "calendar"))
                        .font(.system(size: 14))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    Text("表现与分析")
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                }
                Spacer()
                
                Picker("", selection: $selectedAnalyticsTab) {
                    Text("负荷").tag(0)
                    Text("趋势").tag(1)
                    Text("热力").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            Divider()

            switch selectedAnalyticsTab {
            case 0:
                if dynamicExertionWorkload.isEmpty {
                    compactEmptyState(
                        icon: "waveform.path.ecg",
                        title: "负荷趋势将在训练后出现",
                        detail: "完成或同步一次训练，即可开始建立个人目标范围。"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(targetComparison.valueText)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            Text(dynamicExertionWorkload.isEmpty ? "暂无耗力记录" : targetComparison.contextText)
                                .font(.system(.caption, design: .default, weight: .bold))
                                .foregroundStyle(targetComparison.tint)
                        }
                        Spacer()
                        NavigationLink(destination: VelaMetricDetailView(
                            metric: .strain,
                            selectedDate: selectedDate,
                            dashboardSnapshot: dashboard
                        )) {
                            HStack(spacing: 4) {
                                  Text("详情")
                                  Image(systemName: "chevron.right")
                            }
                            .font(.system(.caption, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                        }
                        .buttonStyle(.cardPress)
                    }
                    
                    SafeZoneWorkloadChartView(
                        workload: dynamicExertionWorkload,
                        showsTargetZone: targetComparison != .unavailable,
                        values: exertionValues,
                        dates: exertionDates
                    )
                        .frame(height: 72)
                        .padding(.vertical, 4)
                    }
                }
            case 1:
                if summaryWorkPathPoints.isEmpty || totalWorkoutDurationText == "--" {
                    compactEmptyState(
                        icon: "chart.line.uptrend.xyaxis",
                        title: "还没有可分析的趋势",
                        detail: "积累几次训练后，这里会显示 30 天训练量变化。"
                    )
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(totalWorkoutDurationText)
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(VelaTheme.rhythmInk)
                            Text("过去 30 天耗力趋势")
                                .font(.system(.caption, design: .default, weight: .medium))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }
                        Spacer()
                        NavigationLink(destination: FitnessActivitySummaryDetailView()) {
                            HStack(spacing: 4) {
                                Text("分析")
                                Image(systemName: "chevron.right")
                            }
                            .font(.system(.caption, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                        }
                        .buttonStyle(.cardPress)
                    }
                    
                    ZStack(alignment: .topTrailing) {
                        AreaChartCurveView(
                            points: summaryWorkPathPoints,
                            values: summaryWorkValues,
                            dates: summaryWorkDates
                        )
                            .frame(height: 100)
                            .padding(.top, 10)
                        
                        Text(summaryPeakStrainText)
                            .font(.system(.caption2, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .offset(y: -4)
                        
                        HStack {
                            Text("30天前")
                            Spacer()
                            Text("15天前")
                            Spacer()
                            Text("今天")
                        }
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .padding(.top, 114)
                    }
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        monthHeatmap(
                            monthTitle: monthTitle(for: previousMonthStart),
                            totalDays: dayCount(in: previousMonthStart),
                            startOffset: startOffset(for: previousMonthStart),
                            activeTiers: previousMonthActiveTiers
                        )
                        
                        monthHeatmap(
                            monthTitle: monthTitle(for: currentMonthStart),
                            totalDays: dayCount(in: currentMonthStart),
                            startOffset: startOffset(for: currentMonthStart),
                            activeTiers: currentMonthActiveTiers
                        )
                    }
                    
                    HStack(spacing: 12) {
                        legendItem(color: VelaTheme.rhythmGlow.opacity(0.55), label: "1 项活动")
                        legendItem(color: VelaTheme.rhythmGlow, label: "2 项活动")
                        legendItem(color: VelaTheme.rhythmDeep, label: "3+ 活动")
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(VelaTheme.rhythmCanvasRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
    }

    private func compactEmptyState(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 36, height: 36)
                .background(VelaTheme.rhythmDeep.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(VelaTheme.subheadline().weight(.semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(detail)
                    .font(VelaTheme.footnote())
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineSpacing(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private func monthHeatmap(
        monthTitle: String,
        totalDays: Int,
        startOffset: Int,
        activeTiers: [Int: Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(monthTitle)
                .font(.system(.footnote, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            
            // Grid Header Days
            HStack(spacing: 5) {
                ForEach(["日", "一", "二", "三", "四", "五", "六"], id: \.self) { d in
                    Text(d)
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.8))
                        .frame(width: 16)
                }
            }
            
            // Grid Cells
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(16), spacing: 5), count: 7),
                spacing: 5
            ) {
                // Empty padding offset cells
                ForEach((0..<startOffset).map { "padding-\($0)" }, id: \.self) { _ in
                    Color.clear
                        .frame(width: 16, height: 16)
                }
                
                // Active calendar days
                ForEach(1...totalDays, id: \.self) { day in
                    let tier = activeTiers[day] ?? 0
                    let cellColor: Color = {
                        switch tier {
                        case 1:  return VelaTheme.rhythmGlow.opacity(0.55) // 轻度
                        case 2:  return VelaTheme.rhythmGlow // 中度
                        case 3:  return VelaTheme.rhythmDeep // 高强度
                        default: return VelaTheme.rhythmMist.opacity(0.7) // 无训练
                        }
                    }()
                    
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .fill(cellColor)
                        .frame(width: 16, height: 16)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            
            Text(label)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
    }
}

struct MuscleVolumeCard: View {
    let summary: RecentTrainingSummary
    let exerciseProgressLines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("过去 7 天肌群有效组")
                    .font(.system(.subheadline, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text("\(summary.sessions) 次力量训练")
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            
            if summary.muscleGroupSets.isEmpty {
                Text("完成力量训练后，这里会显示肌群训练量与局部疲劳。")
                    .font(.system(.caption, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 10) {
                    ForEach(summary.muscleGroupSets.sorted { $0.value > $1.value }, id: \.key) { muscle, sets in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(localizedMuscleGroup(muscle))
                                    .font(.system(.caption, design: .default, weight: .semibold))
                                    .foregroundStyle(VelaTheme.rhythmInk)
                                Spacer()
                                Text("\(sets) 组")
                                    .font(.system(.caption2, design: .default, weight: .bold))
                                    .foregroundStyle(sets >= 18 ? VelaTheme.textColor(for: .poor) : (sets < 6 ? VelaTheme.rhythmDeep : VelaTheme.rhythmGlow))
                            }
                            
                            GeometryReader { geo in
                                let pct = min(CGFloat(sets) / 20.0, 1.0)
                                let barColor = sets >= 18 ? VelaTheme.statePoor : (sets < 6 ? VelaTheme.rhythmDeep : VelaTheme.rhythmGlow)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(VelaTheme.rhythmMist)
                                        .frame(height: 6)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(barColor)
                                        .frame(width: geo.size.width * pct, height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                    }
                }
            }
            
            if !summary.recentPRs.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("近期 PR")
                        .font(.system(.caption2, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    Text(summary.recentPRs.prefix(3).map(\.summary).joined(separator: " · "))
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                }
            }
            
            if let latest = summary.lastWorkoutSummary {
                Divider()
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.left")
                        .font(.caption2)
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    Text("最近一次：\(latest)")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
            }
            
            if !exerciseProgressLines.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("常练动作进步")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    ForEach(exerciseProgressLines.prefix(3), id: \.self) { line in
                        Text("• \(line)")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(VelaTheme.rhythmCanvasRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
    }
}

/// 个人纪录卡：窗口内去重后的真实 PR（动作 × 类型保留最高值）。
struct PersonalRecordsCard: View {
    let records: [PersonalRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("个人纪录", systemImage: "trophy")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text(records.isEmpty ? "" : "\(records.count) 项")
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            if records.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "trophy")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text("打破此前重量或次数后，个人纪录会出现在这里。")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                .padding(.vertical, 6)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(records.prefix(5).enumerated()), id: \.element.id) { index, record in
                        recordRow(record)
                        if index < min(records.count, 5) - 1 {
                            Rectangle()
                                .fill(VelaTheme.rhythmMist)
                                .frame(height: 0.75)
                                .padding(.leading, 12)
                        }
                    }
                    if records.count > 5 {
                        Text("另有 \(records.count - 5) 项纪录")
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .padding(.top, 9)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(VelaTheme.rhythmCanvasRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        )
    }

    private func recordRow(_ record: PersonalRecord) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(VelaTheme.rhythmDeep)
                .frame(width: 6, height: 6)
            Text(record.exerciseName)
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(kindLabel(record.kind))
                .font(.system(.caption2, design: .default, weight: .medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
            Text(valueText(record))
                .font(.system(.footnote, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(minWidth: 58, alignment: .trailing)
            if let previous = record.previousValue {
                Text("+\(Int((record.value - previous).rounded())) \(unit(record.kind))")
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(VelaTheme.rhythmDeep.opacity(0.12), in: Capsule())
            }
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.exerciseName) \(kindLabel(record.kind)) \(valueText(record))")
    }

    private func kindLabel(_ kind: String) -> String {
        switch kind {
        case "max_weight": return "最大重量"
        case "estimated_1rm": return "估算 1RM"
        case "max_reps": return "最大次数"
        default: return kind
        }
    }

    private func unit(_ kind: String) -> String {
        kind == "max_reps" ? "次" : "kg"
    }

    private func valueText(_ record: PersonalRecord) -> String {
        record.value.formatted(.number.precision(.fractionLength(0...1))) + " \(unit(record.kind))"
    }
}

struct RecentWorkoutsSection: View {
    let recentWorkouts: [WorkoutSummary]
    var limit: Int? = 12
    var strengthWorkout: (WorkoutSummary) -> StrengthWorkoutRecord?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("训练记录")
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
            }

            if recentWorkouts.isEmpty {
                Text("暂无可读取的训练记录")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
            } else {
                ForEach(recentWorkouts.prefix(limit ?? recentWorkouts.count)) { workout in
                    NavigationLink(destination: destination(for: workout)) {
                        workoutRow(workout)
                    }
                    .buttonStyle(.cardPress)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for workout: WorkoutSummary) -> some View {
        if let strength = strengthWorkout(workout) {
            StrengthWorkoutDetailView(workout: strength)
        } else {
            WorkoutDetailView(workout: workout)
        }
    }

    private func workoutRow(_ workout: WorkoutSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: workoutListIcon(workout.activityName))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 38, height: 38)
                .background(VelaTheme.rhythmMist.opacity(0.6), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(workout.activityName)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                HStack(spacing: 6) {
                    Text(sourceLabel(for: workout.source))
                    Text("·")
                    Text("\(Int(workout.end.timeIntervalSince(workout.start) / 60)) 分钟")
                    if let kcal = workout.energyKilocalories {
                        Text("·")
                        Text("\(Int(kcal.rounded())) kcal")
                    }
                    if let hr = workout.averageHeartRate {
                        Text("·")
                        Text("\(Int(hr.rounded())) bpm")
                    }
                    if let distance = workout.distanceMeters, distance > 0 {
                        Text("·")
                        Text(distance >= 1_000
                             ? String(format: "%.1f km", distance / 1_000)
                             : "\(Int(distance.rounded())) m")
                    }
                }
                .font(.system(.caption2, design: .default, weight: .medium))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay {
            RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous)
                .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
        }
    }

    private func workoutListIcon(_ name: String) -> String {
        let lowered = name.lowercased()
        if lowered.contains("strength") || lowered.contains("力量") || lowered.contains("weight") {
            return "figure.strengthtraining.traditional"
        }
        if lowered.contains("walk") || lowered.contains("步行") {
            return "figure.walk"
        }
        if lowered.contains("cycle") || lowered.contains("骑行") {
            return "figure.outdoor.cycle"
        }
        if lowered.contains("swim") || lowered.contains("游泳") {
            return "figure.pool.swim"
        }
        return "figure.run"
    }

    private func sourceLabel(for source: String?) -> String {
        switch source {
        case "healthKit+xunji":
            return "Apple + 训记"
        case "xunji":
            return "训记"
        case "strengthLog":
            return "力量"
        case "manual":
            return "手动"
        default:
            return "Apple"
        }
    }
}

struct StrengthWorkoutsSection: View {
    let strengthWorkouts: [StrengthWorkoutRecord]
    let startStrengthWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("力量训练记录")
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Button {
                    startStrengthWorkout()
                } label: {
                    Label("记录力量", systemImage: "plus")
                        .font(.system(.caption, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(VelaTheme.rhythmCanvasRaised))
                }
                .buttonStyle(.plain)
            }

            if strengthWorkouts.isEmpty {
                Text("尚未记录力量训练。完成一次动作与组次记录后，Coach 就能读取容量历史。")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
            } else {
                ForEach(strengthWorkouts.prefix(5)) { workout in
                    NavigationLink(destination: WorkoutDetailView(workout: WorkoutSummary(
                        id: workout.id,
                        start: workout.startedAt,
                        end: workout.startedAt.addingTimeInterval(TimeInterval(workout.durationMinutes * 60)),
                        activityName: workout.title,
                        source: "strengthLog"
                    ))) {
                        HStack(spacing: 12) {
                            Image(systemName: "figure.strengthtraining.traditional")
                                .font(.system(size: 18))
                                .foregroundStyle(VelaTheme.rhythmDeep)
                                .frame(width: 38, height: 38)
                                .background(Circle().fill(VelaTheme.rhythmMist))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(workout.title)
                                    .font(.system(.footnote, design: .default, weight: .bold))
                                    .foregroundStyle(VelaTheme.rhythmInk)
                                Text("\(workout.exerciseCount) 个动作 · \(workout.totalSetCount) 组 · \(Int(workout.totalVolumeKilograms.rounded())) kg 容量")
                                    .font(.system(.caption2, design: .default))
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                                Text(workout.startedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(.caption2, design: .default))
                                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusLg, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Safe-zone workload chart helpers
struct SafeZoneWorkloadChartView: View {
    let workload: [Double]
    let showsTargetZone: Bool
    /// 真实耗力分数与日期（可选）：提供后支持点按标数值 + 拖动查看。
    var values: [Double]? = nil
    var dates: [Date]? = nil

    @State private var showLabels = false
    @State private var scrubIndex: Int?

    private var canInteract: Bool {
        guard let values else { return false }
        return values.count == workload.count && workload.count > 1
    }

    private func pointX(_ index: Int, width: CGFloat) -> CGFloat {
        workload.count > 1 ? CGFloat(index) / CGFloat(workload.count - 1) * width : 0
    }

    private func pointY(_ index: Int, height: CGFloat) -> CGFloat {
        height - (CGFloat(workload[index]) * (height - 8) + 4)
    }

    private func dateText(_ index: Int) -> String {
        guard let dates, dates.indices.contains(index) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: dates[index])
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Green-tinged horizontal safe-zone band
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        showsTargetZone
                            ? VelaTheme.rhythmDeep.opacity(0.16).opacity(0.8)
                            : VelaTheme.rhythmMist.opacity(0.8)
                    )
                    .frame(height: geo.size.height * 0.45)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)

                // Colored workload line
                Path { path in
                    guard workload.count > 1 else { return }
                    for idx in 0..<workload.count {
                        let x = pointX(idx, width: geo.size.width)
                        let y = pointY(idx, height: geo.size.height)
                        if idx == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    LinearGradient(
                        colors: [VelaTheme.recoveryColor, VelaTheme.strainColor, VelaTheme.rhythmDeep],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                )

                // Highlighting end node dot
                if let lastVal = workload.last {
                    let x = geo.size.width
                    let y = geo.size.height - (CGFloat(lastVal) * (geo.size.height - 8) + 4)
                    Circle()
                        .fill(VelaTheme.rhythmDeep)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(VelaTheme.rhythmCanvasRaised, lineWidth: 1.5))
                        .position(x: x, y: y)
                }

                // 数值标注模式：点一下曲线显示每个数据点数值 + 最高/最低图例
                if showLabels, canInteract, let values {
                    ForEach(0..<workload.count, id: \.self) { index in
                        Text("\(Int(values[index].rounded()))")
                            .font(.system(size: 7.5, weight: .medium, design: .rounded))
                            .foregroundStyle(VelaTheme.rhythmInkSecondary)
                            .position(
                                x: min(geo.size.width - 14, pointX(index, width: geo.size.width) + 6),
                                y: max(9, pointY(index, height: geo.size.height) - 6)
                            )
                    }

                    HStack(spacing: 8) {
                        Label("最高 \(Int((values.max() ?? 0).rounded()))", systemImage: "arrow.up")
                        Label("最低 \(Int((values.min() ?? 0).rounded()))", systemImage: "arrow.down")
                    }
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(VelaTheme.rhythmInk)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(VelaTheme.rhythmCanvasRaised.opacity(0.95), in: Capsule())
                    .shadow(color: VelaTheme.rhythmDeep.opacity(0.25), radius: 5)
                    .position(x: geo.size.width - 68, y: 14)
                }

                // 拖动查看：日期 · 真实耗力分数
                if canInteract, let values, let scrubIndex, values.indices.contains(scrubIndex) {
                    let x = pointX(scrubIndex, width: geo.size.width)
                    let y = pointY(scrubIndex, height: geo.size.height)
                    Circle()
                        .fill(VelaTheme.rhythmDeep)
                        .frame(width: 8, height: 8)
                        .position(x: x, y: y)
                    Text("\(dateText(scrubIndex)) · \(Int(values[scrubIndex].rounded()))")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(VelaTheme.rhythmCanvasRaised.opacity(0.95), in: Capsule())
                        .shadow(color: VelaTheme.rhythmDeep.opacity(0.25), radius: 5)
                        .position(
                            x: min(geo.size.width - 46, max(46, x)),
                            y: max(13, y - 16)
                        )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { gesture in
                        guard canInteract, geo.size.width > 0 else { return }
                        let fraction = min(1, max(0, gesture.location.x / geo.size.width))
                        scrubIndex = Int((fraction * CGFloat(workload.count - 1)).rounded())
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                            scrubIndex = nil
                        }
                    }
            )
            .simultaneousGesture(
                TapGesture()
                    .onEnded {
                        guard canInteract else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            showLabels.toggle()
                        }
                    }
            )
        }
    }
}

// MARK: - Yearly training aggregate（历年训练量）

/// 按年聚合训练事实。输入是已经解码的日快照，不读取 SwiftData 行。
enum YearlyTrainingAggregator {
    struct YearStats: Equatable {
        var year: Int
        var trainingDays: Int     // 有训练的天数
        var workoutCount: Int
        var totalMinutes: Double
        var totalCalories: Double
    }

    static func aggregate(
        snapshots: [DailyHealthSnapshot],
        calendar: Calendar = .current
    ) -> [YearStats] {
        var byYear: [Int: YearStats] = [:]
        for snapshot in snapshots {
            let count = snapshot.workoutCount ?? 0
            let duration = snapshot.workoutDuration ?? 0
            // 训练日只看训练次数和时长。全天活动能耗不是训练。
            guard count > 0 || duration > 0 else { continue }
            // 训练消耗来自日快照里已经解码的训练记录。没有训练记录时为 0。
            let workoutEnergy = snapshot.workouts.compactMap(\.energyKilocalories).reduce(0, +)
            let year = calendar.component(.year, from: snapshot.date)
            var stats = byYear[year] ?? YearStats(
                year: year, trainingDays: 0, workoutCount: 0,
                totalMinutes: 0, totalCalories: 0
            )
            stats.trainingDays += 1
            stats.workoutCount += count
            stats.totalMinutes += duration
            stats.totalCalories += workoutEnergy
            byYear[year] = stats
        }
        return byYear.values.sorted { $0.year < $1.year }
    }
}

struct YearlyTrainingCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stats: [YearlyTrainingAggregator.YearStats] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("历年训练量", systemImage: "calendar")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text("Apple 健康历史")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            if stats.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "calendar")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmDeep)
                    Text("回填 Apple 健康历史后，这里会出现每年的训练天数、总时长与消耗。")
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
            } else {
                let maxMinutes = stats.map(\.totalMinutes).max() ?? 1
                VStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.element.year) { index, year in
                        yearRow(year, maxMinutes: maxMinutes)
                        if index < stats.count - 1 {
                            Rectangle()
                                .fill(VelaTheme.rhythmMist)
                                .frame(height: 0.75)
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
        .task { await load() }
    }

    private func load() async {
        let snapshots = (try? HealthSnapshotRepository(modelContext: modelContext).fetchAllSnapshots()) ?? []
        stats = YearlyTrainingAggregator.aggregate(snapshots: snapshots)
    }

    private func yearRow(_ year: YearlyTrainingAggregator.YearStats, maxMinutes: Double) -> some View {
        HStack(spacing: 12) {
            Text("\(year.year)")
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInk)
                .frame(width: 44, alignment: .leading)

            GeometryReader { proxy in
                let ratio = min(1, CGFloat(year.totalMinutes) / CGFloat(max(maxMinutes, 1)))
                ZStack(alignment: .leading) {
                    Capsule().fill(VelaTheme.rhythmMist).frame(height: 6)
                    Capsule().fill(VelaTheme.rhythmDeep)
                        .frame(width: max(5, proxy.size.width * ratio), height: 6)
                }
            }
            .frame(height: 6)

            VStack(alignment: .trailing, spacing: 2) {
                Text("\(year.trainingDays) 天 · \(Int(year.totalMinutes / 60)) 小时")
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text("\(year.workoutCount) 次 · \(Int(year.totalCalories.rounded())) kcal")
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }
            .frame(width: 108, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(year.year) 年，训练 \(year.trainingDays) 天，共 \(year.workoutCount) 次，\(Int(year.totalMinutes / 60)) 小时")
    }
}

// MARK: - Recovery / Strain / Stress Trend Card

/// 深入分析页的恢复、负荷、压力 30 天趋势卡。
/// 三个指标使用同一批日快照，不重算、不换窗；
/// 点击任一行进入对应指标详情（那里还有更长窗口与证据分解）。
struct RecoveryLoadStressTrendsCard: View {
    let records: [DailyHealthSnapshot]
    let selectedDate: Date
    let dashboard: DashboardSummary

    private struct TrendSeries: Identifiable {
        let id: String
        let title: String
        let metric: VelaMetricDetailView.MetricType
        let color: Color
        let values: [Double]
        let dates: [Date]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Label("恢复 · 负荷 · 压力趋势", systemImage: "chart.xyaxis.line")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Spacer()
                Text("最近 30 天")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            VStack(spacing: 0) {
                ForEach(Array(series.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(destination: VelaMetricDetailView(
                        metric: item.metric,
                        selectedDate: selectedDate,
                        dashboardSnapshot: dashboard
                    )) {
                        trendRow(item)
                    }
                    .buttonStyle(.plain)

                    if index < series.count - 1 {
                        Rectangle()
                            .fill(VelaTheme.rhythmMist)
                            .frame(height: 0.75)
                            .padding(.leading, 12)
                    }
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
    }

    private var series: [TrendSeries] {
        [
            TrendSeries(
                id: "recovery",
                title: "恢复",
                metric: .recovery,
                color: VelaTheme.recoveryColor,
                values: metricValues(\.recoveryScore),
                dates: metricDates(\.recoveryScore)
            ),
            TrendSeries(
                id: "strain",
                title: "负荷",
                metric: .strain,
                color: VelaTheme.strainColor,
                values: metricValues(\.strainScore),
                dates: metricDates(\.strainScore)
            ),
            TrendSeries(
                id: "stress",
                title: "压力",
                metric: .stress,
                color: VelaTheme.stressColor,
                values: metricValues(\.stressIndex),
                dates: metricDates(\.stressIndex)
            )
        ]
    }

    private func trendRow(_ item: TrendSeries) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text(latestText(item.values))
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(item.color)
                        .monospacedDigit()
                }
                Text(item.values.isEmpty ? "暂无评分记录" : "\(item.values.count) 天有记录")
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
            }

            Spacer(minLength: 8)

            if item.values.count > 1 {
                AreaChartCurveView(
                    points: normalizedPoints(item.values),
                    values: item.values,
                    dates: item.dates
                )
                .frame(width: 148, height: 40)
            } else {
                Capsule()
                    .fill(VelaTheme.rhythmMist)
                    .frame(width: 148, height: 1.5)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary.opacity(0.7))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title) 趋势，最新 \(latestText(item.values))，\(item.values.count) 天有记录")
    }

    private func metricValues(_ keyPath: KeyPath<DailyHealthSnapshot, Double?>) -> [Double] {
        records.compactMap { $0[keyPath: keyPath] }
    }

    private func metricDates(_ keyPath: KeyPath<DailyHealthSnapshot, Double?>) -> [Date] {
        records.compactMap { record in
            record[keyPath: keyPath] == nil ? nil : record.date
        }
    }

    private func normalizedPoints(_ values: [Double]) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let minValue = values.min() ?? 0
        let maxValue = values.max() ?? 0
        let span = max(maxValue - minValue, 1)
        return values.enumerated().map { index, value in
            let x = Double(index) / Double(values.count - 1)
            let y = 0.86 - (value - minValue) / span * 0.70
            return CGPoint(x: x, y: y)
        }
    }

    private func latestText(_ values: [Double]) -> String {
        guard let latest = values.last else { return "--" }
        return "\(Int(latest.rounded()))"
    }
}
