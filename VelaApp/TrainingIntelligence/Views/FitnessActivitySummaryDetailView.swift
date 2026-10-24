import SwiftUI
import SwiftData

struct FitnessActivitySummaryDetailView: View {
    let selectedDate: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    // P3-11 修复：此前无谓词 @Query 全量加载全表；改为按浏览日 35 天窗口拉取。
    @State private var records: [DailyHealthSummaryRecord] = []
    @State private var workoutEvents: [WorkoutEventRecord] = []

    private var recentRecords: [DailyHealthSummaryRecord] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDate))
            ?? selectedDate
        let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        return records.filter { $0.date >= start && $0.date < end }
    }

    private var activeDays: Int {
        recentRecords.filter {
            ($0.workoutCount ?? 0) > 0 || ($0.activeCalories ?? 0) > 0 || ($0.workoutDuration ?? 0) > 0
        }.count
    }

    private var workoutCount: Int {
        recentRecords.compactMap(\.workoutCount).reduce(0, +)
    }

    private var workoutMinutes: Int {
        Int(recentRecords.compactMap(\.workoutDuration).reduce(0, +).rounded())
    }

    private var activeCalories: Int {
        Int(recentRecords.compactMap(\.activeCalories).reduce(0, +).rounded())
    }

    private var averageStrain: Double? {
        let values = recentRecords.compactMap(\.strainScore)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var recentWorkoutEvents: [WorkoutEventRecord] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDate))
            ?? selectedDate
        let start = calendar.date(byAdding: .day, value: -30, to: end) ?? end
        return workoutEvents.filter { $0.startedAt >= start && $0.startedAt < end }
    }

    private var workoutHeartRates: [Double] {
        recentWorkoutEvents.compactMap(\.averageHeartRate)
    }

    private var averageWorkoutHeartRate: Double? {
        guard !workoutHeartRates.isEmpty else { return nil }
        return workoutHeartRates.reduce(0, +) / Double(workoutHeartRates.count)
    }

    private var maxWorkoutHeartRate: Double? {
        workoutHeartRates.max()
    }

    private var chartPoints: [CGPoint] {
        let values = recentRecords.compactMap(\.strainScore)
        guard values.count > 1 else { return [] }
        let low = values.min() ?? 0
        let high = values.max() ?? low
        let range = high - low
        return values.enumerated().map { index, value in
            let x = Double(index) / Double(max(values.count - 1, 1))
            let normalized = range > 0 ? (value - low) / range : 0.5
            return CGPoint(x: x, y: 0.9 - normalized * 0.78)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summaryHero
                activityStats
                workoutHeartRateCard
                trendCard
                guidanceCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 96)
        }
        .scrollIndicators(.hidden)
        .background(VelaTheme.rhythmCanvas.ignoresSafeArea())
        .navigationTitle("活动摘要")
        .navigationBarTitleDisplayMode(.inline)
        .velaRhythmDetailChrome()
        .task(id: selectedDate) {
            let calendar = Calendar.current
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: selectedDate))
                ?? selectedDate
            let start = calendar.date(byAdding: .day, value: -35, to: end) ?? end
            records = (try? SwiftDataDailyHealthSummaryRepository(modelContext: modelContext)
                .fetch(in: DateRangeQuery(start: start, end: end))) ?? []
            workoutEvents = (try? WorkoutHistoryRepository(modelContext: modelContext).fetchWorkoutEvents(
                from: start,
                until: end
            )) ?? []
        }
    }

    // MARK: - Summary Hero Card
    private var summaryHero: some View {
        VelaGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("训练总时长")
                            .font(.system(.caption, design: .rounded, weight: .bold))
                            .foregroundStyle(VelaTheme.fg2)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(workoutMinutes / 60)")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .foregroundStyle(VelaTheme.fg)
                            Text("小时")
                                .font(.system(.callout, design: .rounded, weight: .semibold))
                                .foregroundStyle(VelaTheme.fg2)
                            Text("\(workoutMinutes % 60)")
                                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                .foregroundStyle(VelaTheme.fg)
                            Text("分钟")
                                .font(.system(.callout, design: .rounded, weight: .semibold))
                                .foregroundStyle(VelaTheme.fg2)
                        }
                    }
                    Spacer()
                    Image(systemName: "timer")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(VelaTheme.accent)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(VelaTheme.accent.opacity(0.12)))
                }
                Text("Apple 健康训练与日常活动汇总")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(VelaTheme.fg2)
            }
        }
    }

    // MARK: - Activity Stats Grid
    private var activityStats: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            activityStat(title: "活跃天数", value: "\(activeDays) 天", icon: "calendar", color: VelaTheme.accent)
            activityStat(title: "训练次数", value: "\(workoutCount) 次", icon: "figure.run", color: VelaTheme.rhythmInk)
            activityStat(title: "活动消耗", value: "\(activeCalories) kcal", icon: "flame.fill", color: VelaTheme.rhythmInk)
            activityStat(title: "平均耗力", value: averageStrain.map { String(format: "%.0f", $0) } ?? "--", icon: "bolt.heart.fill", color: VelaTheme.rhythmInk)
        }
    }

    private func activityStat(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous).fill(color.opacity(0.12)))
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(VelaTheme.fg)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .medium))
                .foregroundStyle(VelaTheme.fg2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .velaNativeCard(radius: 16)
    }

    // MARK: - Workout Heart Rate Card
    private var workoutHeartRateCard: some View {
        VelaGlassCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("训练心率波动", systemImage: "waveform.path.ecg")
                            .font(.system(.footnote, design: .rounded, weight: .bold))
                            .foregroundStyle(VelaTheme.fg)
                        Text("来自统一训练记录的平均心率")
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundStyle(VelaTheme.fg2)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(averageWorkoutHeartRate.map { "\(Int($0.rounded()))" } ?? "--")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(VelaTheme.fg)
                        Text("bpm 平均")
                            .font(.system(.caption2, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.fg2)
                    }
                }

                if workoutHeartRates.count < 2 {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(VelaTheme.fg2)
                        Text("导入或同步至少 2 次带心率的训练后显示波动图。")
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(VelaTheme.fg2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    WorkoutHeartRateRibbonView(values: workoutHeartRates)
                        .frame(height: 126)
                    HStack {
                        Label("峰值 \(Int((maxWorkoutHeartRate ?? 0).rounded())) bpm", systemImage: "heart.fill")
                        Spacer()
                        Text("\(workoutHeartRates.count) 次训练")
                    }
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.accent)
                }
            }
        }
    }

    // MARK: - Strain Trend Card
    private var trendCard: some View {
        VelaGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("耗力趋势", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(.footnote, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
                if chartPoints.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(VelaTheme.fg2)
                        Text("积累至少 2 天记录后显示趋势。")
                            .font(.system(.footnote, design: .default))
                            .foregroundStyle(VelaTheme.fg2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                } else {
                    AreaChartCurveView(points: chartPoints)
                        .frame(height: 112)
                }
            }
        }
    }

    // MARK: - Coach Guidance Card (AI Glow)
    private var guidanceCard: some View {
        Button {
            VelaAppState.shared.routeToCoach(
                question: "请结合我过去 30 天的活动摘要、耗力趋势、恢复、负荷、压力和身体模型，给出下一次训练的明确建议。",
                surface: .training
            )
        } label: {
            VelaGlassCard {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(VelaTheme.accent)
                        .frame(width: 42, height: 42)
                        .background(Circle().fill(VelaTheme.accent.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("让 Coach 分析活动趋势")
                            .font(.system(.footnote, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.fg)
                        Text("结合恢复、负荷、压力和身体模型给出下一步建议")
                            .font(.system(.caption, design: .default))
                            .foregroundStyle(VelaTheme.fg2)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(VelaTheme.fg2)
                }
            }
            .appleIntelligenceGlow(isHighlighted: true, radius: 20)
        }
        .buttonStyle(.cardPress)
    }
}

// MARK: - Area Chart Curve View

struct AreaChartCurveView: View {
    let points: [CGPoint]
    /// 真实数值与日期（可选）：提供后支持拖动查看每天的真实耗力分数。
    var values: [Double]? = nil
    var dates: [Date]? = nil

    @State private var scrubIndex: Int?
    @State private var showLabels = false

    private var canScrub: Bool {
        guard let values else { return false }
        return values.count == points.count && points.count > 1
    }

    private var labelStride: Int {
        points.count > 15 ? 2 : 1
    }

    private func dateText(for index: Int) -> String {
        guard let dates, dates.indices.contains(index) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter.string(from: dates[index])
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Path { path in
                    guard points.count > 1 else { return }
                    path.move(to: CGPoint(x: 0, y: geo.size.height))
                    for pt in points {
                        let x = pt.x * geo.size.width
                        let y = pt.y * geo.size.height
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [VelaTheme.accent.opacity(0.22), VelaTheme.accent.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                Path { path in
                    guard points.count > 1 else { return }
                    for idx in 0..<points.count {
                        let pt = points[idx]
                        let x = pt.x * geo.size.width
                        let y = pt.y * geo.size.height
                        if idx == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(VelaTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                
                ForEach(0..<points.count, id: \.self) { idx in
                    let pt = points[idx]
                    if idx % 3 == 0 || idx == points.count - 1 {
                        let x = pt.x * geo.size.width
                        let y = pt.y * geo.size.height
                        Circle()
                            .fill(VelaTheme.cardBg)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(VelaTheme.accent, lineWidth: 1.5))
                            .position(x: x, y: y)
                    }
                }

                // 数值标注模式：点一下曲线显示数值（>15 点时隔点标注）+ 最高/最低图例
                valueLabelOverlay(geo: geo)

                // 交互：拖动查看每天的真实耗力分数
                scrubOverlay(geo: geo)
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { value in
                        guard canScrub, geo.size.width > 0 else { return }
                        let fraction = min(1, max(0, value.location.x / geo.size.width))
                        scrubIndex = Int((fraction * CGFloat(points.count - 1)).rounded())
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
                        guard canScrub else { return }
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            showLabels.toggle()
                        }
                    }
            )
        }
    }

    @ViewBuilder
    private func valueLabelOverlay(geo: GeometryProxy) -> some View {
        if showLabels, canScrub, let values {
            ForEach(0..<points.count, id: \.self) { index in
                if index % labelStride == 0 || index == points.count - 1 {
                    let pt = points[index]
                    let label = "\(Int(values[index].rounded()))"
                    let labelPosition = CGPoint(
                        x: min(geo.size.width - 13, pt.x * geo.size.width + 6),
                        y: max(9, pt.y * geo.size.height - 6)
                    )
                    ChartValueLabel(text: label, position: labelPosition)
                }
            }

            ChartMaxMinLegend(maxText: maxValueText, minText: minValueText)
                .position(x: geo.size.width - 68, y: 14)
        }
    }

    @ViewBuilder
    private func scrubOverlay(geo: GeometryProxy) -> some View {
        if canScrub, let values {
            let index = scrubIndex ?? points.count - 1
            if points.indices.contains(index) {
                let pt = points[index]
                let x = pt.x * geo.size.width
                let y = pt.y * geo.size.height
                let label = dateText(for: index) + " · \(Int(values[index].rounded()))"
                Circle()
                    .fill(VelaTheme.accent)
                    .frame(width: 8, height: 8)
                    .position(x: x, y: y)
                Text(label)
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(VelaTheme.fg)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(VelaTheme.cardBg, in: Capsule())
                    .position(
                        x: min(geo.size.width - 52, max(52, x)),
                        y: max(16, y - 18)
                    )
            }
        }
    }

    private var maxValueText: String {
        guard let values else { return "--" }
        return "\(Int((values.max() ?? 0).rounded()))"
    }

    private var minValueText: String {
        guard let values else { return "--" }
        return "\(Int((values.min() ?? 0).rounded()))"
    }
}

/// 图表上的小数值标注（独立子视图，减轻大视图类型推导负担）。
private struct ChartValueLabel: View {
    let text: String
    let position: CGPoint

    var body: some View {
        Text(text)
            .font(VelaTheme.caption2())
            .foregroundStyle(VelaTheme.fg2)
            .position(position)
    }
}

/// 最高/最低图例小胶囊。
private struct ChartMaxMinLegend: View {
    let maxText: String
    let minText: String

    var body: some View {
        HStack(spacing: 8) {
            Label("最高 \(maxText)", systemImage: "arrow.up")
            Label("最低 \(minText)", systemImage: "arrow.down")
        }
        .font(VelaTheme.caption2().weight(.semibold))
        .foregroundStyle(VelaTheme.fg)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(VelaTheme.cardBg.opacity(0.95), in: Capsule())
    }
}

// MARK: - Workout Heart Rate Ribbon View

struct WorkoutHeartRateRibbonView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let minValue = max(40, (values.min() ?? 60) - 8)
            let maxValue = max(minValue + 1, (values.max() ?? 120) + 8)
            let range = maxValue - minValue
            ZStack {
                RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                    .fill(VelaTheme.accent.opacity(0.06))
                    .frame(height: geo.size.height * 0.42)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.52)

                ForEach(0..<4, id: \.self) { idx in
                    Rectangle()
                        .fill(VelaTheme.separatorSoft)
                        .frame(height: 0.5)
                        .position(x: geo.size.width / 2, y: geo.size.height * CGFloat(idx + 1) / 5)
                }

                Path { path in
                    guard values.count > 1 else { return }
                    for index in values.indices {
                        let x = CGFloat(index) / CGFloat(max(values.count - 1, 1)) * geo.size.width
                        let normalized = (values[index] - minValue) / range
                        let y = geo.size.height - CGFloat(normalized) * (geo.size.height - 14) - 7
                        if index == values.startIndex {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(
                    VelaTheme.rhythmInk,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )

                ForEach(values.indices, id: \.self) { index in
                    if index == values.startIndex || index == values.index(before: values.endIndex) || index % 3 == 0 {
                        let x = CGFloat(index) / CGFloat(max(values.count - 1, 1)) * geo.size.width
                        let normalized = (values[index] - minValue) / range
                        let y = geo.size.height - CGFloat(normalized) * (geo.size.height - 14) - 7
                        Circle()
                            .fill(VelaTheme.cardBg)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(VelaTheme.rhythmInk, lineWidth: VelaTheme.hairlineWidth))
                            .position(x: x, y: y)
                    }
                }
            }
        }
    }
}
