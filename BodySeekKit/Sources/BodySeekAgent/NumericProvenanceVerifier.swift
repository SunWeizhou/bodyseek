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
        let protectedRanges = findProtectedRanges(in: responseText)

        // Pattern matches numbers tied to health measurement units (excludes 天/月/年/条).
        let unitPattern = #"(?<![0-9A-Za-z.\-])(\d+(?:\.\d+)?)\s*(%|ms|bpm|kcal|大卡|千卡|小时|分钟|h(?![a-zA-Z])|kg|km|公里|mL|毫升|mg|毫克|μg|ug|步|分(?!钟|析|布|配|类|享|别|歧|开|化|为|期))"#
        // Pattern matches numbers directly preceded by explicit physiological metric labels.
        let prefixPattern = #"(?:HRV|静息心率|平均心率|心率|恢复(?:度|得分|评分)?|睡眠(?:分|评分)?|负荷(?:分)?|压力(?:分)?|能量(?:分)?|ACWR|RPE|TRIMP)\s*(?:[:：=≈约达为是]|\s)\s*(\d+(?:\.\d+)?)"#

        struct CandidateMatch {
            let fullRange: NSRange
            let numberString: String
            let insertionPoint: Int
            let priority: Int
        }

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
            if isAllowedNumber(cand.numberString, allowed: allowed) {
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

    private static func collectAllowedNumbers(from texts: [String]) -> Set<Int> {
        var allowedScaled = Set<Int>()
        let pattern = #"(?<![A-Za-z])-?\d+(?:\.\d+)?"#
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
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
        } catch {
            logger.error("Failed collecting tool output numbers: \(error.localizedDescription, privacy: .public)")
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
