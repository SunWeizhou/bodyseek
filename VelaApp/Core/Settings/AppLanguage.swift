import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english
    case simplifiedChinese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english:
            return "English"
        case .simplifiedChinese:
            return "简体中文"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english:
            return "en"
        case .simplifiedChinese:
            return "zh-Hans"
        }
    }

    var isChinese: Bool {
        self == .simplifiedChinese
    }

    static var stored: AppLanguage {
        get {
            if let saved = AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") {
                return saved
            }
            // 未手动选择时跟随系统语言（审计 C3）：系统为中文 → 中文，否则英文。
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
        }
    }

    private static let storageKey = "vela_app_language"
}

enum L10n {
    static func t(_ english: String, _ chinese: String) -> String {
        AppLanguage.stored.isChinese ? chinese : english
    }
}

func localizedBand(_ band: MetricBand) -> String {
    guard AppLanguage.stored.isChinese else { return band.rawValue }
    switch band {
    case .veryLow: return "很低"
    case .low: return "偏低"
    case .normal: return "正常"
    case .high: return "偏高"
    case .veryHigh: return "很高"
    }
}

func localizedConfidence(_ confidence: MetricConfidence) -> String {
    guard AppLanguage.stored.isChinese else { return confidence.rawValue }
    switch confidence {
    case .high: return "高"
    case .medium: return "中"
    case .low: return "低"
    }
}

func localizedDataConfidence(_ confidence: DataConfidence) -> String {
    guard AppLanguage.stored.isChinese else { return confidence.rawValue }
    switch confidence {
    case .high: return "高置信度"
    case .medium: return "中置信度"
    case .low: return "低置信度"
    case .unavailable: return "置信度未知"
    }
}

func localizedDataFreshness(_ freshness: DataFreshness) -> String {
    guard AppLanguage.stored.isChinese else { return freshness.rawValue }
    switch freshness {
    case .live: return "实时同步"
    case .today: return "今日更新"
    case .recent: return "近期更新"
    case .stale: return "数据滞后"
    case .missing: return "数据缺失"
    }
}


func localizedTarget(_ status: StrainTargetStatus) -> String {
    guard AppLanguage.stored.isChinese else { return status.rawValue }
    switch status {
    case .belowTarget: return "低于目标"
    case .withinTarget: return "目标范围内"
    case .aboveTarget: return "高于目标"
    }
}

func localizedStressBand(_ band: MetricBand) -> String {
    guard AppLanguage.stored.isChinese else { return band.rawValue }
    switch band {
    case .veryLow: return "平稳"
    case .low: return "正常"
    case .normal: return "升高"
    case .high, .veryHigh: return "偏高"
    }
}

func localizedEnergy(_ status: EnergyBankStatus) -> String {
    guard AppLanguage.stored.isChinese else { return status.rawValue }
    switch status {
    case .unknown: return "未知"
    case .depleted: return "耗尽"
    case .low: return "偏低"
    case .stable: return "稳定"
    case .strong: return "充足"
    }
}

func localizedHealthAge(_ label: HealthAgeTrendLabel) -> String {
    guard AppLanguage.stored.isChinese else { return label.rawValue }
    switch label {
    case .improving: return "改善"
    case .stable: return "稳定"
    case .worsening: return "变差"
    }
}

func localizedReportTitle(_ type: AIReportType) -> String {
    guard AppLanguage.stored.isChinese else { return type.title }
    switch type {
    case .morningBrief: return "晨间简报"
    case .sleepReview: return "睡眠复盘"
    case .workoutReadiness: return "训练准备度"
    case .weeklyReview: return "周复盘"
    case .coachPrompt: return "教练回应"
    }
}

func localizedReason(_ reason: String) -> String {
    guard AppLanguage.stored.isChinese else { return reason }
    if reason.contains("HRV significantly below personal baseline") {
        if let range = reason.range(of: #"z=-?\d+(\.\d+)?"#, options: .regularExpression) {
            return "HRV 显著低于个人基线（\(reason[range])）"
        }
        return "HRV 显著低于个人基线"
    }
    if reason.contains("HRV slightly below baseline") { return "HRV 略低于基线" }
    if reason.contains("HRV above baseline") { return "HRV 高于个人基线，恢复信号较积极" }
    if reason.contains("HRV within normal range") { return "HRV 处于正常范围" }
    if reason.contains("Resting heart rate elevated") {
        let bpm = reason.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty }
        return bpm.map { "静息心率比基线高 \($0)bpm" } ?? "静息心率高于基线"
    }
    if reason.contains("Resting heart rate slightly above baseline") { return "静息心率略高于基线" }
    if reason.contains("Resting heart rate below baseline") { return "静息心率低于基线，是积极信号" }
    if reason.contains("HRV was below") { return "HRV 低于 28 天基线" }
    if reason.contains("HRV was at or above") { return "HRV 达到或高于 28 天基线" }
    if reason.contains("HRV data unavailable") { return "HRV 数据不可用，恢复评分会使用其余指标。" }
    if reason.contains("Resting heart rate was above") { return "静息心率高于基线" }
    if reason.contains("Resting heart rate was close") { return "静息心率接近基线" }
    if reason.contains("Resting heart rate data unavailable") { return "静息心率数据不可用。" }
    if reason.contains("Sleep score contributed") { return "睡眠评分已纳入恢复计算" }
    if reason.contains("Sleep score unavailable") { return "睡眠评分不可用。" }
    if reason.contains("Prior strain unavailable") { return "前一日负荷不可用。" }
    if reason.contains("Sleep duration") && reason.contains("below target by") {
        return reason
            .replacingOccurrences(of: "Sleep duration", with: "睡眠时长")
            .replacingOccurrences(of: " — below target by ", with: "，低于目标 ")
    }
    if reason.contains("Sleep duration") && reason.contains("within target range") {
        return reason
            .replacingOccurrences(of: "Sleep duration", with: "睡眠时长")
            .replacingOccurrences(of: " — within target range", with: "，位于目标范围内")
    }
    if reason.contains("Sleep duration") && reason.contains("above target") {
        return reason
            .replacingOccurrences(of: "Sleep duration", with: "睡眠时长")
            .replacingOccurrences(of: " — above target", with: "，高于目标")
    }
    if reason.contains("Sleep duration reached") { return reason.replacingOccurrences(of: "Sleep duration reached", with: "睡眠时长达到").replacingOccurrences(of: "of target", with: "目标") }
    if reason.contains("Sleep timing baseline unavailable") { return "睡眠时间基线不可用，暂未评分规律性。" }
    if reason.contains("Today's active energy") { return reason.replacingOccurrences(of: "Today's active energy was", with: "今日活动能量为").replacingOccurrences(of: "of baseline", with: "基线") }
    if reason.contains("Exercise duration was included") { return "锻炼时长已纳入负荷计算" }
    if reason.contains("Workout intensity contributed") { return "训练强度已纳入今日负荷" }
    if reason.contains("Active energy baseline unavailable") { return "活动能量基线不可用。" }
    if reason.contains("Exercise baseline unavailable") { return "锻炼基线不可用。" }
    if reason.contains("No workout intensity data available") { return "暂无训练强度数据。" }
    if reason.contains("Stress proxy data unavailable") { return "压力代理数据不可用。" }
    if reason.contains("Heart rate elevation proxy") { return "已纳入心率升高代理指标" }
    if reason.contains("HRV suppression proxy") { return "已纳入 HRV 抑制代理指标" }
    if reason.contains("Sleep debt context") { return "已纳入睡眠债背景" }
    if reason.contains("Recent strain context") { return "已纳入近期负荷背景" }
    if reason.contains("Morning energy") { return "早晨能量基于恢复和睡眠估算。" }
    if reason.contains("Current energy subtracts") { return "当前能量会扣除负荷和压力代理消耗。" }
    if reason.contains("Health Age Trend") { return "健康年龄趋势是 beta 代理趋势，不代表真实生物年龄。" }
    if reason.contains("Limited data coverage") {
        return "数据覆盖不足：在健康或本地记录可用前，Vela 会使用保守训练建议。"
    }
    return reason
}

func localizedMetricName(_ name: String) -> String {
    guard AppLanguage.stored.isChinese else { return name }
    let normalized = name
        .replacingOccurrences(of: "_", with: " ")
        .lowercased()
    switch normalized {
    case "vo2 max": return "最大摄氧量"
    case "resting heart rate", "rhr": return "静息心率"
    case "sleep regularity": return "睡眠规律性"
    case "sleep duration": return "睡眠时长"
    case "activity consistency": return "活动一致性"
    case "recovery trend": return "恢复趋势"
    case "heart rate elevation": return "心率升高"
    case "hrv suppression": return "HRV 抑制"
    case "sleep debt": return "睡眠债"
    case "recent strain": return "近期负荷"
    default:
        return name.replacingOccurrences(of: "_", with: " ")
    }
}

func localizedWorkoutTemplateTitle(_ title: String) -> String {
    guard AppLanguage.stored.isChinese else { return title }
    switch title.lowercased() {
    case "full body": return "全身训练"
    case "leg day": return "腿部训练"
    case "push day": return "推力训练"
    case "pull day": return "拉力训练"
    case "upper body": return "上肢训练"
    case "lower body": return "下肢训练"
    default: return title
    }
}

func localizedOnboardingGoal(_ value: String) -> String {
    switch value {
    case "performance":
        return L10n.t("Performance", "运动表现")
    case "muscle_gain":
        return L10n.t("Muscle", "增肌塑形")
    case "fat_loss":
        return L10n.t("Fat loss", "减脂")
    case "health", "maintain":
        return L10n.t("Health", "健康管理")
    default:
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func localizedOnboardingTrainingStyle(_ value: String) -> String {
    switch value {
    case "strength":
        return L10n.t("Strength", "力量训练")
    case "hybrid", "mixed":
        return L10n.t("Hybrid", "力量+耐力")
    case "endurance":
        return L10n.t("Endurance", "耐力训练")
    case "cardio":
        return L10n.t("Cardio", "有氧训练")
    case "yoga":
        return L10n.t("Mobility", "瑜伽伸展")
    default:
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func localizedOnboardingExperience(_ value: String) -> String {
    switch value {
    case "beginner":
        return L10n.t("Beginner", "刚开始")
    case "intermediate":
        return L10n.t("Intermediate", "有训练基础")
    case "advanced":
        return L10n.t("Advanced", "进阶训练者")
    default:
        return L10n.t("Unknown", "未确定")
    }
}

func localizedOnboardingCoachStyle(_ value: String) -> String {
    switch value {
    case "direct":
        return L10n.t("Direct", "直接给结论")
    case "balanced":
        return L10n.t("Balanced", "平衡解释")
    case "encouraging":
        return L10n.t("Encouraging", "积极鼓励")
    case "explanatory":
        return L10n.t("Detailed", "详细解释")
    default:
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func localizedOnboardingEquipment(_ value: String) -> String {
    switch value {
    case "gym":
        return L10n.t("Gym", "健身房")
    case "home_equipment":
        return L10n.t("Home", "居家器械")
    case "bodyweight":
        return L10n.t("Bodyweight", "自重训练")
    default:
        return value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func localizedOnboardingFirstBrief(
    primaryGoal: String,
    trainingStyle: String,
    weeklyTrainingDays: Int
) -> String {
    let goal = localizedOnboardingGoal(primaryGoal)
    let style = localizedOnboardingTrainingStyle(trainingStyle)
    guard AppLanguage.stored.isChinese else {
        return "Goal \(goal), training style \(style), \(weeklyTrainingDays)x per week. Vela will start with conservative daily decisions and increase automation as data coverage improves."
    }
    return "目标 \(goal)，训练偏好 \(style)，每周 \(weeklyTrainingDays) 次。Vela 会先用保守规则生成今日建议，数据覆盖提升后再提高自动化强度。"
}

func localizedArtifactType(_ type: String) -> String {
    guard AppLanguage.stored.isChinese else {
        return type.replacingOccurrences(of: "_", with: " ").capitalized
    }
    switch type.lowercased() {
    case "daily_plan": return "每日训练计划"
    case "training_adjustment": return "训练强度调整"
    case "weekly_report": return "每周身体总结"
    case "correlation_chart": return "指标关联图表"
    case "wiki_diff": return "身体特征更新"
    case "nutrition_feedback": return "营养健康反馈"
    default: return type.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

func localizedMuscleGroup(_ muscle: String) -> String {
    guard AppLanguage.stored.isChinese else { return muscle }
    switch muscle.lowercased() {
    case "chest": return "胸部"
    case "back": return "背部"
    case "shoulders", "shoulder": return "肩部"
    case "biceps": return "肱二头肌"
    case "triceps": return "肱三头肌"
    case "quads", "quadriceps": return "股四头肌"
    case "hamstrings": return "腘绳肌"
    case "glutes": return "臀部"
    case "core", "abs": return "核心"
    case "legs", "leg": return "腿部"
    default: return muscle
    }
}

func localizedDriverTitle(_ title: String) -> String {
    guard AppLanguage.stored.isChinese else { return title }
    if title.contains("local fatigue") {
        let muscle = title.replacingOccurrences(of: " local fatigue", with: "").trimmingCharacters(in: .whitespaces)
        let localizedMuscle: String
        switch muscle.lowercased() {
        case "chest": localizedMuscle = "胸部"
        case "back": localizedMuscle = "背部"
        case "quads", "quadriceps": localizedMuscle = "股四头肌"
        case "hamstrings": localizedMuscle = "股二头肌"
        case "shoulders", "shoulder": localizedMuscle = "肩部"
        case "arms", "arm", "biceps", "triceps": localizedMuscle = "手臂"
        case "core", "abs": localizedMuscle = "核心"
        case "legs", "leg": localizedMuscle = "腿部"
        default: localizedMuscle = muscle.capitalized
        }
        return "\(localizedMuscle)局部肌肉疲劳"
    }
    switch title {
    case "Recent training response": return "近期训练恢复反应"
    case "Active status": return "当前生活状态"
    case "Nutrition logged": return "今日营养记录"
    case "Recent self-report": return "近期主观记录"
    case "Active training plan": return "当前激活的计划"
    case "Recent training load": return "近期训练负荷"
    case "Limited data coverage": return "数据覆盖不足"
    default: return title
    }
}

func localizedDriverDetail(_ detail: String) -> String {
    guard AppLanguage.stored.isChinese else { return detail }
    
    // 1. Local fatigue details: "X effective sets in 48h and Y in 7d."
    if detail.contains("effective sets in 48h and") {
        let components = detail.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if components.count >= 2 {
            return "过去 48 小时进行了 \(components[0]) 组有效训练，7 天内累计 \(components[1]) 组。"
        }
    }
    
    // 2. Recent training response: "A [muscles] session was followed by a [change] recovery change."
    if detail.contains("session was followed by a") {
        var clean = detail
        clean = clean.replacingOccurrences(of: "A ", with: "")
        clean = clean.replacingOccurrences(of: " session was followed by a ", with: "训练后，次日恢复评分发生了 ")
        clean = clean.replacingOccurrences(of: " recovery change.", with: " 的变化。")
        // Translate muscle names
        clean = clean.replacingOccurrences(of: "chest", with: "胸部")
        clean = clean.replacingOccurrences(of: "back", with: "背部")
        clean = clean.replacingOccurrences(of: "shoulders", with: "肩部")
        clean = clean.replacingOccurrences(of: "quads", with: "股四头肌")
        clean = clean.replacingOccurrences(of: "hamstrings", with: "大腿后侧")
        clean = clean.replacingOccurrences(of: "arms", with: "手臂")
        clean = clean.replacingOccurrences(of: "core", with: "核心")
        return clean
    }
    
    // 3. User status: "User status is [status]."
    if detail.contains("User status is") {
        let status = detail.replacingOccurrences(of: "User status is ", with: "").replacingOccurrences(of: ".", with: "").trimmingCharacters(in: .whitespaces)
        let localizedStatus: String
        switch status {
        case "sick": localizedStatus = "生病"
        case "injured": localizedStatus = "受伤"
        case "resting": localizedStatus = "休息/调整"
        default: localizedStatus = status
        }
        return "用户标记当前处于【\(localizedStatus)】状态。"
    }
    
    // 4. Nutrition: "[calories] kcal and [protein] g protein recorded today."
    if detail.contains("kcal and") && detail.contains("protein recorded today") {
        let components = detail.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if components.count >= 2 {
            return "今日已记录 \(components[0]) 千卡热量及 \(components[1]) 克蛋白质。"
        }
    }
    
    // 5. Recent activity: "[X] sessions and [Y] minutes in 48h."
    if detail.contains("sessions and") && detail.contains("minutes in 48h") {
        let components = detail.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
        if components.count >= 2 {
            return "过去 48 小时内累计进行了 \(components[0]) 次训练，时长达 \(components[1]) 分钟。"
        }
    }
    
    // 6. Data coverage fallback
    if detail.contains("Vela is using a conservative fallback") {
        return "在获取充足的 HealthKit 历史基线或本地训练记录之前，Vela 将使用保守基线进行评估。"
    }
    
    return detail
}

func localizedSignalTitle(_ title: String) -> String {
    guard AppLanguage.stored.isChinese else { return title }
    switch title.lowercased() {
    case "recovery": return "恢复得分"
    case "sleep": return "睡眠得分"
    case "hrv vs baseline": return "HRV 变异率"
    case "resting hr": return "静息心率"
    case "training load": return "今日耗力负荷"
    case "local fatigue": return "局部肌群疲劳"
    default: return title
    }
}

func localizedSignalValue(_ value: String) -> String {
    guard AppLanguage.stored.isChinese else { return value }
    if value.hasSuffix(" min") {
        return value.replacingOccurrences(of: " min", with: " 分钟")
    }
    if value.hasSuffix(" sets") {
        var clean = value.replacingOccurrences(of: " sets", with: " 组")
        clean = clean.replacingOccurrences(of: "chest", with: "胸部")
        clean = clean.replacingOccurrences(of: "back", with: "背部")
        clean = clean.replacingOccurrences(of: "shoulders", with: "肩部")
        clean = clean.replacingOccurrences(of: "quads", with: "股四头肌")
        clean = clean.replacingOccurrences(of: "hamstrings", with: "大腿后侧")
        clean = clean.replacingOccurrences(of: "arms", with: "手臂")
        clean = clean.replacingOccurrences(of: "core", with: "核心")
        return clean
    }
    return value
}

func localizedSignalBaseline(_ baseline: String) -> String {
    guard AppLanguage.stored.isChinese else { return baseline }
    if baseline == "7d effective sets" {
        return "7 天有效训练组数"
    }
    if baseline.contains("baseline") {
        return baseline.replacingOccurrences(of: " baseline", with: " 基线")
    }
    if baseline.contains("target") {
        return baseline.replacingOccurrences(of: "target ", with: "目标范围 ")
    }
    return baseline
}
