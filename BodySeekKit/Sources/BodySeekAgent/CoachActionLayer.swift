import BodySeekCore
import Foundation

/// Coach 工具调用动作层的入口。
///
/// `BodySeekAgent` 不直接持有执行器：App 在构造 `AgentExecutionContext` 时注入一个闭包
/// （内部调用 `BodySeekStoreClient.executeAction`，来源固定为 `coach`）。没有注入时
/// （预览、评测、离线测试），提案工具保持原来的"只生成确认卡片"行为。
public struct AgentActionGateway: Sendable {
    /// 提交一个动作提案；A、B 级直接执行，C 级返回"需要确认"。
    public let execute: @Sendable (_ proposal: ActionProposal) async throws -> AppActionOutcome

    /// 创建入口。
    public init(execute: @escaping @Sendable (_ proposal: ActionProposal) async throws -> AppActionOutcome) {
        self.execute = execute
    }
}

/// `execute_action` 工具的参数解析结果。解析是纯函数，不触碰任何存储，便于单元测试。
public enum ExecuteActionRequest: Equatable, Sendable {
    /// 保存记忆（A 级）。
    case saveMemory(tier: String, content: String, category: String, expiresDays: Int, patternID: String?)
    /// 停用记忆（B 级，24 小时内可撤销）。
    case retireMemory(memoryID: UUID)
    /// 给训练补标注（A 级）。
    case annotateWorkout(rawText: String, workoutUUID: String?)
    /// 删除一条餐食记录（C 级：只会返回"需要确认"，不会执行）。
    case deleteMeal(dayKey: DayKey, entryID: UUID)

    /// 参数解析错误。
    public enum ParseError: Error, Equatable, Sendable {
        /// 参数不是合法的 JSON 对象。
        case invalidJSON
        /// 缺少 `action`。
        case missingAction
        /// `action` 不在支持范围内。
        case unknownAction(String)
        /// 缺少必填字段。
        case missingField(String)
        /// 字段格式不对。
        case invalidField(String)

        /// 返回给模型的原因说明。
        public var message: String {
            switch self {
            case .invalidJSON: "参数不是合法的 JSON 对象"
            case .missingAction: "缺少 action 字段"
            case let .unknownAction(name): "不支持的 action：\(name)，可用：\(ExecuteActionRequest.supportedActions.joined(separator: "、"))"
            case let .missingField(name): "缺少必填字段 \(name)"
            case let .invalidField(name): "字段 \(name) 的格式不正确"
            }
        }
    }

    /// 支持的 `action` 取值。
    public static let supportedActions = ["save_memory", "retire_memory", "annotate_workout", "delete_meal"]

    private static let aliases: [String: String] = [
        "commitMemory": "save_memory",
        "retireMemory": "retire_memory",
        "annotateWorkout": "annotate_workout",
        "deleteNutritionMeal": "delete_meal",
    ]

    /// 解析工具参数 JSON。
    public static func parse(argumentsJSON: String) -> Result<ExecuteActionRequest, ParseError> {
        guard let data = argumentsJSON.data(using: .utf8),
              let value = try? JSONValue.parseData(data),
              case let .object(args) = value
        else { return .failure(.invalidJSON) }

        guard let rawAction = text(args["action"])?.trimmingCharacters(in: .whitespacesAndNewlines), !rawAction.isEmpty else {
            return .failure(.missingAction)
        }
        let action = aliases[rawAction] ?? rawAction

        switch action {
        case "save_memory":
            guard let content = text(args["content"])?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
                return .failure(.missingField("content"))
            }
            return .success(.saveMemory(
                tier: text(args["tier"]) ?? "activeConstraint",
                content: content,
                category: text(args["category"]) ?? "preference",
                expiresDays: integer(args["expiresDays"]) ?? 14,
                patternID: text(args["patternID"])
            ))
        case "retire_memory":
            guard let raw = text(args["memoryID"]) else { return .failure(.missingField("memoryID")) }
            guard let id = UUID(uuidString: raw) else { return .failure(.invalidField("memoryID")) }
            return .success(.retireMemory(memoryID: id))
        case "annotate_workout":
            guard let raw = text(args["rawText"])?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
                return .failure(.missingField("rawText"))
            }
            return .success(.annotateWorkout(rawText: raw, workoutUUID: text(args["workoutUUID"])))
        case "delete_meal":
            guard let rawDay = text(args["dayKey"]) else { return .failure(.missingField("dayKey")) }
            guard let day = DayKey(isoString: rawDay) else { return .failure(.invalidField("dayKey")) }
            guard let rawEntry = text(args["entryID"]) else { return .failure(.missingField("entryID")) }
            guard let entry = UUID(uuidString: rawEntry) else { return .failure(.invalidField("entryID")) }
            return .success(.deleteMeal(dayKey: day, entryID: entry))
        default:
            return .failure(.unknownAction(rawAction))
        }
    }

    private static func text(_ value: JSONValue?) -> String? {
        guard let value else { return nil }
        switch value {
        case let .string(string): return string
        case let .integer(number): return String(number)
        case let .number(number): return String(number)
        default: return nil
        }
    }

    private static func integer(_ value: JSONValue?) -> Int? {
        guard let value else { return nil }
        switch value {
        case let .integer(number): return number
        case let .number(number): return Int(number.rounded())
        case let .string(string): return Int(string)
        default: return nil
        }
    }
}
