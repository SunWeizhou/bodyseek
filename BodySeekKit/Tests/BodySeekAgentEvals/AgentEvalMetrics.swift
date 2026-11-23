import BodySeekAgent
import Foundation

/// UI v4 §6.3 的两项评测指标。
enum AgentEvalMetrics {
    /// 套话：回复里出现一次算一次，门槛 0。
    static let defensivePhrases = [
        "可能", "或许", "仅供参考", "建议咨询专业", "咨询专业人士", "数据有限，无法判断", "数据有限无法判断",
    ]

    /// 回复里套话出现的总次数。
    static func defensivePhraseCount(in text: String) -> Int {
        defensivePhrases.reduce(0) { total, phrase in
            total + text.components(separatedBy: phrase).count - 1
        }
    }

    /// 未核对数字占比（百分比）；没有数字时为 0。
    static func unverifiedRate(verified: Int, unverified: Int) -> Double {
        let total = verified + unverified
        return total == 0 ? 0 : Double(unverified) / Double(total) * 100
    }

    /// 门槛：套话 0 次，未核对占比 ≤ 5%。
    static let maxUnverifiedRatePercent = 5.0
}
