import SwiftUI
import HealthKit

/// Shows which Apple Health signals Vela reads, which are missing,
/// and how missing data affects judgment quality.
struct DataCoverageView: View {
    @State private var coverageGroups: [CoverageGroup] = []
    @State private var isLoading = true

    var body: some View {
        ZStack {
            VelaTheme.rhythmCanvas.ignoresSafeArea()

            if isLoading {
                VelaEmptyState(
                    title: AppLanguage.stored.isChinese ? "正在检查数据覆盖" : "Checking Data Coverage",
                    message: AppLanguage.stored.isChinese ? "Vela 正在读取授权状态、新鲜度和样本数量。" : "Vela is reading authorization, freshness, and sample counts.",
                    systemImage: "waveform.path.ecg",
                    tint: VelaTheme.accent
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VelaRhythmSectionHeader(
                            eyebrow: "EVIDENCE",
                            title: AppLanguage.stored.isChinese ? "数据覆盖" : "Data Coverage",
                            actionTitle: nil,
                            action: {}
                        )
                        overallScoreCard

                        ForEach(coverageGroups) { group in
                            coverageGroupCard(group)
                        }
                    }
                    .padding(.horizontal, VelaTheme.pagePadding)
                    .padding(.top, 18)
                    .padding(.bottom, 112)
                }
                .scrollIndicators(.hidden)
            }
        }
        .navigationTitle(AppLanguage.stored.isChinese ? "数据覆盖" : "Data Coverage")
        .velaRhythmDetailChrome()
        .task {
            await loadCoverage()
        }
    }

    // MARK: - Overall Score

    private var overallScoreCard: some View {
        let total = coverageGroups.flatMap(\.signals).count
        let usable = coverageGroups.flatMap(\.signals).filter { $0.analyticallyUsable }.count
        let pct = total > 0 ? Int(Double(usable) / Double(total) * 100) : 0
        let missing = total - usable

        return VelaHeroSurface(tint: coverageColor(pct)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(VelaTheme.elevatedBg, lineWidth: 8)
                            .frame(width: 74, height: 74)
                        Circle()
                            .trim(from: 0, to: CGFloat(pct) / 100)
                            .stroke(coverageColor(pct), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 74, height: 74)
                            .rotationEffect(.degrees(-90))
                        Text("\(pct)%")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(VelaTheme.fg)
                            .monospacedDigit()
                    }
                    .accessibilityLabel(AppLanguage.stored.isChinese ? "数据覆盖 \(pct)%" : "Data coverage \(pct)%")

                    VStack(alignment: .leading, spacing: 5) {
                        Text(AppLanguage.stored.isChinese ? "今日可用信号" : "Usable Today")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(VelaTheme.fg)
                        Text(AppLanguage.stored.isChinese
                             ? "\(usable)/\(total) 个信号可分析，\(missing) 个需补齐或授权。"
                             : "\(usable)/\(total) signals analytically usable; \(missing) need data or permission."
                        )
                        .font(.subheadline)
                        .foregroundStyle(VelaTheme.fg2)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    VelaMetricPill(
                        title: AppLanguage.stored.isChinese ? "覆盖" : "Coverage",
                        value: "\(pct)%",
                        systemImage: "checkmark.shield.fill",
                        tint: coverageColor(pct)
                    )
                    VelaMetricPill(
                        title: AppLanguage.stored.isChinese ? "缺失" : "Missing",
                        value: "\(missing)",
                        systemImage: "exclamationmark.triangle.fill",
                        tint: missing == 0 ? VelaTheme.rhythmInk : VelaTheme.rhythmInk
                    )
                }

            }
        }
        .appleIntelligenceGlow(isHighlighted: pct >= 85, radius: 24)
    }

    // MARK: - Group Card

    private func coverageGroupCard(_ group: CoverageGroup) -> some View {
        let usable = group.signals.filter { $0.analyticallyUsable }.count
        let total = group.signals.count
        let staleOrMissing = group.signals.filter { $0.freshness == .stale || $0.freshness == .missing }.count
        let pct = total > 0 ? Int(Double(usable) / Double(total) * 100) : 0
        let tint = groupColor(group)

        return VelaGlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: group.icon)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(tint.opacity(0.12)))
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(VelaTheme.fg)
                        Text(AppLanguage.stored.isChinese
                             ? "\(usable)/\(total) 个信号可分析 · \(staleOrMissing) 个陈旧或缺失"
                             : "\(usable)/\(total) signals analytically usable · \(staleOrMissing) stale or missing"
                        )
                        .font(.caption)
                        .foregroundStyle(VelaTheme.fg2)
                    }

                    Spacer()
                    VelaStatusBadge(
                        label: AppLanguage.stored.isChinese ? "覆盖 \(pct)%" : "Coverage \(pct)%",
                        systemImage: "checkmark.shield.fill",
                        tint: coverageColor(pct)
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLanguage.stored.isChinese ? "影响的判断" : "Affected judgments")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(VelaTheme.muted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(group.affectedJudgments, id: \.self) { judgment in
                            VelaStatusBadge(label: localizedJudgment(judgment), systemImage: "scope", tint: tint)
                        }
                    }
                }

                Divider().overlay(VelaTheme.borderSoft)

                VStack(spacing: 8) {
                    ForEach(group.signals) { signal in
                        VelaDataQualityRow(
                            title: signal.signal.name,
                            subtitle: signalSubtitle(signal),
                            freshness: signal.freshness,
                            qualityLabel: signal.quality.label,
                            tint: qualityColor(signal.quality)
                        )
                    }
                }

                if group.signals.contains(where: { $0.authorizationState == .notRequested }) {
                    VelaInlineAlert(
                        title: AppLanguage.stored.isChinese ? "需要健康权限" : "Health permission needed",
                        message: AppLanguage.stored.isChinese
                        ? "在系统健康权限中打开相关数据类型，可提升 Vela 今天判断的置信度。"
                        : "Enable the related Health data types in system permissions to improve today's confidence.",
                        systemImage: "lock.open.fill",
                        tint: VelaTheme.rhythmInk
                    )
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadCoverage() async {
        coverageGroups = await DataCoverageGroupFactory.loadAllGroups()
        isLoading = false
    }

    // MARK: - Helpers

    private func coverageColor(_ pct: Int) -> Color {
        if pct >= 80 { return VelaTheme.rhythmInk }
        if pct >= 50 { return VelaTheme.accent }
        return VelaTheme.rhythmInk
    }

    private func qualityColor(_ quality: SignalQuality) -> Color {
        switch quality {
        case .enough: return VelaTheme.rhythmInk
        case .partial: return VelaTheme.accent
        case .insufficient: return VelaTheme.rhythmInk
        }
    }

    private func signalSubtitle(_ signal: HealthSignalCoverage) -> String {
        if signal.authorizationState == .notRequested {
            return AppLanguage.stored.isChinese ? "尚未请求 · 可连接 Apple 健康" : "Not requested · connect Apple Health"
        }
        if signal.authorizationState == .noReadableSamples {
            return AppLanguage.stored.isChinese
                ? "近期未读取到样本 · 无法判断读权限或数据是否存在"
                : "No recent samples readable · access and sample availability are indistinguishable"
        }
        if signal.authorizationState == .unavailable {
            return AppLanguage.stored.isChinese ? "设备不支持此数据类型" : "Data type unavailable on this device"
        }
        return AppLanguage.stored.isChinese
            ? "7天 \(signal.sampleCount7d) 条 · 30天 \(signal.sampleCount30d) 条 · \(signal.confidenceImpact)"
            : "7d \(signal.sampleCount7d) samples · 30d \(signal.sampleCount30d) samples · \(signal.confidenceImpact)"
    }

    private func groupColor(_ group: CoverageGroup) -> Color {
        switch group.id {
        case "recovery": return VelaTheme.rhythmInk
        case "sleep": return VelaTheme.rhythmInk
        case "training": return VelaTheme.rhythmInk
        case "gait": return VelaTheme.accent
        case "cardio": return VelaTheme.rhythmInk
        case "nutrition": return VelaTheme.rhythmInk
        case "environment": return VelaTheme.fg2
        default: return VelaTheme.accent
        }
    }

    private func localizedJudgment(_ judgment: String) -> String {
        guard AppLanguage.stored.isChinese else { return judgment }
        switch judgment {
        case "Recovery Score": return "恢复评分"
        case "Autonomic Fatigue": return "恢复相关信号"
        case "HRV Z-Score": return "HRV 基线偏离"
        case "Sleep Score": return "睡眠评分"
        case "Sleep Architecture": return "睡眠结构"
        case "Sleep Deficit": return "睡眠缺口"
        case "Strain Score": return "负荷评分"
        case "Training Load": return "训练负荷"
        case "TSB": return "训练状态平衡"
        case "Gait Assessment": return "步态评估"
        case "Movement Constraints": return "需关注的活动限制信号"
        case "Muscular Fatigue": return "肌肉疲劳"
        case "Cardio Fitness": return "心肺体能"
        case "Health Signal Reference": return "健康信号参考"
        case "Nutrition Score": return "营养评分"
        case "Hydration Status": return "补水状态"
        case "Sleep Quality": return "睡眠质量"
        case "Circadian Rhythm": return "昼夜节律"
        default: return judgment
        }
    }
}

// MARK: - Coverage Data Models

struct CoverageGroup: Identifiable {
    var id: String
    var title: String
    var icon: String
    var signals: [HealthSignalCoverage]
    var affectedJudgments: [String]
}

struct DataCoverageDomainSummary: Hashable, Sendable, Identifiable {
    var id: String
    var title: String
    var icon: String
    var scorePercent: Int
    var usableCount: Int
    var totalCount: Int
}

struct DataCoverageSummaryModel: Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
        case high
        case moderate
        case low
        case unknown
    }

    var scorePercent: Int
    var status: Status
    var title: String
    var subtitle: String
    var actionTitle: String
    var actionSystemImage: String
    var domainSummaries: [DataCoverageDomainSummary]
    var topBlockers: [String]
    var coachContextLine: String

    var agentFactContext: AgentDataCoverageContext {
        let confidence: DataConfidence
        switch status {
        case .high: confidence = .high
        case .moderate: confidence = .medium
        case .low: confidence = .low
        case .unknown: confidence = .unavailable
        }
        let missingDomains = domainSummaries
            .filter { $0.scorePercent < 67 }
            .map(\.id)
            .sorted()
        return AgentDataCoverageContext(
            availableSections: domainSummaries.count - missingDomains.count,
            totalSections: domainSummaries.count,
            missingSections: missingDomains,
            confidence: confidence
        )
    }

    var compactDisplayTitle: String {
        guard status != .unknown else { return title }

        let statusLabel: String
        switch status {
        case .high:
            statusLabel = AppLanguage.stored.isChinese ? "充分" : "Ready"
        case .moderate:
            statusLabel = AppLanguage.stored.isChinese ? "部分" : "Partial"
        case .low:
            statusLabel = AppLanguage.stored.isChinese ? "不足" : "Limited"
        case .unknown:
            statusLabel = ""
        }

        let base = AppLanguage.stored.isChinese ? "数据覆盖" : "Data coverage"
        return "\(base) · \(statusLabel) · \(scorePercent)%"
    }

    static var unknown: DataCoverageSummaryModel {
        DataCoverageSummaryModel(
            scorePercent: 0,
            status: .unknown,
            title: AppLanguage.stored.isChinese ? "正在检查数据覆盖" : "Checking data coverage",
            subtitle: AppLanguage.stored.isChinese
                ? "Vela 正在确认关键健康信号是否新鲜、完整、可用于判断。"
                : "Vela is checking whether key health signals are fresh and usable.",
            actionTitle: AppLanguage.stored.isChinese ? "查看数据" : "View data",
            actionSystemImage: "waveform.path.ecg.rectangle",
            domainSummaries: [],
            topBlockers: [],
            coachContextLine: "Data coverage unknown; avoid high-confidence physiological claims until coverage finishes loading."
        )
    }

    static func build(groups: [CoverageGroup]) -> DataCoverageSummaryModel {
        let signals = groups.flatMap(\.signals)
        guard !signals.isEmpty else { return .unknown }

        let usable = signals.filter(\.analyticallyUsable).count
        let total = signals.count
        let score = Int((Double(usable) / Double(max(total, 1)) * 100).rounded())
        let status = status(for: score)
        let blockers: [String] = Array(signals
            .filter { !$0.analyticallyUsable }
            .map { $0.signal.name }
            .prefix(3))
        let domains = groups.map { group in
            let usable = group.signals.filter(\.analyticallyUsable).count
            let total = group.signals.count
            return DataCoverageDomainSummary(
                id: group.id,
                title: group.title,
                icon: group.icon,
                scorePercent: total > 0 ? Int((Double(usable) / Double(total) * 100).rounded()) : 0,
                usableCount: usable,
                totalCount: total
            )
        }

        let title: String
        let subtitle: String
        switch status {
        case .high:
            title = AppLanguage.stored.isChinese ? "关键数据已就绪" : "Key data is ready"
            subtitle = AppLanguage.stored.isChinese
                ? "关键健康信号足够新鲜，今日建议有较完整依据。"
                : "Key health signals are fresh enough to support today's recommendations."
        case .moderate:
            title = AppLanguage.stored.isChinese ? "部分数据待补充" : "Some data is still needed"
            subtitle = AppLanguage.stored.isChinese
                ? "建议具备部分依据；缺失信号会让训练和恢复判断更保守。"
                : "Recommendations have partial support; missing signals make training and recovery judgments more conservative."
        case .low:
            title = AppLanguage.stored.isChinese ? "正在建立身体基线" : "Building your body baseline"
            subtitle = AppLanguage.stored.isChinese
                ? "Vela 会保守处理今日建议，避免把缺失数据解读成确定结论。"
                : "Vela will stay conservative and avoid treating missing data as certainty."
        case .unknown:
            title = Self.unknown.title
            subtitle = Self.unknown.subtitle
        }

        let reliableDomains = domains
            .filter { $0.scorePercent >= 67 }
            .map(\.id)
            .joined(separator: ", ")
        let blockerText = blockers.isEmpty ? "none" : blockers.joined(separator: ", ")

        return DataCoverageSummaryModel(
            scorePercent: score,
            status: status,
            title: title,
            subtitle: subtitle,
            actionTitle: AppLanguage.stored.isChinese ? "查看数据覆盖" : "View Data Coverage",
            actionSystemImage: "waveform.path.ecg.rectangle",
            domainSummaries: domains,
            topBlockers: Array(blockers),
            coachContextLine: "Data coverage \(score)% (status: \(status.rawValue)); reliable domains: \(reliableDomains.isEmpty ? "none" : reliableDomains); missing/stale: \(blockerText)."
        )
    }

    private static func status(for score: Int) -> Status {
        if score >= 80 { return .high }
        if score >= 50 { return .moderate }
        return .low
    }
}

enum DataCoverageGroupFactory {
    @MainActor
    static func loadPriorityGroups(service: HealthSignalCoverageService = HealthSignalCoverageService()) async -> [CoverageGroup] {
        let recoverySigs = [
            await service.fetchCoverage(for: .hrvSDNN),
            await service.fetchCoverage(for: .restingHR),
            await service.fetchCoverage(for: .respiratoryRate)
        ]

        let sleepSigs = [
            await service.fetchCoverage(for: .sleepAnalysis),
            await service.fetchCoverage(for: .wristTemperature),
            await service.fetchCoverage(for: .oxygenSaturation)
        ]

        let trainingSigs = [
            await service.fetchCoverage(for: .workouts),
            await service.fetchCoverage(for: .activeEnergy),
            await service.fetchCoverage(for: .workoutHR)
        ]

        return [
            CoverageGroup(
                id: "recovery",
                title: AppLanguage.stored.isChinese ? "恢复" : "Recovery",
                icon: "heart.fill",
                signals: recoverySigs,
                affectedJudgments: ["Recovery Score", "Autonomic Fatigue", "HRV Z-Score"]
            ),
            CoverageGroup(
                id: "sleep",
                title: AppLanguage.stored.isChinese ? "睡眠" : "Sleep",
                icon: "moon.zzz.fill",
                signals: sleepSigs,
                affectedJudgments: ["Sleep Score", "Sleep Architecture", "Sleep Deficit"]
            ),
            CoverageGroup(
                id: "training",
                title: AppLanguage.stored.isChinese ? "训练" : "Training",
                icon: "figure.run",
                signals: trainingSigs,
                affectedJudgments: ["Strain Score", "Training Load", "TSB"]
            )
        ]
    }

    @MainActor
    static func loadAllGroups(service: HealthSignalCoverageService = HealthSignalCoverageService()) async -> [CoverageGroup] {
        let priority = await loadPriorityGroups(service: service)

        let gaitSigs = [
            await service.fetchCoverage(for: .walkingSpeed),
            await service.fetchCoverage(for: .walkingAsymmetry),
            await service.fetchCoverage(for: .doubleSupport)
        ]

        let cardioSigs = [
            await service.fetchCoverage(for: .vo2Max)
        ]

        let nutritionSigs = [
            await service.fetchCoverage(for: .dietaryEnergy),
            await service.fetchCoverage(for: .water),
            await service.fetchCoverage(for: .caffeine)
        ]

        let environmentSigs = [
            await service.fetchCoverage(for: .envNoise),
            await service.fetchCoverage(for: .daylight)
        ]

        return priority + [
            CoverageGroup(
                id: "gait",
                title: AppLanguage.stored.isChinese ? "步态与活动" : "Gait & Mobility",
                icon: "figure.walk",
                signals: gaitSigs,
                affectedJudgments: ["Gait Assessment", "Movement Constraints", "Muscular Fatigue"]
            ),
            CoverageGroup(
                id: "cardio",
                title: AppLanguage.stored.isChinese ? "心肺" : "Cardio",
                icon: "lungs.fill",
                signals: cardioSigs,
                affectedJudgments: ["Cardio Fitness", "Health Signal Reference"]
            ),
            CoverageGroup(
                id: "nutrition",
                title: AppLanguage.stored.isChinese ? "营养" : "Nutrition",
                icon: "fork.knife",
                signals: nutritionSigs,
                affectedJudgments: ["Nutrition Score", "Hydration Status"]
            ),
            CoverageGroup(
                id: "environment",
                title: AppLanguage.stored.isChinese ? "环境" : "Environment",
                icon: "ear.fill",
                signals: environmentSigs,
                affectedJudgments: ["Sleep Quality", "Circadian Rhythm"]
            )
        ]
    }
}
