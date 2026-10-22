import SwiftUI
import Charts
import MapKit
import HealthKit
import SwiftData
import os.log


private let logger = Logger(subsystem: "com.sunweizhou.Vela", category: "Workout")
struct WorkoutDetailView: View {
    let workout: WorkoutSummary
    let dashboard: DashboardSummary
    var onRefresh: (() async -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var appState = VelaAppState.shared

    init(
        workout: WorkoutSummary,
        dashboard: DashboardSummary = .empty(),
        onRefresh: (() async -> Void)? = nil
    ) {
        self.workout = workout
        self.dashboard = dashboard
        self.onRefresh = onRefresh
    }
    
    @State private var heartRates: [HeartRateSample] = []
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var isLoading = true
    @State private var showHeartRateInsight = false
    @State private var showDeleteConfirmation = false
    @State private var selectedSet: StrengthSetDetail?
    @State private var mutationError: String?
    @State private var workoutEvents: [WorkoutEventRecord] = []
    @State private var strengthWorkouts: [StrengthWorkoutRecord] = []
    
    private let queryService = HealthKitQueryService()
    
    var body: some View {
        ZStack {
            detailBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    intelligenceStrip
                    heartRateChartSection
                    
                    if let strength = linkedStrengthWorkout {
                        muscleDistribution(strength)
                        WorkoutExerciseListView(
                            strength: strength,
                            strengthWorkouts: strengthWorkouts,
                            selectedSet: $selectedSet
                        )
                        WorkoutNotesCardView(strength: strength)
                    }
                    
                    if !routeCoordinates.isEmpty {
                        gpsRouteSection
                    }
                    workoutCoachCard
                }
                .padding(16)
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(workout.activityName)
        .navigationBarTitleDisplayMode(.inline)
        .velaRhythmDetailChrome()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showHeartRateInsight = true
                    } label: {
                        Image(systemName: "heart.text.square")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(heartRates.isEmpty ? VelaTheme.rhythmInkSecondary.opacity(0.4) : VelaTheme.rhythmDeep)
                    }
                    .disabled(heartRates.isEmpty)
                    .accessibilityLabel("心率区间洞察")
                    
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(VelaTheme.systemRed)
                    }
                    .accessibilityLabel("删除记录")
                }
            }
        }
        .sheet(isPresented: $showHeartRateInsight) {
            WorkoutHeartRateInsightSheet(
                averageText: averageHeartRateText,
                peakText: peakHeartRateText,
                rangeText: heartRateRangeText,
                intensityText: heartRateIntensityText,
                segments: heartRateZoneSegments
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(VelaTheme.rhythmCanvas)
        }
        .sheet(item: $selectedSet) { detail in
            StrengthSetDetailSheet(detail: detail)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(VelaTheme.rhythmCanvas)
        }
        .confirmationDialog("确定要删除这条健身记录吗？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) {
                deleteWorkout()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，该训练对应的耗力、卡路里和负荷计算都将被移除。")
        }
        .alert("无法删除训练记录", isPresented: Binding(
            get: { mutationError != nil },
            set: { if !$0 { mutationError = nil } }
        )) {
            Button("好", role: .cancel) { mutationError = nil }
        } message: {
            Text(mutationError ?? "")
        }
        .task {
            await loadWorkoutDetails()
        }
        .onChange(of: appState.localDataRevision) { _, _ in
            loadLinkedWorkouts()
        }
    }
    
    // MARK: - Subviews

    private var bodyTextColor: Color { VelaTheme.rhythmInk }
    private var mutedColor: Color { VelaTheme.rhythmInkSecondary }
    private var accentColor: Color { VelaTheme.rhythmDeep }

    private var detailBackground: some View {
        ZStack {
            VelaTheme.rhythmCanvas
            LinearGradient(
                colors: [workoutAccentColor.opacity(0.05), VelaTheme.rhythmCanvas, VelaTheme.rhythmCanvas],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private func heroMetric(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .default, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text(unit)
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(mutedColor)
                    .lineLimit(1)
            }
            Text(title)
                .font(.system(.caption2, design: .default, weight: .semibold))
                .foregroundStyle(mutedColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(VelaTheme.rhythmCanvas))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: iconForWorkout(workout.activityName))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(workoutAccentColor)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(workoutAccentColor.opacity(0.14)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(workout.activityName)
                        .font(.system(.headline, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.rhythmInk)
                    Text(workout.start.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                }
                Spacer()
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                heroMetric("时长", "\(Int((workout.end.timeIntervalSince(workout.start) / 60).rounded()))", "分钟")
                heroMetric("活动消耗", workout.energyKilocalories.map { "\(Int($0))" } ?? "--", "kcal")
                if let dist = workout.distanceMeters, dist > 0 {
                    heroMetric("距离", dist >= 1000 ? String(format: "%.1f", dist/1000) : "\(Int(dist.rounded()))", dist >= 1000 ? "km" : "m")
                } else {
                    heroMetric("平均心率", workout.averageHeartRate.map { "\(Int($0))" } ?? "--", "bpm")
                }
            }
        }
        .padding(16)
        .velaNativeCard(radius: 20)
    }

    private var intelligenceStrip: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmDeep)
                .frame(width: 38, height: 38)
                .background(Circle().fill(VelaTheme.rhythmMist.opacity(0.8)))
            VStack(alignment: .leading, spacing: 4) {
                Text("训练智能摘要")
                    .font(.system(.footnote, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
                Text("本次为 \(workout.activityName) 运动，持续时间约 \(Int((workout.end.timeIntervalSince(workout.start) / 60).rounded())) 分钟。")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .velaNativeCard(radius: 18)
    }
    
    private var heartRateChartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(VelaTheme.heartRateAverage)
                
                Text(L10n.t("Heart Rate Fluctuation", "心率波动趋势"))
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
            }
            
            if isLoading {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                            .fill(VelaTheme.borderSoft)
                            .frame(height: 60)
                            .shimmer()
                        RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                            .fill(VelaTheme.borderSoft)
                            .frame(height: 60)
                            .shimmer()
                        RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                            .fill(VelaTheme.borderSoft)
                            .frame(height: 60)
                            .shimmer()
                    }
                    RoundedRectangle(cornerRadius: VelaTheme.radiusSm, style: .continuous)
                        .fill(VelaTheme.borderSoft)
                        .frame(height: 28)
                        .shimmer()
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
            } else if heartRates.isEmpty {
                Text(L10n.t("No heart rate details recorded for this period.", "此时间段未记录心率明细。"))
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.muted)
                    .frame(height: 160)
            } else {
                HStack(spacing: 10) {
                    heartRateFact(title: L10n.t("Average", "平均"), value: averageHeartRateText)
                    heartRateFact(title: L10n.t("Range", "范围"), value: heartRateRangeText)
                    heartRateFact(title: L10n.t("Peak", "峰值"), value: peakHeartRateText)
                }

                HeartRateZoneRibbonView(segments: heartRateZoneSegments)
                    .frame(height: 28)

                Chart {
                    if let averageHeartRate {
                        RuleMark(y: .value("Average", averageHeartRate))
                            .foregroundStyle(VelaTheme.heartRateAverage.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                            .annotation(position: .trailing, alignment: .center) {
                                Text(AppLanguage.stored.isChinese ? "均值" : "AVG")
                                    .font(.system(.caption2, design: .default, weight: .bold))
                                    .foregroundStyle(VelaTheme.heartRateAverage)
                            }
                    }

                    ForEach(binnedHeartRates) { bin in
                        BarMark(
                            x: .value("Time", bin.date),
                            yStart: .value("Min BPM", bin.minBPM),
                            yEnd: .value("Max BPM", bin.maxBPM),
                            width: .fixed(3.0)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: VelaTheme.heartRateBarGradient,
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .cornerRadius(1.5)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(VelaTheme.separatorSoft)
                        AxisValueLabel(format: .dateTime.hour().minute())
                            .font(.system(.caption2, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.muted)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
                            .foregroundStyle(VelaTheme.hairline)
                        AxisValueLabel()
                            .font(.system(.caption2, design: .default, weight: .medium))
                            .foregroundStyle(VelaTheme.muted)
                    }
                }
                .chartYScale(domain: heartRateDomain)
                .frame(height: 160)
                .padding(.top, 6)

                Button {
                    showHeartRateInsight = true
                } label: {
                    HStack {
                        Text(heartRateIntensityText)
                            .font(.system(.caption, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmInk)
                        Spacer()
                        Text(L10n.t("View zones", "查看区间"))
                            .font(.system(.caption, design: .default, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(VelaTheme.rhythmDeep)
                    }
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .velaNativeCard(radius: 20)
    }

    private func heartRateFact(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(.footnote, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInk)
            Text(title)
                .font(.system(.caption2, design: .default))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).fill(VelaTheme.rhythmCanvas))
        .overlay(RoundedRectangle(cornerRadius: VelaTheme.radiusMd).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
    }
    
    private var gpsRouteSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmDeep)
                
                Text(L10n.t("GPS Workout Route", "GPS 运动轨迹"))
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.rhythmInk)
            }
            
            if isLoading {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(VelaTheme.rhythmMist.opacity(0.4))
                    .frame(height: 220)
                    .shimmer()
                    .frame(maxWidth: .infinity)
            } else if routeCoordinates.isEmpty {
                Text(L10n.t("No GPS route mapping recorded for this workout.", "此项运动未记录 GPS 运动轨迹。"))
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    .frame(height: 100)
            } else {
                Map(position: .constant(.region(MKCoordinateRegion(
                    center: centerOfCoordinates(routeCoordinates),
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )))) {
                    MapPolyline(coordinates: routeCoordinates)
                        .stroke(VelaTheme.rhythmInk, lineWidth: 4.5) // Reddish-orange loop like Apple Watch route!
                    
                    if let first = routeCoordinates.first {
                        Annotation(L10n.t("Start", "起点"), coordinate: first) {
                            Circle()
                                .fill(VelaTheme.systemGreen)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 2)
                        }
                    }
                    if let last = routeCoordinates.last {
                        Annotation(L10n.t("End", "终点"), coordinate: last) {
                            Circle()
                                .fill(VelaTheme.systemRed)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                                .shadow(radius: 2)
                        }
                    }
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
            }
        }
        .padding(16)
        .velaNativeCard(radius: 20)
    }
    
    private var workoutCoachCard: some View {
        MetricCoachCard(
            dashboard: dashboardVMForWorkout,
            focus: CoachContextFocus(
                title: workout.activityName,
                systemContext: L10n.t(
                    "Analyze detailed workout segment, heart rate ranges, recovery speed, energy expense, and distance coverage.",
                    "分析特定的训练表现、心率区间分布、恢复速率、运动热量消耗和距离表现细节。"
                ),
                screenContext: CoachScreenContext(
                    surface: .workoutDetail,
                    entityType: "workout",
                    selectedDate: workout.start
                )
            ),
            suggestedQuestion: L10n.t(
                "Analyze my \(workout.activityName) workout today: duration of \(formattedDuration(workout.start, workout.end)), calories burned \(workout.energyKilocalories.map { "\(Int($0))" } ?? "N/A"), average HR \(workout.averageHeartRate.map { "\(Int($0))" } ?? "N/A"). What is the strain score consequence and impact on tomorrow's recovery?",
                "请分析我今天进行的 \(workout.activityName) 运动：持续时间为 \(formattedDuration(workout.start, workout.end))，热量消耗 \(workout.energyKilocalories.map { "\(Int($0))" } ?? "N/A")，平均心率 \(workout.averageHeartRate.map { "\(Int($0))" } ?? "N/A")。它产生了什么负荷影响，对明天的恢复有什么建议？"
            )
        )
    }
    
    // MARK: - Helpers
    
    private var formattedWorkoutTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: workout.start)
    }

    private var formattedDistance: String {
        guard let meters = workout.distanceMeters, meters > 0 else { return "--" }
        if meters >= 1_000 {
            return String(format: "%.2f km", meters / 1_000)
        }
        return "\(Int(meters.rounded())) m"
    }

    private var binnedHeartRates: [HeartRateRangeBin] {
        guard !heartRates.isEmpty else { return [] }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: heartRates) { sample in
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: sample.date)
            return calendar.date(from: components) ?? sample.date
        }
        return grouped.compactMap { (minuteDate, samples) -> HeartRateRangeBin? in
            let bpms = samples.map(\.bpm)
            guard let minVal = bpms.min(), let maxVal = bpms.max() else { return nil }
            return HeartRateRangeBin(date: minuteDate, minBPM: minVal, maxBPM: maxVal)
        }.sorted { $0.date < $1.date }
    }

    private var heartRateDomain: ClosedRange<Double> {
        let values = heartRates.map(\.bpm)
        guard let minimum = values.min(), let maximum = values.max() else {
            return 60...180
        }
        let lower = max(30, floor((minimum - 10) / 10) * 10)
        let upper = max(lower + 20, ceil((maximum + 10) / 10) * 10)
        return lower...upper
    }

    private var heartRateRangeText: String {
        let values = heartRates.map(\.bpm)
        guard let minimum = values.min(), let maximum = values.max() else { return "--" }
        return "\(Int(minimum.rounded()))-\(Int(maximum.rounded())) bpm"
    }

    private var peakHeartRateText: String {
        guard let maximum = heartRates.map(\.bpm).max() else { return "--" }
        return "\(Int(maximum.rounded())) bpm"
    }

    private var averageHeartRate: Double? {
        if !heartRates.isEmpty {
            return heartRates.map(\.bpm).reduce(0, +) / Double(heartRates.count)
        }
        return workout.averageHeartRate
    }

    private var averageHeartRateText: String {
        guard let averageHeartRate else { return "--" }
        return "\(Int(averageHeartRate.rounded())) bpm"
    }

    private var maxHeartRateSample: HeartRateSample? {
        heartRates.max { $0.bpm < $1.bpm }
    }

    private var heartRateIntensityText: String {
        guard let averageHeartRate else {
            return L10n.t("No heart rate intensity available", "暂无心率强度")
        }
        if averageHeartRate >= 155 {
            return L10n.t("High cardiovascular load", "心肺负荷较高")
        }
        if averageHeartRate >= 130 {
            return L10n.t("Steady aerobic effort", "稳定有氧输出")
        }
        return L10n.t("Low-to-moderate intensity", "低到中等强度")
    }

    private var heartRateZoneSegments: [HeartRateZoneSegment] {
        guard !heartRates.isEmpty else { return [] }
        return [
            HeartRateZoneSegment(label: L10n.t("Easy", "轻松"), count: heartRates.filter { $0.bpm < 110 }.count, color: VelaTheme.heartRateZoneEasy),
            HeartRateZoneSegment(label: L10n.t("Aerobic", "有氧"), count: heartRates.filter { $0.bpm >= 110 && $0.bpm < 140 }.count, color: VelaTheme.heartRateZoneAerobic),
            HeartRateZoneSegment(label: L10n.t("Tempo", "节奏"), count: heartRates.filter { $0.bpm >= 140 && $0.bpm < 165 }.count, color: VelaTheme.heartRateZoneTempo),
            HeartRateZoneSegment(label: L10n.t("Peak", "峰值"), count: heartRates.filter { $0.bpm >= 165 }.count, color: VelaTheme.heartRateZonePeak)
        ]
    }

    private var workoutAccentColor: Color {
        VelaTheme.workoutActivityColor(activityName: workout.activityName)
    }

    private var workoutSecondaryColor: Color {
        VelaTheme.workoutSecondaryColor(activityName: workout.activityName)
    }
    
    private var formattedHomeDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: workout.start)
    }
    
    private func formattedDuration(_ start: Date, _ end: Date) -> String {
        let diff = Int(end.timeIntervalSince(start))
        let min = diff / 60
        let sec = diff % 60
        if min > 0 {
            return "\(min)m \(sec)s"
        }
        return "\(sec)s"
    }
    
    private func iconForWorkout(_ name: String) -> String {
        let lowName = name.lowercased()
        if lowName.contains("run") { return "figure.run" }
        if lowName.contains("walk") { return "figure.walk" }
        if lowName.contains("cycl") { return "figure.outdoor.cycle" }
        if lowName.contains("strength") || lowName.contains("lift") || lowName.contains("weight") { return "figure.strengthtraining.traditional" }
        if lowName.contains("yoga") { return "figure.yoga" }
        if lowName.contains("swim") { return "figure.pool.swim" }
        return "figure.run"
    }
    
    private func centerOfCoordinates(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !coords.isEmpty else { return CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090) }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0
        return CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }
    
    private var dashboardVMForWorkout: DashboardSummary {
        var base = dashboard
        base.workouts = [workout]
        return base
    }
    
    private func loadLinkedWorkouts() {
        let history = WorkoutHistoryRepository(modelContext: modelContext)
        workoutEvents = (try? history.fetchWorkoutEventsSortedByStart()) ?? []
        strengthWorkouts = (try? history.fetchStrengthWorkoutsSortedByStart(newestFirst: true)) ?? []
    }

    private func loadWorkoutDetails() async {
        loadLinkedWorkouts()
        isLoading = true
        
        do {
            let samples = try await queryService.heartRateSamples(start: workout.start, end: workout.end)
            heartRates = samples
            
            let route = try await queryService.workoutRoute(workoutId: workout.id)
            if !route.isEmpty {
                routeCoordinates = route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            } else {
                routeCoordinates = []
            }
        } catch {
            logger.error("Workout detail loading failed: \(error.localizedDescription, privacy: .public)")
            heartRates = []
            routeCoordinates = []
        }
        
        isLoading = false
    }

    private func deleteWorkout() {
        do {
            let workoutID = workout.id
            let events = try WorkoutHistoryRepository(modelContext: modelContext)
                .fetchEvents(idOrHealthKitWorkoutId: workoutID)
            for event in events {
                if let strengthId = event.linkedStrengthWorkoutId {
                    if let strWorkout = try WorkoutHistoryRepository(modelContext: modelContext)
                        .fetchStrengthWorkouts(id: strengthId)
                        .first {
                        // deleteStrengthWorkout 内部统一处理黑名单（查重）与计划日回滚。
                        try WorkoutAggregationService.shared.deleteStrengthWorkout(strWorkout, modelContext: modelContext)
                    } else {
                        WorkoutAggregationService.shared.blacklistWorkout(
                            id: event.linkedHealthKitWorkoutId?.uuidString ?? event.id.uuidString,
                            modelContext: modelContext
                        )
                        modelContext.delete(event)
                    }
                } else {
                    if let hkId = event.linkedHealthKitWorkoutId {
                        WorkoutAggregationService.shared.blacklistWorkout(id: hkId.uuidString, modelContext: modelContext)
                    } else if event.source == "healthKit" {
                        WorkoutAggregationService.shared.blacklistWorkout(id: event.id.uuidString, modelContext: modelContext)
                    }
                    modelContext.delete(event)
                }
            }
            if workout.source == "healthKit" || workout.source == nil {
                WorkoutAggregationService.shared.blacklistWorkout(id: workout.id.uuidString, modelContext: modelContext)
            }
            try modelContext.save()
            // 深度专项批次 1：与 deleteStrengthWorkout 一致，删除回滚需整体重算
            //（max 语义会残留旧值），否则 activeMinutes/activeCalories 不回落。
            try? WorkoutAggregationService.shared.aggregateDay(
                date: workout.start,
                modelContext: modelContext,
                resetActivityTotals: true
            )
            
            VelaAppState.shared.markLocalDataChanged()
            
            if let onRefresh {
                Task { await onRefresh() }
            }
            dismiss()
        } catch {
            mutationError = "删除过程中发生错误，请刷新后确认记录状态再重试。"
        }
    }

    private var linkedStrengthWorkout: StrengthWorkoutRecord? {
        // 1. Try explicit link via WorkoutEventRecord
        if let event = workoutEvents.first(where: { $0.id == workout.id || $0.linkedHealthKitWorkoutId == workout.id }),
           let strengthId = event.linkedStrengthWorkoutId {
            if let match = strengthWorkouts.first(where: { $0.id == strengthId }) {
                return match
            }
        }
        // 2. Try direct matching of workout.id
        if let match = strengthWorkouts.first(where: { $0.id == workout.id }) {
            return match
        }
        // 3. Fallback: Find by time overlap (30 mins range)
        let matchRange: TimeInterval = 30 * 60
        if let match = strengthWorkouts.first(where: { abs($0.startedAt.timeIntervalSince(workout.start)) <= matchRange }) {
            return match
        }
        return nil
    }

    private func muscleDistribution(_ strength: StrengthWorkoutRecord) -> some View {
        let analysis = TrainingAnalyticsService().summarizeWorkout(
            strength.dto,
            history: strengthWorkouts.filter { $0.startedAt < strength.startedAt }.map { $0.dto },
            exerciseLibrary: ExerciseLibraryService.defaultDefinitionsDTO()
        )
        return VelaGlassCard(padding: 16, cornerRadius: 20) {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("肌群分布")
                    .font(.system(.subheadline, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.fg)
                Spacer()
                Text("有效组")
                    .font(.system(.caption2, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.fg2)
            }

            if analysis.muscleGroupSets.isEmpty {
                Text("这次训练暂未形成有效组。")
                    .font(.system(.footnote, design: .default))
                    .foregroundStyle(mutedColor)
            } else {
                ForEach(analysis.muscleGroupSets.sorted { $0.value > $1.value }, id: \.key) { muscle, sets in
                    let maxSets = max(analysis.muscleGroupSets.values.max() ?? 1, 1)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(localizedMuscle(muscle))
                                .font(.system(.caption, design: .default, weight: .bold))
                                .foregroundStyle(bodyTextColor)
                            Spacer()
                            Text("\(sets) 组")
                                .font(.system(.caption, design: .default, weight: .bold))
                                .foregroundStyle(mutedColor)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(VelaTheme.neutralCapsule)
                                Capsule()
                                    .fill(muscleColor(muscle))
                                    .frame(width: geo.size.width * CGFloat(Double(sets) / Double(maxSets)))
                            }
                        }
                        .frame(height: 8)
                    }
                }
            }
          }
        }
    }

    private func localizedMuscle(_ muscle: String) -> String {
        [
            "chest": "胸部",
            "back": "背部",
            "quads": "股四头肌",
            "hamstrings": "腘绳肌",
            "glutes": "臀部",
            "shoulders": "肩部",
            "biceps": "肱二头肌",
            "triceps": "肱三头肌",
            "core": "核心",
            "other": "其他"
        ][muscle] ?? muscle
    }

    private func muscleColor(_ muscle: String) -> Color {
        VelaTheme.muscleGroupColor(name: muscle)
    }
}
