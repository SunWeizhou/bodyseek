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

struct DeepSeekSearchHit: Codable, Equatable, Sendable {
    let rerankScore: Double?
    let title: String
    let url: String
    let snippet: String
    let summary: String?

    private enum CodingKeys: String, CodingKey {
        case rerankScore = "rerank_score"
        case title
        case url
        case snippet
        case summary
    }
}

enum ChineseFastFoodQueryExtractor {
    private struct KeywordRule {
        let group: String
        let needle: String
        let query: String
    }

    private static let brandRules: [KeywordRule] = [
        .init(group: "mcdonalds", needle: "麦辣鸡腿堡", query: "麦当劳 麦辣鸡腿汉堡 热量 营养成分表 蛋白质 碳水 脂肪"),
        .init(group: "mcdonalds", needle: "板烧鸡腿堡", query: "麦当劳 板烧鸡腿堡 热量 营养成分表 蛋白质 碳水 脂肪"),
        .init(group: "mcdonalds", needle: "巨无霸", query: "麦当劳 巨无霸 热量 营养成分表 蛋白质 碳水 脂肪"),
        .init(group: "mcdonalds", needle: "麦当劳", query: "麦当劳 中国 官方 营养成分表 热量 蛋白质"),
        .init(group: "mcdonalds", needle: "金拱门", query: "麦当劳 中国 官方 营养成分表 热量 蛋白质"),
        .init(group: "kfc", needle: "香辣鸡腿堡", query: "肯德基 香辣鸡腿堡 热量 营养成分表 蛋白质 碳水 脂肪"),
        .init(group: "kfc", needle: "老北京鸡肉卷", query: "肯德基 老北京鸡肉卷 热量 营养成分表 蛋白质 碳水 脂肪"),
        .init(group: "kfc", needle: "肯德基", query: "肯德基 中国 营养成分表 热量 蛋白质 脂肪"),
        .init(group: "kfc", needle: "kfc", query: "肯德基 KFC 中国 营养成分表 热量 蛋白质"),
        .init(group: "bk", needle: "汉堡王", query: "汉堡王 中国 营养成分表 热量 蛋白质"),
        .init(group: "tastien", needle: "塔斯汀", query: "塔斯汀 中国汉堡 热量 营养成分表"),
        .init(group: "wallace", needle: "华莱士", query: "华莱士 汉堡 热量 营养成分参考"),
        .init(group: "dicos", needle: "德克士", query: "德克士 营养成分表 热量"),
        .init(group: "pizzahut", needle: "必胜客", query: "必胜客 营养成分表 热量"),
        .init(group: "dominos", needle: "达美乐", query: "达美乐 披萨 热量 营养成分表"),
        .init(group: "saizeriya", needle: "萨莉亚", query: "萨莉亚 菜单 热量 营养成分"),
        .init(group: "luckin", needle: "生椰拿铁", query: "瑞幸 生椰拿铁 热量 营养成分表 脂肪 碳水"),
        .init(group: "luckin", needle: "瑞幸", query: "瑞幸咖啡 饮品 热量 营养成分表"),
        .init(group: "luckin", needle: "luckin", query: "瑞幸咖啡 饮品 热量 营养成分表"),
        .init(group: "chagee", needle: "伯牙绝弦", query: "霸王茶姬 伯牙绝弦 热量 营养成分表"),
        .init(group: "chagee", needle: "霸王茶姬", query: "霸王茶姬 热量 营养成分表 公开信息"),
        .init(group: "starbucks", needle: "星巴克", query: "星巴克 中国 饮品 热量 营养成分表"),
        .init(group: "heytea", needle: "喜茶", query: "喜茶 饮品 热量 营养成分表"),
        .init(group: "nayuki", needle: "奈雪", query: "奈雪的茶 热量 营养成分表"),
        .init(group: "mixue", needle: "蜜雪冰城", query: "蜜雪冰城 饮品 热量 糖分"),
        .init(group: "chabaidao", needle: "茶百道", query: "茶百道 奶茶 热量 营养成分"),
        .init(group: "guming", needle: "古茗", query: "古茗 奶茶 热量 营养成分"),
        .init(group: "cotti", needle: "库迪", query: "库迪咖啡 热量 营养成分"),
        .init(group: "laoxiangji", needle: "老乡鸡", query: "老乡鸡 菜品 热量 营养成分表"),
        .init(group: "micun", needle: "米村", query: "米村拌饭 热量 营养成分表"),
        .init(group: "csc", needle: "乡村基", query: "乡村基 菜品 热量 营养成分"),
        .init(group: "damixiansheng", needle: "大米先生", query: "大米先生 菜品 热量 营养成分"),
        .init(group: "kungfu", needle: "真功夫", query: "真功夫 营养成分表 热量"),
        .init(group: "yonghe", needle: "永和大王", query: "永和大王 菜单 热量 营养成分"),
        .init(group: "yoshinoya", needle: "吉野家", query: "吉野家 菜单 热量 营养成分"),
        .init(group: "hefu", needle: "和府捞面", query: "和府捞面 热量 营养成分"),
        .init(group: "yujian", needle: "遇见小面", query: "遇见小面 热量 营养成分"),
        .init(group: "haidilao", needle: "海底捞", query: "海底捞 菜品 热量 营养成分"),
        .init(group: "familymart", needle: "全家", query: "全家便利店 鲜食 饭团 营养成分表 热量"),
        .init(group: "lawson", needle: "罗森", query: "罗森便利店 鲜食 营养成分表 热量"),
        .init(group: "711", needle: "7-11", query: "7-11 便利店 鲜食 营养成分表 热量"),
        .init(group: "711", needle: "711", query: "711 便利店 鲜食 营养成分表 热量"),
        .init(group: "bianlifeng", needle: "便利蜂", query: "便利蜂 鲜食 营养成分表 热量"),
        .init(group: "sams", needle: "山姆", query: "山姆会员店 烘焙熟食 营养成分表 热量"),
        .init(group: "hema", needle: "盒马", query: "盒马 鲜食 营养成分表 热量"),
        .init(group: "shaxian", needle: "沙县", query: "沙县小吃 拌面 蒸饺 热量 营养成分"),
        .init(group: "lanzhou", needle: "兰州拉面", query: "兰州牛肉拉面 每份热量 蛋白质 碳水"),
        .init(group: "dimsum", needle: "广式", query: "广式早茶 虾饺 烧卖 肠粉 热量 营养成分"),
        .init(group: "dimsum", needle: "虾饺", query: "广式水晶虾饺 每只热量 蛋白质 营养成分"),
    ]

    static func extractQueries(from input: String) -> [String] {
        let lower = input.lowercased()
        guard !lower.isEmpty else { return [] }
        var queries: [String] = []
        var seenGroups = Set<String>()
        var seenQueries = Set<String>()
        for rule in brandRules {
            if lower.contains(rule.needle.lowercased()),
               seenGroups.insert(rule.group).inserted,
               seenQueries.insert(rule.query).inserted {
                let capped = String(rule.query.prefix(120))
                queries.append(capped)
                if queries.count >= 2 {
                    break
                }
            }
        }
        return queries
    }

    static func buildSearchReferenceBlock(from hits: [DeepSeekSearchHit]) -> String? {
        let ranked = hits
            .filter { ($0.rerankScore ?? 1.5) >= 1.2 || !$0.snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .prefix(4)
        guard !ranked.isEmpty else { return nil }
        var lines = ["【联网营养参考资料（来自实时网页检索，请结合份量核对，不得编造未出现的数值）】"]
        for (idx, hit) in ranked.enumerated() {
            let body = (hit.summary?.isEmpty == false ? hit.summary : nil) ?? hit.snippet
            let cleanTitle = hit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanBody = String(body.trimmingCharacters(in: .whitespacesAndNewlines).prefix(420))
            lines.append("[\(idx + 1)] \(cleanTitle)：\(cleanBody)")
        }
        return String(lines.joined(separator: "\n").prefix(2_400))
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

    /// 首次回复被截断或格式不完整时的紧凑重试：只保留条目、餐次、份量与热量区间，
    /// 不再要求微量营养素，显著缩短第二次生成时间，避免一次失败变成两次长等待。
    static let compactRetryInstructions = """
        只输出紧凑 JSON，根字段 items，最多 12 项：
        {"items":[{"name":"水煮蛋","meal":"breakfast","reportedPortion":"2 个","amount":100,"unit":"g","isEstimatedPortion":false,"energyEstimate":{"lowerKcal":60,"upperKcal":90,"assumptions":"按两个蛋估算"}}]}。
        只填 name、meal、reportedPortion、amount、unit、isEstimatedPortion、energyEstimate。不要输出 nutrients、macroEstimate、catalogSearchName。
        无法确定的字段用 null。meal 只能是 breakfast、lunch、dinner、snack。先完整闭合 JSON，不得截断。
        """

    static let instructions = """
        将用户的一天或单餐自由描述（含照片）拆成结构化饮食条目，只输出 JSON：
        {"items":[{"name":"水煮蛋","meal":"breakfast","reportedPortion":"2 个","amount":100,"unit":"g","isEstimatedPortion":true}]}。
        最多 32 项。meal 只能是 breakfast、lunch、dinner、snack。按用户时间线索归属：
        - 「早晨/早上/早饭/早茶/早餐」-> breakfast；
        - 「中午/午饭/下午主餐」-> lunch；
        - 「晚上/晚饭/晚餐」-> dinner；
        - 「下午茶/咖啡/奶茶/夜宵/加餐」或独立饮品 -> snack（随正餐饮用并同述的饮品可归该正餐）；若只说吃了某个食物未提时段且附了照片，按合理常见餐次归类。不要把全天摄入都塞进同一餐。
        name 保留原食物、连锁品牌、杯型/甜度与烹饪方式（如「麦当劳麦辣鸡腿堡」「瑞幸生椰拿铁（不另外加糖）」「广式水晶虾饺」）。无品牌的常见食物用简洁通用名称（如「水煮蛋」「白米饭」）。原文中的个、只、屉、笼、杯、包、份写到 reportedPortion。明确克数/毫升数时换算为 g 或 mL，isEstimatedPortion=false。
        确有标准食材对照时填写简短 catalogSearchName；常见中式连锁快餐与早茶点心也可匹配通用简称，实在无固定标准的复合菜留 null。
        中国常见连锁快餐与模糊中式表述（高频场景）：
        - 若输入附带【联网营养参考资料】，对于麦当劳/肯德基/汉堡王/瑞幸/星巴克/霸王茶姬/喜茶/老乡鸡/米村拌饭/便利店鲜食等有明确品牌款式的食物，优先参考检索结果里的公开营养数据并据份量换算，在 assumptions 写明「参考联网营养资料」。
        - 若用户描述较模糊（例如「早上吃了几个广式茶点的小虾饺」「中午随便吃了碗牛肉面」「喝了杯少甜奶茶」），务必按中国常见一人份/常规规格主动给出合理估计份量与重量（如「几个虾饺」≈ 3–4 只 / 90–110g；isEstimatedPortion=true），不要因为没给克数就放弃营养估算。
        为每项食物和饮品尽量同时给出本次摄入下的：
        1. 热量区间 "energyEstimate":{"lowerKcal":下限,"upperKcal":上限,"assumptions":"简述份量与估算依据"}（有明确参考值可给窄区间 ±5%~10%，复合中餐给合理情景宽区间）；
        2. 三大营养素 "macroEstimate":{"proteinG":克数,"carbsG":克数,"fatG":克数}；
        3. 关键膳食纤维、维生素与矿物质 "nutrients":{"diet_fiber_g":[数值,"g"], ...}。请结合主要食材（肉禽蛋奶/水产/果蔬/谷豆/油盐/茶饮）积极估算有合理成分依据的指标：例如虾/肉/面点/蔬菜对应的钠、钾、钙、镁、磷、铁、锌、硒、B族、维A/C/E/K/D 与膳食纤维；仅白水填 diet_water_ml。无法合理推断的痕量营养素省略即可，禁止编造为零。尽量用 1–2 位有效数字。
        金额线索（如「人均120元」）仅辅助判断火锅/桌餐规模写进 reportedPortion，金额不得直接当作重量或热量。不输出咖啡因。
        nutrients 只允许使用以下键及单位（ALA 为 mg，A 为 RAE，叶酸为 DFE，烟酸为 NE）：
        \(nutrientUnits)
        """
}
