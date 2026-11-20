import BodySeekAgent
import BodySeekCore
import BodySeekStore
import Foundation
import XCTest

private final actor MockAgentTransport: AgentHTTPTransport {
    enum Step: Sendable {
        case data(statusCode: Int, body: String)
        case stream(statusCode: Int, lines: [String], errorBody: String)
        case error(NSError)
    }

    private var steps: [Step]
    private(set) var capturedRequests: [URLRequest] = []

    init(steps: [Step]) {
        self.steps = steps
    }

    func performData(_ request: URLRequest) async throws -> (statusCode: Int, data: Data) {
        capturedRequests.append(request)
        guard !steps.isEmpty else {
            return (500, Data("missing mock step".utf8))
        }
        let next = steps.removeFirst()
        switch next {
        case let .data(code, body):
            return (code, Data(body.utf8))
        case let .stream(code, lines, err):
            let text = code < 300 ? lines.joined(separator: "\n") : err
            return (code, Data(text.utf8))
        case let .error(err):
            throw err
        }
    }

    func performStreamLines(_ request: URLRequest) async throws -> (statusCode: Int, lines: [String], errorBody: Data) {
        capturedRequests.append(request)
        guard !steps.isEmpty else {
            return (500, [], Data("missing mock stream step".utf8))
        }
        let next = steps.removeFirst()
        switch next {
        case let .stream(code, lines, err):
            return (code, lines, Data(err.utf8))
        case let .data(code, body):
            if (200..<300).contains(code) {
                return (code, body.components(separatedBy: .newlines), Data())
            }
            return (code, [], Data(body.utf8))
        case let .error(err):
            throw err
        }
    }

    func recordedRequestCount() -> Int {
        capturedRequests.count
    }

    func lastRequest() -> URLRequest? {
        capturedRequests.last
    }
}

final class OpenAICompatibleClientTests: XCTestCase {
    private func sampleContext(referenceDate: Date = Date(timeIntervalSince1970: 1_760_500_000)) -> AgentExecutionContext {
        let rawDays = PreviewSeedFactory.makeRawWindow(endingAt: referenceDate, days: 35)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: rawDays,
            sleepGoalMinutes: 450,
            referenceDate: referenceDate,
            sourceLabel: "测试数据源",
            isAuthorized: true
        )
        return AgentExecutionContext(snapshot: snapshot)
    }

    func testEndpointURLNormalizerHandlesTrailingSlashesAndChatSuffixes() {
        XCTAssertEqual(EndpointURLNormalizer.normalizeBaseURL("https://api.deepseek.com/v1")?.absoluteString, "https://api.deepseek.com/v1")
        XCTAssertEqual(EndpointURLNormalizer.normalizeBaseURL("https://api.deepseek.com/v1/")?.absoluteString, "https://api.deepseek.com/v1")
        XCTAssertEqual(EndpointURLNormalizer.normalizeBaseURL("https://api.deepseek.com/v1/chat/completions")?.absoluteString, "https://api.deepseek.com/v1")
        XCTAssertEqual(EndpointURLNormalizer.normalizeBaseURL("https://proxy.example.com/chat/completions/")?.absoluteString, "https://proxy.example.com")
        XCTAssertNil(EndpointURLNormalizer.normalizeBaseURL("   "))
    }

    func testDeepSeekSSEStreamAssemblesSplitToolCallsAndRunsMultiTurnLoop() async throws {
        let context = sampleContext()
        let recorder = AgentPayloadRecorder()

        // Round 1: SSE stream emits partial tool_calls split across chunks
        let round1Lines = [
            "data: {\"id\":\"cmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"index\":0,\"id\":\"call_today_1\",\"type\":\"function\",\"function\":{\"name\":\"get_today\",\"arguments\":\"\"}}]},\"finish_reason\":null}]}",
            "data: {\"id\":\"cmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"_context\",\"arguments\":\"{\"}}]},\"finish_reason\":null}]}",
            "data: {\"id\":\"cmpl-1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"}\"}}]},\"finish_reason\":\"tool_calls\"}]}",
            "data: [DONE]",
        ]

        // Round 2: SSE stream reads actual today score from context cleanly
        let recScore = context.snapshot.today.recovery.value ?? 80
        let round2Lines = [
            "data: {\"id\":\"cmpl-2\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"今日恢复 \"}}]}",
            "data: {\"id\":\"cmpl-2\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\(recScore) 分，建议稳定推进。\"},\"finish_reason\":\"stop\"}]}",
            "data: [DONE]",
        ]

        let transport = MockAgentTransport(steps: [
            .stream(statusCode: 200, lines: round1Lines, errorBody: ""),
            .stream(statusCode: 200, lines: round2Lines, errorBody: ""),
        ])

        let client = OpenAICompatibleClient(
            transport: transport,
            payloadRecorder: recorder,
            retryBaseDelayNanoseconds: 0
        )

        let msg = try await CoachAgentOrchestrator.runCloudCompletion(
            question: "我今天恢复如何？",
            context: context,
            endpointURL: "https://api.deepseek.com/v1",
            apiKey: "sk-secret-unit-test-token",
            modelName: "deepseek-chat",
            client: client,
            preferStreaming: true
        )

        XCTAssertEqual(msg.toolsInvoked, ["get_today_context"])
        XCTAssertTrue(msg.text.contains("\(recScore) 分"))
        XCTAssertTrue(msg.unverifiedNumbers.isEmpty)
        XCTAssertFalse(msg.text.contains("未核实"))

        let snapshot = await recorder.latest()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.modelName, "deepseek-chat")
        XCTAssertFalse(snapshot?.redactedRequestJSON.contains("sk-secret-unit-test-token") ?? true)
    }

    func testDeepSeekFixtureScrubsLeakedToolCallAndDSMLTagsWithoutDataLoss() {
        let dirtyReply = """
        <think>先检查睡眠数据</think>
        昨晚睡眠时长 438 分钟。
        <tool_call>{"name":"get_sleep_detail","arguments":{}}</tool_call>
        <｜DSML｜function_calls><｜DSML｜invoke name="propose_memory"><｜DSML｜parameter name="content">bad</｜DSML｜parameter></｜DSML｜invoke></｜DSML｜function_calls>
        """
        let result = ToolMarkupScrubber.scrub(dirtyReply)
        XCTAssertTrue(result.leakedMarkupDetected)
        XCTAssertEqual(result.cleaned, "昨晚睡眠时长 438 分钟。")
        XCTAssertFalse(result.cleaned.contains("tool_call"))
        XCTAssertFalse(result.cleaned.contains("DSML"))

        let fenced = "```json\n{\"days\": 7}\n```"
        XCTAssertEqual(ToolMarkupScrubber.cleanJSONArguments(fenced), "{\"days\": 7}")
    }

    func testTransientHTTP429AndTimeoutRetrySucceedsWhileHard401FailsFast() async throws {
        let okJSON = """
        {"id":"ok","choices":[{"index":0,"message":{"role":"assistant","content":"已收到。","reasoning_content":"step"},"finish_reason":"stop"}]}
        """
        let retryingTransport = MockAgentTransport(steps: [
            .error(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)),
            .data(statusCode: 429, body: "{\"error\":\"rate_limit\"}"),
            .data(statusCode: 200, body: okJSON),
        ])
        let client = OpenAICompatibleClient(
            transport: retryingTransport,
            retryBaseDelayNanoseconds: 0
        )

        let completion = try await client.runChatCompletionLoop(
            endpointURL: "https://api.deepseek.com/v1",
            apiKey: "sk-test",
            modelName: "deepseek-chat",
            messages: [OpenAIChatMessage(role: "user", content: "hi")],
            tools: [],
            preferStreaming: false,
            toolExecutor: { _, _ in "{}" }
        )
        XCTAssertEqual(completion.content, "已收到。")
        let attempts = await retryingTransport.recordedRequestCount()
        XCTAssertEqual(attempts, 3)

        let authFailTransport = MockAgentTransport(steps: [
            .data(statusCode: 401, body: "Invalid API Key"),
        ])
        let authClient = OpenAICompatibleClient(transport: authFailTransport, retryBaseDelayNanoseconds: 0)
        do {
            _ = try await authClient.runChatCompletionLoop(
                endpointURL: "https://api.deepseek.com/v1",
                apiKey: "sk-bad",
                modelName: "deepseek-chat",
                messages: [OpenAIChatMessage(role: "user", content: "hi")],
                tools: [],
                preferStreaming: false,
                toolExecutor: { _, _ in "{}" }
            )
            XCTFail("Expected HTTP 401 error")
        } catch let error as OpenAICompatibleClientError {
            XCTAssertEqual(error, .httpStatus(401, "Invalid API Key"))
        }
    }

    func testNumericProvenanceVerifierFlagsHallucinatedMetricsAndPassesToolNumbers() {
        let toolJSON = #"{"tool":"get_today_context","data":{"hrvMs":62.4,"recovery":79,"sleepAsleepMinutes":420}}"#

        let grounded = NumericProvenanceVerifier.verify(
            responseText: "过去 7 天样本显示：今日恢复 79 分，HRV 62.4 ms，睡眠 420 分钟。",
            toolOutputs: [toolJSON],
            userQuestion: "看看我最近 7 天状态"
        )
        XCTAssertTrue(grounded.unverifiedTokens.isEmpty)
        XCTAssertFalse(grounded.annotatedText.contains("未核实"))
        XCTAssertEqual(grounded.verifiedCount, 3)

        let hallucinated = NumericProvenanceVerifier.verify(
            responseText: "今日恢复 95 分，静息心率 42 bpm，建议维持。",
            toolOutputs: [toolJSON],
            userQuestion: "我今天如何"
        )
        XCTAssertEqual(hallucinated.unverifiedTokens.count, 2)
        XCTAssertTrue(hallucinated.annotatedText.contains("95 分（未核实）"))
        XCTAssertTrue(hallucinated.annotatedText.contains("42 bpm（未核实）"))
    }

    func testMemoryContextSelectorFiltersExpiredRetiredRelevanceAndVerifiedPatternGate() {
        let now = Date(timeIntervalSince1970: 1_760_500_000)
        let expiredConstraint = TieredMemoryRecord(
            tier: .activeConstraint,
            content: "右膝不适避免深蹲",
            expiresAt: now.addingTimeInterval(-3600),
            confirmedAt: now.addingTimeInterval(-15 * 86_400)
        )
        let retiredProfile = TieredMemoryRecord(
            tier: .profile,
            content: "旧目标",
            confirmedAt: now.addingTimeInterval(-30 * 86_400),
            retiredAt: now.addingTimeInterval(-86_400)
        )
        let activeShoulder = TieredMemoryRecord(
            tier: .activeConstraint,
            content: "右肩前束略紧，卧推控制下放深度",
            expiresAt: now.addingTimeInterval(10 * 86_400),
            confirmedAt: now
        )
        let sleepGoal = TieredMemoryRecord(
            tier: .profile,
            content: "工作日希望在 23:30 前入睡",
            confirmedAt: now
        )

        let selectedForBench = MemoryContextSelector.selectRelevant(
            query: "今天练胸做杠铃卧推需要注意什么？",
            memories: [expiredConstraint, retiredProfile, activeShoulder, sleepGoal],
            now: now
        )
        XCTAssertEqual(selectedForBench.map(\.content), ["右肩前束略紧，卧推控制下放深度"])

        let candidateFinding = PatternFindingRecord(
            id: UUID(),
            statement: "23:30 后入睡次日 HRV 平均下降",
            effect: -5.2,
            ciLow: -8.1,
            ciHigh: -2.0,
            sampleSize: 120,
            method: "FDR-lag",
            modelVersion: "v1",
            status: .candidate
        )
        let unconfirmedGate = MemoryContextSelector.validateCandidateMemory(
            tier: .verifiedPattern,
            linkedPatternID: candidateFinding.id,
            confirmedFindings: [candidateFinding]
        )
        XCTAssertFalse(unconfirmedGate.allowed)

        var confirmedFinding = candidateFinding
        confirmedFinding.status = .confirmed
        let confirmedGate = MemoryContextSelector.validateCandidateMemory(
            tier: .verifiedPattern,
            linkedPatternID: confirmedFinding.id,
            confirmedFindings: [confirmedFinding]
        )
        XCTAssertTrue(confirmedGate.allowed)
    }

    func testProactiveInsightEngineCapsAtTwoAndIgnoresMissingDays() {
        let now = Date(timeIntervalSince1970: 1_760_500_000)
        var rawDays = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 35)
        for i in (rawDays.count - 3)..<rawDays.count {
            rawDays[i].hrvMs = 28 // Sharp 3-day HRV drop vs baseline ~55-75ms
        }
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: rawDays,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "测试",
            isAuthorized: true
        )
        let unreviewed = StoredWorkoutRecord(
            hkUUID: "UW-1",
            type: "传统力量训练 · Apple Watch",
            start: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(-1200),
            energy: 280,
            reviewState: .unreviewed
        )

        let insights = ProactiveInsightEngine.generate(
            snapshot: snapshot,
            storedWorkouts: [unreviewed],
            enabled: true
        )
        // Priority order: 3-day deviation + post-workout review + morning tone -> hard-capped to 2!
        XCTAssertEqual(insights.count, 2)
        XCTAssertEqual(insights[0].kind, .threeDayDeviation)
        XCTAssertEqual(insights[1].kind, .postWorkoutReview)

        // Disabled toggle yields empty list
        XCTAssertTrue(ProactiveInsightEngine.generate(snapshot: snapshot, storedWorkouts: [unreviewed], enabled: false).isEmpty)

        // Missing day in last 3 days must NOT trigger 3-day consecutive deviation false positive
        var gapRaw = rawDays
        gapRaw[gapRaw.count - 2].hrvMs = nil
        let gapSnapshot = BevelScoringEngine.computeWindow(
            rawDays: gapRaw,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "测试",
            isAuthorized: true
        )
        let gapInsights = ProactiveInsightEngine.generate(
            snapshot: gapSnapshot,
            storedWorkouts: [unreviewed],
            enabled: true
        )
        XCTAssertFalse(gapInsights.contains(where: { $0.kind == .threeDayDeviation }))
    }

    func testFindSimilarDaysNeverLeaksFutureDays() async {
        let now = Date(timeIntervalSince1970: 1_760_500_000)
        var rawDays = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 25)
        // Corrupt the final (future relative to target day at index 15) day with sentinel 999
        rawDays[rawDays.count - 1].hrvMs = 999
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: rawDays,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "测试",
            isAuthorized: true
        )
        let targetKey = snapshot.historyDays[15].dayKey.isoString
        let ctx = AgentExecutionContext(snapshot: snapshot)
        let json = await CoachToolRegistry.execute(
            name: "find_similar_days",
            argumentsJSON: "{\"day\":\"\(targetKey)\"}",
            context: ctx
        )
        XCTAssertFalse(json.contains("999"), "Future HRV sentinel must never appear when querying historical day \(targetKey)")
        XCTAssertTrue(json.contains("\"state\":\"available\""))
    }
}
