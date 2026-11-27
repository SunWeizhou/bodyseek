import Foundation

public enum WorkoutParserSource: String, Hashable, Codable, Sendable {
    case foundationModels
    case chineseLexiconFallback

    public var badgeTitle: String {
        switch self {
        case .foundationModels: "Apple Intelligence 解析"
        case .chineseLexiconFallback: "中文词典解析"
        }
    }
}

public struct WorkoutBodySignal: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let region: String
    public let symptom: String
    public var suggestedConstraint: String
    public var defaultExpiryDays: Int
    public var includeAsMemory: Bool

    public init(
        id: UUID = UUID(),
        region: String,
        symptom: String,
        suggestedConstraint: String,
        defaultExpiryDays: Int = 14,
        includeAsMemory: Bool = true
    ) {
        self.id = id
        self.region = region
        self.symptom = symptom
        self.suggestedConstraint = suggestedConstraint
        self.defaultExpiryDays = defaultExpiryDays
        self.includeAsMemory = includeAsMemory
    }
}

public struct WorkoutAnnotationProposal: Hashable, Codable, Sendable {
    public let rawText: String
    public var primaryMuscles: [BodyRegionMuscle]
    public var secondaryMuscles: [BodyRegionMuscle]
    public var rpe: Int?
    public var exercises: [String]
    public var bodySignals: [WorkoutBodySignal]
    public var parserSource: WorkoutParserSource
    public var degradationReason: String?
    public let parserVersion: AlgorithmVersion

    public init(
        rawText: String,
        primaryMuscles: [BodyRegionMuscle],
        secondaryMuscles: [BodyRegionMuscle] = [],
        rpe: Int? = nil,
        exercises: [String] = [],
        bodySignals: [WorkoutBodySignal] = [],
        parserSource: WorkoutParserSource = .chineseLexiconFallback,
        degradationReason: String? = nil,
        parserVersion: AlgorithmVersion = .workoutParserV1
    ) {
        self.rawText = rawText
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.rpe = rpe
        self.exercises = exercises
        self.bodySignals = bodySignals
        self.parserSource = parserSource
        self.degradationReason = degradationReason
        self.parserVersion = parserVersion
    }
}

public enum WorkoutLoadBuilder {
    public static func buildMuscleLoads(
        workoutUUID: String,
        durationMinutes: Int,
        primaryMuscles: [BodyRegionMuscle],
        secondaryMuscles: [BodyRegionMuscle],
        rpe: Int
    ) -> [WorkoutMuscleLoadRecord] {
        let clampedRPE = Double(min(10, max(1, rpe)))
        let durScale = min(1.30, max(0.55, Double(max(15, durationMinutes)) / 50.0))
        let rpeScale = 0.55 + (clampedRPE / 10.0) * 0.60
        let primaryLoad = min(1.45, max(0.35, 0.85 * durScale * rpeScale))
        let secondaryLoad = min(0.90, max(0.18, primaryLoad * 0.48))

        var out: [WorkoutMuscleLoadRecord] = []
        var seen = Set<BodyRegionMuscle>()

        for muscle in primaryMuscles where seen.insert(muscle).inserted {
            out.append(
                WorkoutMuscleLoadRecord(
                    workoutUUID: workoutUUID,
                    muscle: muscle,
                    role: .primary,
                    load: (primaryLoad * 100.0).rounded() / 100.0,
                    algorithmVersion: .recoveryHeuristicV1
                )
            )
        }
        for muscle in secondaryMuscles where seen.insert(muscle).inserted {
            out.append(
                WorkoutMuscleLoadRecord(
                    workoutUUID: workoutUUID,
                    muscle: muscle,
                    role: .secondary,
                    load: (secondaryLoad * 100.0).rounded() / 100.0,
                    algorithmVersion: .recoveryHeuristicV1
                )
            )
        }
        return out
    }
}

/// Deterministic Chinese + mixed fitness sentence parser used both directly and as offline fallback.
public enum ChineseWorkoutLexiconParser {
    private struct LexiconRule {
        let keywords: [String]
        let canonicalExercise: String?
        let primary: [BodyRegionMuscle]
        let secondary: [BodyRegionMuscle]
    }

    private static let rules: [LexiconRule] = [
        // Chest & Push
        LexiconRule(keywords: ["上斜杠铃卧推", "上斜哑铃卧推", "上斜卧推", "上斜推胸"], canonicalExercise: "上斜卧推", primary: [.chest, .deltoids], secondary: [.triceps]),
        LexiconRule(keywords: ["哑铃卧推"], canonicalExercise: "哑铃卧推", primary: [.chest], secondary: [.triceps, .deltoids]),
        LexiconRule(keywords: ["杠铃卧推", "平板卧推"], canonicalExercise: "杠铃卧推", primary: [.chest], secondary: [.triceps, .deltoids]),
        LexiconRule(keywords: ["卧推", "坐姿推胸", "器械推胸", "推胸", "bench press", "bench"], canonicalExercise: "卧推", primary: [.chest], secondary: [.triceps, .deltoids]),
        LexiconRule(keywords: ["蝴蝶机", "夹胸", "飞鸟", "绳索夹胸", "pec deck", "fly"], canonicalExercise: "夹胸/飞鸟", primary: [.chest], secondary: [.deltoids]),
        LexiconRule(keywords: ["双杠臂屈伸", "臂屈伸", "dips"], canonicalExercise: "双杠臂屈伸", primary: [.chest, .triceps], secondary: [.deltoids]),
        LexiconRule(keywords: ["俯卧撑", "push-up", "pushup"], canonicalExercise: "俯卧撑", primary: [.chest], secondary: [.triceps, .deltoids, .abs]),
        LexiconRule(keywords: ["推力日", "推力分化", "练推", "推日", "push day"], canonicalExercise: nil, primary: [.chest, .deltoids, .triceps], secondary: []),

        // Back & Pull
        LexiconRule(keywords: ["高位下拉", "下拉", "lat pulldown"], canonicalExercise: "高位下拉", primary: [.upperBack], secondary: [.biceps, .forearm]),
        LexiconRule(keywords: ["引体向上", "引体", "pull-up", "pullup", "chin-up"], canonicalExercise: "引体向上", primary: [.upperBack], secondary: [.biceps, .forearm]),
        LexiconRule(keywords: ["俯身杠铃划船", "杠铃划船"], canonicalExercise: "杠铃划船", primary: [.upperBack], secondary: [.biceps, .lowerBack, .forearm]),
        LexiconRule(keywords: ["坐姿划船", "单臂哑铃划船", "哑铃划船", "t杆划船", "划船", "row"], canonicalExercise: "划船", primary: [.upperBack], secondary: [.biceps, .forearm]),
        LexiconRule(keywords: ["面拉", "face pull"], canonicalExercise: "面拉", primary: [.deltoids, .upperBack], secondary: [.trapezius]),
        LexiconRule(keywords: ["直臂下压", "直臂下拉"], canonicalExercise: "直臂下压", primary: [.upperBack], secondary: [.triceps]),
        LexiconRule(keywords: ["耸肩", "shrug"], canonicalExercise: "耸肩", primary: [.trapezius], secondary: [.forearm]),
        LexiconRule(keywords: ["山羊挺身", "背屈伸"], canonicalExercise: "山羊挺身", primary: [.lowerBack], secondary: [.gluteal, .hamstring]),
        LexiconRule(keywords: ["拉力日", "拉力分化", "练拉", "拉日", "pull day"], canonicalExercise: nil, primary: [.upperBack, .biceps], secondary: [.forearm]),

        // Shoulders
        LexiconRule(keywords: ["哑铃推举", "坐姿推举"], canonicalExercise: "哑铃推举", primary: [.deltoids], secondary: [.triceps, .trapezius]),
        LexiconRule(keywords: ["杠铃推举", "站姿推举", "过头推举", "肩推", "推肩", "overhead press", "ohp"], canonicalExercise: "过头推举", primary: [.deltoids], secondary: [.triceps, .abs]),
        LexiconRule(keywords: ["侧平举", "绳索侧平举", "lateral raise"], canonicalExercise: "侧平举", primary: [.deltoids], secondary: []),
        LexiconRule(keywords: ["前平举"], canonicalExercise: "前平举", primary: [.deltoids], secondary: []),
        LexiconRule(keywords: ["俯身飞鸟", "反向飞鸟", "蝴蝶机反向", "后束"], canonicalExercise: "后束飞鸟", primary: [.deltoids], secondary: [.upperBack]),

        // Arms
        LexiconRule(keywords: ["锤式弯举", "杠铃弯举", "哑铃弯举", "牧师凳弯举", "弯举", "bicep curl", "curl"], canonicalExercise: "弯举", primary: [.biceps], secondary: [.forearm]),
        LexiconRule(keywords: ["绳索下压", "三头下压", "碎颅者", "仰卧臂屈伸", "颈后臂屈伸", "triceps"], canonicalExercise: "三头臂屈伸", primary: [.triceps], secondary: []),
        LexiconRule(keywords: ["农夫行走", "握力", "腕弯举"], canonicalExercise: "农夫行走/前臂", primary: [.forearm], secondary: [.trapezius]),

        // Legs & Posterior Chain
        LexiconRule(keywords: ["保加利亚分腿蹲", "保加利亚蹲"], canonicalExercise: "保加利亚分腿蹲", primary: [.quadriceps, .gluteal], secondary: [.hamstring]),
        LexiconRule(keywords: ["前蹲", "高脚杯深蹲", "哈克深蹲", "杠铃深蹲", "深蹲", "squat"], canonicalExercise: "深蹲", primary: [.quadriceps, .gluteal], secondary: [.hamstring, .lowerBack, .abs]),
        LexiconRule(keywords: ["腿举", "倒蹬", "leg press"], canonicalExercise: "腿举", primary: [.quadriceps, .gluteal], secondary: [.hamstring]),
        LexiconRule(keywords: ["腿屈伸", "坐姿踢腿", "leg extension"], canonicalExercise: "坐姿腿屈伸", primary: [.quadriceps], secondary: []),
        LexiconRule(keywords: ["箭步蹲", "弓步蹲", "lunge"], canonicalExercise: "箭步蹲", primary: [.quadriceps, .gluteal], secondary: [.hamstring, .calves]),
        LexiconRule(keywords: ["罗马尼亚硬拉", "直腿硬拉", "rdl"], canonicalExercise: "罗马尼亚硬拉", primary: [.hamstring, .gluteal], secondary: [.lowerBack, .forearm]),
        LexiconRule(keywords: ["相扑硬拉", "传统硬拉", "杠铃硬拉", "硬拉", "deadlift"], canonicalExercise: "硬拉", primary: [.hamstring, .lowerBack, .gluteal], secondary: [.upperBack, .forearm, .quadriceps]),
        LexiconRule(keywords: ["腿弯举", "俯卧腿弯举", "坐姿腿弯举", "leg curl"], canonicalExercise: "腿弯举", primary: [.hamstring], secondary: [.calves]),
        LexiconRule(keywords: ["臀推", "hip thrust"], canonicalExercise: "臀推", primary: [.gluteal], secondary: [.hamstring]),
        LexiconRule(keywords: ["提踵", "calf raise"], canonicalExercise: "提踵", primary: [.calves], secondary: []),
        LexiconRule(keywords: ["腿日", "练腿", "下肢训练", "下肢日", "leg day"], canonicalExercise: nil, primary: [.quadriceps, .hamstring, .gluteal], secondary: [.calves]),
        LexiconRule(keywords: ["上下肢", "全身力量", "全身分化"], canonicalExercise: nil, primary: [.chest, .upperBack, .quadriceps], secondary: [.deltoids, .gluteal]),

        // Core
        LexiconRule(keywords: ["悬垂举腿", "举腿", "leg raise"], canonicalExercise: "悬垂举腿", primary: [.abs], secondary: [.forearm]),
        LexiconRule(keywords: ["卷腹", "腹肌轮", "健腹轮", "crunch"], canonicalExercise: "卷腹/腹肌轮", primary: [.abs], secondary: []),
        LexiconRule(keywords: ["平板支撑", "plank"], canonicalExercise: "平板支撑", primary: [.abs], secondary: [.obliques, .lowerBack]),
        LexiconRule(keywords: ["俄式转体", "侧桥", "侧平板", "russian twist"], canonicalExercise: "俄式转体/核心", primary: [.obliques, .abs], secondary: []),

        // Sports mentioned in notes
        LexiconRule(keywords: ["羽毛球", "打球", "单打", "双打"], canonicalExercise: "羽毛球", primary: [.quadriceps, .calves, .deltoids, .forearm], secondary: [.abs, .gluteal]),
        LexiconRule(keywords: ["跑步", "间歇跑", "tempo", "配速跑", "慢跑"], canonicalExercise: "跑步", primary: [.quadriceps, .calves, .hamstring], secondary: [.gluteal]),
    ]

    private static let explicitMuscleAliases: [(keywords: [String], muscle: BodyRegionMuscle)] = [
        (["胸肌", "练胸", "胸部", "上胸", "中胸", "下胸", "chest"], .chest),
        (["背阔肌", "背阔", "练背", "背部", "上背", "背", "back"], .upperBack),
        (["下背", "竖脊肌", "腰部", "腰背"], .lowerBack),
        (["肩袖", "三角肌", "肩前束", "肩中束", "肩后束", "练肩", "肩部", "肩膀", "肩", "shoulder"], .deltoids),
        (["二头肌", "肱二头", "二头", "biceps"], .biceps),
        (["三头肌", "肱三头", "三头", "triceps"], .triceps),
        (["小臂", "前臂", "forearm"], .forearm),
        (["腹直肌", "腹肌", "练腹", "核心", "腹", "abs", "core"], .abs),
        (["腹斜肌", "人鱼线", "obliques"], .obliques),
        (["股四头肌", "股四", "大腿前侧", "quads"], .quadriceps),
        (["腘绳肌", "大腿后侧", "后链", "hamstring"], .hamstring),
        (["臀大肌", "臀中肌", "练臀", "臀部", "臀腿", "臀", "glutes"], .gluteal),
        (["小腿", "腓肠肌", "比目鱼肌", "calves"], .calves),
        (["斜方肌", "斜方", "traps"], .trapezius),
    ]

    private static let explicitUpperBodySplit = ["上肢推拉", "上肢分化", "上肢", "练上肢"]

    public static func parse(_ text: String) -> WorkoutAnnotationProposal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return WorkoutAnnotationProposal(
                rawText: text,
                primaryMuscles: [.chest],
                secondaryMuscles: [],
                rpe: nil,
                exercises: [],
                bodySignals: [],
                parserSource: .chineseLexiconFallback,
                degradationReason: nil
            )
        }

        let clauses = splitClauses(trimmed)
        let signals = extractBodySignals(clauses: clauses)

        var primaryOrdered: [BodyRegionMuscle] = []
        var secondaryOrdered: [BodyRegionMuscle] = []
        var exerciseOrdered: [String] = []

        func addPrimary(_ m: BodyRegionMuscle) {
            if !primaryOrdered.contains(m) {
                primaryOrdered.append(m)
            }
            secondaryOrdered.removeAll { $0 == m }
        }

        func addSecondary(_ m: BodyRegionMuscle) {
            guard !primaryOrdered.contains(m), !secondaryOrdered.contains(m) else { return }
            secondaryOrdered.append(m)
        }

        for clause in clauses {
            let lowerClause = clause.lowercased()
            // Skip pure negation clauses such as "今天没练腿" / "没做深蹲" / "跳过腹肌"
            if isNegatedWorkoutClause(lowerClause) {
                continue
            }
            // Skip body-pain-only clauses unless they also contain explicit training verbs
            if clauseIsOnlyBodySignal(clause) && !containsTrainingAction(lowerClause) {
                continue
            }

            if explicitUpperBodySplit.contains(where: { lowerClause.contains($0) }) {
                addPrimary(.chest)
                addPrimary(.upperBack)
                addPrimary(.deltoids)
                addSecondary(.biceps)
                addSecondary(.triceps)
            }

            for rule in rules where rule.keywords.contains(where: { lowerClause.contains($0) }) {
                if let ex = rule.canonicalExercise, !exerciseOrdered.contains(ex) {
                    exerciseOrdered.append(ex)
                }
                for m in rule.primary {
                    addPrimary(m)
                }
                for m in rule.secondary {
                    addSecondary(m)
                }
            }

            for entry in explicitMuscleAliases {
                // Skip injury mentions like "右肩紧" / "左膝不适" when promoting muscle targets
                guard entry.keywords.contains(where: { lowerClause.contains($0) }) else { continue }
                if !clauseMentionsSymptomAround(clause: lowerClause, keywords: entry.keywords) {
                    addPrimary(entry.muscle)
                }
            }
        }

        let rpe = extractRPE(from: trimmed)

        if primaryOrdered.isEmpty && !secondaryOrdered.isEmpty {
            primaryOrdered = [secondaryOrdered.removeFirst()]
        }

        return WorkoutAnnotationProposal(
            rawText: text,
            primaryMuscles: primaryOrdered,
            secondaryMuscles: secondaryOrdered,
            rpe: rpe,
            exercises: exerciseOrdered,
            bodySignals: signals,
            parserSource: .chineseLexiconFallback,
            degradationReason: nil
        )
    }

    private static func splitClauses(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: "，,。.;；\n")
        return text
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func isNegatedWorkoutClause(_ lower: String) -> Bool {
        let negPrefixes = ["没练", "没有练", "没做", "没有做", "没加", "跳过", "不练", "不做", "省去", "取消"]
        return negPrefixes.contains { lower.contains($0) }
    }

    private static func containsTrainingAction(_ lower: String) -> Bool {
        let actionHints = ["练", "做", "组", "推", "蹲", "拉", "举", "划船", "硬拉", "弯举", "打", "跑"]
        return actionHints.contains { lower.contains($0) }
    }

    private static func clauseIsOnlyBodySignal(_ clause: String) -> Bool {
        let symptomWords = ["紧", "酸", "痛", "疼", "不适", "弹响", "拉伤", "发炎", "僵", "不舒服", "刺痛"]
        return symptomWords.contains { clause.contains($0) }
    }

    private static func clauseMentionsSymptomAround(clause: String, keywords: [String]) -> Bool {
        let symptomWords = ["微痛", "疼痛", "发紧", "酸痛", "不适", "弹响", "拉伤", "发炎", "僵硬", "刺痛", "有点痛", "略紧", "有些紧", "好紧", "好痛", "痛", "疼", "紧"]
        guard symptomWords.contains(where: { clause.contains($0) }) else {
            return false
        }
        // Only suppress muscle promotion if clause doesn't explicitly contain a training cue for that muscle
        let trainCues = ["练了", "练", "推", "拉", "蹲", "划船", "举", "弯举", "加了", "主练", "强化", "刺激"]
        if trainCues.contains(where: { clause.contains($0) }) {
            return false
        }
        return keywords.contains { clause.contains($0) }
    }

    private static func extractRPE(from text: String) -> Int? {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)

        let numericPatterns = [
            #"(?i)rpe\s*[:：=]?\s*(\d{1,2}(?:\.\d+)?)"#,
            #"(?:主观努力度|努力度|累度|强度)\s*[:：=]?\s*(\d{1,2}(?:\.\d+)?)"#,
            #"(\d{1,2})\s*(?:/10|分疲劳|分累|分强度)"#,
        ]

        for pattern in numericPatterns {
            if let regex = makeRegex(pattern),
               let match = regex.firstMatch(in: text, options: [], range: range),
               match.numberOfRanges >= 2
            {
                let captured = nsText.substring(with: match.range(at: 1))
                if let val = Double(captured) {
                    let clamped = Int(val.rounded())
                    if (1...10).contains(clamped) {
                        return clamped
                    }
                }
            }
        }

        let lower = text.lowercased()
        if lower.contains("完全力竭") || lower.contains("透支") || lower.contains("rpe满") {
            return 10
        }
        if lower.contains("力竭") || lower.contains("拉爆") || lower.contains("快废") || lower.contains("极限") {
            return 9
        }
        if lower.contains("很累") || lower.contains("挺累") || lower.contains("吃力") || lower.contains("偏重") || lower.contains("很重") {
            return 8
        }
        if lower.contains("适中") || lower.contains("中等") || lower.contains("还行") || lower.contains("正常节奏") || lower.contains("稳稳") {
            return 7
        }
        if lower.contains("微汗") || lower.contains("轻松") || lower.contains("恢复为主") || lower.contains("不太累") || lower.contains("轻重量") {
            return 5
        }
        return nil
    }

    private static func extractBodySignals(clauses: [String]) -> [WorkoutBodySignal] {
        let laterality = "(?:左|右|双侧|两侧)?"
        let regions = "(?:大腿前侧|大腿后侧|肩前束|肩中束|肩后束|前束|中束|后束|肩袖|肩膀|肩|膝盖|膝|下背|腰背|腰部|腰|小臂|前臂|手腕|腕|肘关节|手肘|肘|脚踝|踝|跟腱|脖子|颈|髋|腹股沟|小腿|大腿|腘绳肌|股四头肌|股四|胸锁|锁骨)"
        let symptoms = "(?:微痛|微紧|略痛|刺痛|疼痛|不适|发紧|有点紧|略紧|偏紧|很紧|太紧|酸痛|酸胀|酸|僵硬|弹响|拉伤|发炎|乏力|不舒服|痛|疼|紧)"
        let pattern = "(\(laterality)\(regions))(?:稍微|有点|略微|有些|非常|特别|好|隐隐)?(\(symptoms))"

        guard let regex = makeRegex(pattern) else {
            return []
        }

        var signals: [WorkoutBodySignal] = []
        var seen = Set<String>()

        for clause in clauses {
            let nsClause = clause as NSString
            let range = NSRange(location: 0, length: nsClause.length)
            let matches = regex.matches(in: clause, options: [], range: range)
            for match in matches where match.numberOfRanges >= 3 {
                let region = nsClause.substring(with: match.range(at: 1))
                let symptom = nsClause.substring(with: match.range(at: 2))
                let key = "\(region)-\(symptom)"
                guard seen.insert(key).inserted else { continue }
                let constraint = "\(region)\(symptom)（练后复盘反馈，14天内注意降低该部位直接负荷与大角度压迫）"
                signals.append(
                    WorkoutBodySignal(
                        region: region,
                        symptom: symptom,
                        suggestedConstraint: constraint,
                        defaultExpiryDays: 14,
                        includeAsMemory: true
                    )
                )
            }
        }
        return signals
    }

    private static func makeRegex(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            return nil
        }
    }
}
