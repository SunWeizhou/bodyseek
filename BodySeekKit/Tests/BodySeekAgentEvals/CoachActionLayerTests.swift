@testable import BodySeekAgent
import BodySeekCore
import Foundation
import XCTest

private actor GatewayRecorder {
    private(set) var proposals: [ActionProposal] = []

    func record(_ proposal: ActionProposal) {
        proposals.append(proposal)
    }
}

/// `execute_action` 工具与提案工具接入动作层的行为。
final class CoachActionLayerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_500_000)

    private func makeContext(gateway: AgentActionGateway?) -> AgentExecutionContext {
        let rawDays = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 35)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: rawDays,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "测试数据源",
            isAuthorized: true
        )
        return AgentExecutionContext(snapshot: snapshot, asOf: now, actionGateway: gateway)
    }

    /// 模拟动作层：A、B 级返回回执，C 级返回需要确认。
    private func makeGateway(recorder: GatewayRecorder) -> AgentActionGateway {
        let executedAt = now
        return AgentActionGateway { proposal in
            await recorder.record(proposal)
            let descriptor = AppActionCatalog.descriptor(for: proposal.kind)
            if descriptor.requiresConfirmation {
                return .needsConfirmation(kind: proposal.kind, title: descriptor.title)
            }
            return .executed(AppActionReceipt(
                id: proposal.id,
                kind: proposal.kind,
                risk: descriptor.effectiveRisk,
                title: descriptor.title,
                detail: "测试回执",
                executedAt: executedAt,
                isUndoable: descriptor.isUndoable,
                undoDeadline: descriptor.undoWindow.map { executedAt.addingTimeInterval($0) }
            ))
        }
    }

    // MARK: - 参数解析

    func testParseSaveMemoryUsesDefaults() throws {
        let request = try ExecuteActionRequest.parse(
            argumentsJSON: #"{"action":"save_memory","content":"  右肩前束微痛  "}"#
        ).get()
        XCTAssertEqual(
            request,
            .saveMemory(tier: "activeConstraint", content: "右肩前束微痛", category: "preference", expiresDays: 14, patternID: nil)
        )
    }

    func testParseSaveMemoryReadsOptionalFieldsAndStringNumbers() throws {
        let request = try ExecuteActionRequest.parse(
            argumentsJSON: #"{"action":"save_memory","content":"素食","tier":"profile","category":"preference","expiresDays":"30"}"#
        ).get()
        XCTAssertEqual(
            request,
            .saveMemory(tier: "profile", content: "素食", category: "preference", expiresDays: 30, patternID: nil)
        )
    }

    func testParseAcceptsCatalogKindAlias() throws {
        let id = UUID()
        let request = try ExecuteActionRequest.parse(
            argumentsJSON: #"{"action":"retireMemory","memoryID":"\#(id.uuidString)"}"#
        ).get()
        XCTAssertEqual(request, .retireMemory(memoryID: id))
    }

    func testParseAnnotateAndDeleteMeal() throws {
        let annotate = try ExecuteActionRequest.parse(
            argumentsJSON: #"{"action":"annotate_workout","rawText":"今天练胸","workoutUUID":"W1"}"#
        ).get()
        XCTAssertEqual(annotate, .annotateWorkout(rawText: "今天练胸", workoutUUID: "W1"))

        let entry = UUID()
        let delete = try ExecuteActionRequest.parse(
            argumentsJSON: #"{"action":"delete_meal","dayKey":"2026-11-22","entryID":"\#(entry.uuidString)"}"#
        ).get()
        XCTAssertEqual(delete, .deleteMeal(dayKey: DayKey(year: 2026, month: 11, day: 22), entryID: entry))
    }

    func testParseRejectsBadInput() {
        XCTAssertEqual(ExecuteActionRequest.parse(argumentsJSON: "not json").failureValue, .invalidJSON)
        XCTAssertEqual(ExecuteActionRequest.parse(argumentsJSON: "{}").failureValue, .missingAction)
        XCTAssertEqual(
            ExecuteActionRequest.parse(argumentsJSON: #"{"action":"format_disk"}"#).failureValue,
            .unknownAction("format_disk")
        )
        XCTAssertEqual(
            ExecuteActionRequest.parse(argumentsJSON: #"{"action":"save_memory","content":"  "}"#).failureValue,
            .missingField("content")
        )
        XCTAssertEqual(
            ExecuteActionRequest.parse(argumentsJSON: #"{"action":"retire_memory","memoryID":"abc"}"#).failureValue,
            .invalidField("memoryID")
        )
        XCTAssertEqual(
            ExecuteActionRequest.parse(argumentsJSON: #"{"action":"delete_meal","dayKey":"昨天","entryID":"x"}"#).failureValue,
            .invalidField("dayKey")
        )
    }

    // MARK: - 工具行为

    func testExecuteActionToolIsRegistered() {
        let names = CoachToolRegistry.openAIToolDefinitions.map(\.function.name)
        XCTAssertTrue(names.contains("execute_action"))
    }

    func testProposeMemoryAppliesThroughGateway() async {
        let recorder = GatewayRecorder()
        let context = makeContext(gateway: makeGateway(recorder: recorder))
        let output = await CoachToolRegistry.execute(
            name: "propose_memory",
            argumentsJSON: #"{"tier":"activeConstraint","content":"左踝不适","expiresDays":14}"#,
            context: context
        )
        XCTAssertTrue(output.contains(#""status":"applied""#), output)
        XCTAssertTrue(output.contains(#""authorization":"A""#), output)
        let proposals = await recorder.proposals
        XCTAssertEqual(proposals.map(\.kind), [.commitMemory])
        let applied = await context.effects.appliedActions
        XCTAssertEqual(applied.count, 1)
        let card = await context.effects.memoryProposal
        XCTAssertNil(card, "已直接保存，不应再生成确认卡片")
    }

    func testProposeMemoryFallsBackToCardWithoutGateway() async {
        let context = makeContext(gateway: nil)
        let output = await CoachToolRegistry.execute(
            name: "propose_memory",
            argumentsJSON: #"{"tier":"activeConstraint","content":"左踝不适"}"#,
            context: context
        )
        XCTAssertTrue(output.contains("pending_user_confirmation"), output)
        let card = await context.effects.memoryProposal
        XCTAssertNotNil(card)
        let applied = await context.effects.appliedActions
        XCTAssertTrue(applied.isEmpty)
    }

    func testPlanChangeStaysConfirmationCardEvenWithGateway() async {
        let recorder = GatewayRecorder()
        let context = makeContext(gateway: makeGateway(recorder: recorder))
        let output = await CoachToolRegistry.execute(
            name: "propose_plan_change",
            argumentsJSON: #"{"title":"上肢减量","focusTag":"减量","exerciseIDsCSV":"barbell-bench-press","intensityMultiplier":0.8,"restSeconds":90,"rationale":"恢复偏低"}"#,
            context: context
        )
        XCTAssertTrue(output.contains("pending_user_confirmation"), output)
        XCTAssertTrue(output.contains(#""authorization":"C""#), output)
        let proposals = await recorder.proposals
        XCTAssertTrue(proposals.isEmpty, "训练计划是 C 级，不能走直接执行")
        let card = await context.effects.workoutProposal
        XCTAssertNotNil(card)
    }

    func testExecuteActionSaveMemoryAndInvalidArguments() async {
        let recorder = GatewayRecorder()
        let context = makeContext(gateway: makeGateway(recorder: recorder))
        let saved = await CoachToolRegistry.execute(
            name: "execute_action",
            argumentsJSON: #"{"action":"save_memory","content":"不吃海鲜","tier":"profile"}"#,
            context: context
        )
        XCTAssertTrue(saved.contains(#""status":"applied""#), saved)

        let invalid = await CoachToolRegistry.execute(
            name: "execute_action",
            argumentsJSON: #"{"action":"retire_memory","memoryID":"abc"}"#,
            context: context
        )
        XCTAssertTrue(invalid.contains("invalid_arguments"), invalid)
        let proposals = await recorder.proposals
        XCTAssertEqual(proposals.count, 1, "参数不合法时不能提交动作")
    }

    func testExecuteActionDeleteMealOnlyAsksForConfirmation() async {
        let recorder = GatewayRecorder()
        let context = makeContext(gateway: makeGateway(recorder: recorder))
        let output = await CoachToolRegistry.execute(
            name: "execute_action",
            argumentsJSON: #"{"action":"delete_meal","dayKey":"2026-11-22","entryID":"\#(UUID().uuidString)"}"#,
            context: context
        )
        XCTAssertTrue(output.contains("needs_confirmation"), output)
        let applied = await context.effects.appliedActions
        XCTAssertTrue(applied.isEmpty)
    }

    func testExecuteActionWithoutGatewayIsUnavailable() async {
        let context = makeContext(gateway: nil)
        let output = await CoachToolRegistry.execute(
            name: "execute_action",
            argumentsJSON: #"{"action":"save_memory","content":"x"}"#,
            context: context
        )
        XCTAssertTrue(output.contains("unavailable"), output)
    }

    func testSystemPromptDescribesThreeAuthorizationLevels() {
        let prompt = CoachAgentOrchestrator.buildSystemPrompt(query: "你好", context: makeContext(gateway: nil))
        XCTAssertTrue(prompt.contains("A 级"))
        XCTAssertTrue(prompt.contains("B 级"))
        XCTAssertTrue(prompt.contains("C 级"))
        XCTAssertTrue(prompt.contains("execute_action"))
    }
}

private extension Result {
    var failureValue: Failure? {
        if case let .failure(error) = self { return error }
        return nil
    }
}
