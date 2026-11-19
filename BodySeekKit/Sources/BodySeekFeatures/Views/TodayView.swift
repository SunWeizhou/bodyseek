import BodySeekCore
import BodySeekDesign
import ComposableArchitecture
import SwiftUI

public struct TodayView: View {
    @Bindable var store: StoreOf<TodayFeature>
    private let zoomNamespace: Namespace.ID?

    public init(store: StoreOf<TodayFeature>, zoomNamespace: Namespace.ID? = nil) {
        self.store = store
        self.zoomNamespace = zoomNamespace
    }

    public var body: some View {
        ZStack(alignment: .top) {
            BevelTheme.canvas.ignoresSafeArea()
            BevelAmbientAura(recoveryScore: store.today.recovery.value)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    editorialHeader

                    if let error = store.lastError {
                        errorBanner(error)
                    }

                    if !store.snapshot.isAuthorized {
                        unauthorizedBanner
                    }

                    heroInstrumentCard

                    todayActionCard

                    stressAndEnergyRow

                    checkInCard

                    todayNutritionCard

                    sleepCard

                    vitalsGrid

                    if !store.today.raw.workouts.isEmpty {
                        workoutsCard
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .refreshable {
                store.send(.refreshTapped)
            }
        }
        .navigationTitle("")
        .bodyseekNavigationBarInline()
        .bodyseekTransparentNavigationBar()
        .toolbar {
            ToolbarItemGroup(placement: .bodyseekTrailing) {
                Menu {
                    Button {
                        store.send(.refreshTapped)
                    } label: {
                        Label("刷新健康数据", systemImage: "arrow.clockwise")
                    }
                    Button {
                        store.send(.openCheckInTapped)
                    } label: {
                        Label("记录今日状态", systemImage: "square.and.pencil")
                    }
                    Button {
                        store.send(.openNutritionTapped)
                    } label: {
                        Label("记录饮食与营养", systemImage: "fork.knife")
                    }
                    Button {
                        store.send(.askCoachTapped("请解读我今天的身体恢复与睡眠状态"))
                    } label: {
                        Label("询问 Coach", systemImage: "sparkles")
                    }
                    if !store.snapshot.isAuthorized {
                        Button {
                            store.send(.authorizationTapped)
                        } label: {
                            Label("授权 Apple 健康", systemImage: "heart.text.square")
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("记录")
                .accessibilityIdentifier("bodyseek-menu")

                Button {
                    store.send(.openSettingsTapped)
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("设置")
                .accessibilityIdentifier("settings-button")
            }
        }
    }

    // MARK: - Subviews

    private var editorialHeader: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(formattedEditorialDate(store.today.date)) · \(store.snapshot.sourceLabel)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BevelTheme.inkSecondary)

                Text("今日")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(BevelTheme.ink)
            }

            Spacer()

            if !store.snapshot.isAuthorized {
                Button {
                    store.send(.authorizationTapped)
                } label: {
                    Label("授权健康", systemImage: "heart.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BevelTheme.onBrand)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(BevelTheme.brand, in: Capsule())
                }
                .accessibilityIdentifier("today-authorize-button")
            } else if store.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .padding(.bottom, 6)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    private func errorBanner(_ message: String) -> some View {
        BevelCard(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(BevelTheme.dangerColor)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.ink)
            }
        }
    }

    private var unauthorizedBanner: some View {
        BevelCard {
            HStack(spacing: 16) {
                ReadinessEmptyIllustration()
                VStack(alignment: .leading, spacing: 6) {
                    Text("等待连接 Apple 健康")
                        .font(.headline)
                        .foregroundStyle(BevelTheme.ink)
                    Text("授权读取 HRV、睡眠分期与 Apple Watch 心率训练后，自动计算五项状态并构建 28 天基线。")
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        store.send(.authorizationTapped)
                    } label: {
                        Text("立即授权")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(BevelTheme.brand, in: Capsule())
                            .foregroundStyle(BevelTheme.onBrand)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var heroInstrumentCard: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            BodySeekBrandMark(size: 16)
                            Text("BodySeek · \(formattedTime(store.snapshot.lastUpdatedAt))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(BevelTheme.inkSecondary)
                            if case let .generated(_, engineName) = store.briefingStatus {
                                Text(engineName)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(BevelTheme.brandSoft, in: Capsule())
                                    .foregroundStyle(BevelTheme.brand)
                            }
                        }

                        briefingHeadlineView
                    }
                    Spacer(minLength: 8)
                    Button {
                        store.send(.toggleEvidenceBreakdown)
                    } label: {
                        Label("依据", systemImage: "doc.text.magnifyingglass")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.brand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(BevelTheme.brandSoft, in: Capsule())
                    }
                    .accessibilityIdentifier("today-advice-evidence")
                }

                if store.showEvidenceBreakdown {
                    Text(store.today.evidenceSummary)
                        .font(.caption)
                        .foregroundStyle(BevelTheme.inkSecondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 12) {
                    ringButton(for: store.today.recovery, identifier: "today-score-recovery")
                    ringButton(for: store.today.sleep, identifier: "today-score-sleep")
                    ringButton(for: store.today.strain, identifier: "today-score-strain")
                }

                VStack(alignment: .leading, spacing: 8) {
                    promptChip("结合近 7 天恢复与 ACWR，今天适合什么训练强度？")
                    promptChip("帮我根据昨晚睡眠构成安排今晚的恢复策略")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("today-score-instrument")
    }

    @ViewBuilder
    private var briefingHeadlineView: some View {
        switch store.briefingStatus {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在基于客观数据生成 AI 生理简报...")
                    .font(.subheadline)
                    .foregroundStyle(BevelTheme.inkSecondary)
            }
        case let .generated(text, _):
            Text(text)
                .font(.headline)
                .foregroundStyle(BevelTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        case .unconfigured, .idle:
            VStack(alignment: .leading, spacing: 6) {
                Text(store.today.factualSummary)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BevelTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    store.send(.openSettingsTapped)
                } label: {
                    Label("连接 DeepSeek 或 Apple 智能生成真 AI 简报", systemImage: "slider.horizontal.3")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BevelTheme.brand)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func ringButton(for score: MetricScore, identifier: String) -> some View {
        let base = Button {
            store.send(.metricTapped(score.kind))
        } label: {
            VStack(spacing: 8) {
                MetricRingView(score: score, diameter: 86, lineWidth: 9)
                Text(score.kind.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.ink)
                Text(score.subtitle)
                    .font(.caption2)
                    .foregroundStyle(BevelTheme.deviationInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)

        if let zoomNamespace {
            base.bodyseekZoomSource(id: "today-metric-\(score.kind.rawValue)", in: zoomNamespace)
        } else {
            base
        }
    }

    private func promptChip(_ text: String) -> some View {
        Button {
            store.send(.askCoachTapped(text))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(BevelTheme.brand)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(BevelTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(BevelTheme.surfaceElevated, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var todayActionCard: some View {
        let visibleItems = store.planItems.filter { $0.state != .dismissed }
        if !visibleItems.isEmpty {
            BevelCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("今日行动建议", systemImage: "checkmark.circle.trianglebadge.exclamationmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.brand)
                        Spacer()
                        Text("\(visibleItems.filter { $0.state == .adopted }.count)/\(visibleItems.count) 已采纳")
                            .font(.caption2.monospacedDigit())
                            .fontDesign(.rounded)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    ForEach(visibleItems) { record in
                        let item = record.decodedActionItem()
                        let isAdopted = record.state == .adopted
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: isAdopted ? "checkmark.circle.fill" : "circle.dashed")
                                    .foregroundStyle(isAdopted ? BevelTheme.recoveryColor : BevelTheme.brand)
                                    .font(.subheadline)
                                    .padding(.top, 2)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item?.title ?? "生理执行建议")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BevelTheme.ink)
                                    if let detail = item?.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(BevelTheme.inkSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    if let basis = item?.metricBasis {
                                        Text("依据：\(basis)")
                                            .font(.caption2)
                                            .foregroundStyle(BevelTheme.deviationInk)
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                Spacer()
                                if !isAdopted {
                                    Button("跳过") {
                                        store.send(.dismissPlanItem(record.id))
                                    }
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(BevelTheme.inkSecondary)
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("today-action-dismiss-\(record.id.uuidString)")
                                }
                                Button {
                                    store.send(.adoptPlanItem(record.id))
                                } label: {
                                    Text(isAdopted ? "已采纳" : "采纳")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .background(
                                            isAdopted ? BevelTheme.recoveryColor.opacity(0.16) : BevelTheme.brand,
                                            in: Capsule()
                                        )
                                        .foregroundStyle(isAdopted ? BevelTheme.recoveryColor : BevelTheme.onBrand)
                                }
                                .buttonStyle(.plain)
                                .disabled(isAdopted)
                                .accessibilityIdentifier("today-action-adopt-\(record.id.uuidString)")
                            }
                        }
                        .padding(10)
                        .background(BevelTheme.surfaceElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("today-action-card")
        }
    }

    private var todayNutritionCard: some View {
        let log = store.todayNutritionLog
        let todayKey = store.snapshot.referenceDate.physiologicalDayKey()
        let validated = NutritionTargetEvaluator.validate(plan: store.nutritionTargetPlan, on: todayKey)
        let isClosed = log?.dietDayComplete == true
        let coreIDs = ["diet_kcal", "diet_carbs_g", "diet_protein_g", "diet_fat_g"]

        return Button {
            store.send(.openNutritionTapped)
        } label: {
            BevelCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("每日营养与能量平衡", systemImage: "fork.knife.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.brand)
                        Spacer()
                        Text(isClosed ? "已结账" : (log == nil ? "未记录" : "记录中 · 未结账"))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                (isClosed ? BevelTheme.nutritionColor(for: .met) : BevelTheme.nutritionColor(for: .unknown)).opacity(0.16),
                                in: Capsule()
                            )
                            .foregroundStyle(BevelTheme.nutritionInkColor(for: isClosed ? .met : .unknown))
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("今日已记热量")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)
                            Text(log?.dietKcal.map { "\(Int($0.rounded())) kcal" } ?? "-- kcal")
                                .font(.title3.weight(.bold).monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(BevelTheme.ink)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("近 7 日日均缺口")
                                .font(.caption2)
                                .foregroundStyle(BevelTheme.inkSecondary)
                            Text(store.nutritionRollingDeficit7d.map { "\(Int($0.rounded())) kcal/日" } ?? "--")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .fontDesign(.rounded)
                                .foregroundStyle(BevelTheme.ink)
                        }
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], alignment: .leading, spacing: 6) {
                        ForEach(coreIDs, id: \.self) { id in
                            let eval = NutritionTargetEvaluator.evaluate(metricID: id, log: log, validatedPlan: validated)
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(BevelTheme.nutritionColor(for: eval.status))
                                    .frame(width: 8, height: 8)
                                Text(eval.metricName.replacingOccurrences(of: "总", with: ""))
                                    .font(.caption2)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-nutrition-card")
    }

    private var checkInCard: some View {
        Button {
            store.send(.openCheckInTapped)
        } label: {
            BevelCard(padding: 14) {
                HStack(spacing: 12) {
                    Image(systemName: store.todayCheckIn == nil ? "heart.text.square" : "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundStyle(store.todayCheckIn == nil ? BevelTheme.brand : BevelTheme.recoveryColor)

                    VStack(alignment: .leading, spacing: 3) {
                        if let checkIn = store.todayCheckIn {
                            Text("今日体感已记录")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BevelTheme.ink)
                            let sorenessText = checkIn.soreness.isEmpty ? "" : " · 酸痛 \(checkIn.soreness.count) 处"
                            Text("精力 \(checkIn.energy)/5 · 情绪 \(checkIn.mood)/5 · 压力 \(checkIn.stress)/5\(sorenessText)")
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .lineLimit(1)
                        } else {
                            Text("今日体感尚未记录 · 10 秒打卡")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BevelTheme.ink)
                            Text("量化主观精力、情绪、压力与酸痛，持续校准个人身体模型")
                                .font(.caption)
                                .foregroundStyle(BevelTheme.inkSecondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(store.todayCheckIn == nil ? "打卡" : "修改")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(BevelTheme.brandSoft, in: Capsule())
                        .foregroundStyle(BevelTheme.brand)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-checkin-card")
    }

    @ViewBuilder
    private var stressAndEnergyRow: some View {
        HStack(spacing: 12) {
            stressCardButton
            energyCardButton
        }
    }

    @ViewBuilder
    private var stressCardButton: some View {
        let button = Button {
            store.send(.metricTapped(.stress))
        } label: {
            BevelCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("压力", systemImage: MetricKind.stress.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.stressColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(store.today.stress.formattedScore)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                            .foregroundStyle(BevelTheme.ink)
                        Text(store.today.stress.badge)
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    IntradayBarChart(bins: store.today.stressTimeline, height: 34)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-card-stress")

        if let zoomNamespace {
            button.bodyseekZoomSource(id: "today-metric-stress", in: zoomNamespace)
        } else {
            button
        }
    }

    @ViewBuilder
    private var energyCardButton: some View {
        let button = Button {
            store.send(.metricTapped(.energy))
        } label: {
            BevelCard(padding: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("能量", systemImage: MetricKind.energy.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.energyColor)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(store.today.energy.formattedScore)
                            .font(.title2.weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                            .foregroundStyle(BevelTheme.ink)
                        Text(store.today.energy.subtitle)
                            .font(.caption)
                            .foregroundStyle(BevelTheme.inkSecondary)
                            .lineLimit(1)
                    }

                    EnergyAreaChart(curve: store.today.energyCurve, height: 34)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("today-card-energy")

        if let zoomNamespace {
            button.bodyseekZoomSource(id: "today-metric-energy", in: zoomNamespace)
        } else {
            button
        }
    }

    private var sleepCard: some View {
        Button {
            store.send(.metricTapped(.sleep))
        } label: {
            BevelCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("昨夜睡眠分期结构", systemImage: MetricKind.sleep.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BevelTheme.sleepColor)
                        Spacer()
                        Text(store.today.sleep.subtitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BevelTheme.ink)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }

                    if store.today.raw.sleepAsleepMinutes != nil {
                        SleepStageChart(segments: store.today.raw.sleepSegments, height: 148, interactive: false)
                    } else {
                        Text(store.today.sleep.availability.reasonText ?? "昨晚暂无睡眠分段数据")
                            .font(.footnote)
                            .foregroundStyle(BevelTheme.inkSecondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var vitalsGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("生理指标 · 近 14 天")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BevelTheme.inkSecondary)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                vitalCard(
                    title: "HRV",
                    valueText: store.today.raw.hrvMs.map { "\(Int($0.rounded())) ms" } ?? "-- ms",
                    points: store.recentHRVSeries,
                    tint: BevelTheme.recoveryColor
                )
                vitalCard(
                    title: "静息心率",
                    valueText: store.today.raw.restingHeartRateBpm.map { "\(Int($0.rounded())) bpm" } ?? "-- bpm",
                    points: store.recentRHRSeries,
                    tint: BevelTheme.heartRateAverage
                )
                vitalCard(
                    title: "呼吸频率",
                    valueText: store.today.raw.respiratoryRateBrpm.map { String(format: "%.1f 次/分", $0) } ?? "-- 次/分",
                    points: store.recentRespiratorySeries,
                    tint: BevelTheme.sleepColor
                )
                vitalCard(
                    title: "血氧饱和度",
                    valueText: store.today.raw.oxygenSaturationPct.map { String(format: "%.0f%%", $0) } ?? "-- %",
                    points: store.recentSpO2Series,
                    tint: BevelTheme.infoBlue
                )
            }
        }
    }

    private func vitalCard(
        title: String,
        valueText: String,
        points: [VitalSparkPoint],
        tint: Color
    ) -> some View {
        BevelCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BevelTheme.inkSecondary)
                Text(valueText)
                    .font(.title3.weight(.semibold).monospacedDigit())
                    .fontDesign(.rounded)
                    .contentTransition(.numericText())
                    .foregroundStyle(valueText.contains("--") ? BevelTheme.inkSecondary : BevelTheme.ink)
                MiniSparkline(vitalPoints: points, tint: tint, height: 42)
            }
        }
    }

    private var workoutsCard: some View {
        BevelCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("今日训练记录", systemImage: "figure.run.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BevelTheme.strainColor)

                ForEach(store.today.raw.workouts) { workout in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 12) {
                            Image(systemName: workout.symbolName)
                                .font(.title3)
                                .foregroundStyle(BevelTheme.strainColor)
                                .frame(width: 36, height: 36)
                                .background(BevelTheme.strainColor.opacity(0.14), in: Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workout.activityName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BevelTheme.ink)
                                Text("\(workout.durationMinutes) 分钟 · \(Int(workout.activeEnergyKcal.rounded())) kcal")
                                    .font(.caption)
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                            Spacer()
                            if let effort = workout.effortScore {
                                Text(String(format: "努力度 %.1f", effort))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(BevelTheme.strainColor.opacity(0.14), in: Capsule())
                                    .foregroundStyle(BevelTheme.strainColor)
                            } else if let avgHR = workout.averageHeartRate {
                                Text("\(Int(avgHR.rounded())) bpm")
                                    .font(.caption.weight(.medium).monospacedDigit())
                                    .foregroundStyle(BevelTheme.inkSecondary)
                            }
                        }

                        if let zones = workout.heartRateZones, zones.totalZoneMinutes > 0 {
                            ZoneBar(zones: zones)
                        }
                    }
                }
            }
        }
    }

    private func formattedEditorialDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans")
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
