import BodySeekCore
import BodySeekDesign
import SwiftUI

/// Coach 通过动作层自动执行的动作回执：用 `BSReceipt` 展示做了什么，A、B 级都带撤销按钮。
struct CoachReceiptCard: View {
    let receipt: AppActionReceipt
    let isUndone: Bool
    let isPending: Bool
    let onUndo: () -> Void

    var body: some View {
        BSReceipt(
            title: receipt.title,
            detail: receipt.detail,
            level: level,
            status: status,
            before: receipt.beforeText,
            after: receipt.afterText,
            onUndo: undoAction,
            undoIdentifier: "coach-receipt-undo"
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach-receipt-card")
        .accessibilityAction(named: "撤销") {
            if canUndo { onUndo() }
        }
    }

    private var canUndo: Bool {
        !isUndone && !isPending && receipt.canUndo(at: Date())
    }

    private var level: BSActionLevel {
        receipt.risk == .b ? .highlighted : .automatic
    }

    private var status: BSActionStatus {
        if isUndone || receipt.undoneAt != nil { return .undone }
        if isPending { return .running }
        return .done
    }

    private var undoAction: (() -> Void)? {
        canUndo ? onUndo : nil
    }
}
