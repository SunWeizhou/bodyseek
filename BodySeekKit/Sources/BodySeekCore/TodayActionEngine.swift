import Foundation

public struct TodayActionItem: Identifiable, Hashable, Codable, Sendable {
    public enum Category: String, Hashable, Codable, Sendable {
        case trainingFocus
        case sleepWindow
        case recoveryAction
    }

    public let id: UUID
    public let title: String
    public let detail: String
    public let category: Category
    public let metricBasis: String
    public let coachPrompt: String

    public init(
        id: UUID = UUID(),
        title: String,
        detail: String,
        category: Category,
        metricBasis: String,
        coachPrompt: String
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.category = category
        self.metricBasis = metricBasis
        self.coachPrompt = coachPrompt
    }

    public var planItemKind: PlanItemKind {
        switch category {
        case .trainingFocus: .trainingFocus
        case .sleepWindow: .sleepWindow
        case .recoveryAction: .recoveryAction
        }
    }
}

public extension PlanItemRecord {
    func decodedActionItem(decoder: JSONDecoder = JSONDecoder()) -> TodayActionItem? {
        guard let data = payloadJSON.data(using: .utf8) else { return nil }
        do {
            return try decoder.decode(TodayActionItem.self, from: data)
        } catch {
            return nil
        }
    }

    static func make(
        dayKey: DayKey,
        action: TodayActionItem,
        state: PlanItemState = .suggested,
        origin: ActionProposal.Origin = .system,
        encoder: JSONEncoder = JSONEncoder()
    ) -> PlanItemRecord {
        let jsonString: String
        do {
            let data = try encoder.encode(action)
            jsonString = String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            jsonString = "{}"
        }
        return PlanItemRecord(
            id: action.id,
            dayKey: dayKey,
            kind: action.planItemKind,
            payloadJSON: jsonString,
            state: state,
            origin: origin
        )
    }

    func updatingState(_ newState: PlanItemState) -> PlanItemRecord {
        PlanItemRecord(
            id: id,
            dayKey: dayKey,
            kind: kind,
            payloadJSON: payloadJSON,
            state: newState,
            origin: origin
        )
    }
}

public enum TodayActionGenerator {
    public static func generateDefaultPlanItems(
        for snapshot: BodySeekDashboardSnapshot,
        dayKey: DayKey
    ) -> [PlanItemRecord] {
        guard snapshot.isAuthorized else {
            let onboardingAction = TodayActionItem(
                id: deterministicUUID(dayKey: dayKey, slot: "auth"),
                title: "连接 Apple 健康",
                detail: "授权读取 HRV、睡眠分期与 Apple Watch 心率训练后，自动生成每日训练与恢复行动建议。",
                category: .recoveryAction,
                metricBasis: "尚未授权健康数据源",
                coachPrompt: "连接 Apple 健康后，BodySeek 会先评估哪些指标？"
            )
            return [PlanItemRecord.make(dayKey: dayKey, action: onboardingAction)]
        }

        let today = snapshot.today
        let load = snapshot.trainingLoad
        var actions: [TodayActionItem] = []

        // 1. Training focus based on available recovery & ACWR
        if let rec = today.recovery.value {
            if rec >= 75 && load.zone != .highRisk {
                let basis = load.acwrRatio.map { String(format: "恢复 %d · ACWR %.2f", rec, $0) } ?? "恢复 \(rec)"
                actions.append(TodayActionItem(
                    id: deterministicUUID(dayKey: dayKey, slot: "training"),
                    title: "今天可以安排强度训练",
                    detail: "当前恢复储备充沛且负荷未过载，适合开展核心复合动作或高质量技术训练，注意保留 1–2 次余力。",
                    category: .trainingFocus,
                    metricBasis: basis,
                    coachPrompt: "结合我今天 \(basis)，帮我安排一份恰当强度的训练重点。"
                ))
            } else if rec < 50 || load.zone == .highRisk {
                let basis = load.acwrRatio.map { String(format: "恢复 %d · ACWR %.2f", rec, $0) } ?? "恢复 \(rec)"
                actions.append(TodayActionItem(
                    id: deterministicUUID(dayKey: dayKey, slot: "training"),
                    title: "今天减量，留时间恢复",
                    detail: "恢复偏低或急性负荷高于长期均值，建议控制在 Z1–Z2 低强度有氧与柔韧拉伸，避免高冲击大重量。",
                    category: .trainingFocus,
                    metricBasis: basis,
                    coachPrompt: "为什么今天建议主动恢复？适合做什么低负荷活动？"
                ))
            } else {
                let basis = load.acwrRatio.map { String(format: "恢复 %d · ACWR %.2f", rec, $0) } ?? "恢复 \(rec)"
                actions.append(TodayActionItem(
                    id: deterministicUUID(dayKey: dayKey, slot: "training"),
                    title: "保持中等训练量，专注动作",
                    detail: "状态平稳，可完成常规分化的动作节奏与控制训练，结束后留意次日晨起静息心率变化。",
                    category: .trainingFocus,
                    metricBasis: basis,
                    coachPrompt: "今天适合怎样分配力量与有氧比例？"
                ))
            }
        }

        // 2. Sleep window recommendation based on sleep duration
        if let sleepMin = today.raw.sleepAsleepMinutes {
            let hours = Double(sleepMin) / 60.0
            if sleepMin < 420 {
                actions.append(TodayActionItem(
                    id: deterministicUUID(dayKey: dayKey, slot: "sleep"),
                    title: "今晚提前 30 分钟准备入睡",
                    detail: String(format: "昨夜实睡 %.1f 小时略偏短，今晚尽量减少睡前蓝光并提前放松，优先补足深睡与 REM 窗口。", hours),
                    category: .sleepWindow,
                    metricBasis: String(format: "昨夜睡眠 %.1f 小时", hours),
                    coachPrompt: "结合昨晚睡眠构成，今晚怎样提高深睡与入睡效率？"
                ))
            } else {
                actions.append(TodayActionItem(
                    id: deterministicUUID(dayKey: dayKey, slot: "sleep"),
                    title: "按平时时间睡觉和起床",
                    detail: String(format: "昨夜睡眠 %.1f 小时处于良性区间，维持 ±30 分钟内作息波动最有利于 HRV 稳定。", hours),
                    category: .sleepWindow,
                    metricBasis: String(format: "昨夜睡眠 %.1f 小时", hours),
                    coachPrompt: "我的近两周入睡时间规律吗？"
                ))
            }
        }

        // 3. Stress / subjective calibration
        if let stress = today.stress.value, stress >= 65 {
            actions.append(TodayActionItem(
                id: deterministicUUID(dayKey: dayKey, slot: "stress"),
                title: "留 10 分钟散步或放松",
                detail: "日间自主神经压力偏高，训练后或晚间安排 10 分钟慢呼气/散步有助于副交感神经回升。",
                category: .recoveryAction,
                metricBasis: "今日压力 \(stress)",
                coachPrompt: "分析今天哪几个小时压力峰值较高。"
            ))
        } else {
            actions.append(TodayActionItem(
                id: deterministicUUID(dayKey: dayKey, slot: "checkin"),
                title: "睡前记录精力和酸痛",
                detail: "记录今日精力与局部酸痛度，帮助模型区分生理曲线与真实主观疲劳差异。",
                category: .recoveryAction,
                metricBasis: "主客观闭环校准",
                coachPrompt: "最近主观感受与 HRV 趋势匹配吗？"
            ))
        }

        return actions.prefix(3).map { PlanItemRecord.make(dayKey: dayKey, action: $0) }
    }

    private static func deterministicUUID(dayKey: DayKey, slot: String) -> UUID {
        let seed = "\(dayKey.isoString)::\(slot)"
        var bytes = [UInt8](repeating: 0, count: 16)
        for (idx, b) in seed.utf8.enumerated() {
            bytes[idx % 16] ^= b &+ UInt8(truncatingIfNeeded: idx * 31)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

public enum NutritionPlanFactory {
    /// Estimates Mifflin-St Jeor BMR when weight/height/age are known; returns nil when required fields are absent.
    public static func estimateBMR(
        sex: String?,
        weightKg: Double?,
        heightCm: Double?,
        age: Int?
    ) -> Double? {
        guard let weightKg, let heightCm, let age,
              weightKg > 25, heightCm > 100, age > 10
        else { return nil }
        let base = 10.0 * weightKg + 6.25 * heightCm - 5.0 * Double(age)
        let isFemale = sex?.contains("女") == true || sex?.lowercased() == "female"
        return (base + (isFemale ? -161.0 : 5.0)).rounded()
    }

    /// Generates an auditable, schema-valid DRIs target plan compliant with `NutritionTargetEvaluator`.
    public static func makeDefaultDRIsPlan(
        for profile: NutritionProfile,
        effectiveFrom: DayKey,
        version: String = "v1.0"
    ) -> NutritionTargetPlan {
        let weight = profile.referenceWeightKg ?? 68.0
        let bmr = profile.bmrKcalReference
            ?? estimateBMR(sex: profile.referenceSex, weightKg: weight, heightCm: profile.heightCm, age: profile.age)
            ?? 1600.0
        let goalIsCut = profile.primaryGoal?.contains("减脂") == true || profile.primaryGoal?.contains("减重") == true
        let goalIsGain = profile.primaryGoal?.contains("增肌") == true
        let isMale = !(profile.referenceSex?.contains("女") == true || profile.referenceSex?.lowercased() == "female")

        let energyLow: Double = goalIsCut ? (bmr * 1.15).rounded() : (goalIsGain ? (bmr * 1.45).rounded() : (bmr * 1.30).rounded())
        let energyHigh: Double = goalIsCut ? (bmr * 1.35).rounded() : (goalIsGain ? (bmr * 1.65).rounded() : (bmr * 1.50).rounded())
        let proteinMin: Double = (weight * (goalIsCut || goalIsGain ? 1.6 : 1.2)).rounded()

        var items: [NutritionTargetItem] = [
            NutritionTargetItem(id: "diet_kcal", unit: "kcal", mode: .range, lower: energyLow, upper: energyHigh, source: "Mifflin-St Jeor × 活动系数", referenceType: "个体目标", adopted: true),
            NutritionTargetItem(id: "diet_carbs_g", unit: "%E", mode: .range, lower: 45, upper: 65, source: "中国居民膳食营养素参考摄入量 2023", referenceType: "AMDR", adopted: true),
            NutritionTargetItem(id: "diet_protein_g", unit: "g", mode: .min, lower: proteinMin, source: "中国营养学会运动营养 / DRIs 2023", referenceType: "个体RNI", adopted: true),
            NutritionTargetItem(id: "diet_fat_g", unit: "%E", mode: .range, lower: 20, upper: 30, source: "中国居民膳食营养素参考摄入量 2023", referenceType: "AMDR", adopted: true),
            NutritionTargetItem(id: "diet_fiber_g", unit: "g", mode: .min, lower: 25, source: "中国营养学会 / WHO 成人建议", referenceType: "AI", adopted: true),
            NutritionTargetItem(id: "diet_water_ml", unit: "mL", mode: .min, lower: isMale ? 1700 : 1500, source: "中国居民膳食指南 2022", referenceType: "AI", adopted: true),
            NutritionTargetItem(id: "diet_ala_mg", unit: "%E", mode: .min, lower: 0.6, source: "DRIs 2023 n-3 必需脂肪酸", referenceType: "AMDR", adopted: true),
            NutritionTargetItem(id: "diet_epa_dha_mg", unit: "mg", mode: .min, lower: 250, source: "DRIs 2023 成人建议", referenceType: "AI", adopted: true),
            // Key vitamins & minerals with strict chemical forms + safe UL where applicable
            NutritionTargetItem(id: "diet_vitamins::A（RAE）", unit: "μg", mode: .min, lower: isMale ? 770 : 660, source: "DRIs 2023", referenceType: "RNI", adopted: true),
            NutritionTargetItem(id: "diet_vitamins::B1", unit: "mg", mode: .min, lower: isMale ? 1.4 : 1.2, source: "DRIs 2023", referenceType: "RNI", adopted: true),
            NutritionTargetItem(id: "diet_vitamins::B2", unit: "mg", mode: .min, lower: isMale ? 1.4 : 1.2, source: "DRIs 2023", referenceType: "RNI", adopted: true),
            NutritionTargetItem(id: "diet_vitamins::烟酸（NE）", unit: "mg", mode: .min, lower: isMale ? 15 : 12, source: "DRIs 2023", referenceType: "RNI", adopted: true),
            NutritionTargetItem(id: "diet_vitamins::B6", unit: "mg", mode: .min, lower: 1.4, source: "DRIs 2023", referenceType: "RNI", adopted: true, upperLimit: 60, upperLimitSource: "DRIs 2023 UL", upperLimitScope: "total"),
            NutritionTargetItem(id: "diet_vitamins::叶酸（DFE）", unit: "μg", mode: .min, lower: 400, source: "DRIs 2023", referenceType: "RNI", adopted: true),
            NutritionTargetItem(id: "diet_vitamins::B12", unit: "μg", mode: .min, lower: 2.4, source: "DRIs 2023", referenceType: "RNI", adopted: true),
            NutritionTargetItem(id: "diet_vitamins::C", unit: "mg", mode: .min, lower: 100, source: "DRIs 2023", referenceType: "RNI", adopted: true, upperLimit: 2000, upperLimitSource: "DRIs 2023 UL", upperLimitScope: "total"),
            NutritionTargetItem(id: "diet_vitamins::D", unit: "μg", mode: .min, lower: 10, source: "DRIs 2023", referenceType: "RNI", adopted: true, upperLimit: 50, upperLimitSource: "DRIs 2023 UL", upperLimitScope: "total"),
            NutritionTargetItem(id: "diet_vitamins::E（α-TE）", unit: "mg", mode: .min, lower: 14, source: "DRIs 2023", referenceType: "AI", adopted: true, upperLimit: 700, upperLimitSource: "DRIs 2023 UL", upperLimitScope: "total"),
            NutritionTargetItem(id: "diet_vitamins::K", unit: "μg", mode: .min, lower: 80, source: "DRIs 2023", referenceType: "AI", adopted: true),
            NutritionTargetItem(id: "diet_minerals::钙", unit: "mg", mode: .min, lower: 800, source: "DRIs 2023", referenceType: "RNI", adopted: true, upperLimit: 2000, upperLimitSource: "DRIs 2023 UL", upperLimitScope: "total"),
            NutritionTargetItem(id: "diet_minerals::钾", unit: "mg", mode: .min, lower: 2000, source: "DRIs 2023", referenceType: "AI", adopted: true),
            NutritionTargetItem(id: "diet_minerals::钠", unit: "mg", mode: .max, upper: 2000, source: "DRIs 2023 PI-NCD 减钠上限", referenceType: "PI-NCD", adopted: true),
            NutritionTargetItem(id: "diet_minerals::镁", unit: "mg", mode: .min, lower: 330, source: "DRIs 2023", referenceType: "RNI", adopted: true),
            NutritionTargetItem(id: "diet_minerals::铁", unit: "mg", mode: .min, lower: isMale ? 12 : 18, source: "DRIs 2023", referenceType: "RNI", adopted: true, upperLimit: 42, upperLimitSource: "DRIs 2023 UL", upperLimitScope: "total"),
            NutritionTargetItem(id: "diet_minerals::锌", unit: "mg", mode: .min, lower: isMale ? 12.0 : 8.5, source: "DRIs 2023", referenceType: "RNI", adopted: true, upperLimit: 40, upperLimitSource: "DRIs 2023 UL", upperLimitScope: "total"),
            NutritionTargetItem(id: "diet_minerals::硒", unit: "μg", mode: .min, lower: 60, source: "DRIs 2023", referenceType: "RNI", adopted: true, upperLimit: 400, upperLimitSource: "DRIs 2023 UL", upperLimitScope: "total"),
        ]
        // Include remaining tracked micronutrients as pending-adoption items so user sees full 14+15 matrix
        let existingIDs = Set(items.map(\.id))
        for v in NutritionCatalog.vitaminOrder {
            let id = "diet_vitamins::\(v)"
            if !existingIDs.contains(id), let unit = NutritionCatalog.vitaminUnits[v] {
                items.append(NutritionTargetItem(id: id, unit: unit, mode: .min, lower: 1, source: "DRIs 2023 参考", referenceType: "AI", adopted: false))
            }
        }
        for m in NutritionCatalog.mineralOrder {
            let id = "diet_minerals::\(m)"
            if !existingIDs.contains(id), let unit = NutritionCatalog.mineralUnits[m] {
                items.append(NutritionTargetItem(id: id, unit: unit, mode: .min, lower: 1, source: "DRIs 2023 参考", referenceType: "AI", adopted: false))
            }
        }

        return NutritionTargetPlan(
            nutritionSchema: 1,
            targetStatus: .active,
            targetVersion: version,
            effectiveFrom: effectiveFrom,
            items: items,
            actionSummary: "基于个人档案与 DRIs 2023 生成；仅已采用项参与四态着色。"
        )
    }

    public static func makePreviewProfile() -> NutritionProfile {
        NutritionProfile(
            age: 28,
            referenceSex: "男",
            heightCm: 176,
            referenceWeightKg: 68.5,
            primaryGoal: "维持体能与体脂管理",
            dietaryPreferences: "日常高蛋白平衡饮食，重训练日补碳水",
            activitySummary: "力量训练 + 羽毛球",
            bmrKcalReference: 1640
        )
    }

    public static func makePreviewLogs(
        endingAt todayKey: DayKey,
        bmrKcal: Double = 1640
    ) -> [DailyNutritionLog] {
        let cal = Calendar(identifier: .gregorian)
        let todayDate = todayKey.calendarDayStart(calendar: cal)
        let starter = Dictionary(uniqueKeysWithValues: NutritionCatalog.starterFoodItems.map { ($0.foodID, $0) })

        var logs: [DailyNutritionLog] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            let dayDate = cal.date(byAdding: .day, value: offset, to: todayDate) ?? todayDate
            let key = DayKey.fromCalendarDay(dayDate, calendar: cal)
            let isComplete = offset < 0 // Today stays open (dietDayComplete: nil) to demonstrate honest .unknown state!

            var entries: [MealEntry] = []
            if let egg = starter["egg_boiled"] {
                entries.append(egg.makeMealEntry(dayKey: key, mealType: .breakfast, portionAmount: 110, recordedAt: dayDate))
            }
            if let milk = starter["whole_milk_plain"] {
                entries.append(milk.makeMealEntry(dayKey: key, mealType: .breakfast, portionAmount: 250, recordedAt: dayDate))
            }
            if let rice = starter["rice_cooked"] {
                entries.append(rice.makeMealEntry(dayKey: key, mealType: .lunch, portionAmount: offset == -2 ? 320 : 240, recordedAt: dayDate))
            }
            if let chicken = starter["chicken_breast_boiled"] {
                entries.append(chicken.makeMealEntry(dayKey: key, mealType: .lunch, portionAmount: offset == -1 ? 260 : 220, recordedAt: dayDate))
            }
            if let broccoli = starter["broccoli_boiled"] {
                entries.append(broccoli.makeMealEntry(dayKey: key, mealType: .dinner, portionAmount: 200, recordedAt: dayDate))
            }
            if offset != 0, let matcha = starter["matcha_powder"] {
                entries.append(matcha.makeMealEntry(dayKey: key, mealType: .snack, portionAmount: 4, recordedAt: dayDate))
            }
            entries.append(
                MealEntry(
                    dayKey: key,
                    mealType: .water,
                    foodName: "温水与电解质补水",
                    portionAmount: offset == -3 ? 1200 : 1950,
                    portionUnit: "mL",
                    waterMl: offset == -3 ? 1200 : 1950,
                    recordedAt: dayDate
                )
            )
            // Supplement dinner / olive oil + salmon meal so daily kcal/macros/sodium are realistic
            entries.append(
                MealEntry(
                    dayKey: key,
                    mealType: .dinner,
                    foodName: "煎三文鱼配糙米杂粮",
                    portionAmount: 360,
                    portionUnit: "g",
                    kcal: isComplete ? (offset == -2 ? 980 : 920) : 520,
                    carbsG: isComplete ? 92 : 48,
                    proteinG: isComplete ? 46 : 24,
                    fatG: isComplete ? (offset == -2 ? 44 : 32) : 16,
                    fiberG: isComplete ? 14 : 6,
                    alaMg: isComplete ? 950 : 400,
                    epaDhaMg: isComplete ? 780 : 320,
                    vitamins: isComplete ? ["C": 68, "D": 12.5, "E（α-TE）": 11.0, "K": 90, "B1": 1.3, "B2": 1.5, "B6": 1.6, "B12": 4.2, "叶酸（DFE）": 320, "烟酸（NE）": 16] : [:],
                    minerals: isComplete ? ["钠": offset == -4 ? 2280 : 1540, "钾": 2150, "钙": 740, "镁": 340, "铁": 13.5, "锌": 11.0, "硒": 64] : [:],
                    isEstimated: true,
                    recordedAt: dayDate
                )
            )

            var log = DailyNutritionLog(
                dayKey: key,
                entries: entries,
                dietDayComplete: isComplete ? true : nil,
                dietPartialFields: isComplete ? [] : ["dinner", "water"],
                healthConfirmedFields: isComplete ? ["diet_protein_g", "diet_kcal"] : [],
                sportHours: 0.75,
                sportKcal: isComplete ? 395 : 210,
                steps: isComplete ? 8240 : 4850,
                bmrKcalUsed: bmrKcal,
                weightKg: 68.5,
                reviewSummary: isComplete ? "蛋白达标，注意蔬菜多样性" : nil,
                updatedAt: dayDate
            )
            log.recalculateTotals()
            logs.append(log)
        }
        return logs
    }
}
