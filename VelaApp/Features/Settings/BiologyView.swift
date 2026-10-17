import SwiftUI
import SwiftData
import UIKit
import Charts
import PDFKit
import UniformTypeIdentifiers
import Vision

struct BiologicalAgeHistoryPoint: Identifiable, Hashable {
    var id: Date { date }
    var date: Date
    var biologicalAge: Double
    var chronologicalAge: Double
    var evidenceCount: Int
}

enum BiologicalAgeHistoryBuilder {
    static func build(
        biomarkers: [BiomarkerRecord],
        currentChronologicalAge: Double,
        asOf: Date = Date(),
        calendar: Calendar = .current
    ) -> [BiologicalAgeHistoryPoint] {
        let days = Set(biomarkers.map { calendar.startOfDay(for: $0.date) }).sorted()
        return days.compactMap { day in
            let records = latestRecords(upTo: day, from: biomarkers, calendar: calendar)
            let yearsAgo = max(0, asOf.timeIntervalSince(day) / (365.25 * 86_400))
            let ageAtDate = max(0, currentChronologicalAge - yearsAgo)
            let result = BiologicalAgeEngine().calculate(input: BiologicalAgeInput(
                chronologicalAge: ageAtDate,
                biomarkers: records
            ))
            guard result.isPhenoAge else { return nil }
            return BiologicalAgeHistoryPoint(
                date: day,
                biologicalAge: result.biologicalAge,
                chronologicalAge: ageAtDate,
                evidenceCount: result.factors.count
            )
        }
    }

    private static func latestRecords(
        upTo day: Date,
        from biomarkers: [BiomarkerRecord],
        calendar: Calendar
    ) -> [BiomarkerRecord] {
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        var seen = Set<String>()
        return biomarkers
            .filter { $0.date < end }
            .sorted { $0.date > $1.date }
            .filter { seen.insert(normalizedName($0.name)).inserted }
    }

    private static func normalizedName(_ name: String) -> String {
        name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct BiologyView: View {
    let dashboard: DashboardSummary

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BiomarkerRecord.date, order: .reverse) private var biomarkers: [BiomarkerRecord]

    @State private var showLogSheet = false
    @State private var hoverFactorId: UUID? = nil
    @State private var biomarkerSearch = ""
    @State private var selectedBiomarkerName: String?
    @State private var showHealthRecordImporter = false
    @State private var healthRecordDraft: HealthRecordReviewDraft?
    @State private var healthRecordImportError: String?
    @AppStorage("vela_favorite_biomarker_names") private var favoriteBiomarkersRaw = ""

    private var language: AppLanguage {
        AppLanguage.stored
    }

    private var chronologicalAge: Int? {
        dashboard.extendedMetrics.age ?? WikiFileService.getAgeFromWiki()
    }

    private var hasHealthAgeInput: Bool {
        let dashboard = dashboard
        return dashboard.recoveryMetrics.restingHeartRate != nil
            || dashboard.bodyMetrics.vo2Max != nil
            || dashboard.sleepSummary.totalSleepMinutes > 0
            || dashboard.sleepScore.metrics["sleep_efficiency"] != nil
            || dashboard.strain.metrics["steps_raw"] != nil
            || !biomarkers.isEmpty
    }

    // Calculated Result
    private var bioAgeResult: BiologicalAgeResult {
        let chronologicalAge = Double(chronologicalAge ?? 0)
        let restingHR = dashboard.recoveryMetrics.restingHeartRate
        let vo2Max = dashboard.bodyMetrics.vo2Max
        let sleepMinutes = dashboard.sleepSummary.totalSleepMinutes
        let sleepHours = sleepMinutes > 0 ? Double(sleepMinutes) / 60.0 : nil
        let steps = dashboard.strain.metrics["steps_raw"]
        let sleepEfficiency = dashboard.sleepScore.metrics["sleep_efficiency"].map { $0 / 100 }

        let input = BiologicalAgeInput(
            chronologicalAge: chronologicalAge,
            restingHR: restingHR,
            vo2Max: vo2Max,
            sleepHours: sleepHours,
            sleepEfficiency: sleepEfficiency,
            steps: steps,
            biomarkers: Array(biomarkers)
        )

        return BiologicalAgeEngine().calculate(input: input)
    }

    // MARK: - Biology Title Header
    private var biologyHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hasHealthAgeInput && bioAgeResult.isPhenoAge
                    ? L10n.t("Biological Age Estimate", "生物年龄估算")
                    : L10n.t("Health Signal Reference", "健康信号参考")
                )
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(VelaTheme.fg)
                Text(L10n.t("BIOLOGY DASHBOARD", "生物特征仪表盘"))
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.accent)
                    .tracking(0.8)
            }
            Spacer()

            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                showLogSheet = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(VelaTheme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if chronologicalAge == nil {
                    profileSetupCard
                } else if !hasHealthAgeInput {
                    healthSignalSetupCard
                } else {
                    // Arc Gauge Hero Card
                    bioAgeArcCard

                    // Stats Breakdown Grid
                    statsGrid

                    biologicalAgeTimelineSection

                    // Wearables and Biomarkers Sections
                    VStack(alignment: .leading, spacing: 16) {
                        SectionLabel(title: L10n.t("Wearable Physiology", "生理可穿戴指标"), icon: "appletwatch")
                        wearableFactorsSection

                        HStack {
                            SectionLabel(title: L10n.t("Lab Blood Biomarkers", "血检生化指标"), icon: "drop.fill")
                            Spacer()
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                showLogSheet = true
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus.circle.fill")
                                    Text(L10n.t("Add Lab Results", "录入血检"))
                                }
                                .font(.caption.bold())
                                .foregroundStyle(VelaTheme.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(VelaTheme.accent.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        }
                        .padding(.top, 8)

                        biomarkersSection

                        healthRecordsSection
                    }
                    .padding(.horizontal, VelaTheme.pagePadding)
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                biologyHeader
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial)

                Divider()
                    .opacity(0.4)
            }
        }
        .background(VelaTheme.rhythmCanvas)
        .sheet(isPresented: $showLogSheet) {
            BloodLogSheetView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { selectedBiomarkerName != nil },
            set: { if !$0 { selectedBiomarkerName = nil } }
        )) {
            if let selectedBiomarkerName {
                BiomarkerHistorySheet(
                    name: selectedBiomarkerName,
                    records: biomarkers.filter { $0.name.caseInsensitiveCompare(selectedBiomarkerName) == .orderedSame }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
        .sheet(item: $healthRecordDraft) { draft in
            HealthRecordReviewSheet(draft: draft)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showHealthRecordImporter,
            allowedContentTypes: [.pdf, .plainText, .image],
            allowsMultipleSelection: false
        ) { result in
            importHealthRecord(result)
        }
        .alert("健康记录导入失败", isPresented: Binding(
            get: { healthRecordImportError != nil },
            set: { if !$0 { healthRecordImportError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(healthRecordImportError ?? "")
        }
    }

    // MARK: - Subviews

    private var profileSetupCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.text.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(VelaTheme.accent)
            Text(L10n.t("Set up your profile first", "请先完成个人档案初始设置"))
                .font(.headline)
                .foregroundStyle(VelaTheme.fg)
            Text(L10n.t(
                "Biological age needs your real chronological age. Vela reads it from Apple Health or your personal Wiki profile.",
                "生物年龄需要你的真实年龄。Vela 会优先读取个人 Wiki 档案，也可以读取 Apple 健康中的年龄。"
            ))
            .font(.caption)
            .multilineTextAlignment(.center)
            .foregroundStyle(VelaTheme.fg2)
            NavigationLink(destination: WikiProfileView()) {
                Text(L10n.t("Open personal Wiki", "打开个人 Wiki 档案"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(VelaTheme.accent))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge).fill(VelaTheme.surface))
        .padding(.horizontal, VelaTheme.pagePadding)
    }

    private var healthSignalSetupCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 34))
                .foregroundStyle(VelaTheme.accent)
            Text("健康信号尚未形成")
                .font(.headline)
                .foregroundStyle(VelaTheme.fg)
            Text("同步至少一项静息心率、睡眠、活动、最大摄氧量或化验记录后，才会显示健康信号参考。完整 PhenoAge 化验组合齐全后才生成生物年龄估算。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(VelaTheme.fg2)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: VelaTheme.radiusCardLarge).fill(VelaTheme.surface))
        .padding(.horizontal, VelaTheme.pagePadding)
    }

    private var bioAgeArcCard: some View {
        let result = bioAgeResult
        let chronologicalAge = Double(chronologicalAge ?? 0)
        let diff = chronologicalAge - result.biologicalAge
        let isPositive = result.isPhenoAge
            ? result.biologicalAge <= chronologicalAge
            : result.healthAgeTrend != "worsening"

        return VStack(spacing: 20) {
            ZStack {
                // Glow Backdrop
                Circle()
                    .fill(isPositive ? VelaTheme.recoveryColor.opacity(0.08) : VelaTheme.stressColor.opacity(0.08))
                    .frame(width: 170, height: 170)
                    .blur(radius: 20)

                // 270 degree Gauge Arc
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(
                        Color.black.opacity(0.05),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 170, height: 170)
                    .rotationEffect(.degrees(135))

                // Value Arc
                Circle()
                    .trim(from: 0.0, to: 0.75 * CGFloat(result.overallScore / 100))
                    .stroke(
                        LinearGradient(
                            colors: isPositive
                                ? [VelaTheme.accent, VelaTheme.recoveryColor]
                                : [VelaTheme.energyColor, VelaTheme.stressColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 170, height: 170)
                    .rotationEffect(.degrees(135))

                // End Dot Pointer with Neon Glow
                let progressAngle = 135.0 + (result.overallScore / 100.0) * 270.0
                let radius = 170.0 / 2.0
                Circle()
                    .fill(isPositive ? VelaTheme.recoveryColor : VelaTheme.stressColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: isPositive ? VelaTheme.recoveryColor : VelaTheme.stressColor, radius: 6)
                    .offset(
                        x: cos(CGFloat(progressAngle * .pi / 180.0)) * radius,
                        y: sin(CGFloat(progressAngle * .pi / 180.0)) * radius
                    )

                // Center Data Display
                VStack(spacing: 2) {
                    if result.isPhenoAge {
                        Text(String(format: "%.1f", result.biologicalAge))
                            .font(.system(.largeTitle, design: .rounded, weight: .black))
                            .foregroundStyle(VelaTheme.fg)
                            .monospacedDigit()

                        Text(L10n.t("Years Old", "岁 (生物年龄)"))
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.muted)
                            .tracking(1)

                        HStack(spacing: 4) {
                            Image(systemName: isPositive ? "arrow.down.forward.and.arrow.up.backward" : "arrow.up.forward.and.arrow.down.backward")
                            Text(String(format: "%.1f", chronologicalAge))
                                .bold()
                        }
                        .font(.system(.caption, design: .default))
                        .foregroundStyle(VelaTheme.fg2)
                        .padding(.top, 4)
                    } else {
                        Text(result.healthAgeTrendLabel)
                            .font(.system(.title, design: .rounded, weight: .black))
                            .foregroundStyle(VelaTheme.fg)

                        Text(L10n.t("Health Signal Reference", "健康信号参考"))
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(VelaTheme.muted)
                            .tracking(1)
                    }
                }
            }
            .frame(width: 200, height: 200)

            // Age Comparison Banner
            HStack(spacing: 8) {
                Image(systemName: isPositive ? "leaf.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(isPositive ? VelaTheme.recoveryColor : VelaTheme.stressColor)

                Text(result.isPhenoAge
                    ? (diff >= 0
                        ? L10n.t(String(format: "Estimated biological age is %.1f years below chronological age.", diff), String(format: "生物年龄估算比实际年龄低 %.1f 岁。", diff))
                        : L10n.t(String(format: "Estimated biological age is %.1f years above chronological age.", -diff), String(format: "生物年龄估算比实际年龄高 %.1f 岁。", -diff)))
                    : L10n.t("Current health signals: \(result.healthAgeTrendLabel)", "当前健康信号：\(result.healthAgeTrendLabel)")
                )
                .font(.system(.footnote, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.fg)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                    .fill(isPositive ? VelaTheme.recoveryColor.opacity(0.08) : VelaTheme.stressColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                    .stroke(isPositive ? VelaTheme.recoveryColor.opacity(0.15) : VelaTheme.stressColor.opacity(0.15), lineWidth: 1)
            )
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .velaNativeCard(radius: 24)
        .appleIntelligenceGlow(isHighlighted: isPositive, radius: 24)
        .padding(.horizontal, VelaTheme.pagePadding)
    }

    private var statsGrid: some View {
        let result = bioAgeResult

        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            StatGridCard(
                title: L10n.t("Overall Score", "综合活力分"),
                value: String(format: "%.0f", result.overallScore),
                unit: "/100",
                icon: "bolt.heart.fill",
                color: VelaTheme.accent
            )

            StatGridCard(
                title: L10n.t("Biomarkers Status", "指标正常数"),
                value: "\(result.optimalCount)",
                unit: "/\(result.factors.count)",
                icon: "checkmark.shield.fill",
                color: VelaTheme.recoveryColor
            )

            StatGridCard(
                title: L10n.t("Confidence", "估算可信度"),
                value: result.isPhenoAge ? L10n.t("High", "较高") : L10n.t("Limited", "有限"),
                unit: result.isPhenoAge ? L10n.t("complete labs", "完整化验") : L10n.t("partial signals", "部分信号"),
                icon: "checkmark.seal.fill",
                color: result.isPhenoAge ? VelaTheme.recoveryColor : VelaTheme.energyColor
            )

            StatGridCard(
                title: L10n.t("20-year scenario", "20 年情景"),
                value: result.isPhenoAge ? String(format: "%.1f", result.biologicalAge + 20) : "—",
                unit: result.isPhenoAge ? L10n.t("if gap stays", "差值不变") : L10n.t("insufficient data", "数据不足"),
                icon: "calendar.badge.clock",
                color: VelaTheme.sleepColor
            )
        }
        .padding(.horizontal, VelaTheme.pagePadding)
    }

    @ViewBuilder
    private var biologicalAgeTimelineSection: some View {
        let history = BiologicalAgeHistoryBuilder.build(
            biomarkers: biomarkers,
            currentChronologicalAge: Double(chronologicalAge ?? 0)
        )
        if bioAgeResult.isPhenoAge {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("生物年龄历史与 Projection")
                            .font(VelaTheme.headline())
                        Text("仅使用当时已存在的完整 PhenoAge 化验组合")
                            .font(VelaTheme.caption2())
                            .foregroundStyle(VelaTheme.muted)
                    }
                    Spacer()
                    Image(systemName: "chart.xyaxis.line")
                        .foregroundStyle(VelaTheme.accent)
                }

                if history.count >= 2 {
                    Chart {
                        ForEach(history) { point in
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("生物年龄", point.biologicalAge)
                            )
                            .foregroundStyle(by: .value("系列", "生物年龄"))
                            PointMark(
                                x: .value("日期", point.date),
                                y: .value("生物年龄", point.biologicalAge)
                            )
                            .foregroundStyle(by: .value("系列", "生物年龄"))
                            LineMark(
                                x: .value("日期", point.date),
                                y: .value("实际年龄", point.chronologicalAge)
                            )
                            .foregroundStyle(by: .value("系列", "实际年龄"))
                        }
                    }
                    .chartForegroundStyleScale([
                        "生物年龄": VelaTheme.accent,
                        "实际年龄": VelaTheme.muted
                    ])
                    .frame(height: 180)
                } else {
                    VelaStateCard(
                        state: .partial,
                        title: "需要第二组完整化验",
                        message: "当前估算有效，但只有一次完整 PhenoAge 面板，暂不能绘制历史趋势。"
                    )
                }

                HStack(spacing: 10) {
                    projectionMetric("现在", biological: bioAgeResult.biologicalAge, chronological: Double(chronologicalAge ?? 0))
                    Image(systemName: "arrow.right")
                        .foregroundStyle(VelaTheme.rhythmInkSecondary)
                    projectionMetric("20 年情景", biological: bioAgeResult.biologicalAge + 20, chronological: Double(chronologicalAge ?? 0) + 20)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(VelaTheme.rhythmCanvasRaised))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(VelaTheme.rhythmMist, lineWidth: 0.75))
            .padding(.horizontal, VelaTheme.pagePadding)
        }
    }

    private func projectionMetric(_ title: String, biological: Double, chronological: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(VelaTheme.caption2().weight(.semibold))
                .foregroundStyle(VelaTheme.muted)
            Text(String(format: "%.1f 岁", biological))
                .font(VelaTheme.subheadline().weight(.bold).monospacedDigit())
            Text("实际年龄 \(String(format: "%.1f", chronological))")
                .font(.system(.caption2, design: .default))
                .foregroundStyle(VelaTheme.muted)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VelaTheme.secondaryGroupedBackground, in: RoundedRectangle(cornerRadius: 14))
    }

    private var wearableFactorsSection: some View {
        let result = bioAgeResult
        let wearables = result.factors.filter { $0.type == .wearable }

        return VStack(spacing: 12) {
            if wearables.isEmpty {
                Text(L10n.t("No wearable logs found for calculation.", "暂无生理指标数据。"))
                    .font(.caption)
                    .foregroundStyle(VelaTheme.muted)
                    .padding()
            } else {
                ForEach(wearables) { factor in
                    FactorRowView(factor: factor)
                }
            }
        }
        .padding(14)
        .velaNativeCard(radius: 16)
    }

    private var biomarkersSection: some View {
        let result = bioAgeResult
        let bios = result.factors.filter { $0.type == .biomarker }
        let visible = visibleBiomarkers

        return VStack(spacing: 12) {
            if bios.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "drop.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(VelaTheme.muted)

                    Text(L10n.t("No blood records entered.", "还没有录入过血检指标。"))
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)

                    Text(L10n.t("Record lab values here for reference. A biological-age estimate appears only when the complete PhenoAge laboratory set is available.", "可在这里记录化验指标供参考；只有完整的 PhenoAge 化验组合齐全后才会生成生物年龄估算。"))
                        .font(.caption)
                        .foregroundStyle(VelaTheme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(VelaTheme.muted)
                    TextField(L10n.t("Search biomarkers", "搜索指标"), text: $biomarkerSearch)
                        .textInputAutocapitalization(.never)
                    if !biomarkerSearch.isEmpty {
                        Button {
                            biomarkerSearch = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(VelaTheme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(11)
                .background(VelaTheme.surface, in: RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous))

                // Grid of circular glowing badges
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 14) {
                    ForEach(visible) { bm in
                        Button {
                            selectedBiomarkerName = bm.name
                        } label: {
                            BiomarkerBadgeView(
                                biomarker: bm,
                                isFavorite: favoriteBiomarkerNames.contains(bm.name)
                            )
                        }
                        .buttonStyle(.cardPress)
                        .accessibilityHint(L10n.t("Open history and record controls", "查看趋势、收藏和记录管理"))
                    }
                }
                .padding(.vertical, 8)

                Divider().background(VelaTheme.borderSoft)

                // Detailed biomarker list
                VStack(spacing: 12) {
                    ForEach(bios) { factor in
                        FactorRowView(factor: factor)
                    }
                }
            }
        }
        .padding(14)
        .velaNativeCard(radius: 16)
    }

    private var healthRecordsSection: some View {
        let names = Array(Set(biomarkers.compactMap(\.sourceDocumentName))).sorted()
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "健康记录", icon: "doc.text.magnifyingglass")
                Spacer()
                Button {
                    showHealthRecordImporter = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
            }

            if names.isEmpty {
                Text("可导入 PDF、文本或化验单图片。Vela 只在本机提取候选指标，并要求你逐项核对后才保存。")
                    .font(.caption)
                    .foregroundStyle(VelaTheme.muted)
            } else {
                ForEach(names, id: \.self) { name in
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(VelaTheme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(biomarkers.filter { $0.sourceDocumentName == name }.count) 项已审核指标")
                                .font(.caption2)
                                .foregroundStyle(VelaTheme.muted)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            deleteHealthRecord(named: name)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除健康记录及关联指标")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .velaNativeCard(radius: 16)
    }

    private func importHealthRecord(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result { healthRecordImportError = error.localizedDescription }
            return
        }
        Task { @MainActor in
            do {
                let text = try await HealthRecordTextExtractor.extract(from: url)
                let candidates = HealthRecordBiomarkerParser.parse(text)
                guard !candidates.isEmpty else {
                    throw HealthRecordImportError.noRecognizedBiomarkers
                }
                healthRecordDraft = HealthRecordReviewDraft(
                    sourceName: url.lastPathComponent,
                    candidates: candidates
                )
            } catch {
                healthRecordImportError = error.localizedDescription
            }
        }
    }

    private func deleteHealthRecord(named name: String) {
        for record in biomarkers where record.sourceDocumentName == name {
            modelContext.delete(record)
        }
        try? modelContext.save()
    }

    private var favoriteBiomarkerNames: Set<String> {
        Set(favoriteBiomarkersRaw.split(separator: "|").map(String.init))
    }

    private var visibleBiomarkers: [BiomarkerRecord] {
        var latestByName: [String: BiomarkerRecord] = [:]
        for record in biomarkers {
            let key = record.name.lowercased()
            if latestByName[key] == nil { latestByName[key] = record }
        }
        return latestByName.values
            .filter { biomarkerSearch.isEmpty || $0.name.localizedCaseInsensitiveContains(biomarkerSearch) }
            .sorted {
                let lhsFavorite = favoriteBiomarkerNames.contains($0.name)
                let rhsFavorite = favoriteBiomarkerNames.contains($1.name)
                if lhsFavorite != rhsFavorite { return lhsFavorite }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }
}

// MARK: - Section Label
struct SectionLabel: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline.bold())
                .foregroundStyle(VelaTheme.accent)
            Text(title)
                .font(.system(.callout, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.fg)
        }
    }
}

// MARK: - Grid Card
struct StatGridCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .font(.body)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)

                    Text(unit)
                        .font(.caption)
                        .foregroundStyle(VelaTheme.fg2)
                }

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .padding(14)
        .velaNativeCard(radius: 16)
    }
}

// MARK: - Factor Row
struct FactorRowView: View {
    let factor: BiologicalAgeFactor

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(factor.isOptimal ? VelaTheme.recoveryColor.opacity(0.12) : VelaTheme.stressColor.opacity(0.12))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: factor.isOptimal ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(factor.isOptimal ? VelaTheme.recoveryColor : VelaTheme.stressColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(factor.name)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(VelaTheme.fg)

                Text(factor.description)
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f", factor.score))
                    .font(.system(.callout, design: .default, weight: .bold))
                    .foregroundStyle(factor.isOptimal ? VelaTheme.recoveryColor : VelaTheme.stressColor)

                Text(L10n.t("Score", "得分"))
                    .font(.system(.caption2, design: .default))
                    .foregroundStyle(VelaTheme.muted)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.01))
    }
}

// MARK: - Biomarker Badge View
struct BiomarkerBadgeView: View {
    let biomarker: BiomarkerRecord
    var isFavorite = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Glowing outer ring
                Circle()
                    .stroke(biomarker.isOptimal ? VelaTheme.recoveryColor.opacity(0.15) : VelaTheme.stressColor.opacity(0.15), lineWidth: 4)
                    .frame(width: 66, height: 66)
                    .shadow(color: biomarker.isOptimal ? VelaTheme.recoveryColor.opacity(0.2) : VelaTheme.stressColor.opacity(0.2), radius: 4)

                Circle()
                    .fill(VelaTheme.bg.opacity(0.8))
                    .frame(width: 58, height: 58)

                VStack(spacing: 1) {
                    Text(String(format: "%.1f", biomarker.value))
                        .font(.system(.footnote, design: .default, weight: .bold))
                        .foregroundStyle(VelaTheme.fg)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)

                    Text(biomarker.unit)
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(VelaTheme.muted)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
            }
            .frame(width: 70, height: 70)

            Text(biomarker.name)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.fg)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if isFavorite {
                Label(L10n.t("Favorite", "已收藏"), systemImage: "star.fill")
                    .font(.system(.caption2, design: .default, weight: .bold))
                    .foregroundStyle(VelaTheme.energyColor)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: VelaTheme.radiusMd, style: .continuous)
                .fill(Color.black.opacity(0.02))
        )
    }
}

private struct BiomarkerHistorySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("vela_favorite_biomarker_names") private var favoritesRaw = ""

    let name: String
    let records: [BiomarkerRecord]

    private var sortedRecords: [BiomarkerRecord] {
        records.sorted { $0.date < $1.date }
    }

    private var isFavorite: Bool {
        Set(favoritesRaw.split(separator: "|").map(String.init)).contains(name)
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedRecords.count >= 2 {
                    Section(L10n.t("Trend", "趋势")) {
                        Chart(sortedRecords) { record in
                            LineMark(
                                x: .value("Date", record.date),
                                y: .value("Value", record.value)
                            )
                            .foregroundStyle(VelaTheme.accent)
                            PointMark(
                                x: .value("Date", record.date),
                                y: .value("Value", record.value)
                            )
                            .foregroundStyle(record.isOptimal ? VelaTheme.recoveryColor : VelaTheme.stressColor)
                        }
                        .frame(height: 180)
                    }
                }

                Section(L10n.t("Records", "历史记录")) {
                    ForEach(sortedRecords.reversed()) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("\(record.value, specifier: "%.2f") \(record.unit)")
                                    .font(.headline.monospacedDigit())
                                Spacer()
                                Text(record.date, style: .date)
                                    .font(.caption)
                                    .foregroundStyle(VelaTheme.muted)
                            }
                            Text("\(record.referenceMin, specifier: "%.2f")–\(record.referenceMax, specifier: "%.2f") \(record.unit)")
                                .font(.caption)
                                .foregroundStyle(VelaTheme.muted)
                            if let source = record.sourceDocumentName, !source.isEmpty {
                                Label(source, systemImage: "doc.text")
                                    .font(.caption2)
                                    .foregroundStyle(VelaTheme.fg2)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                modelContext.delete(record)
                                try? modelContext.save()
                            } label: {
                                Label(L10n.t("Delete", "删除"), systemImage: "trash")
                            }
                        }
                    }
                }

                Section {
                    Text(L10n.t(
                        "Trends reflect entered laboratory records only. Reference intervals can differ by laboratory and are not a diagnosis.",
                        "趋势只反映已录入的化验记录。参考区间可能因实验室而异，不构成诊断。"
                    ))
                    .font(.caption)
                    .foregroundStyle(VelaTheme.muted)
                }
            }
            .navigationTitle(name)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        toggleFavorite()
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                    }
                    .accessibilityLabel(isFavorite ? L10n.t("Remove favorite", "取消收藏") : L10n.t("Favorite", "收藏"))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("Done", "完成")) { dismiss() }
                }
            }
        }
    }

    private func toggleFavorite() {
        var values = Set(favoritesRaw.split(separator: "|").map(String.init))
        if values.contains(name) { values.remove(name) } else { values.insert(name) }
        favoritesRaw = values.sorted().joined(separator: "|")
    }
}

struct HealthRecordBiomarkerCandidate: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var valueText: String
    var unit: String
    var referenceMinText: String
    var referenceMaxText: String
    var isIncluded = true
}

struct HealthRecordReviewDraft: Identifiable {
    let id = UUID()
    let sourceName: String
    var candidates: [HealthRecordBiomarkerCandidate]
}

enum HealthRecordImportError: LocalizedError {
    case unsupportedFile
    case unreadableFile
    case noRecognizedBiomarkers

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: "暂不支持这个文件格式。请选择 PDF、文本或图片。"
        case .unreadableFile: "无法读取这份文件。"
        case .noRecognizedBiomarkers: "没有找到可可靠识别的常见化验指标。请改用手工录入，并核对原始报告。"
        }
    }
}

enum HealthRecordTextExtractor {
    static func extract(from url: URL) async throws -> String {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)

        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(data: data) else { throw HealthRecordImportError.unreadableFile }
            let text = (0..<document.pageCount)
                .compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n")
            guard !text.isEmpty else { throw HealthRecordImportError.unreadableFile }
            return text
        }

        if let text = String(data: data, encoding: .utf8), !text.isEmpty {
            return text
        }

        guard let image = UIImage(data: data), let cgImage = image.cgImage else {
            throw HealthRecordImportError.unsupportedFile
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        try VNImageRequestHandler(cgImage: cgImage).perform([request])
        let text = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        guard !text.isEmpty else { throw HealthRecordImportError.unreadableFile }
        return text
    }
}

enum HealthRecordBiomarkerParser {
    private struct Definition {
        let canonicalName: String
        let aliases: [String]
        let unit: String
        let range: ClosedRange<Double>
    }

    private static let definitions = [
        Definition(canonicalName: "Albumin", aliases: ["albumin", "白蛋白"], unit: "g/dL", range: 3.5...5.0),
        Definition(canonicalName: "Creatinine", aliases: ["creatinine", "肌酐"], unit: "mg/dL", range: 0.6...1.2),
        Definition(canonicalName: "Glucose", aliases: ["glucose", "葡萄糖", "血糖"], unit: "mg/dL", range: 70...100),
        Definition(canonicalName: "CRP", aliases: ["crp", "c-reactive protein", "c反应蛋白"], unit: "mg/L", range: 0...3),
        Definition(canonicalName: "Lymphocyte Percentage", aliases: ["lymphocyte", "淋巴细胞百分比"], unit: "%", range: 20...40),
        Definition(canonicalName: "MCV", aliases: ["mcv", "平均红细胞体积"], unit: "fL", range: 80...100),
        Definition(canonicalName: "RDW", aliases: ["rdw", "红细胞分布宽度"], unit: "%", range: 11...15),
        Definition(canonicalName: "Alkaline Phosphatase", aliases: ["alkaline phosphatase", "alp", "碱性磷酸酶"], unit: "U/L", range: 44...147),
        Definition(canonicalName: "WBC", aliases: ["wbc", "white blood cell", "白细胞"], unit: "10^3/uL", range: 4...11),
        Definition(canonicalName: "Vitamin D", aliases: ["vitamin d", "25-oh", "维生素d"], unit: "ng/mL", range: 30...100),
        Definition(canonicalName: "Ferritin", aliases: ["ferritin", "铁蛋白"], unit: "ng/mL", range: 30...400),
        Definition(canonicalName: "HbA1c", aliases: ["hba1c", "glycated hemoglobin", "糖化血红蛋白"], unit: "%", range: 4...5.6)
    ]

    static func parse(_ text: String) -> [HealthRecordBiomarkerCandidate] {
        let lines = text.components(separatedBy: .newlines)
        var found: [String: HealthRecordBiomarkerCandidate] = [:]
        for line in lines {
            let normalized = line.lowercased()
            guard let definition = definitions.first(where: { definition in
                definition.aliases.contains { normalized.contains($0.lowercased()) }
            }), let value = firstNumber(afterAny: definition.aliases, in: line) else { continue }
            found[definition.canonicalName] = HealthRecordBiomarkerCandidate(
                name: definition.canonicalName,
                valueText: value,
                unit: detectedUnit(in: line) ?? definition.unit,
                referenceMinText: definition.range.lowerBound.formatted(),
                referenceMaxText: definition.range.upperBound.formatted()
            )
        }
        return found.values.sorted { $0.name < $1.name }
    }

    private static func firstNumber(afterAny aliases: [String], in line: String) -> String? {
        let source = line as NSString
        guard let alias = aliases.first(where: {
            source.range(of: $0, options: .caseInsensitive).location != NSNotFound
        }) else { return nil }
        let aliasRange = source.range(of: alias, options: .caseInsensitive)
        let suffix = source.substring(from: NSMaxRange(aliasRange))
        guard let regex = try? NSRegularExpression(pattern: "[-+]?[0-9]+(?:[.,][0-9]+)?"),
              let match = regex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)),
              let swiftRange = Range(match.range, in: suffix) else { return nil }
        return String(suffix[swiftRange]).replacingOccurrences(of: ",", with: ".")
    }

    private static func detectedUnit(in line: String) -> String? {
        ["mg/dL", "mg/L", "g/dL", "ng/mL", "U/L", "fL", "%", "10^3/uL"]
            .first { line.localizedCaseInsensitiveContains($0) }
    }
}

private struct HealthRecordReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let draft: HealthRecordReviewDraft
    @State private var candidates: [HealthRecordBiomarkerCandidate]
    @State private var testDate = Date()
    @State private var errorMessage: String?

    init(draft: HealthRecordReviewDraft) {
        self.draft = draft
        _candidates = State(initialValue: draft.candidates)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("原始记录") {
                    LabeledContent("文件", value: draft.sourceName)
                    DatePicker("检测日期", selection: $testDate, displayedComponents: .date)
                    Text("原始文件不会被 Vela 保留；只保存你确认的结构化指标和来源文件名。")
                        .font(.caption)
                        .foregroundStyle(VelaTheme.muted)
                }

                ForEach($candidates) { $candidate in
                    Section {
                        Toggle("保存此指标", isOn: $candidate.isIncluded)
                        TextField("指标名称", text: $candidate.name)
                        HStack {
                            TextField("数值", text: $candidate.valueText)
                                .keyboardType(.decimalPad)
                            TextField("单位", text: $candidate.unit)
                                .multilineTextAlignment(.trailing)
                        }
                        HStack {
                            TextField("参考下限", text: $candidate.referenceMinText)
                                .keyboardType(.decimalPad)
                            TextField("参考上限", text: $candidate.referenceMaxText)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        Text(candidate.name)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("审核识别结果")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认保存") { save() }
                }
            }
        }
    }

    private func save() {
        let included = candidates.filter(\.isIncluded)
        guard !included.isEmpty else {
            errorMessage = "请至少选择一项指标。"
            return
        }
        for candidate in included {
            guard let value = Double(candidate.valueText),
                  let minimum = Double(candidate.referenceMinText),
                  let maximum = Double(candidate.referenceMaxText),
                  value.isFinite, minimum.isFinite, maximum.isFinite,
                  minimum <= maximum,
                  !candidate.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !candidate.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "请核对每项数值、单位和参考区间。"
                return
            }
            modelContext.insert(BiomarkerRecord(
                name: candidate.name.trimmingCharacters(in: .whitespacesAndNewlines),
                value: value,
                unit: candidate.unit.trimmingCharacters(in: .whitespacesAndNewlines),
                date: testDate,
                isOptimal: value >= minimum && value <= maximum,
                referenceMin: minimum,
                referenceMax: maximum,
                sourceDocumentName: draft.sourceName
            ))
        }
        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            errorMessage = "健康记录未保存，请重试。"
        }
    }
}

// MARK: - Manual Blood Log Sheet Form
struct BloodLogSheetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var valueString = ""
    @State private var unit = "ng/mL"
    @State private var refMinString = ""
    @State private var refMaxString = ""
    @State private var date = Date()
    @State private var errorMsg: String? = nil

    private let commonBiomarkers = [
        "Albumin", "Creatinine", "Glucose", "CRP", "Lymphocyte Percentage", "MCV", "RDW",
        "Alkaline Phosphatase", "WBC", "Vitamin D", "Cortisol", "Ferritin", "Cholesterol",
        "Testosterone", "TSH", "HbA1c"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                VelaTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        if let errorMsg = errorMsg {
                            HStack {
                                Image(systemName: "exclamationmark.octagon.fill")
                                    .foregroundStyle(VelaTheme.stressColor)
                                Text(errorMsg)
                                    .font(.caption)
                                    .foregroundStyle(VelaTheme.fg)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(VelaTheme.stressColor.opacity(0.12))
                            .cornerRadius(10)
                        }

                        // Suggestion chips
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L10n.t("Common Biomarkers", "常用血检指标"))
                                .font(.caption.bold())
                                .foregroundStyle(VelaTheme.fg2)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(commonBiomarkers, id: \.self) { item in
                                        Button {
                                            UISelectionFeedbackGenerator().selectionChanged()
                                            name = item
                                            autoFillDefaults(for: item)
                                        } label: {
                                            Text(item)
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(name == item ? VelaTheme.bg : VelaTheme.fg)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 6)
                                                .background(name == item ? VelaTheme.accent : Color.black.opacity(0.08))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }

                        // Fields
                        VStack(spacing: 16) {
                            StyledTextField(label: L10n.t("BIOMARKER NAME", "指标名称"), placeholder: "e.g., Vitamin D", text: $name)

                            HStack(spacing: 12) {
                                StyledTextField(label: L10n.t("VALUE", "数值"), placeholder: "e.g., 42.5", text: $valueString)
                                    .keyboardType(.decimalPad)

                                StyledTextField(label: L10n.t("UNIT", "单位"), placeholder: "e.g., ng/mL", text: $unit)
                            }

                            HStack(spacing: 12) {
                                StyledTextField(label: L10n.t("MIN REFERENCE", "标准下限"), placeholder: "e.g., 30", text: $refMinString)
                                    .keyboardType(.decimalPad)

                                StyledTextField(label: L10n.t("MAX REFERENCE", "标准上限"), placeholder: "e.g., 100", text: $refMaxString)
                                    .keyboardType(.decimalPad)
                            }

                            DatePicker(
                                L10n.t("TEST DATE", "检测日期"),
                                selection: $date,
                                displayedComponents: .date
                            )
                            .tint(VelaTheme.accent)
                            .font(.subheadline.bold())
                            .foregroundStyle(VelaTheme.fg)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(VelaTheme.rhythmCanvasRaised)
                            )
                        }

                        Spacer(minLength: 20)

                        Button {
                            saveBiomarker()
                        } label: {
                            Text(L10n.t("Save Biomarker", "保存指标"))
                                .font(.system(.body, design: .rounded).bold())
                                .foregroundStyle(VelaTheme.bg)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(VelaTheme.accent)
                                .cornerRadius(99)
                        }
                    }
                    .padding(VelaTheme.pagePadding)
                }
            }
            .navigationTitle(L10n.t("Log Lab Biomarker", "录入血检数据"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("Cancel", "取消")) {
                        dismiss()
                    }
                    .foregroundStyle(VelaTheme.fg2)
                }
            }
        }
    }

    private func autoFillDefaults(for bName: String) {
        switch bName {
        case "Albumin":
            unit = "g/dL"
            refMinString = "3.5"
            refMaxString = "5.0"
        case "Creatinine":
            unit = "mg/dL"
            refMinString = "0.6"
            refMaxString = "1.2"
        case "Glucose":
            unit = "mg/dL"
            refMinString = "70"
            refMaxString = "100"
        case "CRP":
            unit = "mg/L"
            refMinString = "0"
            refMaxString = "3"
        case "Lymphocyte Percentage":
            unit = "%"
            refMinString = "20"
            refMaxString = "40"
        case "MCV":
            unit = "fL"
            refMinString = "80"
            refMaxString = "100"
        case "RDW":
            unit = "%"
            refMinString = "11"
            refMaxString = "15"
        case "Alkaline Phosphatase":
            unit = "U/L"
            refMinString = "44"
            refMaxString = "147"
        case "WBC":
            unit = "10^3/uL"
            refMinString = "4"
            refMaxString = "11"
        case "Vitamin D":
            unit = "ng/mL"
            refMinString = "30"
            refMaxString = "100"
        case "Cortisol":
            unit = "mcg/dL"
            refMinString = "6"
            refMaxString = "23"
        case "Ferritin":
            unit = "ng/mL"
            refMinString = "30"
            refMaxString = "400"
        case "Cholesterol":
            unit = "mg/dL"
            refMinString = "100"
            refMaxString = "199"
        case "Testosterone":
            unit = "ng/dL"
            refMinString = "300"
            refMaxString = "1000"
        case "TSH":
            unit = "uIU/mL"
            refMinString = "0.4"
            refMaxString = "4.0"
        case "HbA1c":
            unit = "%"
            refMinString = "4.0"
            refMaxString = "5.6"
        default:
            break
        }
    }

    private func saveBiomarker() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMsg = L10n.t("Name is required.", "请输入指标名称。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard let val = Double(valueString), val.isFinite else {
            errorMsg = L10n.t("Invalid value format.", "请输入有效的数值。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard let rMin = Double(refMinString), let rMax = Double(refMaxString),
              rMin.isFinite, rMax.isFinite else {
            errorMsg = L10n.t("Reference min and max are required.", "请输入标准上限和下限。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMsg = L10n.t("Unit is required.", "请输入单位。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        guard rMin <= rMax else {
            errorMsg = L10n.t("Reference minimum must not exceed maximum.", "标准下限不能高于上限。")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        let isOptimal = val >= rMin && val <= rMax
        let record = BiomarkerRecord(
            name: name,
            value: val,
            unit: unit,
            date: date,
            isOptimal: isOptimal,
            referenceMin: rMin,
            referenceMax: rMax
        )

        modelContext.insert(record)

        do {
            try modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMsg = L10n.t("Could not save biomarker.", "指标保存失败，请重试。")
        }
    }
}

// MARK: - Styled Text Field Helper
struct StyledTextField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .default, weight: .bold))
                .foregroundStyle(VelaTheme.rhythmInkSecondary)
                .tracking(1)

            TextField(placeholder, text: $text)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(VelaTheme.rhythmCanvasRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(VelaTheme.rhythmMist, lineWidth: 0.75)
                )
                .foregroundStyle(VelaTheme.rhythmInk)
        }
    }
}
