import BodySeekAgent
import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

/// 健身页：L0 肌群图与整体状态；L1 Coach 解读；L2 待复盘与负荷曲线；L3 手表训练档案。
public struct WorkoutView: View {
    private enum ArchiveFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case unreviewed = "待复盘"
        case annotated = "已复盘"

        var id: String { rawValue }
    }

    private static let loadDisplayDays = 56
    private static let inboxPreviewCount = 3
    private static let archivePreviewCount = 6

    @Bindable var store: StoreOf<WorkoutFeature>
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAllUnreviewed = false
    @State private var showAllArchive = false
    @State private var archiveFilter: ArchiveFilter = .all
    @State private var selectedLoadPoint: FitnessFatiguePoint?
    @State private var showAdvice = false

    public init(store: StoreOf<WorkoutFeature>) {
        self.store = store
    }

    public var body: some View {
        BSPage("健身") {
            heroSection
        } note: {
            noteSection
        } sections: {
            sectionsContent
        } links: {
            EmptyView()
        }
        .oneLineHeader(subtitle: "肌群恢复与训练")
        .onAppear {
            store.send(.onAppear)
        }
        .refreshable {
            await store.send(.refreshRequested).finish()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                store.send(.recoveryTick)
                do {
                    try await Task.sleep(for: .seconds(30))
                } catch {
                    return
                }
            }
        }
        .sheet(isPresented: $showAdvice) {
            adviceSheet
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: reviewSheetBinding) {
            WorkoutReviewSheetView(store: store)
        }
        .sheet(item: muscleSheetBinding) { muscle in
            MuscleRecoveryDetailSheet(store: store, muscle: muscle)
        }
        .sheet(item: workoutSheetBinding) { workout in
            WorkoutDetailSheetView(store: store, workout: workout)
        }
    }

    private var reviewSheetBinding: Binding<Bool> {
        Binding(
            get: { store.reviewDraft != nil },
            set: { presented in
                if !presented {
                    store.send(.dismissReviewSheet)
                }
            }
        )
    }

    private var muscleSheetBinding: Binding<BodyRegionMuscle?> {
        Binding(
            get: { store.inspectedMuscleForRecovery },
            set: { store.send(.inspectMuscleRecovery($0)) }
        )
    }

    private var workoutSheetBinding: Binding<StoredWorkoutRecord?> {
        Binding(
            get: { store.inspectedWorkoutDetail },
            set: { store.send(.inspectWorkoutDetail($0)) }
        )
    }

    // MARK: - L0 肌群图与整体状态

    private var heroSection: some View {
        VStack(spacing: BSSpace.s) {
            banner
            bodyMapCard
        }
    }

    @ViewBuilder
    private var banner: some View {
        if let error = store.lastError {
            BSStateView(
                .error,
                message: error,
                actionTitle: "知道了",
                action: { store.send(.clearStatusBanner) }
            )
        } else if let status = store.statusMessage {
            statusBanner(status)
        }
    }

    private func statusBanner(_ text: String) -> some View {
        BSCard {
            HStack(spacing: BSSpace.xs) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(BSColor.recovery)
                Text(text)
                    .bsText(.label)
                Spacer(minLength: BSSpace.xs)
                Button {
                    store.send(.clearStatusBanner)
                } label: {
                    Image(systemName: "xmark")
                        .frame(minWidth: BSSize.hitTarget, minHeight: BSSize.hitTarget)
                }
                .buttonStyle(.bsPressable)
                .accessibilityLabel("关闭提示")
            }
        }
    }

    private var bodyMapCard: some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack(alignment: .firstTextBaseline, spacing: BSSpace.xs) {
                    Text("肌群疲劳")
                        .bsText(.cardTitle)
                    Text("模型估算")
                        .bsText(.caption)
                    Spacer(minLength: BSSpace.xs)
                }
                sidePicker
                HStack(alignment: .top, spacing: BSSpace.m) {
                    bodyMap
                    musclePanel
                }
                overallStatusRow
                legend
            }
        }
    }

    private var sidePicker: some View {
        Picker("视角", selection: Binding(
            get: { store.selectedBodySide },
            set: { store.send(.bodySideChanged($0)) }
        )) {
            Text("正面").tag(BodySideOption.front)
            Text("背面").tag(BodySideOption.back)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("workout.bodySidePicker")
    }

    private var overallStatusRow: some View {
        let latest = loadSeries.last(where: { $0.fitness != nil })
        return HStack(alignment: .top, spacing: BSSpace.m) {
            statBlock("体能", value: formatLoad(latest?.fitness))
            statBlock("疲劳", value: formatLoad(latest?.fatigue))
            statBlock("状态差", value: formatForm(latest?.form), isNegative: (latest?.form ?? 0) < 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-overall-status")
    }

    private func statBlock(_ title: String, value: String, isNegative: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: BSSpace.xxs) {
            Text(value)
                .bsText(.number)
                .foregroundStyle(isNegative ? BSColor.strain : Color.primary)
            Text(title)
                .bsText(.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodyMap: some View {
        BSBodyMap(
            side: store.selectedBodySide == .front ? .front : .back,
            intensities: bodyIntensities,
            selected: store.selectedMuscle?.rawValue
        ) { raw in
            store.send(.muscleSelected(BodyRegionMuscle(rawValue: raw)))
        }
        .accessibilityIdentifier("workout.muscleMap")
    }

    private var bodyIntensities: [String: Double] {
        Dictionary(
            store.muscleLoadLast72h.map { ($0.key.rawValue, $0.value) },
            uniquingKeysWith: max
        )
    }

    private var musclePanel: some View {
        VStack(alignment: .leading, spacing: BSSpace.xs) {
            if let muscle = store.selectedMuscle {
                selectedMuscleDetail(muscle)
            } else {
                rankedMuscles
            }
            Spacer(minLength: BSSpace.xxs)
            Button {
                store.send(.askCoachForMuscleTapped(store.selectedMuscle))
            } label: {
                Label("让 AI 教练排课", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .frame(minHeight: BSSize.hitTarget)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func selectedMuscleDetail(_ muscle: BodyRegionMuscle) -> some View {
        let est = store.recoverySnapshot.estimate(for: muscle)
        let tint = est.isReadyForPrimaryWork ? BSColor.recovery : BSColor.strain
        return VStack(alignment: .leading, spacing: BSSpace.xs) {
            Text(muscle.title)
                .bsText(.cardTitle)
            Text("预计恢复 \(est.recoveryPercent)%")
                .bsText(.label)
                .foregroundStyle(tint)
            Text(est.readyETADescription)
                .bsText(.caption)
            Button {
                store.send(.inspectMuscleRecovery(muscle))
            } label: {
                Label("查看\(muscle.title)恢复详情", systemImage: "chart.bar.doc.horizontal")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(BSColor.tint)
            .frame(minHeight: BSSize.hitTarget)
            .accessibilityIdentifier("workout-muscle-recovery-detail")
            Button("清除筛选") {
                store.send(.muscleSelected(nil))
            }
            .buttonStyle(.bsPressable)
            .bsText(.caption)
            .frame(minHeight: BSSize.hitTarget)
        }
    }

    @ViewBuilder
    private var rankedMuscles: some View {
        let ranked = store.recoverySnapshot.rankedByFatigue
        Text("训练涉及的肌群")
            .bsText(.label)
        if ranked.isEmpty {
            Text("近 7 天暂无肌群负荷记录。")
                .bsText(.caption)
        } else {
            ForEach(ranked.prefix(5)) { est in
                rankRow(est)
            }
        }
    }

    private func rankRow(_ est: MuscleRecoveryEstimate) -> some View {
        let fatigue = Self.fullScale - est.recoveryPercent
        return Button {
            store.send(.inspectMuscleRecovery(est.muscle))
        } label: {
            VStack(spacing: BSSpace.xxs) {
                HStack {
                    Text(est.muscle.title)
                        .bsText(.label)
                    Spacer()
                    Text("\(fatigue) / \(Self.fullScale)")
                        .bsText(.caption)
                }
                // 与人体图同一条色标：以前一律用负荷色，和图例的四级配色、旁边的人体图都对不上。
                BSStripedProgressBar(
                    recorded: Double(fatigue),
                    estimated: 0,
                    target: Double(Self.fullScale),
                    tint: BSBodyMap.fatigueColor(intensity: Double(fatigue) / Double(Self.fullScale))
                )
            }
            .frame(minHeight: BSSize.hitTarget)
            .contentShape(.rect)
        }
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier("workout-muscle-rank-\(est.muscle.rawValue)")
    }

    private static let fullScale = 100

    private var legend: some View {
        HStack(spacing: BSSpace.s) {
            legendDot(color: BSColor.surfaceInset, label: "已充分恢复")
            legendDot(color: BSColor.tint.opacity(BSOpacity.disabled), label: "轻度残留")
            legendDot(color: BSColor.energy, label: "中等疲劳")
            legendDot(color: BSColor.strain, label: "建议休整")
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: BSSpace.xxs) {
            Circle()
                .fill(color)
                .frame(width: BSSize.dot, height: BSSize.dot)
            Text(label)
                .bsText(.caption)
        }
    }

    // MARK: - L1 Coach 解读

    private var noteSection: some View {
        BSCoachEntryRow(
            title: "今天练什么",
            summary: entrySummary,
            identifier: "workout-advice-entry"
        ) {
            showAdvice = true
        }
    }

    /// 入口行只放得下两行。逐项都写会从中间截断（"股四头肌约 3…"），所以把最该先看到的三件事
    /// 按短句排开：今天的恢复、还没缓过来的首要肌群、负荷比；完整解读在 sheet 里。
    /// 每段内部用不断行空格，需要换行时只在" · "处断开，不会出现"负荷 / 比 0.91"。
    private var entrySummary: String {
        if store.dailyBrief?.note(for: .workout) != nil { return noteText }
        let nbsp = "\u{00A0}"
        var parts: [String] = []
        if let recovery = store.snapshot.today.recovery.value {
            parts.append("恢复\(nbsp)\(recovery)\(nbsp)分")
        }
        if let tired = store.recoverySnapshot.rankedByFatigue.first(where: { !$0.isReadyForPrimaryWork }) {
            parts.append("\(tired.muscle.title)约\(nbsp)\(tired.recoveryPercent)%")
        }
        if let ratio = store.snapshot.trainingLoad.acwrRatio {
            parts.append("负荷比\(nbsp)" + ratio.formatted(.number.precision(.fractionLength(2))))
        }
        if parts.isEmpty {
            return "戴表记录训练并一句话复盘后，将自动关联负荷与肌群恢复"
        }
        return parts.joined(separator: " · ")
    }

    private var adviceSheet: some View {
        NavigationStack {
            ScrollView {
                BSCoachNote(
                    noteText,
                    engine: BSBriefEngine(store.dailyBrief?.engine),
                    onAsk: {
                        showAdvice = false
                        askCoachAction()
                    },
                    askIdentifier: "workout-ask-coach-button"
                )
                .padding(BSSpace.m)
            }
            .background(BSColor.canvas)
            .navigationTitle("今天练什么")
            .bodyseekNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .bodyseekTrailing) {
                    Button("完成") { showAdvice = false }
                        .accessibilityIdentifier("workout-advice-done")
                }
            }
        }
    }

    private var askCoachAction: () -> Void {
        { store.send(.askCoachTapped("结合我当前的训练负荷、体能疲劳曲线和肌群恢复状态，今天最适合什么训练强度和部位？")) }
    }

    private var noteText: String {
        store.dailyBrief?.note(for: .workout) ?? loadCoachMicroInsight
    }

    private var loadCoachMicroInsight: String {
        let load = store.snapshot.trainingLoad
        let fatigued = store.recoverySnapshot.rankedByFatigue.filter { !$0.isReadyForPrimaryWork }.prefix(2)
        let ratioPart: String = if let ratio = load.acwrRatio {
            String(format: "7 天/28 天负荷比 %.2f（%@）", ratio, load.zone.title)
        } else {
            "训练基线积累中"
        }
        let recoveryPart = store.snapshot.today.recovery.value.map { "今日恢复 \($0) 分" } ?? "恢复样本待补充"
        let musclePart: String = if !fatigued.isEmpty {
            fatigued.map { "\($0.muscle.title)约\($0.recoveryPercent)%" }.joined(separator: "、") + "仍在恢复"
        } else if !store.recoverySnapshot.rankedByFatigue.isEmpty {
            "近期主训肌群已基本恢复就绪"
        } else {
            "戴表记录训练并一句话复盘后，将自动关联负荷与肌群恢复"
        }
        return "\(ratioPart) · \(recoveryPart)；\(musclePart)。"
    }

    // MARK: - L2 待复盘与负荷曲线

    @ViewBuilder
    private var sectionsContent: some View {
        if let proposal = store.pendingProposal {
            proposalCard(proposal)
        }
        if !store.unreviewedWorkouts.isEmpty {
            reviewSection
        }
        archiveSection
        performanceSection
        loadSection
    }

    // MARK: - 表现记录（真实数据；e1RM 暂无数据模型，显示空状态，不放假数据）

    private var performanceSection: some View {
        BSSection("表现记录") {
            BSCard {
                VStack(spacing: BSSpace.xs) {
                    performanceRow(
                        title: "最大摄氧量", systemImage: "lungs.fill", tint: BSColor.respiration,
                        unit: "mL/kg/min", digits: 1, values: historyValues(\.vo2MaxMlKgMin)
                    )
                    Divider()
                    performanceRow(
                        title: "体重", systemImage: "scalemass.fill", tint: BSColor.oxygen,
                        unit: "kg", digits: 1, values: historyValues(\.bodyMassKg)
                    )
                    Divider()
                    BSVitalRow(
                        title: "深蹲 e1RM", systemImage: "figure.strengthtraining.traditional",
                        tint: BSColor.strain, value: nil, unit: "kg",
                        comparison: "复盘里记下重量和次数后可估算"
                    )
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("workout-performance-card")
        }
    }

    private func historyValues(_ keyPath: KeyPath<DailyRawMetrics, Double?>) -> [Double] {
        let days = store.snapshot.historyDays.map(\.raw) + [store.snapshot.today.raw]
        return days.compactMap { $0[keyPath: keyPath] }
    }

    private func performanceRow(
        title: String,
        systemImage: String,
        tint: Color,
        unit: String,
        digits: Int,
        values: [Double]
    ) -> some View {
        let latest = values.last
        return BSVitalRow(
            title: title,
            systemImage: systemImage,
            tint: tint,
            value: latest.map { $0.formatted(.number.precision(.fractionLength(digits))) },
            unit: unit,
            comparison: changeText(values: values, unit: unit, digits: digits),
            trend: Array(values.suffix(Self.performanceTrendCount))
        )
    }

    private static let performanceTrendCount = 30

    private func changeText(values: [Double], unit: String, digits: Int) -> String {
        guard let first = values.first, let last = values.last else { return "暂无同步数据" }
        guard values.count >= 2 else { return "仅 1 次记录" }
        let delta = last - first
        let magnitude = abs(delta).formatted(.number.precision(.fractionLength(digits)))
        if magnitude == (0.0).formatted(.number.precision(.fractionLength(digits))) { return "较此前持平" }
        return "较此前 \(delta > 0 ? "+" : "−")\(magnitude) \(unit)"
    }

    private func proposalCard(_ proposal: WorkoutProposal) -> some View {
        BSCard {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                HStack {
                    Label("AI 训练建议", systemImage: "sparkles")
                        .bsText(.label)
                    Spacer()
                    Text(proposal.template.focusTag)
                        .bsText(.caption)
                }
                Text(proposal.template.title)
                    .bsText(.cardTitle)
                Text(proposal.rationale)
                    .bsText(.caption)
                proposalChips(proposal)
                HStack(spacing: BSSpace.s) {
                    Button {
                        store.send(.askCoachTapped("针对 Coach 推荐的「\(proposal.template.title)」，结合我当前恢复与负荷状态帮我细化组次或调整动作"))
                    } label: {
                        Label("去 Coach 细化", systemImage: "sparkles")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BSColor.tint)
                    .frame(minHeight: BSSize.hitTarget)

                    Button("收起") {
                        store.send(.dismissProposalTapped)
                    }
                    .buttonStyle(.bordered)
                    .frame(minHeight: BSSize.hitTarget)
                }
            }
        }
    }

    private func proposalChips(_ proposal: WorkoutProposal) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpace.xs) {
                ForEach(proposal.template.exercises) { item in
                    let name = ExerciseCatalog.find(id: item.exerciseID)?.name ?? item.exerciseID
                    BSEvidenceChip("\(name) \(item.targetSets)×\(item.targetReps)")
                }
            }
        }
    }

    private var reviewSection: some View {
        BSSection(
            "待复盘",
            actionTitle: reviewToggleTitle,
            action: reviewToggleAction
        ) {
            VStack(spacing: BSSpace.s) {
                ForEach(visibleUnreviewed) { workout in
                    reviewRow(workout)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-review-inbox")
    }

    private var visibleUnreviewed: [StoredWorkoutRecord] {
        let all = store.unreviewedWorkouts
        return showAllUnreviewed ? all : Array(all.prefix(Self.inboxPreviewCount))
    }

    private var reviewToggleTitle: String? {
        let count = store.unreviewedWorkouts.count
        guard count > Self.inboxPreviewCount else { return nil }
        return showAllUnreviewed ? "收起" : "查看全部 (\(count))"
    }

    private var reviewToggleAction: (() -> Void)? {
        guard store.unreviewedWorkouts.count > Self.inboxPreviewCount else { return nil }
        return { showAllUnreviewed.toggle() }
    }

    private func reviewRow(_ workout: StoredWorkoutRecord) -> some View {
        let minutes = max(1, Int((workout.end.timeIntervalSince(workout.start) / 60).rounded()))
        let when = workout.start.formatted(.dateTime.month().day().hour().minute())
        return BSActionRow(
            title: workout.type,
            basis: "\(when) · \(minutes) 分钟",
            actionTitle: "一句话复盘",
            onExecute: { store.send(.openReviewTapped(workout)) },
            dismissTitle: "跳过",
            onDismiss: { store.send(.skipReviewTapped(workout)) },
            executeIdentifier: "workout-inbox-review-\(workout.hkUUID)",
            dismissIdentifier: "workout-inbox-skip-\(workout.hkUUID)"
        )
    }

    private var loadSection: some View {
        BSSection("负荷曲线", actionTitle: "查看趋势", action: { store.send(.openTrendsTapped) }) {
            loadCard
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("workout-training-load-card")
        }
    }

    private var loadSeries: [FitnessFatiguePoint] {
        FitnessFatigueModel.series(from: store.snapshot.historyDays)
    }

    private var loadCard: some View {
        let points = Array(loadSeries.suffix(Self.loadDisplayDays))
        let shown: FitnessFatiguePoint? = selectedLoadPoint ?? points.last(where: { $0.fitness != nil })
        let covered = points.filter { $0.load != nil }.count
        let label = loadLabel
        let side = loadSide(shown)
        let availability = loadAvailability(points)
        let caption = "体能 = 42 天指数加权负荷，疲劳 = 7 天 · 覆盖 \(covered)/\(points.count) 天"
        return BSChartCard(
            title: "训练负荷",
            label: label,
            value: shown.flatMap { $0.form }.map { formatForm($0) },
            range: loadRange(points),
            side: side,
            availability: availability,
            height: .standard,
            caption: caption
        ) {
            FitnessFatigueChart(points: points) { selectedLoadPoint = $0 }
        }
    }

    private var loadLabel: String {
        guard let selectedLoadPoint else { return "状态差（体能 − 疲劳）" }
        return selectedLoadPoint.date.formatted(.dateTime.month().day())
    }

    private func loadSide(_ point: FitnessFatiguePoint?) -> String {
        "体能 \(formatLoad(point?.fitness)) · 疲劳 \(formatLoad(point?.fatigue))"
    }

    private func loadAvailability(_ points: [FitnessFatiguePoint]) -> MetricAvailability {
        if points.contains(where: { $0.fitness != nil }) { return .available }
        return .missing(reason: "近 8 周还没有训练负荷数据")
    }

    private func loadRange(_ points: [FitnessFatiguePoint]) -> String {
        guard let first = points.first, let last = points.last else { return "" }
        let start = first.date.formatted(.dateTime.month().day())
        let end = last.date.formatted(.dateTime.month().day())
        return "\(start)–\(end)"
    }

    private func formatLoad(_ value: Double?) -> String {
        guard let value else { return "--" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    private func formatForm(_ value: Double?) -> String {
        guard let value else { return "--" }
        let rounded = value.rounded()
        let text = rounded.formatted(.number.precision(.fractionLength(0)))
        return rounded > 0 ? "+" + text : text
    }

    // MARK: - L3 训练档案

    private var archiveSection: some View {
        BSSection(
            "最近训练",
            actionTitle: archiveToggleTitle,
            action: archiveToggleAction
        ) {
            VStack(alignment: .leading, spacing: BSSpace.s) {
                if showAllArchive {
                    archiveFilterBar
                }
                archiveList(visibleArchive)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workout-archive-section")
    }

    private var visibleArchive: [StoredWorkoutRecord] {
        if showAllArchive {
            return filteredArchive(store.storedWorkouts)
        }
        return Array(store.archiveWorkouts.prefix(Self.archivePreviewCount))
    }

    private var canToggleArchive: Bool {
        showAllArchive
            || store.storedWorkouts.count > Self.archivePreviewCount
            || store.storedWorkouts.count > store.archiveWorkouts.count
    }

    private var archiveToggleTitle: String? {
        guard canToggleArchive else { return nil }
        return showAllArchive ? "仅看近期" : "查看全部 (\(store.storedWorkouts.count))"
    }

    private var archiveToggleAction: (() -> Void)? {
        guard canToggleArchive else { return nil }
        return { toggleArchive() }
    }

    private func toggleArchive() {
        showAllArchive.toggle()
        if !showAllArchive {
            archiveFilter = .all
        }
    }

    private func filteredArchive(_ base: [StoredWorkoutRecord]) -> [StoredWorkoutRecord] {
        switch archiveFilter {
        case .all:
            base
        case .unreviewed:
            base.filter { $0.reviewState == .unreviewed }
        case .annotated:
            base.filter { $0.reviewState == .annotated || $0.reviewState == .autoAttributed }
        }
    }

    private var archiveFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BSSpace.xs) {
                ForEach(ArchiveFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
        }
    }

    private func filterChip(_ filter: ArchiveFilter) -> some View {
        let selected = archiveFilter == filter
        return Button {
            archiveFilter = filter
        } label: {
            Text(filter.rawValue)
                .bsText(.label)
                .padding(.horizontal, BSSpace.s)
                .padding(.vertical, BSSpace.xxs)
                .background(selected ? BSColor.tint.opacity(BSOpacity.faint) : BSColor.surfaceInset, in: Capsule())
        }
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier("workout-archive-filter-\(filter.rawValue)")
    }

    @ViewBuilder
    private func archiveList(_ items: [StoredWorkoutRecord]) -> some View {
        if items.isEmpty {
            BSStateView(
                .empty,
                message: showAllArchive ? "当前筛选条件下暂无训练记录。" : "近 30 天还没有同步的手表训练。"
            )
        } else {
            ForEach(items) { workout in
                archiveRow(workout)
            }
        }
    }

    private func archiveRow(_ workout: StoredWorkoutRecord) -> some View {
        Button {
            store.send(.inspectWorkoutDetail(workout))
        } label: {
            BSCard {
                VStack(alignment: .leading, spacing: BSSpace.xs) {
                    HStack {
                        Text(workout.type)
                            .bsText(.cardTitle)
                        Spacer()
                        reviewBadge(workout.reviewState)
                    }
                    archiveMeta(workout)
                    archiveBadges(workout)
                    if let zones = workout.zones, zones.totalZoneMinutes > 0 {
                        ZoneBar(zones: zones, showsTrimp: true)
                    }
                }
            }
        }
        .buttonStyle(.bsPressable)
        .accessibilityIdentifier("workout-archive-row-\(workout.hkUUID)")
    }

    private func archiveMeta(_ workout: StoredWorkoutRecord) -> some View {
        let minutes = max(1, Int((workout.end.timeIntervalSince(workout.start) / 60).rounded()))
        let when = workout.start.formatted(.dateTime.month().day().hour().minute())
        let kcal = Int(workout.energy.rounded())
        let heartRate = workout.avgHR.map { " · 平均心率 \(Int($0.rounded()))" } ?? ""
        return Text("\(when) · \(minutes) 分钟 · \(kcal) kcal\(heartRate)")
            .bsText(.caption)
    }

    @ViewBuilder
    private func archiveBadges(_ workout: StoredWorkoutRecord) -> some View {
        let primary = store.muscleLoads
            .filter { $0.workoutUUID == workout.hkUUID && $0.role == .primary }
            .map(\.muscle.title)
        HStack(spacing: BSSpace.xs) {
            if let effortUser = workout.effortUser {
                BSEvidenceChip(String(format: "主观用力 %.1f", effortUser))
            }
            if let effortEst = workout.effortEstimated {
                BSEvidenceChip(String(format: "手表估算 %.1f", effortEst))
            }
            if !primary.isEmpty {
                Text(primary.joined(separator: "·"))
                    .bsText(.caption)
                    .lineLimit(1)
            }
        }
    }

    private func reviewBadge(_ state: WorkoutReviewState) -> some View {
        let title: String = switch state {
        case .unreviewed: "待复盘"
        case .autoAttributed: "自动归因"
        case .annotated: "已复盘"
        case .skipped: "已跳过"
        }
        return Text(title)
            .bsText(.caption)
    }
}
