import XCTest
import SwiftData
@testable import Vela

final class AgentActionParserTests: XCTestCase {
    func testShortHealthQuestionsUseToolCapablePath() {
        for text in ["今晚怎么睡更好？", "恢复？", "今天能跑吗", "谢谢，帮我分析恢复", "hi, analyze my sleep"] {
            XCTAssertFalse(ResponseLengthPolicy.forQuery(text, lang: .simplifiedChinese) == .casual, text)
        }
        XCTAssertTrue(ResponseLengthPolicy.forQuery("你好", lang: .simplifiedChinese) == .casual)
    }

    @MainActor
    func testMalformedToolTextIsRepairedThroughNativeCalls() async throws {
        let provider = FakeAgentChatProvider(responses: [
            LLMResponse(content: #"<tool_call>{"name":"check_health_data","arguments":{}}</tool_call>"#, toolCalls: nil),
            LLMResponse(content: "", toolCalls: [ToolCall(id: "read-1", name: "first_tool", arguments: "{}")]),
            LLMResponse(content: "Based on the returned evidence.", toolCalls: nil)
        ])
        let loop = AgentLoop(provider: provider, toolRegistry: ToolRegistry(tools: [
            StaticAgentTool(name: "first_tool", result: "known evidence")
        ]), maxIterations: 3)
        var displayed = ""
        let result = try await loop.run(messages: [ChatMessage(role: .user, content: "read evidence")], onStreamDelta: { displayed += $0 })
        XCTAssertEqual(result.executedTools.map(\.name), ["first_tool"])
        XCTAssertEqual(result.response, "Based on the returned evidence.")
        XCTAssertFalse(displayed.contains("<tool_call>"))
    }

    @MainActor
    func testRepeatedProtocolTextDoesNotExecuteOrAppearAsSuccess() async throws {
        let raw = #"<tool_call>{"name":"first_tool","arguments":{}}</tool_call>"#
        let provider = FakeAgentChatProvider(responses: [
            LLMResponse(content: raw, toolCalls: nil), LLMResponse(content: raw, toolCalls: nil)
        ])
        let loop = AgentLoop(provider: provider, toolRegistry: ToolRegistry(tools: [
            StaticAgentTool(name: "first_tool", result: "must not execute")
        ]))
        do {
            _ = try await loop.run(messages: [ChatMessage(role: .user, content: "question")])
            XCTFail("Malformed protocol must produce a retryable error")
        } catch let error as LLMProviderError {
            XCTAssertEqual(error, .invalidResponse)
        }
        XCTAssertEqual(provider.chatCallToolAvailability, [true, true])
        XCTAssertTrue(CoachProtocolOutput.isMalformed(raw))
        XCTAssertFalse(CoachProtocolOutput.failureText.contains("<tool_call>"))
        XCTAssertFalse(CoachProtocolOutput.isMalformed("Normal answer [ARTIFACT:correlation:sleep]"))
    }

    func testAgentActionParserPreservesActionOrderAndCleansDisplayText() {
        let raw = """
        我会先更新长期档案，然后记录今天日志。

        [ACTION:update_wiki]
        file: training.md
        用户决定每周二固定进行下肢力量训练。
        [/ACTION]

        [ACTION:create_daily_log]
        今天训练后主观疲劳为 7/10。
        [/ACTION]
        """

        let parsed = AgentActionParser.parse(raw)

        XCTAssertEqual(parsed.displayText, "我会先更新长期档案，然后记录今天日志。")
        XCTAssertEqual(parsed.actions.map(\.type), [.updateWiki, .createDailyLog])
        XCTAssertEqual(parsed.actions.first?.target, "training.md")
        XCTAssertEqual(parsed.actions.first?.content, "用户决定每周二固定进行下肢力量训练。")
        XCTAssertEqual(parsed.actions.last?.target, "daily")
        XCTAssertEqual(parsed.actions.last?.content, "今天训练后主观疲劳为 7/10。")
    }

    func testWebSearchHelperParsesTraceableResultLinks() {
        let html = """
        <ol>
          <li class="b_algo">
            <h2><a href="https://www.ncbi.nlm.nih.gov/pmc/articles/PMC123/?a=1&amp;b=2">Creatine and strength review</a></h2>
            <div class="b_caption"><p class="b_lineclamp2">A review of creatine supplementation and resistance training outcomes.</p></div>
          </li>
          <li class="b_algo">
            <h2><a href="https://www.acsm.org/guidelines">ACSM training guidance</a></h2>
            <p>Guidance for training load and recovery decisions.</p>
          </li>
        </ol>
        """

        let results = WebSearchHelper.parseResults(from: html, max: 2)
        let formatted = WebSearchHelper.formatResults(results)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.title, "Creatine and strength review")
        XCTAssertEqual(results.first?.url, "https://www.ncbi.nlm.nih.gov/pmc/articles/PMC123/?a=1&b=2")
        XCTAssertEqual(results.first?.snippet, "A review of creatine supplementation and resistance training outcomes.")
        XCTAssertTrue(formatted.contains("[Creatine and strength review](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC123/?a=1&b=2)"))
        XCTAssertTrue(formatted.contains("Guidance for training load and recovery decisions."))
    }

    func testWebSearchToolDetectsSourcePolicyForChineseHealthAndTrainingQueries() {
        XCTAssertEqual(WebSearchTool.detectPolicy(for: "最新肌酸研究对力量训练有什么建议？"), .medicalPrimary)
        XCTAssertEqual(WebSearchTool.detectPolicy(for: "最近关于增肌和恢复的运动科学研究"), .sportsScience)

        let enrichedMedical = WebSearchTool.enrichQuery("最新肌酸研究", policy: .medicalPrimary)
        let enrichedSports = WebSearchTool.enrichQuery("增肌恢复研究", policy: .sportsScience)

        XCTAssertTrue(enrichedMedical.contains("site:nih.gov"))
        XCTAssertTrue(enrichedMedical.contains("site:ncbi.nlm.nih.gov"))
        XCTAssertTrue(enrichedSports.contains("site:acsm.org"))
        XCTAssertTrue(enrichedSports.contains("site:jissn.biomedcentral.com"))
    }

    func testCoachArtifactParserParsesStructuredJSON() throws {
        let json = """
        {
          "artifactType": "morning_brief",
          "title": "今天适合减量训练",
          "summary": "睡眠充足，但 HRV 低于基线且下肢局部负荷偏高。",
          "decision": "reduce",
          "confidence": 0.78,
          "reasons": [
            {
              "signal": "HRV",
              "value": "below_baseline",
              "explanation": "HRV 低于 14 天基线，提示恢复压力偏高。"
            }
          ],
          "actions": [
            {
              "type": "adjust_workout",
              "label": "将今天训练容量降低 20%",
              "payload": {}
            }
          ],
          "followUpQuestion": "训练后是否感觉异常疲劳？"
        }
        """

        let artifact = try CoachArtifactParser.parse(json, sourceContextHash: "ctx-1")

        XCTAssertEqual(artifact.type, .morningBrief)
        XCTAssertEqual(artifact.decision, "reduce")
        XCTAssertEqual(artifact.confidence, 0.78, accuracy: 0.001)
        XCTAssertEqual(artifact.reasons.first?.signal, "HRV")
        XCTAssertEqual(artifact.actions.first?.type, "adjust_workout")
        XCTAssertEqual(artifact.sourceContextHash, "ctx-1")
    }

    func testCoachArtifactParserFallsBackWhenJSONIsInvalid() {
        let artifact = CoachArtifactParser.fallback(
            from: "今天数据不足，但建议先做轻量活动。",
            type: .askCoachAnswer,
            sourceContextHash: "ctx-fallback"
        )

        XCTAssertEqual(artifact.type, .askCoachAnswer)
        XCTAssertEqual(artifact.status, .created)
        XCTAssertEqual(artifact.sourceContextHash, "ctx-fallback")
        XCTAssertTrue(artifact.summary.contains("轻量活动"))
        XCTAssertEqual(artifact.actions.first?.type, "start_check_in")
    }

    func testAgentLoopRunsMultipleToolIterationsBeforeFinalAnswer() async throws {
        let provider = FakeAgentChatProvider(responses: [
            LLMResponse(
                content: "",
                toolCalls: [ToolCall(id: "call-1", name: "first_tool", arguments: #"{"step":1}"#)]
            ),
            LLMResponse(
                content: "",
                toolCalls: [ToolCall(id: "call-2", name: "second_tool", arguments: #"{"step":2}"#)]
            ),
            LLMResponse(content: "final answer", toolCalls: nil)
        ])
        let registry = ToolRegistry(tools: [
            StaticAgentTool(name: "first_tool", result: "first result"),
            StaticAgentTool(name: "second_tool", result: "second result")
        ])
        let loop = AgentLoop(provider: provider, toolRegistry: registry, maxIterations: 3)

        let result = try await loop.run(
            messages: [ChatMessage(role: .user, content: "run tools")],
            initialDataVersion: "canonical-snapshot-hash"
        )

        XCTAssertEqual(result.response, "final answer")
        XCTAssertEqual(result.executedTools.map(\.name), ["first_tool", "second_tool"])
        XCTAssertEqual(provider.chatCallToolAvailability, [true, true, true])
        XCTAssertEqual(result.finalMessages.filter { $0.role == .tool }.map(\.content), ["first result", "second result"])
        XCTAssertEqual(result.trace.executedTools.map(\.name), ["first_tool", "second_tool"])
        XCTAssertEqual(result.trace.finalResponse, "final answer")
        XCTAssertEqual(result.trace.contextHash, "canonical-snapshot-hash")
        XCTAssertEqual(result.trace.contextHashSource, "agent_fact_snapshot")
    }

    @MainActor
    func testHealthTrendToolNormalizesLegacyFourteenDayRequestToCanonicalThirtyDayWindow() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext
        let now = Date()
        context.insert(DailyHealthSummaryRecord(
            dayIdentifier: DailyHealthSummaryRecord.dayIdentifier(for: now),
            date: now,
            recoveryScore: 72,
            stressIndex: 38,
            currentEnergy: 64,
            hrvAverage: 51,
            restingHeartRate: 57,
            sleepHours: 7.4
        ))
        try context.save()

        let output = try await HealthTrendTool(
            executionContext: ToolExecutionContext(modelContext: context, dashboard: .preview(date: now))
        ).execute(arguments: #"{"days":14,"metrics":["hrv","rhr","sleep","recovery","stress","energy"]}"#)

        // 14d is not a published HealthTrendHorizon. Legacy callers are
        // normalized to the complete canonical 30d window instead of
        // returning a 14-point series labeled 30d.
        XCTAssertTrue(output.contains(#""days" : 30"#))
        XCTAssertTrue(output.contains(#""hrv" : 51"#))
        XCTAssertTrue(output.contains(#""recovery" : 72"#))
        XCTAssertTrue(output.contains(#""source" : "DailyHealthSummaryRecord""#))
        XCTAssertTrue(output.contains(#""context_hash" : null"#))
        XCTAssertTrue(output.contains(#""generated_at" : null"#))
        XCTAssertTrue(output.contains(#""as_of" : null"#))
    }

    @MainActor
    func testHealthTrendToolUsesRequestSnapshotFindingAndRecordPointsSeparately() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let generatedAt = now.addingTimeInterval(1_234)
        context.insert(DailyHealthSummaryRecord(
            dayIdentifier: DailyHealthSummaryRecord.dayIdentifier(for: now),
            date: now,
            recoveryScore: 72,
            hrvAverage: 51,
            restingHeartRate: 57,
            sleepHours: 7.4
        ))
        try context.save()

        // Deliberately disagree with the raw record. The tool must return this
        // canonical finding and must not invoke HealthTrendEngine again.
        var dashboard = DashboardSummary.preview(date: now)
        dashboard.healthTrends = [HealthTrendFinding(
            metric: .hrv,
            horizon: .thirtyDays,
            direction: .improving,
            valueDirection: .rising,
            assessment: .favorable,
            currentValue: 99,
            currentValueFormatted: "99 ms",
            baselineValue: 88,
            currentDeviationValue: 11,
            currentDeviationPercent: 12.5,
            temporalTrendDeltaPercent: 20,
            sampleCount: 30,
            requiredSampleCount: 14,
            summary: "canonical snapshot finding",
            isNotable: true
        )]
        let snapshot = AIContextBuilder().buildFacts(
            dashboard: dashboard,
            journalEntries: [],
            historicalReports: [],
            userWiki: [:],
            generatedAt: generatedAt
        ).snapshot

        let output = try await HealthTrendTool(
            executionContext: ToolExecutionContext(
                modelContext: context,
                dashboard: dashboard,
                agentFactSnapshot: snapshot
            )
        ).execute(arguments: #"{"days":30,"metrics":["hrv"]}"#)

        XCTAssertTrue(output.contains("canonical snapshot finding"))
        XCTAssertTrue(output.contains(#""latestValue" : 99"#))
        XCTAssertTrue(output.contains(#""hrv" : 51"#), "points remain sourced from raw DailyHealthSummaryRecord")
        XCTAssertTrue(output.contains(#""finding_source" : "AgentFactSnapshot""#))
        XCTAssertTrue(output.contains(snapshot.contextHash))
        XCTAssertTrue(output.contains(ISO8601DateFormatter().string(from: generatedAt)))
    }

    @MainActor
    func testHealthTrendToolMalformedArgumentsDefaultToCanonicalThirtyDayWindow() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let now = Date()
        let output = try await HealthTrendTool(
            executionContext: ToolExecutionContext(modelContext: container.mainContext, dashboard: .preview(date: now))
        ).execute(arguments: "not-json")

        XCTAssertTrue(output.contains(#""days" : 30"#))
    }

    @MainActor
    func testHealthTrendToolEmptyArgumentsDefaultToCanonicalThirtyDayWindow() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let now = Date()
        let output = try await HealthTrendTool(
            executionContext: ToolExecutionContext(modelContext: container.mainContext, dashboard: .preview(date: now))
        ).execute(arguments: "")

        XCTAssertTrue(output.contains(#""days" : 30"#))
    }

    @MainActor
    func testTrainingResponseHistoryToolReturnsRecoveryDeltasAndFlags() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext
        let now = Date()
        context.insert(TrainingResponseRecord(
            workoutId: UUID(),
            date: now.addingTimeInterval(-86_400),
            nextDayDate: now,
            primaryMuscleGroups: ["legs"],
            totalEffectiveSets: 12,
            totalVolumeKg: 8_400,
            sessionRPE: 8,
            nextDayRecoveryDelta: -11,
            nextDayHRVDelta: -13,
            nextDayRHRDelta: 6
        ))
        try context.save()

        let output = try await TrainingResponseHistoryTool(
            executionContext: ToolExecutionContext(modelContext: context, dashboard: .preview(date: now))
        ).execute(arguments: #"{"days":28,"muscle_group":"legs"}"#)

        XCTAssertTrue(output.contains(#""next_day_recovery_delta" : -11"#))
        XCTAssertTrue(output.contains(#""primary_muscle_groups" : ["#))
        XCTAssertTrue(output.contains(#""flagged" : true"#))
    }

    func testAgentLoopRequestsFinalAnswerWhenLastAllowedIterationStillUsesTool() async throws {
        let provider = FakeAgentChatProvider(responses: [
            LLMResponse(
                content: "",
                toolCalls: [ToolCall(id: "call-1", name: "first_tool", arguments: "{}")]
            ),
            LLMResponse(
                content: "",
                toolCalls: [ToolCall(id: "call-2", name: "second_tool", arguments: "{}")]
            ),
            LLMResponse(content: "final after tools", toolCalls: nil)
        ])
        let registry = ToolRegistry(tools: [
            StaticAgentTool(name: "first_tool", result: "first result"),
            StaticAgentTool(name: "second_tool", result: "second result")
        ])
        let loop = AgentLoop(provider: provider, toolRegistry: registry, maxIterations: 2)

        let result = try await loop.run(messages: [ChatMessage(role: .user, content: "run bounded tools")])

        XCTAssertEqual(result.response, "final after tools")
        XCTAssertEqual(result.executedTools.map(\.name), ["first_tool", "second_tool"])
        XCTAssertEqual(provider.chatCallToolAvailability, [true, true, false])
    }

    @MainActor
    func testAgentLoopPublishesExistingFinalResponseWithoutDuplicateStreamingRequest() async throws {
        let provider = FakeAgentChatProvider(
            responses: [
                LLMResponse(
                    content: "",
                    toolCalls: [ToolCall(id: "call-1", name: "first_tool", arguments: "{}")]
                ),
                LLMResponse(content: "non-stream final", toolCalls: nil)
            ],
            streamChunks: ["stream ", "final"]
        )
        let registry = ToolRegistry(tools: [
            StaticAgentTool(name: "first_tool", result: "first result")
        ])
        let loop = AgentLoop(provider: provider, toolRegistry: registry, maxIterations: 3)
        var streamed = ""

        let result = try await loop.run(
            messages: [ChatMessage(role: .user, content: "run tool then stream")],
            onStreamDelta: { streamed += $0 }
        )

        XCTAssertEqual(result.response, "non-stream final")
        XCTAssertEqual(streamed, "non-stream final")
        XCTAssertEqual(result.executedTools.map(\.name), ["first_tool"])
        XCTAssertEqual(provider.streamCallCount, 0)
        XCTAssertEqual(provider.chatCallToolAvailability, [true, true])
        XCTAssertEqual(result.trace.providerCallCount, 2)
    }

    func testProviderFailureMessageClassifiesOfflineTimeoutAndAuthentication() {
        XCTAssertEqual(
            LLMProviderError.classify(URLError(.notConnectedToInternet)),
            .networkUnavailable
        )
        XCTAssertEqual(
            LLMProviderError.classify(URLError(.timedOut)),
            .timedOut
        )
        XCTAssertEqual(
            LLMProviderError.httpFailure(statusCode: 401, body: "invalid key"),
            .authenticationFailed
        )
        XCTAssertTrue(LLMProviderError.networkUnavailable.userFacingMessage(isChinese: true).contains("网络"))
        XCTAssertTrue(LLMProviderError.authenticationFailed.userFacingMessage(isChinese: false).contains("Settings"))
    }

    func testRetryingAgentChatProviderRetriesTransientFailures() async throws {
        let base = ScriptedAgentChatProvider(steps: [
            .failure(LLMProviderError.timedOut),
            .failure(LLMProviderError.networkUnavailable),
            .success(LLMResponse(content: "recovered", toolCalls: nil))
        ])
        let provider = RetryingAgentChatProvider(
            base: base,
            maxAttempts: 3,
            initialDelayNanoseconds: 0,
            sleeper: { _ in }
        )

        let response = try await provider.chat(
            messages: [ChatMessage(role: .user, content: "coach me")],
            tools: nil
        )

        XCTAssertEqual(response.content, "recovered")
        XCTAssertEqual(base.chatCallCount, 3)
    }

    func testRetryingAgentChatProviderDoesNotRetryAuthenticationFailures() async throws {
        let base = ScriptedAgentChatProvider(steps: [
            .failure(LLMProviderError.authenticationFailed),
            .success(LLMResponse(content: "should not be used", toolCalls: nil))
        ])
        let provider = RetryingAgentChatProvider(
            base: base,
            maxAttempts: 3,
            initialDelayNanoseconds: 0,
            sleeper: { _ in }
        )

        do {
            _ = try await provider.chat(
                messages: [ChatMessage(role: .user, content: "coach me")],
                tools: nil
            )
            XCTFail("Authentication errors must not be retried.")
        } catch {
            XCTAssertEqual(error as? LLMProviderError, .authenticationFailed)
            XCTAssertEqual(base.chatCallCount, 1)
        }
    }

    func testAgentLoopRetryDoesNotReplaySuccessfulWriteTool() async throws {
        let writeTool = CountingAgentTool(
            name: "create_training_plan",
            result: #"{"status":"saved","idempotency_key":"plan-1"}"#
        )
        let base = ScriptedAgentChatProvider(steps: [
            .success(LLMResponse(
                content: "",
                toolCalls: [ToolCall(
                    id: "call-1",
                    name: "create_training_plan",
                    arguments: #"{"title":"4 week plan","idempotency_key":"plan-1"}"#
                )]
            )),
            .failure(LLMProviderError.timedOut),
            .success(LLMResponse(content: "plan saved", toolCalls: nil))
        ])
        let provider = RetryingAgentChatProvider(
            base: base,
            maxAttempts: 2,
            initialDelayNanoseconds: 0,
            sleeper: { _ in }
        )
        let loop = AgentLoop(
            provider: provider,
            toolRegistry: ToolRegistry(tools: [writeTool]),
            maxIterations: 2
        )

        let result = try await loop.run(messages: [ChatMessage(role: .user, content: "make a plan")])

        XCTAssertEqual(result.response, "plan saved")
        XCTAssertEqual(result.executedTools.map(\.name), ["create_training_plan"])
        XCTAssertEqual(writeTool.executionCount, 1)
        XCTAssertEqual(base.chatCallCount, 3)
    }

    func testProviderErrorRecoveryRoutesAuthenticationToSettingsAndTransientErrorsToRetry() {
        let auth = LLMProviderError.authenticationFailed.recoveryAction(isChinese: true)
        XCTAssertEqual(auth.destination, .settings)
        XCTAssertTrue(auth.title.contains("设置"))

        let timeout = LLMProviderError.timedOut.recoveryAction(isChinese: true)
        XCTAssertEqual(timeout.destination, .retry)
        XCTAssertTrue(timeout.title.contains("重试"))
    }

    @MainActor
    func testUnifiedWorkoutHistoryToolReturnsMergedWorkoutTimeline() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(-3600)
        let strength = StrengthWorkoutRecord(
            title: "背部二头",
            startedAt: start,
            durationMinutes: 60,
            exercises: [
                StrengthExerciseLog(
                    name: "杠铃划船",
                    equipment: "barbell",
                    primaryMuscleGroup: "back",
                    sets: [StrengthSetLog(repetitions: 8, weightKilograms: 80, isCompleted: true)]
                )
            ]
        )
        context.insert(strength)
        context.insert(WorkoutEventRecord(
            source: "healthKit+xunji",
            startedAt: start,
            endedAt: start.addingTimeInterval(3600),
            activityType: "TraditionalStrengthTraining",
            title: "背部二头",
            energyKilocalories: 420,
            averageHeartRate: 132,
            linkedStrengthWorkoutId: strength.id,
            linkedHealthKitWorkoutId: UUID()
        ))
        try context.save()

        let tool = UnifiedWorkoutHistoryTool(
            executionContext: ToolExecutionContext(modelContext: context, dashboard: .preview())
        )
        let output = try await tool.execute(arguments: #"{"days":7,"include_strength_details":true}"#)

        XCTAssertTrue(output.contains("healthKit+xunji"))
        XCTAssertTrue(output.contains("背部二头"))
        XCTAssertTrue(output.contains("杠铃划船"))
        XCTAssertTrue(output.contains("strength_details"))
    }

    @MainActor
    func testUnifiedWorkoutHistoryToolSeparatesCompletedAndUncompletedStrengthSets() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext
        let start = Date().addingTimeInterval(-3600)
        let strength = StrengthWorkoutRecord(
            title: "胸部训练",
            startedAt: start,
            durationMinutes: 50,
            exercises: [
                StrengthExerciseLog(
                    name: "杠铃卧推",
                    equipment: "barbell",
                    primaryMuscleGroup: "chest",
                    sets: [
                        StrengthSetLog(repetitions: 8, weightKilograms: 80, isCompleted: true),
                        StrengthSetLog(repetitions: 8, weightKilograms: 90, isCompleted: false),
                        StrengthSetLog(repetitions: 5, weightKilograms: 60, isWarmup: true, isCompleted: true)
                    ]
                )
            ]
        )
        context.insert(strength)
        context.insert(WorkoutEventRecord(
            source: "healthKit+xunji",
            startedAt: start,
            endedAt: start.addingTimeInterval(3000),
            activityType: "TraditionalStrengthTraining",
            title: "胸部训练",
            linkedStrengthWorkoutId: strength.id,
            linkedHealthKitWorkoutId: UUID()
        ))
        try context.save()

        let tool = UnifiedWorkoutHistoryTool(
            executionContext: ToolExecutionContext(modelContext: context, dashboard: .preview())
        )
        let output = try await tool.execute(arguments: #"{"days":7,"include_strength_details":true}"#)

        XCTAssertTrue(output.contains(#""completed_work_sets" : 1"#))
        XCTAssertTrue(output.contains(#""completed_volume_kilograms" : 640"#))
        XCTAssertTrue(output.contains(#""uncompleted_sets" : ["#))
        XCTAssertTrue(output.contains(#""weight_kilograms" : 90"#))
        XCTAssertTrue(output.contains(#""warmup_sets" : ["#))
    }

    @MainActor
    func testHealthHistoryToolReturnsDailyBodyMetrics() async throws {
        let container = try VelaModelContainer.make(inMemory: true)
        let context = container.mainContext
        context.insert(DailyHealthSummaryRecord(
            dayIdentifier: DailyHealthSummaryRecord.dayIdentifier(for: Date()),
            date: Date(),
            sleepScore: 82,
            recoveryScore: 74,
            strainScore: 41,
            hrvAverage: 52,
            restingHeartRate: 58,
            sleepHours: 7.3,
            bodyWeight: 76.5,
            oxygenSaturation: 98,
            dailyLoad: 88,
            tsb: -4
        ))
        try context.save()

        let tool = HealthHistoryTool(
            executionContext: ToolExecutionContext(modelContext: context, dashboard: .preview())
        )
        let output = try await tool.execute(arguments: #"{"days":7}"#)

        XCTAssertTrue(output.contains(#""recovery_score" : 74"#))
        XCTAssertTrue(output.contains(#""hrv_average" : 52"#))
        XCTAssertTrue(output.contains(#""body_weight" : 76.5"#))
        XCTAssertTrue(output.contains(#""daily_load" : 88"#))
    }

    func testCoachPromptPinsTrainingAdviceToCanonicalDecisionAndMissingDataRules() {
        let composer = CoachPromptComposer(
            lang: .english,
            personality: .guardian,
            wikiText: "",
            baselinePrompt: "",
            activePlan: nil,
            contextJSON: #"{"body_state":{"confidence":"low"},"training_decision":{"decision":"reduce","source":"TrainingDecisionKernel"}}"#,
            correlationText: "",
            wikiFiles: "profile.md"
        )

        let prompt = composer.compose(for: ResponseLengthPolicy.focused)

        XCTAssertTrue(prompt.contains("TrainingDecisionKernel"))
        XCTAssertTrue(prompt.contains("DailyOperatingPlanPayload"))
        XCTAssertTrue(prompt.contains("Do not apply cross-diagnosis patterns unless every required input field is present"))
        XCTAssertTrue(prompt.contains("Missing or unavailable data is not normal data"))
    }

    func testChineseCoachPromptIncludesEvidenceBoundariesBeforeScientificPatterns() {
        let prompt = CoachPromptComposer(
            lang: .simplifiedChinese,
            personality: .guardian,
            wikiText: "",
            baselinePrompt: "",
            activePlan: nil,
            contextJSON: #"{"body_state":{"confidence":"unavailable"}}"#,
            correlationText: "",
            wikiFiles: "profile.md"
        ).compose(for: .full)

        XCTAssertTrue(prompt.contains("TrainingDecisionKernel"))
        XCTAssertTrue(prompt.contains("DailyOperatingPlanPayload"))
        XCTAssertTrue(prompt.contains("缺失或不可用的数据不是正常数据"))
        XCTAssertTrue(prompt.contains("只有当所需字段全部存在"))
    }

    func testCoachPromptHonorsMetricEntryFocus() {
        let focus = CoachContextFocus(
            title: "HRV 详情",
            systemContext: "优先解释 HRV 的近期变化、个人基线和数据置信度。"
        )
        let prompt = CoachPromptComposer(
            lang: .simplifiedChinese,
            personality: .guardian,
            focus: focus,
            wikiText: "",
            baselinePrompt: "",
            activePlan: nil,
            contextJSON: "{}",
            correlationText: "",
            wikiFiles: "profile.md"
        ).compose(for: .focused)

        XCTAssertTrue(prompt.contains("## 当前专项上下文"))
        XCTAssertTrue(prompt.contains("入口：HRV 详情"))
        XCTAssertTrue(prompt.contains("优先解释 HRV 的近期变化、个人基线和数据置信度"))
        XCTAssertTrue(prompt.contains(#""surface":"coach""#))
    }
}

private final class FakeAgentChatProvider: AgentChatProvider, @unchecked Sendable {
    private var responses: [LLMResponse]
    private let streamChunks: [String]

    private(set) var chatCallToolAvailability: [Bool] = []
    private(set) var streamCallCount: Int = 0

    init(responses: [LLMResponse], streamChunks: [String] = []) {
        self.responses = responses
        self.streamChunks = streamChunks
    }

    func chat(messages: [ChatMessage], tools: [[String: Value]]?) async throws -> LLMResponse {
        chatCallToolAvailability.append(tools?.isEmpty == false)
        guard !responses.isEmpty else {
            return LLMResponse(content: "", toolCalls: nil)
        }
        return responses.removeFirst()
    }

    func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        streamCallCount += 1
        let chunks = streamChunks

        return AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
    }
}

private enum AgentProviderScriptStep {
    case success(LLMResponse)
    case failure(Error)
}

private final class ScriptedAgentChatProvider: AgentChatProvider, @unchecked Sendable {
    private var steps: [AgentProviderScriptStep]
    private let lock = NSLock()
    private var _chatCallCount: Int = 0

    var chatCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _chatCallCount
    }

    init(steps: [AgentProviderScriptStep]) {
        self.steps = steps
    }

    func chat(messages: [ChatMessage], tools: [[String: Value]]?) async throws -> LLMResponse {
        let step = nextStep()

        switch step {
        case .success(let response):
            return response
        case .failure(let error):
            throw error
        case .none:
            return LLMResponse(content: "", toolCalls: nil)
        }
    }

    private func nextStep() -> AgentProviderScriptStep? {
        lock.lock()
        defer { lock.unlock() }
        _chatCallCount += 1
        return steps.isEmpty ? nil : steps.removeFirst()
    }

    func streamChat(messages: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private struct StaticAgentTool: AgentTool {
    let name: String
    let result: String
    let description = "Static test tool."
    let parameters: [String: Value] = ["type": .string("object")]

    func execute(arguments: String) async throws -> String {
        result
    }
}

private final class CountingAgentTool: AgentTool, @unchecked Sendable {
    let name: String
    let result: String
    let riskLevel: ToolRiskLevel
    let description = "Counting test tool."
    let parameters: [String: Value] = ["type": .string("object")]

    private let lock = NSLock()
    private var count = 0

    var executionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    init(name: String, result: String, riskLevel: ToolRiskLevel = .read) {
        self.name = name
        self.result = result
        self.riskLevel = riskLevel
    }

    func execute(arguments: String) async throws -> String {
        recordExecution()
        return result
    }

    private func recordExecution() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

// MARK: - Safety and Safeguards Tests
final class AgentLoopSafetyTests: XCTestCase {
    func testSemanticallyIdenticalJSONToolCallsExecuteOnlyOnce() async throws {
        let readTool = CountingAgentTool(name: "read_metric", result: "ok")
        let provider = ScriptedAgentChatProvider(steps: [
            .success(LLMResponse(
                content: "",
                toolCalls: [
                    ToolCall(id: "call-1", name: "read_metric", arguments: #"{"day":1,"metric":"hrv"}"#),
                    ToolCall(id: "call-2", name: "read_metric", arguments: #"{"metric":"hrv","day":1}"#)
                ]
            )),
            .success(LLMResponse(content: "done", toolCalls: nil))
        ])

        let result = try await AgentLoop(
            provider: provider,
            toolRegistry: ToolRegistry(tools: [readTool]),
            maxIterations: 2
        ).run(messages: [ChatMessage(role: .user, content: "read it")])

        XCTAssertEqual(readTool.executionCount, 1)
        XCTAssertTrue(result.finalMessages.contains { $0.content.contains("DUPLICATE DETECTED") })
    }

    func testUnknownToolIsBlockedByAllowlistBeforeExecution() async throws {
        let provider = ScriptedAgentChatProvider(steps: [
            .success(LLMResponse(
                content: "",
                toolCalls: [ToolCall(id: "call-1", name: "erase_everything", arguments: "{}")]
            )),
            .success(LLMResponse(content: "blocked", toolCalls: nil))
        ])

        let result = try await AgentLoop(
            provider: provider,
            toolRegistry: ToolRegistry(tools: []),
            maxIterations: 2
        ).run(messages: [ChatMessage(role: .user, content: "do it")])

        XCTAssertEqual(result.executedTools.count, 1)
        XCTAssertTrue(result.executedTools[0].result.contains("not in this session's allowlist"))
    }

    func testHealthToolAuditTraceRedactsShortSensitiveResult() async throws {
        let tool = CountingAgentTool(name: "get_today_health", result: "sleep score 88, recovery 76")
        let provider = ScriptedAgentChatProvider(steps: [
            .success(LLMResponse(
                content: "",
                toolCalls: [ToolCall(id: "call-1", name: "get_today_health", arguments: #"{"date":"2026-08-01"}"#)]
            )),
            .success(LLMResponse(content: "done", toolCalls: nil))
        ])

        let result = try await AgentLoop(
            provider: provider,
            toolRegistry: ToolRegistry(tools: [tool]),
            maxIterations: 2
        ).run(messages: [ChatMessage(role: .user, content: "today")])

        XCTAssertFalse(result.trace.executedTools[0].result.contains("88"))
        XCTAssertTrue(result.trace.executedTools[0].result.contains("REDACTED"))
        XCTAssertTrue(result.trace.executedTools[0].arguments.contains("REDACTED"))
    }

    func testWriteToolRequiresConfirmationRejected() async throws {
        let writeTool = CountingAgentTool(
            name: "create_training_plan",
            result: #"{"status":"saved"}"#,
            riskLevel: .write
        )
        let base = ScriptedAgentChatProvider(steps: [
            .success(LLMResponse(
                content: "",
                toolCalls: [ToolCall(
                    id: "call-1",
                    name: "create_training_plan",
                    arguments: #"{"title":"4 week plan"}"#
                )]
            )),
            .success(LLMResponse(content: "user rejected it", toolCalls: nil))
        ])
        
        let loop = AgentLoop(
            provider: base,
            toolRegistry: ToolRegistry(tools: [writeTool]),
            maxIterations: 2,
            onConfirmToolCall: { _ in false }
        )
        
        let result = try await loop.run(messages: [ChatMessage(role: .user, content: "make a plan")])
        XCTAssertEqual(writeTool.executionCount, 0)
        XCTAssertTrue(result.finalMessages.contains { $0.role == .tool && $0.content.contains("User rejected") })
    }

    func testWriteToolRequiresConfirmationAccepted() async throws {
        let writeTool = CountingAgentTool(
            name: "create_training_plan",
            result: #"{"status":"saved"}"#,
            riskLevel: .write
        )
        let base = ScriptedAgentChatProvider(steps: [
            .success(LLMResponse(
                content: "",
                toolCalls: [ToolCall(
                    id: "call-1",
                    name: "create_training_plan",
                    arguments: #"{"title":"4 week plan"}"#
                )]
            )),
            .success(LLMResponse(content: "plan saved", toolCalls: nil))
        ])
        
        let loop = AgentLoop(
            provider: base,
            toolRegistry: ToolRegistry(tools: [writeTool]),
            maxIterations: 2,
            onConfirmToolCall: { _ in true }
        )
        
        let result = try await loop.run(messages: [ChatMessage(role: .user, content: "make a plan")])
        XCTAssertEqual(writeTool.executionCount, 1)
        XCTAssertTrue(result.finalMessages.contains { $0.role == .tool && $0.content.contains("saved") })
    }

    func testDeepSeekStreamReadsFinishReasonLength() {
        let payload = #"{"choices":[{"index":0,"delta":{"content":"尾"},"finish_reason":"length"}]}"#
        XCTAssertEqual(DeepSeekStreamSignals.finishReason(inJSON: Data(payload.utf8)), "length")
        XCTAssertEqual(
            DeepSeekStreamCompletion.resolve(didReceiveDone: true, finishReason: "length"),
            .truncated
        )
        XCTAssertEqual(
            DeepSeekStreamCompletion.resolve(didReceiveDone: false, finishReason: "stop"),
            .complete
        )
        XCTAssertEqual(
            DeepSeekStreamCompletion.resolve(didReceiveDone: false, finishReason: nil),
            .incomplete
        )
    }
}
