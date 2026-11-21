import BodySeekCore
import Foundation
import os

public struct NumericProvenanceReport: Equatable, Sendable {
    public let annotatedText: String
    public let unverifiedTokens: [String]
    public let verifiedCount: Int

    public init(annotatedText: String, unverifiedTokens: [String], verifiedCount: Int) {
        self.annotatedText = annotatedText
        self.unverifiedTokens = unverifiedTokens
        self.verifiedCount = verifiedCount
    }
}

private struct CandidateMatch {
    let fullRange: NSRange
    let numberString: String
    let insertionPoint: Int
    let priority: Int
}

/// Validates every quantitative health claim in assistant text against the current turn's tool JSON outputs.
public enum NumericProvenanceVerifier {
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "NumericProvenance")

    public static func verify(
        responseText: String,
        toolOutputs: [String],
        userQuestion: String = ""
    ) -> NumericProvenanceReport {
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NumericProvenanceReport(annotatedText: responseText, unverifiedTokens: [], verifiedCount: 0)
        }

        let allowed = collectAllowedNumbers(from: toolOutputs + [userQuestion])
        let typedFacts = collectTypedFacts(from: toolOutputs)
        let protectedRanges = findProtectedRanges(in: responseText)

        // Pattern matches numbers tied to health measurement units (excludes 天/月/年/条).
        let unitPattern = #"(?<![0-9A-Za-z.\-])(\d+(?:\.\d+)?)\s*(%|ms|bpm|kcal|大卡|千卡|小时|分钟|h(?![a-zA-Z])|kg|km|公里|mL|毫升|mg|毫克|μg|ug|步|分(?!钟|析|布|配|类|享|别|歧|开|化|为|期))"#
        // Pattern matches numbers directly preceded by explicit physiological metric labels.
        let prefixPattern = #"(?:HRV|静息心率|平均心率|心率|恢复(?:度|得分|评分)?|睡眠(?:分|评分)?|负荷(?:分)?|压力(?:分)?|能量(?:分)?|ACWR|RPE|TRIMP)\s*(?:[:：=≈约达为是]|\s)\s*(\d+(?:\.\d+)?)"#

        var candidates: [CandidateMatch] = []

        func scan(pattern: String, numberGroup: Int, anchorGroup: Int, priority: Int) {
            do {
                let regex = try NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
                let fullNSRange = NSRange(responseText.startIndex..., in: responseText)
                for match in regex.matches(in: responseText, options: [], range: fullNSRange) {
                    let matchRange = match.range(at: anchorGroup)
                    let numRange = match.range(at: numberGroup)
                    guard matchRange.location != NSNotFound, numRange.location != NSNotFound else { continue }
                    if isInsideProtectedRange(matchRange, protectedRanges: protectedRanges) { continue }
                    let numStr = (responseText as NSString).substring(with: numRange)
                    let tokenEnd = matchRange.location + matchRange.length
                    candidates.append(
                        CandidateMatch(
                            fullRange: matchRange,
                            numberString: numStr,
                            insertionPoint: tokenEnd,
                            priority: priority
                        )
                    )
                }
            } catch {
                logger.error("Invalid regex \(pattern, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        // Prefer unit-suffixed matches (e.g. "95 分", "42 bpm") over label-only prefixes (e.g. "恢复 95")
        scan(pattern: unitPattern, numberGroup: 1, anchorGroup: 0, priority: 2)
        scan(pattern: prefixPattern, numberGroup: 1, anchorGroup: 0, priority: 1)

        var seenRanges = [NSRange]()
        let uniqueCandidates = candidates
            .sorted {
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.fullRange.location < $1.fullRange.location
            }
            .filter { cand in
                if seenRanges.contains(where: { NSIntersectionRange($0, cand.fullRange).length > 0 }) {
                    return false
                }
                seenRanges.append(cand.fullRange)
                return true
            }
            .sorted { $0.fullRange.location < $1.fullRange.location }

        var verifiedCount = 0
        var unverifiedTokens: [String] = []
        var insertions: [(offset: Int, label: String)] = []
        let nsResponse = responseText as NSString

        for cand in uniqueCandidates {
            let typedResult = typedFacts.isEmpty ? nil : verifyAgainstTypedFacts(
                candidate: cand,
                text: responseText,
                facts: typedFacts
            )
            // A number that does not appear in typed evidence may still come from a
            // legacy tool result in the same turn. Only enforce metric/date/unit when
            // the value is actually present in typed evidence.
            let verified = typedResult ?? isAllowedNumber(cand.numberString, allowed: allowed)
            if verified {
                verifiedCount += 1
            } else {
                let matchedSnippet = nsResponse.substring(with: cand.fullRange)
                unverifiedTokens.append(matchedSnippet)
                let tailLength = min(10, nsResponse.length - cand.insertionPoint)
                let tailSnippet = tailLength > 0
                    ? nsResponse.substring(with: NSRange(location: cand.insertionPoint, length: tailLength))
                    : ""
                if !tailSnippet.contains("未核实") {
                    insertions.append((cand.insertionPoint, "（未核实）"))
                }
            }
        }

        guard !insertions.isEmpty else {
            return NumericProvenanceReport(
                annotatedText: responseText,
                unverifiedTokens: unverifiedTokens,
                verifiedCount: verifiedCount
            )
        }

        let mutable = NSMutableString(string: responseText)
        for ins in insertions.sorted(by: { $0.offset > $1.offset }) {
            mutable.insert(ins.label, at: ins.offset)
        }

        logger.warning("Flagged \(unverifiedTokens.count, privacy: .public) unverified health numbers in Coach reply.")
        return NumericProvenanceReport(
            annotatedText: mutable as String,
            unverifiedTokens: unverifiedTokens,
            verifiedCount: verifiedCount
        )
    }

    // MARK: - Helpers

    // Compiling these once avoids re-compiling on every candidate number in a reply.
    private static let unitRegex = compileRegex(
        #"(?i)(?:\s*)(%|ms|bpm|kcal|大卡|千卡|小时|分钟|h|kg|km|公里|ml|毫升|mg|毫克|μg|ug|步|分)(?=[\s。；;，,）)]|$)"#
    )
    private static let dayRegex = compileRegex(
        #"(\d{4})-(\d{2})-(\d{2})|(\d{1,2})月(\d{1,2})日"#
    )
    private static let numberRegex = compileRegex(
        #"(?<![A-Za-z])-?\d+(?:\.\d+)?"#
    )

    private static func compileRegex(_ pattern: String) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            logger.error("Invalid provenance regex \(pattern, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Typed evidence

    private struct TypedEvidenceFact {
        let scaledValues: Set<Int>
        let unit: String
        let metric: String
        let dayKey: String?
    }

    private static func collectTypedFacts(from toolOutputs: [String]) -> [TypedEvidenceFact] {
        var facts: [TypedEvidenceFact] = []
        for text in toolOutputs {
            guard let data = text.data(using: .utf8) else { continue }
            let object: [String: Any]
            do {
                guard let parsed = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                object = parsed
            } catch {
                continue
            }
            guard let evidence = object["evidence"] as? [[String: Any]] else { continue }
            for item in evidence {
                guard let value = (item["value"] as? NSNumber)?.doubleValue,
                      let unit = item["unit"] as? String,
                      let metric = item["metric"] as? String
                else { continue }
                var scaled = Set<Int>()
                insertScaled(value, into: &scaled)
                if unit == "ratio" {
                    insertScaled(value * 100, into: &scaled)
                }
                facts.append(TypedEvidenceFact(
                    scaledValues: scaled,
                    unit: unit,
                    metric: metric,
                    dayKey: item["dayKey"] as? String
                ))
            }
        }
        return facts
    }

    private static func verifyAgainstTypedFacts(
        candidate: CandidateMatch,
        text: String,
        facts: [TypedEvidenceFact]
    ) -> Bool? {
        guard let value = Double(candidate.numberString), value.isFinite else { return false }
        var scaled = Set<Int>()
        insertScaled(value, into: &scaled)
        let matched = facts.filter { !$0.scaledValues.isDisjoint(with: scaled) }
        guard !matched.isEmpty else { return nil }

        let nsText = text as NSString
        let snippet = nsText.substring(with: candidate.fullRange)
        let tokenUnit = extractUnit(from: snippet)
        if let tokenUnit, !unitIsCompatible(tokenUnit: tokenUnit, facts: matched) {
            return false
        }

        let context = contextSnippet(around: candidate.fullRange, in: text)
        let metricFamilies = detectedMetricFamilies(in: context)
        if !metricFamilies.isEmpty {
            let factFamilies = Set(matched.map { metricFamily(for: $0.metric) })
            if factFamilies.isDisjoint(with: metricFamilies) {
                return false
            }
        }

        if let contextDay = detectedDayKey(in: context) {
            let dayFacts = matched.compactMap(\.dayKey)
            if !dayFacts.isEmpty, !dayFacts.contains(where: {
                $0 == contextDay || (contextDay.count == 5 && $0.hasSuffix(contextDay))
            }) {
                return false
            }
        }
        return true
    }

    private static func extractUnit(from snippet: String) -> String? {
        guard let regex = unitRegex,
              let match = regex.firstMatch(in: snippet, range: NSRange(snippet.startIndex..., in: snippet)),
              let range = Range(match.range(at: 1), in: snippet)
        else { return nil }
        return String(snippet[range]).lowercased()
    }

    private static func unitIsCompatible(tokenUnit: String, facts: [TypedEvidenceFact]) -> Bool {
        let canonical: String
        switch tokenUnit {
        case "ms", "bpm", "kcal", "hours", "minutes", "kg", "km", "ml", "mg", "ug", "steps", "%":
            canonical = tokenUnit
        case "大卡", "千卡": canonical = "kcal"
        case "小时", "h": canonical = "hours"
        case "分钟": canonical = "minutes"
        case "公里": canonical = "km"
        case "毫升": canonical = "ml"
        case "毫克": canonical = "mg"
        case "步": canonical = "steps"
        case "分":
            return facts.contains { ["score_0_100", "score_points", "minutes"].contains($0.unit) }
        default:
            return true
        }
        return facts.contains { fact in
            if canonical == "%" {
                return fact.unit == "percent" || fact.unit == "ratio"
            }
            return fact.unit == canonical
        }
    }

    private static func metricFamily(for metric: String) -> String {
        switch metric {
        case "recovery": "recovery"
        case "sleep", "sleep_asleep": "sleep"
        case "strain", "workout_count", "active_energy": "strain"
        case "stress": "stress"
        case "energy": "energy"
        case "hrv": "hrv"
        case "resting_heart_rate": "resting_heart_rate"
        case "nutrition_kcal", "nutrition_protein": "nutrition"
        case "checkin_energy", "checkin_mood", "checkin_stress": "checkin"
        default: metric
        }
    }

    private static func detectedMetricFamilies(in context: String) -> Set<String> {
        var families = Set<String>()
        let rules: [(String, [String])] = [
            ("recovery", ["恢复"]),
            ("sleep", ["睡眠", "入睡", "深睡", "rem"]),
            ("strain", ["负荷", "训练量", "acwr", "急性负荷"]),
            ("stress", ["压力"]),
            ("energy", ["能量"]),
            ("hrv", ["hrv", "心率变异性"]),
            ("resting_heart_rate", ["静息心率", "rhr"]),
            ("nutrition", ["热量", "摄入", "蛋白质", "碳水", "脂肪"]),
            ("checkin", ["精力", "情绪", "体感"]),
        ]
        let lower = context.lowercased()
        for (family, keywords) in rules where keywords.contains(where: { lower.contains($0) }) {
            families.insert(family)
        }
        return families
    }

    private static func contextSnippet(around range: NSRange, in text: String) -> String {
        let ns = text as NSString
        let startBoundary = max(0, range.location - 80)
        let endBoundary = min(ns.length, NSMaxRange(range) + 80)
        return ns.substring(with: NSRange(location: startBoundary, length: endBoundary - startBoundary))
    }

    private static func detectedDayKey(in context: String) -> String? {
        guard let regex = dayRegex,
              let match = regex.firstMatch(in: context, range: NSRange(context.startIndex..., in: context))
        else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: context) else { return nil }
            return String(context[swiftRange])
        }
        if let year = group(1), let month = group(2), let day = group(3) {
            return "\(year)-\(month)-\(day)"
        }
        if let month = group(4), let day = group(5) {
            return String(format: "%02d-%02d", Int(month) ?? 0, Int(day) ?? 0)
        }
        return nil
    }

    private static func collectAllowedNumbers(from texts: [String]) -> Set<Int> {
        var allowedScaled = Set<Int>()
        if let regex = numberRegex {
            for text in texts {
                let range = NSRange(text.startIndex..., in: text)
                let ns = text as NSString
                for match in regex.matches(in: text, options: [], range: range) {
                    let raw = ns.substring(with: match.range)
                    guard let val = Double(raw), val.isFinite else { continue }
                    insertScaled(val, into: &allowedScaled)
                    insertScaled(val.rounded(), into: &allowedScaled)
                }
            }
        }
        return allowedScaled
    }

    private static func insertScaled(_ value: Double, into set: inout Set<Int>) {
        guard abs(value) < 1_000_000 else { return }
        let hundredths = Int((value * 100.0).rounded())
        set.insert(hundredths)
    }

    private static func isAllowedNumber(_ numberString: String, allowed: Set<Int>) -> Bool {
        guard let val = Double(numberString), val.isFinite else { return false }
        let hundredths = Int((val * 100.0).rounded())
        if allowed.contains(hundredths) { return true }
        // Allow rounding difference within +/- 0.1 for displayed 1-decimal or integer rounded figures if exact integer matches
        let roundedIntHundredths = Int((val.rounded() * 100.0).rounded())
        if val.rounded() == val, allowed.contains(roundedIntHundredths) {
            return true
        }
        return false
    }

    private static func findProtectedRanges(in text: String) -> [NSRange] {
        var out: [NSRange] = []
        let patterns = [
            #"\b\d{4}-\d{2}-\d{2}\b"#,
            #"\b\d{1,2}:\d{2}\b"#,
            #"\bZ[1-5]\b"#,
            #"(?m)^\s*\d+[\.\)、]\s"#,
            #"\bN-of-1\b"#,
        ]
        let full = NSRange(text.startIndex..., in: text)
        for p in patterns {
            do {
                let r = try NSRegularExpression(pattern: p, options: [])
                out.append(contentsOf: r.matches(in: text, options: [], range: full).map(\.range))
            } catch {
                logger.error("Invalid protected-range pattern: \(error.localizedDescription, privacy: .public)")
            }
        }
        return out
    }

    private static func isInsideProtectedRange(_ range: NSRange, protectedRanges: [NSRange]) -> Bool {
        protectedRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }
}
