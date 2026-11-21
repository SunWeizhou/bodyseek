import BodySeekCore
import Foundation

public struct MealMacroEstimate: Codable, Hashable, Sendable {
    public let proteinG: Double?
    public let carbsG: Double?
    public let fatG: Double?
}

public struct MealDraftCandidate: Codable, Hashable, Sendable {
    public let name: String
    public let amount: Double?
    public let unit: String?

    public let meal: MealType?
    public let reportedPortion: String?
    public let isEstimatedPortion: Bool?
    public let catalogSearchName: String?
    public let energyEstimate: MealEnergyEstimate?
    public let macroEstimate: MealMacroEstimate?
    public let additionalEstimates: [String: Double]?

    public init(name: String, amount: Double?, unit: String?, meal: MealType? = nil,
                reportedPortion: String? = nil, isEstimatedPortion: Bool? = nil,
                catalogSearchName: String? = nil, energyEstimate: MealEnergyEstimate? = nil,
                macroEstimate: MealMacroEstimate? = nil, additionalEstimates: [String: Double]? = nil) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.meal = meal
        self.reportedPortion = reportedPortion
        self.isEstimatedPortion = isEstimatedPortion
        self.catalogSearchName = catalogSearchName
        self.energyEstimate = energyEstimate
        self.macroEstimate = macroEstimate
        self.additionalEstimates = additionalEstimates
    }
}

public enum MealDraftAnalysisError: LocalizedError, Sendable {
    case unconfigured, noFoods, invalidReply, incompatibleModel, imageTooLarge, serviceUnavailable

    public var errorDescription: String? {
        switch self {
        case .unconfigured: "请先连接支持 HTTPS 的 AI 模型，也可以手动记录。"
        case .noFoods: "模型没有返回食物条目。可以重试，或从食物库选择。"
        case .invalidReply: "AI 回复格式不完整，暂时无法生成草稿。请重试，原文已保留。"
        case .incompatibleModel: "模型未能分析照片。可以改用支持图片的模型，或写一句话记录。"
        case .imageTooLarge: "照片无法处理，请重新选择或改用文字。"
        case .serviceUnavailable: "暂时连不上 AI 服务，可以重试或手动记录。"
        }
    }
}

struct MealDraftAnalysis {
    static func decode(_ response: String) throws -> [MealDraftCandidate] {
        guard response.utf8.count <= 65_536,
              let start = response.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = response.lastIndex(where: { $0 == "}" || $0 == "]" }), start < end
        else { throw MealDraftAnalysisError.invalidReply }

        let root: JSONValue
        do {
            root = try JSONValue.parseData(Data(response[start...end].utf8))
        } catch {
            throw MealDraftAnalysisError.invalidReply
        }
        let items: [JSONValue]
        switch root {
        case let .object(response):
            guard case let .array(values) = response["items"] else { throw MealDraftAnalysisError.invalidReply }
            items = values
        case let .array(values):
            items = values
        default:
            throw MealDraftAnalysisError.invalidReply
        }

        guard !items.isEmpty else { throw MealDraftAnalysisError.noFoods }
        guard items.count <= 32 else { throw MealDraftAnalysisError.invalidReply }
        let candidates = items.compactMap(candidate)
        guard candidates.count == items.count else { throw MealDraftAnalysisError.invalidReply }
        return candidates
    }

    private static func candidate(_ value: JSONValue) -> MealDraftCandidate? {
        guard case let .object(item) = value,
              let name = string(item["name"]), !name.isEmpty, name.count <= 80 else { return nil }
        let portionUnit = string(item["unit"])?.lowercased()
        let unit: String?
        switch portionUnit {
        case "g", "克": unit = "g"
        case "ml", "毫升", "l", "升": unit = "ml"
        default: unit = nil
        }
        let amount = number(item["amount"]).flatMap { raw -> Double? in
            let scaled = portionUnit == "l" || portionUnit == "升" ? raw * 1000 : raw
            return unit != nil && scaled.isFinite && scaled > 0 && scaled <= 10_000 ? scaled : nil
        }

        let mealName = string(item["meal"])?.lowercased()
        let meal: MealType?
        switch mealName {
        case "早餐", "早饭": meal = .breakfast
        case "午餐", "午饭": meal = .lunch
        case "晚餐", "晚饭": meal = .dinner
        case "加餐", "饮品", "饮水", "water": meal = .snack
        default: meal = mealName.flatMap(MealType.init(rawValue:))
        }
        let estimated: Bool? = if case let .bool(value) = item["isEstimatedPortion"] { value } else { nil }
        return MealDraftCandidate(
            name: name, amount: amount, unit: unit, meal: meal,
            reportedPortion: string(item["reportedPortion"]).map { String($0.prefix(120)) },
            isEstimatedPortion: estimated,
            catalogSearchName: string(item["catalogSearchName"]).flatMap { !$0.isEmpty && $0.count <= 40 ? $0 : nil },
            energyEstimate: validatedEstimate(item["energyEstimate"]),
            macroEstimate: validatedMacros(item["macroEstimate"], grams: unit == "g" ? amount : nil),
            additionalEstimates: validatedAdditionalEstimates(item["nutrients"], amount: amount, unit: unit, foodName: name)
        )
    }

    private static func string(_ value: JSONValue?) -> String? {
        guard case let .string(text) = value else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func number(_ value: JSONValue?) -> Double? {
        switch value {
        case let .integer(number): Double(number)
        case let .number(number): number
        default: string(value).flatMap(Double.init)
        }
    }

    private static func validatedAdditionalEstimates(
        _ value: JSONValue?, amount: Double?, unit: String?, foodName: String
    ) -> [String: Double]? {
        guard case let .object(fields) = value else { return nil }
        var result: [String: Double] = [:]
        for id in MealEntry.additionalNutrientIDs {
            guard let descriptor = NutritionCatalog.allKnownDescriptors[id],
                  case let .array(pair) = fields[id], pair.count == 2,
                  let raw = number(pair[0]), raw.isFinite, raw > 0,
                  let suppliedUnit = string(pair[1]) else { continue }
            let expected = descriptor.rawUnit ?? descriptor.unit
            let normalized: Double?
            if expected == "mg" || expected == "μg" {
                normalized = NutritionCatalog.normalizeMicroValue(raw, fromUnit: suppliedUnit, toUnit: expected)
            } else {
                normalized = suppliedUnit.lowercased() == expected.lowercased() ? raw : nil
            }
            guard let normalized, normalized.isFinite, normalized > 0 else { continue }
            if expected == "mL" {
                let plainWater = ["水", "白水", "白开水", "温开水", "温水", "矿泉水", "纯净水", "饮用水", "自来水", "water", "plain water"]
                guard plainWater.contains(foodName.lowercased()), unit == "ml", let amount, normalized <= amount
                else { continue }
            } else {
                let grams = normalized / (expected == "μg" ? 1_000_000 : expected == "mg" ? 1_000 : 1)
                guard grams <= (unit == "g" ? amount ?? 2_500 : 2_500) else { continue }
            }
            result[id] = normalized
        }
        return result.isEmpty ? nil : result
    }

    private static func validatedMacros(_ value: JSONValue?, grams: Double?) -> MealMacroEstimate? {
        guard case let .object(fields) = value else { return nil }
        func gramsValue(_ key: String) -> Double? {
            guard let value = number(fields[key]), value.isFinite, (0...2_500).contains(value) else { return nil }
            return value
        }
        let estimate = MealMacroEstimate(proteinG: gramsValue("proteinG"), carbsG: gramsValue("carbsG"), fatG: gramsValue("fatG"))
        let values = [estimate.proteinG, estimate.carbsG, estimate.fatG].compactMap { $0 }
        guard !values.isEmpty, values.reduce(0, +) <= (grams.map { $0 * 1.05 } ?? 2_500) else { return nil }
        return estimate
    }

    private static func validatedEstimate(_ value: JSONValue?) -> MealEnergyEstimate? {
        guard case let .object(estimate) = value,
              let lower = number(estimate["lowerKcal"]), let upper = number(estimate["upperKcal"]),
              lower.isFinite, upper.isFinite, lower >= 0, upper > lower, upper <= 10_000,
              let assumptions = string(estimate["assumptions"]), !assumptions.isEmpty else { return nil }
        return MealEnergyEstimate(lowerKcal: lower, upperKcal: upper, assumptions: String(assumptions.prefix(240)))
    }

    private static let nutrientUnits = MealEntry.additionalNutrientIDs.compactMap { id -> String? in
        guard let descriptor = NutritionCatalog.allKnownDescriptors[id] else { return nil }
        return "\(id)=\(descriptor.rawUnit ?? descriptor.unit)"
    }.joined(separator: "，")

    static let instructions = """
        将用户的一天饮食拆成条目，只输出 JSON：
        {"items":[{"name":"水煮蛋","meal":"breakfast","reportedPortion":"2 个","amount":100,"unit":"g","isEstimatedPortion":true}]}。
        最多 32 项。meal 只能是 breakfast、lunch、dinner、snack。按用户叙述归属早餐、午餐、晚餐或加餐，保留饮品，未明确归属的饮品归加餐。下午的主餐可归午餐。
        按餐次归类，文字里的先后顺序不决定餐次。用同一餐次下的独立条目记录不同食物和饮品；与主餐一起喝的饮品归该餐，单独喝的咖啡归加餐。不要把全天摄入都归为同一餐。
        name 保留原食物、品牌、烹饪方式和关键配方信息。无品牌的常见食物用简洁的通用名称，例如「水煮蛋」「燕麦」，不要把份量或餐次塞进 name。原文中的个、勺、包、杯、份写到 reportedPortion。明确克数或毫升数时，换算成 g 或 mL，isEstimatedPortion 为 false。
        确有同类型食物时，可以加可选字段 catalogSearchName，使用简短的通用品名供用户在食物库核对，保持食材、干湿状态与烹饪方式一致。配方不明的复合菜和饮品留 null。
        没有克数或毫升数时，优先按食物、数量和常见份量估算本次摄入的可食重量或体积，isEstimatedPortion 为 true。完全没有合理份量依据时才留空，并保留原文份量。把「人均120元」之类的消费线索写入 reportedPortion，金额不得当作质量或热量。
        尽量为每项食物和饮品给出本次总热量粗略区间，供没有可靠食物库匹配或份量资料时使用。按已知或估算的份量计算，而非每 100g：
        "energyEstimate":{"lowerKcal":下限,"upperKcal":上限,"assumptions":"说明假设和影响区间的主要因素"}。
        火锅按一人实际摄入，用较轻到较丰盛的菜品、蘸料或喝汤情景估算。价格仅辅助选择情景，不用价格乘系数，也不虚构点单明细。饮品按已知体积乘合理的每100mL热量范围；如用户说 1 L，使用 1000 mL，少甜仍可能含糖和果汁本身的热量。与火锅同餐的果汁请单独计算，避免重复。对价格、配方、糖量不确定的情景给较宽范围。无合理情景则留空。
        同一份量下的三大营养素可给粗估中间值，格式为 "macroEstimate":{"proteinG":克数,"carbsG":克数,"fatG":克数}。与热量区间使用同一配方和份量假设；单项缺乏依据时留 null，不把未知填成 0。不输出咖啡因，不编造品牌官方数据或来源。
        对有常见成分依据的食物，尽可能补充膳食纤维、ALA、EPA＋DHA、维生素和矿物质。把本次摄入的粗估写入可选 nutrients 对象，值使用 [数值,"单位"]，例如 "nutrients":{"diet_fiber_g":[3,"g"],"diet_minerals::钙":[60,"mg"]}。饮水字段仅用于明确喝下的白水，不把食物水分、汤和混合饮品填成饮水。
        按食材、已知或典型配方及本份重量估算，一个食品只输出有合理依据的指标。复合外食可根据明确食材估算常见成分；无法判断强化配方、烹调盐或痕量矿物质时省略对应指标。不得为凑齐指标而补值，也不得把缺失写成零。尽量用一到两位有效数字。
        只用以下指标及对应单位。ALA 是毫克，A 需用 RAE，叶酸需用 DFE，烟酸需用 NE。
        \(nutrientUnits)
        """
}
