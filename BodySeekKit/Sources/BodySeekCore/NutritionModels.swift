import Foundation

// MARK: - Nutrient Catalog & Formal Units (port of 每日营养素 / 脚本/营养目标.js + data-contract.md)

public struct NutrientDescriptor: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let field: String?
    public let component: String?
    public let name: String
    public let unit: String
    public let rawUnit: String?
    public let energyFactor: Double?
    public let isPendingForm: Bool

    public init(
        id: String,
        field: String? = nil,
        component: String? = nil,
        name: String,
        unit: String,
        rawUnit: String? = nil,
        energyFactor: Double? = nil,
        isPendingForm: Bool = false
    ) {
        self.id = id
        self.field = field
        self.component = component
        self.name = name
        self.unit = unit
        self.rawUnit = rawUnit
        self.energyFactor = energyFactor
        self.isPendingForm = isPendingForm
    }
}

public enum NutritionCatalog {
    public static let macroDescriptors: [NutrientDescriptor] = [
        NutrientDescriptor(id: "diet_kcal", name: "总能量", unit: "kcal"),
        NutrientDescriptor(id: "diet_carbs_g", name: "碳水化合物", unit: "%E", rawUnit: "g", energyFactor: 4.0),
        NutrientDescriptor(id: "diet_protein_g", name: "蛋白质", unit: "g"),
        NutrientDescriptor(id: "diet_fat_g", name: "总脂肪", unit: "%E", rawUnit: "g", energyFactor: 9.0),
        NutrientDescriptor(id: "diet_fiber_g", name: "膳食纤维", unit: "g"),
        NutrientDescriptor(id: "diet_water_ml", name: "饮水", unit: "mL"),
        NutrientDescriptor(id: "diet_ala_mg", name: "ALA", unit: "%E", rawUnit: "mg", energyFactor: 0.009),
        NutrientDescriptor(id: "diet_epa_dha_mg", name: "EPA＋DHA", unit: "mg"),
    ]

    public static let vitaminUnits: [String: String] = [
        "B1": "mg",
        "B2": "mg",
        "B6": "mg",
        "B12": "μg",
        "C": "mg",
        "D": "μg",
        "K": "μg",
        "A（RAE）": "μg",
        "E（α-TE）": "mg",
        "烟酸（NE）": "mg",
        "叶酸（DFE）": "μg",
        "泛酸": "mg",
        "生物素": "μg",
        "胆碱": "mg",
    ]

    public static let mineralUnits: [String: String] = [
        "钙": "mg",
        "磷": "mg",
        "钾": "mg",
        "钠": "mg",
        "镁": "mg",
        "铁": "mg",
        "锌": "mg",
        "硒": "μg",
        "碘": "μg",
        "铜": "mg",
        "锰": "mg",
        "氯": "mg",
        "氟": "mg",
        "铬": "μg",
        "钼": "μg",
    ]

    public static let unresolvedMicroUnits: [String: String] = [
        "A": "μg",
        "E": "mg",
        "E（α-生育酚）": "mg",
        "烟酸": "mg",
        "叶酸": "μg",
    ]

    public static let specialFormULRestrictedComponents: Set<String> = [
        "A（RAE）",
        "烟酸（NE）",
        "叶酸（DFE）",
    ]

    public static let vitaminOrder: [String] = [
        "A（RAE）", "B1", "B2", "烟酸（NE）", "泛酸", "B6", "生物素", "叶酸（DFE）", "B12", "C", "D", "E（α-TE）", "K", "胆碱",
    ]

    public static let mineralOrder: [String] = [
        "钙", "磷", "钾", "钠", "镁", "铁", "锌", "铜", "锰", "硒", "碘", "氯", "氟", "铬", "钼",
    ]

    public static let allKnownDescriptors: [String: NutrientDescriptor] = {
        var map = Dictionary(uniqueKeysWithValues: macroDescriptors.map { ($0.id, $0) })
        for (name, unit) in vitaminUnits {
            let id = "diet_vitamins::\(name)"
            map[id] = NutrientDescriptor(
                id: id,
                field: "diet_vitamins",
                component: name,
                name: "维生素 · \(name)",
                unit: unit,
                isPendingForm: false
            )
        }
        for (name, unit) in mineralUnits {
            let id = "diet_minerals::\(name)"
            map[id] = NutrientDescriptor(
                id: id,
                field: "diet_minerals",
                component: name,
                name: "矿物质 · \(name)",
                unit: unit,
                isPendingForm: false
            )
        }
        return map
    }()

    public static func descriptor(forID id: String) -> NutrientDescriptor? {
        if let exact = allKnownDescriptors[id] {
            return exact
        }
        if id.hasPrefix("diet_vitamins::") {
            let comp = String(id.dropFirst("diet_vitamins::".count))
            return NutrientDescriptor(
                id: id,
                field: "diet_vitamins",
                component: comp,
                name: "维生素 · \(comp)",
                unit: unresolvedMicroUnits[comp] ?? "mg",
                isPendingForm: true
            )
        }
        if id.hasPrefix("diet_minerals::") {
            let comp = String(id.dropFirst("diet_minerals::".count))
            return NutrientDescriptor(
                id: id,
                field: "diet_minerals",
                component: comp,
                name: "矿物质 · \(comp)",
                unit: unresolvedMicroUnits[comp] ?? "mg",
                isPendingForm: true
            )
        }
        return nil
    }

    public static func normalizeMicroValue(_ value: Double, fromUnit: String, toUnit: String) -> Double? {
        guard value.isFinite, value >= 0 else { return nil }
        let normalizedFrom = normalizeUnitSymbol(fromUnit)
        let normalizedTo = normalizeUnitSymbol(toUnit)
        if normalizedFrom == normalizedTo { return value }
        if normalizedFrom == "mg" && normalizedTo == "μg" { return value * 1000.0 }
        if normalizedFrom == "μg" && normalizedTo == "mg" { return value * 0.001 }
        return nil
    }

    private static func normalizeUnitSymbol(_ unit: String) -> String {
        switch unit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "ug", "mcg", "µg", "μg": "μg"
        case "mg": "mg"
        case "g": "g"
        case "ml": "mL"
        case "kcal": "kcal"
        case "%e": "%E"
        default: unit
        }
    }

    /// Official traceable food entries seeded from verified public nutrition tables (MEXT 8th Rev 2023 / USDA).
    public static let commonMealFoodItems: [FoodLibraryItem] = [
        FoodLibraryItem(
            foodID: "oats_plain_dry", name: "燕麦片（原味干重）",
            aliases: ["燕麦", "燕麦片", "原味燕麦"], category: "谷物", stateDescription: "未冲泡、无添加",
            dataKind: "官方成分表", energyKcalPer100: 350, carbsGPer100: 69.1,
            proteinGPer100: 13.7, fatGPer100: 5.7, fiberGPer100: 9.4,
            sourceName: "日本食品标准成分表（八订）增补2023，01004",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=1_01004_7"
        ),
        FoodLibraryItem(
            foodID: "potato_fries_generic", name: "炸薯条（通用参考）",
            aliases: ["薯条", "炸薯条"], category: "薯类", stateDescription: "油炸冷冻薯条，成分随品牌与做法变化",
            dataKind: "官方成分表", energyKcalPer100: 229, carbsGPer100: 32.4,
            proteinGPer100: 2.9, fatGPer100: 10.6, fiberGPer100: 3.1,
            sourceName: "日本食品标准成分表（八订）增补2023，02020",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=2_02020_7"
        ),
    ]

    public static let starterFoodItems: [FoodLibraryItem] = commonMealFoodItems + [
        FoodLibraryItem(
            foodID: "rice_cooked",
            name: "白米饭（熟）",
            aliases: ["米饭", "熟白米饭"],
            category: "谷薯",
            stateDescription: "熟，可食部",
            basisAmount: 100,
            basisUnit: "g",
            dataKind: "官方成分表",
            usable: true,
            energyKcalPer100: 156,
            carbsGPer100: 37.1,
            proteinGPer100: 2.5,
            fatGPer100: 0.3,
            fiberGPer100: 1.5,
            vitaminsPer100: ["B1": 0.02, "B2": 0.01, "烟酸（NE）": 0.8, "B6": 0.02, "叶酸（DFE）": 3.0, "泛酸": 0.25, "生物素": 0.5],
            mineralsPer100: ["钠": 1.0, "钾": 29.0, "钙": 3.0, "镁": 7.0, "磷": 34.0, "铁": 0.1, "锌": 0.6, "铜": 0.1, "锰": 0.35, "硒": 1.0, "钼": 30.0],
            sourceName: "日本食品标准成分表（八订）增补2023，01088",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=1_01088_7",
            verifiedOn: DayKey(year: 2026, month: 11, day: 3)
        ),
        FoodLibraryItem(
            foodID: "egg_boiled",
            name: "鸡蛋（水煮）",
            aliases: ["水煮蛋", "白煮蛋"],
            category: "蛋奶",
            stateDescription: "熟，去壳可食部",
            basisAmount: 100,
            basisUnit: "g",
            dataKind: "官方成分表",
            usable: true,
            energyKcalPer100: 134,
            carbsGPer100: 0.3,
            proteinGPer100: 12.5,
            fatGPer100: 10.4,
            fiberGPer100: 0,
            vitaminsPer100: ["A（RAE）": 170, "B1": 0.06, "B2": 0.32, "B6": 0.09, "B12": 1.0, "D": 2.5, "E（α-TE）": 1.2, "K": 11, "叶酸（DFE）": 48],
            mineralsPer100: ["钙": 47, "磷": 170, "钾": 130, "钠": 140, "镁": 11, "铁": 1.5, "锌": 1.1, "硒": 25],
            sourceName: "日本食品标准成分表（八订）增补2023，12005",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=12_12005_7",
            verifiedOn: DayKey(year: 2026, month: 11, day: 15)
        ),
        FoodLibraryItem(
            foodID: "mung_sprouts_boiled",
            name: "绿豆芽（水煮）",
            aliases: ["豆芽"],
            category: "蔬菜",
            stateDescription: "水煮沥干，不含油",
            basisAmount: 100,
            basisUnit: "g",
            dataKind: "官方成分表",
            usable: true,
            energyKcalPer100: 12,
            carbsGPer100: 2.3,
            proteinGPer100: 1.6,
            fatGPer100: 0,
            fiberGPer100: 1.5,
            vitaminsPer100: ["B1": 0.03, "B2": 0.04, "烟酸（NE）": 0.5, "B6": 0.02, "叶酸（DFE）": 33.0, "泛酸": 0.14, "C": 2.0, "E（α-TE）": 0.1, "K": 3.0],
            mineralsPer100: ["钠": 2.0, "钾": 24.0, "钙": 11.0, "镁": 7.0, "磷": 24.0, "铁": 0.3, "锌": 0.2, "铜": 0.06, "锰": 0.06],
            sourceName: "日本食品标准成分表（八订）增补2023",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=6_06292_7",
            verifiedOn: DayKey(year: 2026, month: 11, day: 15)
        ),
        FoodLibraryItem(
            foodID: "matcha_powder",
            name: "抹茶（纯粉）",
            aliases: ["纯抹茶粉", "无糖抹茶粉"],
            category: "茶饮",
            stateDescription: "干粉，无糖",
            basisAmount: 100,
            basisUnit: "g",
            dataKind: "官方成分表",
            usable: true,
            energyKcalPer100: 237,
            carbsGPer100: 39.5,
            proteinGPer100: 29.6,
            fatGPer100: 5.3,
            fiberGPer100: 38.5,
            vitaminsPer100: ["A（RAE）": 2400.0, "E（α-TE）": 28.0, "K": 2900.0, "B1": 0.6, "B2": 1.35, "烟酸（NE）": 12.0, "B6": 0.96, "叶酸（DFE）": 1200.0, "泛酸": 3.7, "C": 60.0],
            mineralsPer100: ["钠": 6.0, "钾": 2700.0, "钙": 420.0, "镁": 230.0, "磷": 350.0, "铁": 17.0, "锌": 6.3, "铜": 0.6],
            sourceName: "日本食品标准成分表（八订）增补2023，16035",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=16_16035_7",
            verifiedOn: DayKey(year: 2026, month: 11, day: 3)
        ),
        FoodLibraryItem(
            foodID: "whole_milk_plain",
            name: "纯牛奶（全脂）",
            aliases: ["全脂牛奶", "鲜牛奶"],
            category: "蛋奶",
            stateDescription: "液态，无糖全脂",
            basisAmount: 100,
            basisUnit: "mL",
            dataKind: "官方成分表",
            usable: true,
            energyKcalPer100: 62,
            carbsGPer100: 4.8,
            proteinGPer100: 3.3,
            fatGPer100: 3.8,
            fiberGPer100: 0,
            vitaminsPer100: ["A（RAE）": 38, "B2": 0.15, "B12": 0.3],
            mineralsPer100: ["钙": 110, "磷": 93, "钾": 150, "钠": 41, "镁": 10, "锌": 0.4],
            sourceName: "日本食品标准成分表（八订）增补2023，13003",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=13_13003_7",
            verifiedOn: DayKey(year: 2026, month: 11, day: 3)
        ),
        FoodLibraryItem(
            foodID: "chicken_breast_boiled",
            name: "鸡胸肉（去皮水煮）",
            aliases: ["水煮鸡胸", "鸡胸"],
            category: "肉禽",
            stateDescription: "熟，去皮可食部",
            basisAmount: 100,
            basisUnit: "g",
            dataKind: "官方成分表",
            usable: true,
            energyKcalPer100: 116,
            carbsGPer100: 0,
            proteinGPer100: 24.4,
            fatGPer100: 1.9,
            fiberGPer100: 0,
            vitaminsPer100: ["B6": 0.6, "烟酸（NE）": 15.0],
            mineralsPer100: ["钾": 340, "磷": 230, "镁": 29, "钠": 42, "铁": 0.3, "锌": 0.7],
            sourceName: "日本食品标准成分表（八订）增补2023，11220",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=11_11220_7",
            verifiedOn: DayKey(year: 2026, month: 11, day: 3)
        ),
        FoodLibraryItem(
            foodID: "broccoli_boiled",
            name: "西兰花（水煮）",
            aliases: ["绿花菜", "花椰菜"],
            category: "蔬菜",
            stateDescription: "水煮沥干，不含油",
            basisAmount: 100,
            basisUnit: "g",
            dataKind: "官方成分表",
            usable: true,
            energyKcalPer100: 30,
            carbsGPer100: 4.5,
            proteinGPer100: 3.9,
            fatGPer100: 0.3,
            fiberGPer100: 3.7,
            vitaminsPer100: ["C": 55.0, "K": 180.0, "叶酸（DFE）": 120.0, "A（RAE）": 58.0],
            mineralsPer100: ["钾": 210.0, "钙": 42.0, "镁": 21.0, "磷": 66.0, "铁": 0.8],
            sourceName: "日本食品标准成分表（八订）增补2023，06264",
            sourceURL: "https://fooddb.mext.go.jp/details/details.pl?ITEM_NO=6_06264_7",
            verifiedOn: DayKey(year: 2026, month: 11, day: 3)
        ),
    ]
}

// MARK: - User Nutrition Profile (个人档案)

public struct NutritionProfile: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var age: Int?
    public var birthYearMonth: String?
    public var referenceSex: String?
    public var heightCm: Double?
    public var referenceWeightKg: Double?
    public var waistCm: Double?
    public var primaryGoal: String?
    public var dietaryPreferences: String?
    public var allergies: [String]
    public var medicalRestrictions: [String]
    public var activitySummary: String?
    public var bmrKcalReference: Double?
    public var assumePhotoFinished: Bool?
    public var allowPortionEstimate: Bool?
    public var treatBlankSnackAsZero: Bool?
    public var preferredWeightUnit: String
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        age: Int? = nil,
        birthYearMonth: String? = nil,
        referenceSex: String? = nil,
        heightCm: Double? = nil,
        referenceWeightKg: Double? = nil,
        waistCm: Double? = nil,
        primaryGoal: String? = nil,
        dietaryPreferences: String? = nil,
        allergies: [String] = [],
        medicalRestrictions: [String] = [],
        activitySummary: String? = nil,
        bmrKcalReference: Double? = nil,
        assumePhotoFinished: Bool? = nil,
        allowPortionEstimate: Bool? = nil,
        treatBlankSnackAsZero: Bool? = nil,
        preferredWeightUnit: String = "kg",
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.age = age
        self.birthYearMonth = birthYearMonth
        self.referenceSex = referenceSex
        self.heightCm = heightCm
        self.referenceWeightKg = referenceWeightKg
        self.waistCm = waistCm
        self.primaryGoal = primaryGoal
        self.dietaryPreferences = dietaryPreferences
        self.allergies = allergies
        self.medicalRestrictions = medicalRestrictions
        self.activitySummary = activitySummary
        self.bmrKcalReference = bmrKcalReference
        self.assumePhotoFinished = assumePhotoFinished
        self.allowPortionEstimate = allowPortionEstimate
        self.treatBlankSnackAsZero = treatBlankSnackAsZero
        self.preferredWeightUnit = preferredWeightUnit
        self.updatedAt = updatedAt
    }

    public var hasBaselineDemographics: Bool {
        (age != nil || birthYearMonth != nil) && referenceSex != nil && primaryGoal != nil
    }
}

// MARK: - Personal Nutrition Targets & Evaluation (营养目标)

public enum NutritionTargetStatus: String, Hashable, Codable, Sendable {
    case pendingProfile = "pending_profile"
    case draft
    case active
}

public enum NutritionTargetMode: String, Hashable, Codable, Sendable {
    case min
    case max
    case range
}

public struct NutritionTargetItem: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let unit: String
    public let mode: NutritionTargetMode
    public let lower: Double?
    public let upper: Double?
    public let source: String
    public let referenceType: String?
    public let adopted: Bool
    public let upperLimit: Double?
    public let upperLimitSource: String?
    public let upperLimitScope: String?

    public init(
        id: String,
        unit: String,
        mode: NutritionTargetMode,
        lower: Double? = nil,
        upper: Double? = nil,
        source: String,
        referenceType: String? = nil,
        adopted: Bool = false,
        upperLimit: Double? = nil,
        upperLimitSource: String? = nil,
        upperLimitScope: String? = nil
    ) {
        self.id = id
        self.unit = unit
        self.mode = mode
        self.lower = lower
        self.upper = upper
        self.source = source
        self.referenceType = referenceType
        self.adopted = adopted
        self.upperLimit = upperLimit
        self.upperLimitSource = upperLimitSource
        self.upperLimitScope = upperLimitScope
    }
}

public struct NutritionTargetPlan: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var nutritionSchema: Int
    public var targetStatus: NutritionTargetStatus
    public var targetVersion: String
    public var effectiveFrom: DayKey?
    public var items: [NutritionTargetItem]
    public var actionSummary: String?
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        nutritionSchema: Int = 1,
        targetStatus: NutritionTargetStatus = .pendingProfile,
        targetVersion: String = "",
        effectiveFrom: DayKey? = nil,
        items: [NutritionTargetItem] = [],
        actionSummary: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.nutritionSchema = nutritionSchema
        self.targetStatus = targetStatus
        self.targetVersion = targetVersion
        self.effectiveFrom = effectiveFrom
        self.items = items
        self.actionSummary = actionSummary
        self.updatedAt = updatedAt
    }
}

public enum NutritionReadingStatus: String, Hashable, Codable, Sendable {
    case met
    case low
    case over
    case unknown

    public var label: String {
        switch self {
        case .met: "达标"
        case .low: "不足"
        case .over: "超标"
        case .unknown: "暂不判断"
        }
    }

    public var hexColor: String {
        switch self {
        case .met: "#4A9D72"
        case .low: "#D79939"
        case .over: "#D65C5C"
        case .unknown: "#8A9099"
        }
    }
}

public struct NutritionEvaluatedReading: Equatable, Hashable, Codable, Sendable {
    public let metricID: String
    public let metricName: String
    public let value: Double?
    public let rawAmount: Double?
    public let displayUnit: String
    public let rawUnit: String?
    public let status: NutritionReadingStatus
    public let reason: String
    public let targetSummary: String
    public let isDayComplete: Bool
    public let isConfirmed: Bool
    /// True when the amount used for this reading includes AI estimates.
    /// Estimated readings are directional only and must not be presented as confirmed adequacy.
    public let isEstimated: Bool

    public init(
        metricID: String,
        metricName: String,
        value: Double?,
        rawAmount: Double?,
        displayUnit: String,
        rawUnit: String? = nil,
        status: NutritionReadingStatus,
        reason: String,
        targetSummary: String,
        isDayComplete: Bool,
        isConfirmed: Bool,
        isEstimated: Bool = false
    ) {
        self.metricID = metricID
        self.metricName = metricName
        self.value = value
        self.rawAmount = rawAmount
        self.displayUnit = displayUnit
        self.rawUnit = rawUnit
        self.status = status
        self.reason = reason
        self.targetSummary = targetSummary
        self.isDayComplete = isDayComplete
        self.isConfirmed = isConfirmed
        self.isEstimated = isEstimated
    }
}

public struct ValidatedTargetPlan: Equatable, Sendable {
    public let isActive: Bool
    public let errors: [String]
    public let validAdoptedItems: [String: NutritionTargetItem]
    public let statusMessage: String

    public init(
        isActive: Bool,
        errors: [String],
        validAdoptedItems: [String: NutritionTargetItem],
        statusMessage: String
    ) {
        self.isActive = isActive
        self.errors = errors
        self.validAdoptedItems = validAdoptedItems
        self.statusMessage = statusMessage
    }
}

/// Pure validator & evaluator implementing the exact semantics of `营养目标.js`.
public enum NutritionTargetEvaluator {
    public static func validate(plan: NutritionTargetPlan?, on todayKey: DayKey) -> ValidatedTargetPlan {
        guard let plan else {
            return ValidatedTargetPlan(
                isActive: false,
                errors: [],
                validAdoptedItems: [:],
                statusMessage: "待设置目标 · 请先补充个人档案并由 Coach 生成采用目标"
            )
        }

        var errors: [String] = []
        let trimmedVersion = plan.targetVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let isActive: Bool = if plan.nutritionSchema == 1,
                                plan.targetStatus == .active,
                                !trimmedVersion.isEmpty,
                                let effective = plan.effectiveFrom,
                                effective <= todayKey {
            true
        } else {
            false
        }

        if plan.targetStatus == .active && !isActive {
            errors.append("采用状态缺少有效结构版本、目标版本、生效日期，或尚未到生效日")
        }

        var itemsByID: [String: NutritionTargetItem] = [:]
        var duplicateIDs = Set<String>()
        for item in plan.items {
            let trimmedID = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedID.isEmpty {
                errors.append("目标项目缺少 id")
                continue
            }
            if itemsByID[trimmedID] != nil {
                duplicateIDs.insert(trimmedID)
            }
            itemsByID[trimmedID] = item
        }
        for dup in duplicateIDs.sorted() {
            errors.append("\(dup) 重复，暂停评价")
        }

        var validAdopted: [String: NutritionTargetItem] = [:]
        for (id, item) in itemsByID where !duplicateIDs.contains(id) {
            guard let descriptor = NutritionCatalog.descriptor(forID: id), !descriptor.isPendingForm else {
                errors.append("\(id)：未知指标或形态待核对")
                continue
            }
            let allowedUnits = Set([descriptor.unit, descriptor.rawUnit].compactMap { $0 })
            guard allowedUnits.contains(item.unit) else {
                errors.append("\(id)：单位不匹配")
                continue
            }
            guard !item.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errors.append("\(id)：缺少依据")
                continue
            }

            let validBounds: Bool
            switch item.mode {
            case .min:
                validBounds = (item.lower.map { $0.isFinite && $0 >= 0 } == true) && item.upper == nil
            case .max:
                validBounds = (item.upper.map { $0.isFinite && $0 >= 0 } == true) && item.lower == nil
            case .range:
                if let lo = item.lower, let hi = item.upper, lo.isFinite, hi.isFinite, lo >= 0, lo <= hi {
                    validBounds = true
                } else {
                    validBounds = false
                }
            }
            guard validBounds else {
                errors.append("\(id)：上下界无效")
                continue
            }

            if item.unit == "%E" {
                let exceeds = [item.lower, item.upper].compactMap { $0 }.contains { $0 > 100 }
                if exceeds {
                    errors.append("\(id)：供能比超出 100%")
                    continue
                }
            }

            if let ul = item.upperLimit {
                let ulSourceOK = item.upperLimitSource.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } == true
                let isRestrictedComp = descriptor.component.map { NutritionCatalog.specialFormULRestrictedComponents.contains($0) } == true
                let upperBound = item.upper ?? item.lower ?? 0
                if !ul.isFinite || ul < 0 || !ulSourceOK || item.upperLimitScope != "total" || isRestrictedComp || ul < upperBound {
                    errors.append("\(id)：UL 必须有同口径总摄入依据且不低于目标；特殊形态不可混用")
                    continue
                }
            }

            if isActive && item.adopted {
                validAdopted[id] = item
            }
        }

        let msg: String
        if !validAdopted.isEmpty, let effective = plan.effectiveFrom {
            msg = "当前目标 \(trimmedVersion) · 生效于 \(effective.isoString) · \(validAdopted.count) 项已采用"
        } else {
            msg = "待设置目标 · 请由 Coach 根据个人档案生成并记录采用状态"
        }

        return ValidatedTargetPlan(
            isActive: isActive,
            errors: errors,
            validAdoptedItems: validAdopted,
            statusMessage: msg
        )
    }

    public static func evaluate(
        metricID: String,
        log: DailyNutritionLog?,
        validatedPlan: ValidatedTargetPlan,
        allowEstimates: Bool = false
    ) -> NutritionEvaluatedReading {
        let descriptor = NutritionCatalog.descriptor(forID: metricID)
            ?? NutrientDescriptor(id: metricID, name: metricID, unit: "g", isPendingForm: true)
        let targetItem = validatedPlan.validAdoptedItems[metricID]
        let displayUnit = targetItem?.unit ?? descriptor.unit
        let targetLabel: String = if let item = targetItem {
            formatTargetLabel(item: item)
        } else {
            descriptor.isPendingForm ? "口径待核对，暂不评价" : "待设置目标"
        }

        let hasPartialMeals = log?.dietPartialFields.isEmpty == false
        let hasAIEstimate = log?.entries.contains { $0.aiEstimatedNutrientIDs?.contains(metricID) == true } == true
        let isDayComplete = log?.dietDayComplete == true
            && !hasPartialMeals
            && (allowEstimates || !hasAIEstimate)
        let isConfirmed = log?.healthConfirmedFields.contains(metricID) == true
        let readingIsEstimated = hasAIEstimate && allowEstimates
        let rawAmount = log?.rawValue(forMetricID: metricID)

        guard let rawAmount, rawAmount.isFinite, rawAmount >= 0 else {
            return NutritionEvaluatedReading(
                metricID: metricID,
                metricName: descriptor.name,
                value: nil,
                rawAmount: nil,
                displayUnit: displayUnit,
                rawUnit: descriptor.rawUnit,
                status: .unknown,
                reason: "无有效摄入记录",
                targetSummary: targetLabel,
                isDayComplete: isDayComplete,
                isConfirmed: false
            )
        }

        // Convert to %E when the active/default unit uses energy percentage and raw unit exists.
        var evaluatedValue: Double = rawAmount
        if displayUnit == "%E", let factor = descriptor.energyFactor {
            guard let kcal = log?.dietKcal, kcal.isFinite, kcal > 0 else {
                return NutritionEvaluatedReading(
                    metricID: metricID,
                    metricName: descriptor.name,
                    value: nil,
                    rawAmount: rawAmount,
                    displayUnit: displayUnit,
                    rawUnit: descriptor.rawUnit,
                    status: .unknown,
                    reason: "全天能量缺失、无效或非正，不能换算供能比",
                    targetSummary: targetLabel,
                    isDayComplete: isDayComplete,
                    isConfirmed: isConfirmed
                )
            }
            let pct = rawAmount * factor / kcal * 100.0
            guard pct.isFinite, pct <= 100.0 + 1e-6 else {
                return NutritionEvaluatedReading(
                    metricID: metricID,
                    metricName: descriptor.name,
                    value: nil,
                    rawAmount: rawAmount,
                    displayUnit: displayUnit,
                    rawUnit: descriptor.rawUnit,
                    status: .unknown,
                    reason: "营养素与全天能量不一致，供能比超出100%",
                    targetSummary: targetLabel,
                    isDayComplete: isDayComplete,
                    isConfirmed: isConfirmed
                )
            }
            evaluatedValue = pct
        }

        guard isDayComplete else {
            return NutritionEvaluatedReading(
                metricID: metricID,
                metricName: descriptor.name,
                value: evaluatedValue,
                rawAmount: rawAmount,
                displayUnit: displayUnit,
                rawUnit: descriptor.rawUnit,
                status: .unknown,
                reason: hasAIEstimate ? "含 AI 粗估，暂不判定达标或超限" : (hasPartialMeals ? "有餐食的营养记录不完整" : "当天未收尾"),
                targetSummary: targetLabel,
                isDayComplete: isDayComplete,
                isConfirmed: isConfirmed,
                isEstimated: readingIsEstimated
            )
        }

        guard let target = targetItem else {
            return NutritionEvaluatedReading(
                metricID: metricID,
                metricName: descriptor.name,
                value: evaluatedValue,
                rawAmount: rawAmount,
                displayUnit: displayUnit,
                rawUnit: descriptor.rawUnit,
                status: .unknown,
                reason: targetLabel,
                targetSummary: targetLabel,
                isDayComplete: true,
                isConfirmed: isConfirmed,
                isEstimated: readingIsEstimated
            )
        }

        if let ul = target.upperLimit, evaluatedValue > ul {
            return NutritionEvaluatedReading(
                metricID: metricID,
                metricName: descriptor.name,
                value: evaluatedValue,
                rawAmount: rawAmount,
                displayUnit: displayUnit,
                rawUnit: descriptor.rawUnit,
                status: .over,
                reason: "超过UL \(formatNumber(ul)) \(target.unit)（安全上限，非目标）",
                targetSummary: targetLabel,
                isDayComplete: true,
                isConfirmed: isConfirmed,
                isEstimated: readingIsEstimated
            )
        }

        let status: NutritionReadingStatus
        switch target.mode {
        case .min:
            status = evaluatedValue < (target.lower ?? 0) ? .low : .met
        case .max:
            status = evaluatedValue > (target.upper ?? .infinity) ? .over : .met
        case .range:
            let lo = target.lower ?? 0
            let hi = target.upper ?? .infinity
            if evaluatedValue < lo {
                status = .low
            } else if evaluatedValue > hi {
                status = .over
            } else {
                status = .met
            }
        }

        return NutritionEvaluatedReading(
            metricID: metricID,
            metricName: descriptor.name,
            value: evaluatedValue,
            rawAmount: rawAmount,
            displayUnit: displayUnit,
            rawUnit: descriptor.rawUnit,
            status: status,
            reason: targetLabel,
            targetSummary: targetLabel,
            isDayComplete: true,
            isConfirmed: isConfirmed,
            isEstimated: readingIsEstimated
        )
    }

    private static func formatTargetLabel(item: NutritionTargetItem) -> String {
        let ref = (item.referenceType?.isEmpty == false) ? item.referenceType! : "采用目标"
        let boundary: String
        switch item.mode {
        case .min:
            boundary = "≥\(formatNumber(item.lower ?? 0))"
        case .max:
            boundary = "≤\(formatNumber(item.upper ?? 0))"
        case .range:
            boundary = "\(formatNumber(item.lower ?? 0))–\(formatNumber(item.upper ?? 0))"
        }
        return "\(ref) \(boundary) \(item.unit) · \(item.source)"
    }

    private static func formatNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }
}

// MARK: - Food Library & Daily Logs (营养库 & 每日饮食记录)

public struct FoodLibraryItem: Identifiable, Hashable, Codable, Sendable {
    public var id: String { foodID }
    public let foodID: String
    public var name: String
    public var aliases: [String]
    public var category: String
    public var stateDescription: String
    public var basisAmount: Double
    public var basisUnit: String
    public var dataKind: String
    public var usable: Bool
    public var energyKcalPer100: Double?
    public var carbsGPer100: Double?
    public var proteinGPer100: Double?
    public var fatGPer100: Double?
    public var fiberGPer100: Double?
    public var alaMgPer100: Double?
    public var epaDhaMgPer100: Double?
    public var vitaminsPer100: [String: Double]
    public var mineralsPer100: [String: Double]
    public var sourceName: String
    public var sourceURL: String?
    public var verifiedOn: DayKey?
    public var notes: String?

    public init(
        foodID: String,
        name: String,
        aliases: [String] = [],
        category: String = "常见食物",
        stateDescription: String = "可食部",
        basisAmount: Double = 100,
        basisUnit: String = "g",
        dataKind: String = "用户或官方核验",
        usable: Bool = true,
        energyKcalPer100: Double? = nil,
        carbsGPer100: Double? = nil,
        proteinGPer100: Double? = nil,
        fatGPer100: Double? = nil,
        fiberGPer100: Double? = nil,
        alaMgPer100: Double? = nil,
        epaDhaMgPer100: Double? = nil,
        vitaminsPer100: [String: Double] = [:],
        mineralsPer100: [String: Double] = [:],
        sourceName: String = "待补充来源",
        sourceURL: String? = nil,
        verifiedOn: DayKey? = nil,
        notes: String? = nil
    ) {
        self.foodID = foodID
        self.name = name
        self.aliases = aliases
        self.category = category
        self.stateDescription = stateDescription
        self.basisAmount = max(1, basisAmount)
        self.basisUnit = basisUnit
        self.dataKind = dataKind
        self.usable = usable
        self.energyKcalPer100 = energyKcalPer100
        self.carbsGPer100 = carbsGPer100
        self.proteinGPer100 = proteinGPer100
        self.fatGPer100 = fatGPer100
        self.fiberGPer100 = fiberGPer100
        self.alaMgPer100 = alaMgPer100
        self.epaDhaMgPer100 = epaDhaMgPer100
        self.vitaminsPer100 = vitaminsPer100
        self.mineralsPer100 = mineralsPer100
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.verifiedOn = verifiedOn
        self.notes = notes
    }

    public func makeMealEntry(
        dayKey: DayKey,
        mealType: MealType,
        portionAmount: Double,
        portionDescription: String? = nil,
        isEstimated: Bool = false,
        recordedAt: Date = Date(),
        id: UUID = UUID()
    ) -> MealEntry {
        let ratio = max(0, portionAmount) / max(1.0, basisAmount)
        return MealEntry(
            id: id,
            dayKey: dayKey,
            mealType: mealType,
            foodID: foodID,
            foodName: name,
            portionAmount: portionAmount,
            portionUnit: basisUnit,
            portionDescription: portionDescription ?? "\(Int(portionAmount.rounded())) \(basisUnit)",
            kcal: energyKcalPer100.map { ($0 * ratio).rounded() },
            carbsG: carbsGPer100.map { (($0 * ratio) * 10).rounded() / 10 },
            proteinG: proteinGPer100.map { (($0 * ratio) * 10).rounded() / 10 },
            fatG: fatGPer100.map { (($0 * ratio) * 10).rounded() / 10 },
            fiberG: fiberGPer100.map { (($0 * ratio) * 10).rounded() / 10 },
            waterMl: nil,
            alaMg: alaMgPer100.map { ($0 * ratio).rounded() },
            epaDhaMg: epaDhaMgPer100.map { ($0 * ratio).rounded() },
            vitamins: vitaminsPer100.mapValues { (($0 * ratio) * 100).rounded() / 100 },
            minerals: mineralsPer100.mapValues { (($0 * ratio) * 100).rounded() / 100 },
            isEstimated: isEstimated,
            recordedAt: recordedAt
        )
    }
}

public enum MealType: String, CaseIterable, Hashable, Codable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
    case water

    public var title: String {
        switch self {
        case .breakfast: "早餐"
        case .lunch: "午餐"
        case .dinner: "晚餐"
        case .snack: "加餐"
        case .water: "饮水"
        }
    }
}

public struct MealEnergyEstimate: Hashable, Codable, Sendable {
    public let lowerKcal: Double
    public let upperKcal: Double
    public let assumptions: String

    public init(lowerKcal: Double, upperKcal: Double, assumptions: String) {
        self.lowerKcal = lowerKcal
        self.upperKcal = upperKcal
        self.assumptions = assumptions
    }

    public var midpointKcal: Double { ((lowerKcal + upperKcal) / 2).rounded() }
    public var displayRange: String { "\(lowerKcal.formatted(.number.precision(.fractionLength(0))))–\(upperKcal.formatted(.number.precision(.fractionLength(0)))) kcal" }
}

public struct MealEntry: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let dayKey: DayKey
    public var mealType: MealType
    public var foodID: String?
    public var foodName: String
    public var portionAmount: Double?
    public var portionUnit: String
    public var portionDescription: String
    public var kcal: Double?
    public var carbsG: Double?
    public var proteinG: Double?
    public var fatG: Double?
    public var fiberG: Double?
    public var waterMl: Double?
    public var alaMg: Double?
    public var epaDhaMg: Double?
    public var vitamins: [String: Double]
    public var minerals: [String: Double]
    public var isEstimated: Bool
    public var estimationNote: String?
    public var isExplicitlyPartial: Bool?
    public var energyEstimate: MealEnergyEstimate?
    public var recordedAt: Date

    public var aiEstimatedNutrientIDs: Set<String>?

    public static let additionalNutrientIDs = ["diet_fiber_g", "diet_water_ml", "diet_ala_mg", "diet_epa_dha_mg"]
        + NutritionCatalog.vitaminOrder.map { "diet_vitamins::" + $0 }
        + NutritionCatalog.mineralOrder.map { "diet_minerals::" + $0 }

    public static func additionalNutrientKeyPath(_ id: String) -> WritableKeyPath<Self, Double?>? {
        switch id {
        case "diet_fiber_g": return \.fiberG
        case "diet_water_ml": return \.waterMl
        case "diet_ala_mg": return \.alaMg
        case "diet_epa_dha_mg": return \.epaDhaMg
        default:
            guard let descriptor = NutritionCatalog.allKnownDescriptors[id], let component = descriptor.component else { return nil }
            if descriptor.field == "diet_vitamins" { return \Self.vitamins[component] }
            if descriptor.field == "diet_minerals" { return \Self.minerals[component] }
            return nil
        }
    }

    public init(
        id: UUID = UUID(),
        dayKey: DayKey,
        mealType: MealType,
        foodID: String? = nil,
        foodName: String,
        portionAmount: Double?,
        portionUnit: String,
        portionDescription: String? = nil,
        kcal: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        fiberG: Double? = nil,
        waterMl: Double? = nil,
        alaMg: Double? = nil,
        epaDhaMg: Double? = nil,
        vitamins: [String: Double] = [:],
        minerals: [String: Double] = [:],
        isEstimated: Bool = false,
        estimationNote: String? = nil,
        recordedAt: Date = Date()
    ) {
        self.id = id
        self.dayKey = dayKey
        self.mealType = mealType
        self.foodID = foodID
        self.foodName = foodName
        self.portionAmount = portionAmount
        self.portionUnit = portionUnit
        self.portionDescription = portionDescription ?? portionAmount.map { "\(Int($0.rounded()))\(portionUnit)" } ?? "份量待补"
        self.kcal = kcal
        self.carbsG = carbsG
        self.proteinG = proteinG
        self.fatG = fatG
        self.fiberG = fiberG
        self.waterMl = waterMl
        self.alaMg = alaMg
        self.epaDhaMg = epaDhaMg
        self.vitamins = vitamins
        self.minerals = minerals
        self.isEstimated = isEstimated
        self.estimationNote = estimationNote
        self.recordedAt = recordedAt
    }
}

public struct MealEnergySummary: Encodable, Sendable {
    public let knownKcalSubtotal: Double?
    public let estimatedLowerKcal: Double?
    public let estimatedUpperKcal: Double?
    public let missingEntryCount: Int

    public init(entries: [MealEntry]) {
        let foods = entries.filter { $0.mealType != .water || $0.kcal != nil }
        let known = foods.filter { $0.energyEstimate == nil }.compactMap(\.kcal)
        let ranges = foods.compactMap(\.energyEstimate)
        let base = known.reduce(0, +)
        knownKcalSubtotal = known.isEmpty ? nil : base
        estimatedLowerKcal = ranges.isEmpty ? nil : ranges.reduce(base) { $0 + $1.lowerKcal }
        estimatedUpperKcal = ranges.isEmpty ? nil : ranges.reduce(base) { $0 + $1.upperKcal }
        missingEntryCount = foods.filter { $0.kcal == nil && $0.energyEstimate == nil }.count
    }

    public var displayRange: String? {
        guard let lower = estimatedLowerKcal, let upper = estimatedUpperKcal else { return nil }
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        return "\(lower.formatted(format))–\(upper.formatted(format))"
    }
}

public struct DailyNutritionLog: Identifiable, Hashable, Codable, Sendable {
    public var id: DayKey { dayKey }
    public let dayKey: DayKey
    public var entries: [MealEntry]
    public var dietKcal: Double?
    public var dietCarbsG: Double?
    public var dietProteinG: Double?
    public var dietFatG: Double?
    public var dietFiberG: Double?
    public var dietWaterMl: Double?
    public var dietAlaMg: Double?
    public var dietEpaDhaMg: Double?
    public var dietVitamins: [String: Double]
    public var dietMinerals: [String: Double]
    public var dietDayComplete: Bool?
    public var dietPartialFields: [String]
    public var healthConfirmedFields: [String]
    public var sportHours: Double?
    public var sportKcal: Double?
    public var steps: Int?
    public var bmrKcalUsed: Double?
    public var weightKg: Double?
    public var waistCm: Double?
    public var calorieSurplusKcal: Double?
    public var reviewSummary: String?
    public var notes: [String]
    public var updatedAt: Date

    public init(
        dayKey: DayKey,
        entries: [MealEntry] = [],
        dietKcal: Double? = nil,
        dietCarbsG: Double? = nil,
        dietProteinG: Double? = nil,
        dietFatG: Double? = nil,
        dietFiberG: Double? = nil,
        dietWaterMl: Double? = nil,
        dietAlaMg: Double? = nil,
        dietEpaDhaMg: Double? = nil,
        dietVitamins: [String: Double] = [:],
        dietMinerals: [String: Double] = [:],
        dietDayComplete: Bool? = nil,
        dietPartialFields: [String] = [],
        healthConfirmedFields: [String] = [],
        sportHours: Double? = nil,
        sportKcal: Double? = nil,
        steps: Int? = nil,
        bmrKcalUsed: Double? = nil,
        weightKg: Double? = nil,
        waistCm: Double? = nil,
        calorieSurplusKcal: Double? = nil,
        reviewSummary: String? = nil,
        notes: [String] = [],
        updatedAt: Date = Date()
    ) {
        self.dayKey = dayKey
        self.entries = entries
        self.dietKcal = dietKcal
        self.dietCarbsG = dietCarbsG
        self.dietProteinG = dietProteinG
        self.dietFatG = dietFatG
        self.dietFiberG = dietFiberG
        self.dietWaterMl = dietWaterMl
        self.dietAlaMg = dietAlaMg
        self.dietEpaDhaMg = dietEpaDhaMg
        self.dietVitamins = dietVitamins
        self.dietMinerals = dietMinerals
        self.dietDayComplete = dietDayComplete
        self.dietPartialFields = dietPartialFields
        self.healthConfirmedFields = healthConfirmedFields
        self.sportHours = sportHours
        self.sportKcal = sportKcal
        self.steps = steps
        self.bmrKcalUsed = bmrKcalUsed
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.calorieSurplusKcal = calorieSurplusKcal
        self.reviewSummary = reviewSummary
        self.notes = notes
        self.updatedAt = updatedAt
    }

    public mutating func recalculateTotals() {
        guard !entries.isEmpty else {
            dietKcal = nil
            dietCarbsG = nil
            dietProteinG = nil
            dietFatG = nil
            dietFiberG = nil
            dietWaterMl = nil
            dietAlaMg = nil
            dietEpaDhaMg = nil
            dietVitamins = [:]
            dietMinerals = [:]
            recalculateSurplus()
            return
        }

        func sumOptional(_ keyPath: KeyPath<MealEntry, Double?>) -> Double? {
            let vals = entries.compactMap { $0[keyPath: keyPath] }
            guard !vals.isEmpty else { return nil }
            return (vals.reduce(0, +) * 100).rounded() / 100
        }

        dietKcal = sumOptional(\.kcal)
        dietCarbsG = sumOptional(\.carbsG)
        dietProteinG = sumOptional(\.proteinG)
        dietFatG = sumOptional(\.fatG)
        dietFiberG = sumOptional(\.fiberG)
        dietWaterMl = sumOptional(\.waterMl)
        dietAlaMg = sumOptional(\.alaMg)
        dietEpaDhaMg = sumOptional(\.epaDhaMg)

        var vitSums: [String: Double] = [:]
        var minSums: [String: Double] = [:]
        for entry in entries {
            for (k, v) in entry.vitamins {
                vitSums[k, default: 0] += v
            }
            for (k, v) in entry.minerals {
                minSums[k, default: 0] += v
            }
        }
        dietVitamins = vitSums.mapValues { ($0 * 100).rounded() / 100 }
        dietMinerals = minSums.mapValues { ($0 * 100).rounded() / 100 }
        recalculateSurplus()
    }

    /// Computes energy surplus ONLY when intake is closed (`dietDayComplete == true`) and both BMR & active expenditure exist.
    public mutating func recalculateSurplus() {
        guard dietDayComplete == true,
              dietPartialFields.isEmpty,
              let intake = dietKcal,
              let bmr = bmrKcalUsed,
              let active = sportKcal,
              intake.isFinite, bmr > 0, active >= 0
        else {
            calorieSurplusKcal = nil
            return
        }
        calorieSurplusKcal = (intake - (bmr + active)).rounded()
    }

    public func rawValue(forMetricID metricID: String) -> Double? {
        switch metricID {
        case "diet_kcal": dietKcal
        case "diet_carbs_g": dietCarbsG
        case "diet_protein_g": dietProteinG
        case "diet_fat_g": dietFatG
        case "diet_fiber_g": dietFiberG
        case "diet_water_ml": dietWaterMl
        case "diet_ala_mg": dietAlaMg
        case "diet_epa_dha_mg": dietEpaDhaMg
        case _ where metricID.hasPrefix("diet_vitamins::"):
            dietVitamins[String(metricID.dropFirst("diet_vitamins::".count))]
        case _ where metricID.hasPrefix("diet_minerals::"):
            dietMinerals[String(metricID.dropFirst("diet_minerals::".count))]
        default: nil
        }
    }
}

// MARK: - Weekly & Monthly Board Aggregation

public struct NutritionMetricPeriodAverage: Equatable, Hashable, Codable, Sendable {
    public let metricID: String
    public let metricName: String
    public let unit: String
    public let averageValue: Double?
    public let validCompletedDays: Int
    public let status: NutritionReadingStatus
    /// Period average/status including closed days whose nutrients contain AI estimates.
    /// Directional only; never overrides the confirmed `status`.
    public let estimatedAverageValue: Double?
    public let estimatedStatus: NutritionReadingStatus
    public let estimatedDays: Int

    public init(
        metricID: String,
        metricName: String,
        unit: String,
        averageValue: Double?,
        validCompletedDays: Int,
        status: NutritionReadingStatus,
        estimatedAverageValue: Double? = nil,
        estimatedStatus: NutritionReadingStatus = .unknown,
        estimatedDays: Int = 0
    ) {
        self.metricID = metricID
        self.metricName = metricName
        self.unit = unit
        self.averageValue = averageValue
        self.validCompletedDays = validCompletedDays
        self.status = status
        self.estimatedAverageValue = estimatedAverageValue
        self.estimatedStatus = estimatedStatus
        self.estimatedDays = estimatedDays
    }

    /// Confirmed status wins; otherwise fall back to the estimated directional status.
    public var displayStatus: NutritionReadingStatus {
        status != .unknown ? status : estimatedStatus
    }

    public var isEstimateOnly: Bool {
        status == .unknown && estimatedStatus != .unknown
    }
}

public struct NutritionPeriodSummary: Equatable, Sendable {
    public let startDayKey: DayKey
    public let endDayKey: DayKey
    public let validatedPlan: ValidatedTargetPlan
    public let dayLogsByKey: [DayKey: DailyNutritionLog]
    public let metricAverages: [NutritionMetricPeriodAverage]
    public let rollingDeficit7dKcal: Double?
    public let validSurplusDays: Int

    public init(
        startDayKey: DayKey,
        endDayKey: DayKey,
        validatedPlan: ValidatedTargetPlan,
        dayLogsByKey: [DayKey: DailyNutritionLog],
        metricAverages: [NutritionMetricPeriodAverage],
        rollingDeficit7dKcal: Double?,
        validSurplusDays: Int
    ) {
        self.startDayKey = startDayKey
        self.endDayKey = endDayKey
        self.validatedPlan = validatedPlan
        self.dayLogsByKey = dayLogsByKey
        self.metricAverages = metricAverages
        self.rollingDeficit7dKcal = rollingDeficit7dKcal
        self.validSurplusDays = validSurplusDays
    }
}

public enum NutritionBoardAggregator {
    public static func rollingDeficit(logs: [DailyNutritionLog], endingAt end: DayKey) -> Double? {
        let start = end.addingDays(-6)
        let byDay = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, latest in latest })
        let values = byDay.values.compactMap { log -> Double? in
            guard (start...end).contains(log.dayKey), log.dietDayComplete == true, log.dietPartialFields.isEmpty
            else { return nil }
            return log.calorieSurplusKcal
        }
        guard values.count >= 3 else { return nil }
        return -values.reduce(0, +) / Double(values.count)
    }

    public static func summarizePeriod(
        logs: [DailyNutritionLog],
        targetPlan: NutritionTargetPlan?,
        startDayKey: DayKey,
        endDayKey: DayKey,
        todayKey: DayKey,
        sortByStatus: Bool = true
    ) -> NutritionPeriodSummary {
        let validated = NutritionTargetEvaluator.validate(plan: targetPlan, on: todayKey)
        let byKey = Dictionary(logs.map { ($0.dayKey, $0) }, uniquingKeysWith: { _, latest in latest })

        var metricIDs = NutritionCatalog.macroDescriptors.map(\.id)
        for v in NutritionCatalog.vitaminOrder { metricIDs.append("diet_vitamins::\(v)") }
        for m in NutritionCatalog.mineralOrder { metricIDs.append("diet_minerals::\(m)") }

        let relevantLogs = byKey
            .filter { $0.key >= startDayKey && $0.key <= endDayKey && $0.key <= todayKey }
            .sorted { $0.key < $1.key }

        var averages: [NutritionMetricPeriodAverage] = []
        averages.reserveCapacity(metricIDs.count)

        for id in metricIDs {
            let descriptor = NutritionCatalog.descriptor(forID: id)!
            var sum = 0.0
            var count = 0
            var displayUnit = validated.validAdoptedItems[id]?.unit ?? descriptor.unit
            var metDays = 0
            var lowDays = 0
            var overDays = 0
            var estimatedSum = 0.0
            var estimatedCount = 0
            var estimatedDayCount = 0

            for (_, log) in relevantLogs {
                let eval = NutritionTargetEvaluator.evaluate(metricID: id, log: log, validatedPlan: validated)
                let estimatedEval = NutritionTargetEvaluator.evaluate(
                    metricID: id,
                    log: log,
                    validatedPlan: validated,
                    allowEstimates: true
                )
                displayUnit = eval.displayUnit
                if eval.isDayComplete, let v = eval.value {
                    sum += v
                    count += 1
                    switch eval.status {
                    case .met: metDays += 1
                    case .low: lowDays += 1
                    case .over: overDays += 1
                    case .unknown: break
                    }
                }
                if estimatedEval.status != .unknown, let v = estimatedEval.value {
                    estimatedSum += v
                    estimatedCount += 1
                    if estimatedEval.isEstimated { estimatedDayCount += 1 }
                }
            }

            let avg: Double? = count > 0 ? (sum / Double(count)) : nil
            let avgStatus: NutritionReadingStatus
            if let avg {
                var synthetic = DailyNutritionLog(dayKey: todayKey, dietDayComplete: true)
                synthetic.dietKcal = relevantLogs.compactMap { $0.value.dietDayComplete == true ? $0.value.dietKcal : nil }.first ?? 1800
                // Compare period average directly when unit is not %E, else build consistent synthetic log
                if id == "diet_kcal" {
                    synthetic.dietKcal = avg
                } else if displayUnit == "%E", let factor = descriptor.energyFactor {
                    synthetic.dietKcal = 1000.0
                    let rawFor1000 = (avg / 100.0) * 1000.0 / factor
                    switch id {
                    case "diet_carbs_g": synthetic.dietCarbsG = rawFor1000
                    case "diet_fat_g": synthetic.dietFatG = rawFor1000
                    case "diet_ala_mg": synthetic.dietAlaMg = rawFor1000
                    default: break
                    }
                } else {
                    switch id {
                    case "diet_protein_g": synthetic.dietProteinG = avg
                    case "diet_fiber_g": synthetic.dietFiberG = avg
                    case "diet_water_ml": synthetic.dietWaterMl = avg
                    case "diet_epa_dha_mg": synthetic.dietEpaDhaMg = avg
                    case _ where id.hasPrefix("diet_vitamins::"):
                        synthetic.dietVitamins[String(id.dropFirst("diet_vitamins::".count))] = avg
                    case _ where id.hasPrefix("diet_minerals::"):
                        synthetic.dietMinerals[String(id.dropFirst("diet_minerals::".count))] = avg
                    default: break
                    }
                }
                avgStatus = NutritionTargetEvaluator.evaluate(metricID: id, log: synthetic, validatedPlan: validated).status
            } else {
                avgStatus = .unknown
            }

            let estimatedAvg: Double? = estimatedCount > 0 ? estimatedSum / Double(estimatedCount) : nil
            let estimatedAvgStatus: NutritionReadingStatus
            if let estimatedAvg {
                var synthetic = DailyNutritionLog(dayKey: todayKey, dietDayComplete: true)
                synthetic.dietKcal = 1_000.0
                if id == "diet_kcal" {
                    synthetic.dietKcal = estimatedAvg
                } else if displayUnit == "%E", let factor = descriptor.energyFactor {
                    let rawFor1000 = (estimatedAvg / 100.0) * 1_000.0 / factor
                    switch id {
                    case "diet_carbs_g": synthetic.dietCarbsG = rawFor1000
                    case "diet_fat_g": synthetic.dietFatG = rawFor1000
                    case "diet_ala_mg": synthetic.dietAlaMg = rawFor1000
                    default: break
                    }
                } else {
                    switch id {
                    case "diet_protein_g": synthetic.dietProteinG = estimatedAvg
                    case "diet_fiber_g": synthetic.dietFiberG = estimatedAvg
                    case "diet_water_ml": synthetic.dietWaterMl = estimatedAvg
                    case "diet_epa_dha_mg": synthetic.dietEpaDhaMg = estimatedAvg
                    case _ where id.hasPrefix("diet_vitamins::"):
                        synthetic.dietVitamins[String(id.dropFirst("diet_vitamins::".count))] = estimatedAvg
                    case _ where id.hasPrefix("diet_minerals::"):
                        synthetic.dietMinerals[String(id.dropFirst("diet_minerals::".count))] = estimatedAvg
                    default: break
                    }
                }
                estimatedAvgStatus = NutritionTargetEvaluator.evaluate(
                    metricID: id, log: synthetic, validatedPlan: validated, allowEstimates: true
                ).status
            } else {
                estimatedAvgStatus = .unknown
            }

            averages.append(
                NutritionMetricPeriodAverage(
                    metricID: id,
                    metricName: descriptor.name,
                    unit: displayUnit,
                    averageValue: avg,
                    validCompletedDays: count,
                    status: avgStatus,
                    estimatedAverageValue: estimatedAvg,
                    estimatedStatus: estimatedAvgStatus,
                    estimatedDays: estimatedDayCount
                )
            )
            _ = (metDays, lowDays, overDays)
        }

        if sortByStatus {
            averages.sort { lhs, rhs in
                let rankL = statusSortRank(
                    lhs.displayStatus,
                    hasAvg: lhs.averageValue != nil || lhs.estimatedAverageValue != nil
                )
                let rankR = statusSortRank(
                    rhs.displayStatus,
                    hasAvg: rhs.averageValue != nil || rhs.estimatedAverageValue != nil
                )
                if rankL != rankR { return rankL < rankR }
                return lhs.metricID < rhs.metricID
            }
        }

        let validSurplusDays = relevantLogs.filter { _, log in
            log.dietDayComplete == true && log.dietPartialFields.isEmpty && log.calorieSurplusKcal != nil
        }.count
        let deficit7d = rollingDeficit(logs: relevantLogs.map(\.value), endingAt: min(endDayKey, todayKey))

        return NutritionPeriodSummary(
            startDayKey: startDayKey,
            endDayKey: endDayKey,
            validatedPlan: validated,
            dayLogsByKey: byKey,
            metricAverages: averages,
            rollingDeficit7dKcal: deficit7d,
            validSurplusDays: validSurplusDays
        )
    }

    private static func statusSortRank(_ status: NutritionReadingStatus, hasAvg: Bool) -> Int {
        guard hasAvg else { return 99 }
        switch status {
        case .met: return 0
        case .low: return 1
        case .over: return 2
        case .unknown: return 50
        }
    }
}

// MARK: - Obsidian-Compatible Markdown Exporter

public enum NutritionMarkdownExporter {
    public static func exportDailyMarkdown(log: DailyNutritionLog) -> String {
        var lines: [String] = ["---", "title: 日计划", "date: \"\(log.dayKey.isoString)\""]
        func optNum(_ k: String, _ v: Double?) {
            if let v { lines.append("\(k): \(formatCompact(v))") } else { lines.append("\(k):") }
        }
        optNum("sport_h", log.sportHours)
        if let steps = log.steps { lines.append("steps: \(steps)") } else { lines.append("steps:") }
        optNum("sport_kcal", log.sportKcal)
        optNum("diet_kcal", log.dietKcal)
        optNum("calorie_surplus_kcal", log.calorieSurplusKcal)
        optNum("diet_carbs_g", log.dietCarbsG)
        optNum("diet_protein_g", log.dietProteinG)
        optNum("diet_fat_g", log.dietFatG)
        optNum("diet_fiber_g", log.dietFiberG)
        optNum("diet_water_ml", log.dietWaterMl)
        optNum("diet_ala_mg", log.dietAlaMg)
        optNum("diet_epa_dha_mg", log.dietEpaDhaMg)

        if log.dietVitamins.isEmpty {
            lines.append("diet_vitamins: []")
        } else {
            lines.append("diet_vitamins:")
            for k in log.dietVitamins.keys.sorted() {
                let unit = NutritionCatalog.vitaminUnits[k] ?? "mg"
                lines.append("  - \(k) \(formatCompact(log.dietVitamins[k] ?? 0)) \(unit)")
            }
        }
        if log.dietMinerals.isEmpty {
            lines.append("diet_minerals: []")
        } else {
            lines.append("diet_minerals:")
            for k in log.dietMinerals.keys.sorted() {
                let unit = NutritionCatalog.mineralUnits[k] ?? "mg"
                lines.append("  - \(k) \(formatCompact(log.dietMinerals[k] ?? 0)) \(unit)")
            }
        }
        if let complete = log.dietDayComplete {
            lines.append("diet_day_complete: \(complete ? "true" : "false")")
        } else {
            lines.append("diet_day_complete:")
        }
        lines.append("diet_partial_fields: [\(log.dietPartialFields.joined(separator: ", "))]")
        lines.append("health_confirmed_fields: [\(log.healthConfirmedFields.joined(separator: ", "))]")
        lines.append("---")
        lines.append("")
        lines.append("## 饮食记录")
        lines.append("")
        lines.append("| 餐次 | 食物 | 份量 | 热量(kcal) | 碳水(g) | 蛋白(g) | 脂肪(g) | 纤维(g) |")
        lines.append("| --- | --- | --- | --- | --- | --- | --- | --- |")
        for entry in log.entries {
            lines.append("| \(entry.mealType.title) | \(entry.foodName) | \(entry.portionDescription) | \(entry.kcal.map(formatCompact) ?? "—") | \(entry.carbsG.map(formatCompact) ?? "—") | \(entry.proteinG.map(formatCompact) ?? "—") | \(entry.fatG.map(formatCompact) ?? "—") | \(entry.fiberG.map(formatCompact) ?? "—") |")
        }
        if let review = log.reviewSummary, !review.isEmpty {
            lines.append("")
            lines.append("## 今日回顾")
            lines.append("")
            lines.append(review)
        }
        if !log.notes.isEmpty {
            lines.append("")
            lines.append("## 其他备注")
            lines.append("")
            for note in log.notes {
                lines.append("- \(note)")
            }
        }
        return lines.joined(separator: "\n")
    }

    public static func exportTargetsMarkdown(plan: NutritionTargetPlan) -> String {
        var lines = [
            "---",
            "title: 营养目标",
            "nutrition_schema: \(plan.nutritionSchema)",
            "target_status: \(plan.targetStatus.rawValue)",
            "target_version: \"\(plan.targetVersion)\"",
            "effective_from: \(plan.effectiveFrom.map { "\"\($0.isoString)\"" } ?? "")",
            "---",
            "",
            "# 营养目标",
            "",
            "| 指标 | 单位 | 模式 | 下界 | 上界 | 采用 | 来源 |",
            "| --- | --- | --- | --- | --- | --- | --- |",
        ]
        for item in plan.items {
            lines.append("| \(item.id) | \(item.unit) | \(item.mode.rawValue) | \(item.lower.map(formatCompact) ?? "—") | \(item.upper.map(formatCompact) ?? "—") | \(item.adopted ? "是" : "否") | \(item.source) |")
        }
        return lines.joined(separator: "\n")
    }

    private static func formatCompact(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.2f", value).replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }
}

// MARK: - ActionProposal Payloads for Nutrition

public struct UpsertNutritionProfilePayload: Hashable, Codable, Sendable {
    public let profile: NutritionProfile
    public init(profile: NutritionProfile) { self.profile = profile }
}

public struct CommitNutritionTargetsPayload: Hashable, Codable, Sendable {
    public let plan: NutritionTargetPlan
    public init(plan: NutritionTargetPlan) { self.plan = plan }
}

public struct DeleteNutritionMealPayload: Hashable, Codable, Sendable {
    public let dayKey: DayKey
    public let entryID: UUID

    public init(dayKey: DayKey, entryID: UUID) {
        self.dayKey = dayKey
        self.entryID = entryID
    }
}

public struct LogNutritionMealsPayload: Hashable, Codable, Sendable {
    public let dayKey: DayKey
    public let entries: [MealEntry]

    public init(dayKey: DayKey, entries: [MealEntry]) {
        self.dayKey = dayKey
        self.entries = entries
    }
}

public struct LogNutritionMealPayload: Hashable, Codable, Sendable {
    public let dayKey: DayKey
    public let entry: MealEntry
    public let partialFields: [String]
    public let note: String?

    public init(dayKey: DayKey, entry: MealEntry, partialFields: [String] = [], note: String? = nil) {
        self.dayKey = dayKey
        self.entry = entry
        self.partialFields = partialFields
        self.note = note
    }
}

public struct CloseNutritionDayPayload: Hashable, Codable, Sendable {
    public let dayKey: DayKey
    public let markComplete: Bool
    public let sportHours: Double?
    public let sportKcal: Double?
    public let steps: Int?
    public let bmrKcalUsed: Double?
    public let reviewSummary: String?

    public init(
        dayKey: DayKey,
        markComplete: Bool = true,
        sportHours: Double? = nil,
        sportKcal: Double? = nil,
        steps: Int? = nil,
        bmrKcalUsed: Double? = nil,
        reviewSummary: String? = nil
    ) {
        self.dayKey = dayKey
        self.markComplete = markComplete
        self.sportHours = sportHours
        self.sportKcal = sportKcal
        self.steps = steps
        self.bmrKcalUsed = bmrKcalUsed
        self.reviewSummary = reviewSummary
    }
}
