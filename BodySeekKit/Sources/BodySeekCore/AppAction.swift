import Foundation

/// 动作的风险级别（ADR 0020）。
public enum AppActionRisk: String, Hashable, Codable, Sendable, CaseIterable {
    /// A：直接执行，回执里给出撤销按钮。
    case a
    /// B：直接执行并突出提示，展示改动前后对比，24 小时内可撤销。
    case b
    /// C：必须先确认，确认后才执行。
    case c

    /// 是否必须先经用户确认。
    public var requiresConfirmation: Bool { self == .c }

    /// 面向用户的级别说明。
    public var title: String {
        switch self {
        case .a: "自动执行，可撤销"
        case .b: "自动执行并提示，24 小时内可撤销"
        case .c: "需要确认"
        }
    }
}

/// 动作目录里的一项：每个 `ActionProposal.Kind` 对应一项。
public struct AppActionDescriptor: Hashable, Sendable {
    /// 动作种类。
    public let kind: ActionProposal.Kind
    /// 目录里声明的风险级别。
    public let risk: AppActionRisk
    /// 面向用户的动作名称。
    public let title: String
    /// 执行器是否已经实现了这类动作的撤销（有 before / after 快照）。
    public let isUndoable: Bool

    /// 创建目录项。
    public init(kind: ActionProposal.Kind, risk: AppActionRisk, title: String, isUndoable: Bool) {
        self.kind = kind
        self.risk = risk
        self.title = title
        self.isUndoable = isUndoable
    }

    /// 实际生效的级别：B 级动作必须可撤销，尚未实现撤销的 B 级动作按 C 级处理（保守）。
    public var effectiveRisk: AppActionRisk {
        (risk == .b && !isUndoable) ? .c : risk
    }

    /// 是否必须先确认。
    public var requiresConfirmation: Bool { effectiveRisk.requiresConfirmation }

    /// 撤销窗口：只有 B 级有 24 小时期限。
    public var undoWindow: TimeInterval? {
        (effectiveRisk == .b && isUndoable) ? AppActionCatalog.highlightedUndoWindow : nil
    }
}

/// `AppAction` 目录：所有写入动作的风险级别和撤销能力集中在这里。
///
/// 新增 `ActionProposal.Kind` 时，这里的 `switch` 会因为不完整而编译失败，强制先定级。
public enum AppActionCatalog {
    /// B 级动作的撤销期限：24 小时。
    public static let highlightedUndoWindow: TimeInterval = 24 * 60 * 60

    /// 返回某种动作的目录项。
    public static func descriptor(for kind: ActionProposal.Kind) -> AppActionDescriptor {
        switch kind {
        case .annotateWorkout:
            AppActionDescriptor(kind: kind, risk: .a, title: "补训练标注", isUndoable: true)
        case .commitMemory:
            AppActionDescriptor(kind: kind, risk: .a, title: "保存记忆", isUndoable: true)
        case .recordCheckIn:
            AppActionDescriptor(kind: kind, risk: .a, title: "记录打卡", isUndoable: false)
        case .logNutritionMeal, .logNutritionMeals:
            AppActionDescriptor(kind: kind, risk: .a, title: "记一餐", isUndoable: true)
        case .retireMemory:
            AppActionDescriptor(kind: kind, risk: .b, title: "停用记忆", isUndoable: true)
        case .closeNutritionDay:
            AppActionDescriptor(kind: kind, risk: .b, title: "结账营养日", isUndoable: true)
        case .adjustPlan:
            AppActionDescriptor(kind: kind, risk: .b, title: "修改训练计划", isUndoable: false)
        case .upsertNutritionProfile:
            AppActionDescriptor(kind: kind, risk: .b, title: "修改营养档案", isUndoable: false)
        case .commitNutritionTargets:
            AppActionDescriptor(kind: kind, risk: .b, title: "修改营养目标", isUndoable: false)
        case .deleteNutritionMeal:
            AppActionDescriptor(kind: kind, risk: .c, title: "删除餐食记录", isUndoable: true)
        }
    }
}

/// 动作回执：执行后返回给页面或 Coach，用于展示 `BSReceipt` 和撤销。
public struct AppActionReceipt: Identifiable, Hashable, Codable, Sendable {
    /// 审计记录标识，撤销时使用。
    public let id: UUID
    /// 动作种类。
    public let kind: ActionProposal.Kind
    /// 实际生效的风险级别。
    public let risk: AppActionRisk
    /// 动作名称。
    public let title: String
    /// 做了什么、改在哪里。
    public let detail: String
    /// 执行时间。
    public let executedAt: Date
    /// 是否可撤销。
    public let isUndoable: Bool
    /// 撤销期限；`nil` 表示没有期限。
    public let undoDeadline: Date?
    /// B 级动作：改动前的值（用于改动前后对比）。
    public let beforeText: String?
    /// B 级动作：改动后的值。
    public let afterText: String?
    /// 撤销时间；`nil` 表示尚未撤销。
    public var undoneAt: Date?

    /// 创建回执。
    public init(
        id: UUID,
        kind: ActionProposal.Kind,
        risk: AppActionRisk,
        title: String,
        detail: String,
        executedAt: Date,
        isUndoable: Bool,
        undoDeadline: Date? = nil,
        beforeText: String? = nil,
        afterText: String? = nil,
        undoneAt: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.risk = risk
        self.title = title
        self.detail = detail
        self.executedAt = executedAt
        self.isUndoable = isUndoable
        self.undoDeadline = undoDeadline
        self.beforeText = beforeText
        self.afterText = afterText
        self.undoneAt = undoneAt
    }

    /// 在给定时刻是否还能撤销：可撤销、未撤销、未超过期限。
    public func canUndo(at date: Date) -> Bool {
        guard isUndoable, undoneAt == nil else { return false }
        if let undoDeadline { return date <= undoDeadline }
        return true
    }
}

/// 动作层一次执行的结果。
public enum AppActionOutcome: Hashable, Sendable {
    /// A、B 级：已经执行，附回执。
    case executed(AppActionReceipt)
    /// C 级：没有执行，需要用户先确认。
    case needsConfirmation(kind: ActionProposal.Kind, title: String)

    /// 已执行时的回执。
    public var receipt: AppActionReceipt? {
        if case let .executed(receipt) = self { return receipt }
        return nil
    }
}

/// 动作层的错误。
public enum AppActionError: Error, LocalizedError, Sendable, Equatable {
    /// C 级动作没有经过确认。
    case confirmationRequired(kind: ActionProposal.Kind)
    /// 已超过撤销期限。
    case undoWindowExpired
    /// 这个动作没有可用的撤销快照，或已经被撤销。
    case notUndoable(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .confirmationRequired(kind):
            "这个操作需要你先确认（\(AppActionCatalog.descriptor(for: kind).title)）。"
        case .undoWindowExpired:
            "已超过撤销期限。"
        case let .notUndoable(reason):
            "这个操作无法撤销：\(reason)"
        }
    }
}

/// 营养日志类动作的撤销快照（审计 `snapshotVersion` = 3）。
public struct NutritionLogUndoSnapshot: Codable, Sendable {
    /// 快照格式版本。
    public static let currentVersion = 3

    /// 生理日。
    public let dayKey: DayKey
    /// 动作之前的日志；当天原本没有日志时为 `nil`。
    public let before: DailyNutritionLog?
    /// 动作之后写入的日志；撤销前必须与当前库中的日志一致。
    public let after: DailyNutritionLog

    /// 创建快照。
    public init(dayKey: DayKey, before: DailyNutritionLog?, after: DailyNutritionLog) {
        self.dayKey = dayKey
        self.before = before
        self.after = after
    }
}

/// 记忆类动作的撤销快照（审计 `snapshotVersion` = 4）。
public struct MemoryUndoSnapshot: Codable, Sendable {
    /// 快照格式版本。
    public static let currentVersion = 4

    /// 记忆标识。
    public let memoryID: UUID
    /// 保存记忆时：动作之前该记忆是否已存在（已存在则无法自动还原）。
    public let existedBefore: Bool
    /// 停用记忆时：动作之前的退役时间。
    public let previousRetiredAt: Date?

    /// 创建快照。
    public init(memoryID: UUID, existedBefore: Bool, previousRetiredAt: Date?) {
        self.memoryID = memoryID
        self.existedBefore = existedBefore
        self.previousRetiredAt = previousRetiredAt
    }
}
