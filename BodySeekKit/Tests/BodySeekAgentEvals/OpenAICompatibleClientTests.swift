@testable import BodySeekAgent
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

    func allCapturedRequests() -> [URLRequest] {
        capturedRequests
    }

    func lastRequest() -> URLRequest? {
        capturedRequests.last
    }
}

final class OpenAICompatibleClientTests: XCTestCase {
    func testAdditionalNutrientEstimatesValidateUnitsKeysAndDrinkingWater() throws {
        let parsed = try MealDraftAnalysis.decode("""
            {"items":[
                {"name":"豆腐","amount":150,"unit":"g","nutrients":{
                    "diet_minerals::钙":[120,"mg"], "diet_vitamins::B12":[0.0012,"mg"],
                    "diet_fiber_g":[2,"mg"], "diet_ala_mg":[0.4,"g"], "diet_minerals::铁":[170000,"mg"],
                    "diet_vitamins::A":[30,"μg"], "diet_minerals::锌":[0,"mg"]}},
                {"name":"白水","amount":1,"unit":"L","nutrients":{"diet_water_ml":[1000,"mL"]}},
                {"name":"桑葚汁","amount":1,"unit":"L","nutrients":{"diet_water_ml":[1000,"mL"]}}
            ]}
            """)
        let estimates = try XCTUnwrap(parsed[0].additionalEstimates)
        XCTAssertEqual(estimates["diet_minerals::钙"], 120)
        XCTAssertEqual(try XCTUnwrap(estimates["diet_vitamins::B12"]), 1.2, accuracy: 0.0001)
        XCTAssertEqual(estimates.count, 2)
        XCTAssertEqual(parsed[1].additionalEstimates?["diet_water_ml"], 1_000)
        XCTAssertNil(parsed[2].additionalEstimates)
    }

    func testMealDraftAcceptsMacroEstimatesAndRejectsImplausibleMass() throws {
        let entries = try MealDraftAnalysis.decode("""
            {"items":[
              {"name":"家常菜","amount":200,"unit":"g","macroEstimate":{"proteinG":25,"carbsG":30,"fatG":12}},
              {"name":"其他菜","amount":100,"unit":"g","macroEstimate":{"proteinG":95,"carbsG":95,"fatG":20}}
            ]}
            """)
        XCTAssertEqual(entries[0].macroEstimate?.proteinG, 25)
        XCTAssertEqual(entries[0].macroEstimate?.fatG, 12)
        XCTAssertNil(entries[1].macroEstimate)
    }

    func testMealDraftRejectsPartiallyUnreadableReply() {
        XCTAssertThrowsError(try MealDraftAnalysis.decode(
            #"{"items":[{"name":"水煮蛋","meal":"breakfast"},{"meal":"dinner"}]}"#
        ))
    }

    func testCoachIncludesBoundedPriorTurns() {
        let snapshot = sampleContext().snapshot
        let history = (0..<10).map {
            CoachMessage(role: $0.isMultiple(of: 2) ? .user : .assistant, text: "消息 \($0)")
        }
        let turns = CoachAgentOrchestrator.conversationTurns(.init(snapshot: snapshot, conversationHistory: history))
        XCTAssertEqual(turns.count, 6)
        XCTAssertEqual(turns.first?.content, "消息 4")
        XCTAssertEqual(turns.last?.role, "assistant")
    }

    func testNutritionToolRetainsRangeAndMissingEntries() async {
        let snapshot = sampleContext().snapshot
        let day = snapshot.referenceDate.physiologicalDayKey()
        var hotpot = MealEntry(dayKey: day, mealType: .dinner, foodName: "火锅", portionAmount: nil, portionUnit: "g", kcal: 700)
        hotpot.energyEstimate = MealEnergyEstimate(lowerKcal: 400, upperKcal: 1_000, assumptions: "份量未知")
        let egg = MealEntry(dayKey: day, mealType: .breakfast, foodName: "鸡蛋", portionAmount: 100, portionUnit: "g", kcal: 134)
        let unknown = MealEntry(dayKey: day, mealType: .snack, foodName: "果汁", portionAmount: nil, portionUnit: "mL")
        var log = DailyNutritionLog(dayKey: day, entries: [hotpot, egg, unknown])
        log.recalculateTotals()
        let json = await CoachToolRegistry.execute(name: "get_eating_context", argumentsJSON: "{}",
                                                    context: .init(snapshot: snapshot, nutritionLogs: [log]))
        XCTAssertTrue(json.contains(#""estimatedLowerKcal":534"#), json)
        XCTAssertTrue(json.contains(#""estimatedUpperKcal":1134"#), json)
        XCTAssertTrue(json.contains(#""missingEntryCount":1"#), json)
    }

    func testHistoricalSleepAndSimilarDaysDoNotSubstituteLatestDate() async {
        for tool in ["get_sleep_detail", "find_similar_days"] {
            let json = await CoachToolRegistry.execute(name: tool, argumentsJSON: #"{"date":"2000-01-01","day":"2000-01-01"}"#,
                                                        context: sampleContext())
            XCTAssertTrue(json.contains(#""state":"missing""#), json)
            XCTAssertTrue(json.contains("2000-01-01"), json)
        }
    }

    func testMealDraftSurvivesUnexpectedOptionalFields() throws {
        let items = try MealDraftAnalysis.decode("""
        ```json
        {"items":[{"name":"水煮蛋","meal":"早餐","amount":"100","unit":"克"},
        {"name":"火锅","meal":"晚餐","amount":"未知","energyEstimate":{"lowerKcal":"约500","upperKcal":900}},
        {"name":"桑葚混合果汁","meal":"dinner","amount":1,"unit":"L",
         "energyEstimate":{"lowerKcal":"250","upperKcal":"500","assumptions":"按一升果汁估算"}}]}
        ```
        """)
        XCTAssertEqual(items.map(\.meal), [.breakfast, .dinner, .dinner])
        XCTAssertEqual(items.map(\.amount), [100, nil, 1000])
        XCTAssertNil(items[1].energyEstimate)
        XCTAssertEqual(items[2].energyEstimate?.midpointKcal, 375)
    }

    func testMealRequestRetriesAfterTruncatedOutput() async throws {
        let transport = MockAgentTransport(steps: [
            .data(statusCode: 200, body: #"{"choices":[{"finish_reason":"length","message":{"role":"assistant","content":null}}]}"#),
            .data(statusCode: 200, body: #"{"choices":[{"message":{"role":"assistant","content":"{\"items\":[{\"name\":\"火锅\",\"meal\":\"dinner\"}]}"}}]}"#),
        ])
        let client = OpenAICompatibleClient(transport: transport)
        let items = try await client.analyzeMeal(endpointURL: "https://api.example.com/v1", apiKey: "mock",
                                                modelName: "mock", input: "晚上吃了火锅", jpeg: nil)
        XCTAssertEqual(items.first?.name, "火锅")
        let requestCount = await transport.recordedRequestCount()
        XCTAssertEqual(requestCount, 2)
        let requests = await transport.capturedRequests
        XCTAssertEqual(requests.first?.timeoutInterval, 120)
        let retryBody = try XCTUnwrap(requests.last?.httpBody)
        let retryPayload = try XCTUnwrap(JSONSerialization.jsonObject(with: retryBody) as? [String: Any])
        let retryMessages = try XCTUnwrap(retryPayload["messages"] as? [[String: Any]])
        XCTAssertTrue((retryMessages.first?["content"] as? String)?.contains("不要输出 nutrients") == true)
    }

    func testMealAnalysisTimeoutIsNotRetried() async throws {
        let transport = MockAgentTransport(steps: [
            .error(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)),
            .data(statusCode: 200, body: #"{"choices":[{"message":{"role":"assistant","content":"{\"items\":[{\"name\":\"米饭\"}]}"}}]}"#),
        ])
        let client = OpenAICompatibleClient(transport: transport)
        do {
            _ = try await client.analyzeMeal(
                endpointURL: "https://api.example.com/v1",
                apiKey: "mock",
                modelName: "mock",
                input: "午饭吃了米饭",
                jpeg: nil
            )
            XCTFail("expected timeout to surface")
        } catch let error as MealDraftAnalysisError {
            XCTAssertEqual(error, .serviceUnavailable)
        }
        let requestCount = await transport.recordedRequestCount()
        XCTAssertEqual(requestCount, 1, "a timed-out meal generation must not be retried")
    }

    func testMealDraftSupportsScenarioEstimatesWithoutWeightAndRejectsInvalidRanges() throws {
        let items = try MealDraftAnalysis.decode("""
            {"items":[
              {"name":"火锅","meal":"dinner","reportedPortion":"人均120元","energyEstimate":{"lowerKcal":550,"upperKcal":1050,"assumptions":"按个人夹取食材和蘸料估算，饮品另计"}},
              {"name":"混合果汁","meal":"dinner","amount":1000,"unit":"mL","energyEstimate":{"lowerKcal":250,"upperKcal":550,"assumptions":"按每100mL 25–55 kcal估算"}},
              {"name":"其他饮品","energyEstimate":{"lowerKcal":300,"upperKcal":100,"assumptions":"无效区间"}}
            ]}
            """)
        XCTAssertNil(items[0].amount)
        XCTAssertEqual(items[0].reportedPortion, "人均120元")
        XCTAssertEqual(items[0].energyEstimate?.midpointKcal, 800)
        XCTAssertEqual(items[1].amount, 1000)
        XCTAssertEqual(items[1].energyEstimate?.upperKcal, 550)
        XCTAssertNil(items[2].energyEstimate)
    }

    func testAllDayMealDraftKeepsMealsAndUnscaledPortionDescriptions() async throws {
        let input = "下午吃了脆皮鸡腿和一包薯条，晚上吃火锅人均120，还喝了1升少甜桑葚混合果汁。早上两个水煮蛋、两勺燕麦和一包豆浆粉。上午一杯胶囊黑咖啡，下午四份单份浓缩。"
        let reply = """
            {"items":[
              {"name":"水煮蛋","meal":"breakfast","reportedPortion":"两个","amount":100,"unit":"g","isEstimatedPortion":true},
              {"name":"燕麦","meal":"breakfast","reportedPortion":"两勺","amount":20,"unit":"g","isEstimatedPortion":true},
              {"name":"豆浆粉","meal":"breakfast","reportedPortion":"一包","amount":null},
              {"name":"脆皮鸡腿","meal":"lunch","catalogSearchName":" 炸鸡腿 ","amount":null},
              {"name":"薯条","meal":"lunch","reportedPortion":"一包","amount":null},
              {"name":"火锅","meal":"dinner","reportedPortion":"人均120元","amount":null},
              {"name":"少甜桑葚混合果汁","meal":"dinner","reportedPortion":"1升","amount":1000,"unit":"mL","isEstimatedPortion":false},
              {"name":"胶囊黑咖啡","meal":"snack","reportedPortion":"一杯","amount":null},
              {"name":"浓缩咖啡","meal":"snack","reportedPortion":"四份单份浓缩","amount":null}
            ]}
            """
        let envelope = try JSONSerialization.data(withJSONObject: ["choices": [["message": ["role": "assistant", "content": reply]]]])
        let mock = MockAgentTransport(steps: [.data(statusCode: 200, body: String(decoding: envelope, as: UTF8.self))])
        let client = OpenAICompatibleClient(transport: mock, payloadRecorder: AgentPayloadRecorder())
        let decoded = try await client.analyzeMeal(endpointURL: "https://api.example.com/v1", apiKey: "test",
                                                   modelName: "test-model", input: input, jpeg: nil)
        XCTAssertEqual(decoded.map(\.meal), [.breakfast, .breakfast, .breakfast, .lunch, .lunch, .dinner, .dinner, .snack, .snack])
        XCTAssertTrue(decoded[0].isEstimatedPortion == true)
        XCTAssertEqual(decoded[3].catalogSearchName, "炸鸡腿")
        XCTAssertNil(decoded[5].amount)
        XCTAssertEqual(decoded[5].reportedPortion, "人均120元")
        XCTAssertEqual(decoded[6].amount, 1000)
        XCTAssertEqual(decoded[6].unit, "ml")
        XCTAssertEqual(decoded[7].reportedPortion, "一杯")
        XCTAssertEqual(decoded[8].reportedPortion, "四份单份浓缩")
        let request = await mock.lastRequest()
        let body = try XCTUnwrap(request?.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.last?["content"] as? String, input)
    }

    func testWorkoutAnnotationBindsToTheRequestedDay() async {
        let day = DayKey(year: 2026, month: 11, day: 20)
        let now = day.startDate().addingTimeInterval(12 * 3600)
        let snapshot = sampleContext(referenceDate: now.addingTimeInterval(-7_200)).snapshot
        let start = now.addingTimeInterval(-3600)
        let chest = StoredWorkoutRecord(hkUUID: "chest-today", type: "力量训练", start: start,
                                         end: start.addingTimeInterval(1800), energy: 180)
        let legs = StoredWorkoutRecord(hkUUID: "legs-yesterday", type: "力量训练",
                                        start: start.addingTimeInterval(-86_400),
                                        end: start.addingTimeInterval(-84_600), energy: 260)
        let mismatch = AgentExecutionContext(snapshot: snapshot, storedWorkouts: [legs, chest], asOf: now)
        _ = await CoachToolRegistry.execute(name: "propose_workout_annotation",
            argumentsJSON: #"{"rawText":"今天练胸","workoutUUID":"legs-yesterday"}"#, context: mismatch)
        let rejected = await mismatch.effects.workoutAnnotationProposal
        XCTAssertNil(rejected)

        let correct = AgentExecutionContext(snapshot: snapshot, storedWorkouts: [legs, chest], asOf: now)
        _ = await CoachToolRegistry.execute(name: "propose_workout_annotation",
            argumentsJSON: #"{"rawText":"今天练胸"}"#, context: correct)
        let proposed = await correct.effects.workoutAnnotationProposal
        XCTAssertEqual(proposed?.workoutUUID, chest.hkUUID)
        XCTAssertTrue(proposed?.muscleLoads.contains(where: { $0.muscle == .chest }) == true)
    }

    func testNutritionEvaluationSeparatesEstimatedFromConfirmed() throws {
        let day = DayKey(year: 2026, month: 11, day: 20)
        let plan = NutritionTargetPlan(
            nutritionSchema: 1,
            targetStatus: .active,
            targetVersion: "test-v1",
            effectiveFrom: day,
            items: [
                NutritionTargetItem(
                    id: "diet_vitamins::C",
                    unit: "mg",
                    mode: .min,
                    lower: 100,
                    source: "DRIs 2023",
                    referenceType: "RNI",
                    adopted: true
                ),
            ]
        )
        let validated = NutritionTargetEvaluator.validate(plan: plan, on: day)
        XCTAssertTrue(validated.isActive)

        var entry = MealEntry(
            dayKey: day,
            mealType: .breakfast,
            foodName: "彩椒",
            portionAmount: 100,
            portionUnit: "g",
            kcal: 30,
            carbsG: 6,
            proteinG: 1,
            fatG: 0.3
        )
        entry.vitamins = ["C": 120]
        entry.aiEstimatedNutrientIDs = ["diet_vitamins::C"]
        var log = DailyNutritionLog(dayKey: day, entries: [entry])
        log.dietDayComplete = true
        log.dietPartialFields = []
        log.recalculateTotals()

        let confirmedOnly = NutritionTargetEvaluator.evaluate(
            metricID: "diet_vitamins::C",
            log: log,
            validatedPlan: validated
        )
        XCTAssertEqual(confirmedOnly.status, NutritionReadingStatus.unknown)
        XCTAssertFalse(confirmedOnly.isEstimated)

        let estimated = NutritionTargetEvaluator.evaluate(
            metricID: "diet_vitamins::C",
            log: log,
            validatedPlan: validated,
            allowEstimates: true
        )
        XCTAssertEqual(estimated.status, NutritionReadingStatus.met)
        XCTAssertTrue(estimated.isEstimated)

        log.dietPartialFields = ["breakfast"]
        let partial = NutritionTargetEvaluator.evaluate(
            metricID: "diet_vitamins::C",
            log: log,
            validatedPlan: validated,
            allowEstimates: true
        )
        XCTAssertEqual(partial.status, NutritionReadingStatus.unknown, "partial meals must not be judged")
    }

    func testEatingContextIncludesMicronutrientAdequacy() async throws {
        let day = DayKey(year: 2026, month: 11, day: 20)
        let plan = NutritionTargetPlan(
            nutritionSchema: 1,
            targetStatus: .active,
            targetVersion: "test-v1",
            effectiveFrom: day,
            items: [
                NutritionTargetItem(
                    id: "diet_vitamins::C", unit: "mg", mode: .min,
                    lower: 100, source: "DRIs 2023", referenceType: "RNI", adopted: true
                ),
                NutritionTargetItem(
                    id: "diet_minerals::钙", unit: "mg", mode: .min,
                    lower: 800, source: "DRIs 2023", referenceType: "RNI", adopted: true
                ),
            ]
        )
        var entry = MealEntry(
            dayKey: day, mealType: .breakfast, foodName: "彩椒与豆腐",
            portionAmount: 200, portionUnit: "g",
            kcal: 180, carbsG: 10, proteinG: 12, fatG: 8
        )
        entry.vitamins = ["C": 150]
        entry.minerals = ["钙": 400]
        var log = DailyNutritionLog(dayKey: day, entries: [entry])
        log.dietDayComplete = true
        log.dietPartialFields = []
        log.recalculateTotals()

        let context = AgentExecutionContext(
            snapshot: sampleContext(referenceDate: day.startDate().addingTimeInterval(12 * 3600)).snapshot,
            nutritionTargetPlan: plan,
            nutritionLogs: [log]
        )
        let json = await CoachToolRegistry.execute(
            name: "get_eating_context",
            argumentsJSON: #"{"days":7}"#,
            context: context
        )
        XCTAssertTrue(json.contains(#""recentAdequacy""#), json)
        XCTAssertTrue(json.contains(#""diet_vitamins::C""#), json)
        XCTAssertTrue(json.contains(#""metDays":1"#), json)
        XCTAssertTrue(json.contains(#""status":"met""#), json)
    }

    func testCoachPromptRequiresDietContextForNutritionQuestions() {
        let context = sampleContext()
        let prompt = CoachAgentOrchestrator.buildSystemPrompt(
            query: "我最近的维生素和矿物质够吗？",
            context: context
        )
        XCTAssertTrue(prompt.contains("get_eating_context"))
        XCTAssertTrue(prompt.contains("recentAdequacy"))
        XCTAssertTrue(prompt.contains("AI 估算"))
    }

    func testMealPhotoUsesConfiguredEndpointAndOmitsPrivateContentFromAudit() async throws {
        let output = #"{"choices":[{"message":{"role":"assistant","content":"{\"items\":[{\"name\":\"白米饭\",\"amount\":150,\"unit\":\"g\"},{\"name\":\"鸡蛋\",\"amount\":2,\"unit\":\"个\"}]}"}}]}"#
        let transport = MockAgentTransport(steps: [.data(statusCode: 200, body: output)])
        let recorder = AgentPayloadRecorder()
        let client = OpenAICompatibleClient(transport: transport, payloadRecorder: recorder)
        let photo = Data([0xff, 0xd8, 0xff, 0xd9])
        let text = "我的午饭，白米饭 150 克"
        let items = try await client.analyzeMeal(endpointURL: "https://api.example.com/v1", apiKey: "test",
                                                 modelName: "vision-model", input: text, jpeg: photo)
        XCTAssertEqual(items.map(\.name), ["白米饭", "鸡蛋"])
        XCTAssertEqual(items.first?.amount, 150)
        XCTAssertNil(items.last?.amount)

        let requestValue = await transport.lastRequest()
        let request = try XCTUnwrap(requestValue)
        XCTAssertEqual(request.url?.absoluteString, "https://api.example.com/v1/chat/completions")
        let body = try XCTUnwrap(request.httpBody)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["model"] as? String, "vision-model")
        let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages.last?["content"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, text)
        let image = parts.last?["image_url"] as? [String: Any]
        XCTAssertEqual(image?["url"] as? String, "data:image/jpeg;base64,\(photo.base64EncodedString())")
        let auditRecord = await recorder.latest()
        let audit = try XCTUnwrap(auditRecord)
        XCTAssertFalse(audit.redactedRequestJSON.contains(text))
        XCTAssertFalse(audit.redactedRequestJSON.contains(photo.base64EncodedString()))
    }

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

    func testWorkoutEvidenceMergesLinkedSessionAndPreservesManualOnlySession() async throws {
        let context = sampleContext()
        let now = context.snapshot.referenceDate
        let start = now.addingTimeInterval(-3_600)
        let end = now.addingTimeInterval(-1_800)
        let id = "BA03E536-EB3C-4D3C-84F2-D1EC95635A61"
        let imported = StoredWorkoutRecord(hkUUID: id, type: "力量训练", start: start, end: end,
                                           energy: 220, avgHR: 124)
        let linked = LoggedWorkoutSession(title: "补录训练组", startedAt: start, completedAt: end,
                                           exercises: [], rpe: 7, estimatedCalories: 220,
                                           syncedHealthKitUUID: id.lowercased())
        let manual = LoggedWorkoutSession(title: "手动训练", startedAt: start, completedAt: end,
                                           exercises: [], rpe: 5, estimatedCalories: 90)
        let future = LoggedWorkoutSession(title: "未来训练", startedAt: now.addingTimeInterval(60),
                                           completedAt: now.addingTimeInterval(1_800),
                                           exercises: [], rpe: 6, estimatedCalories: 150)
        let json = await CoachToolRegistry.execute(
            name: "get_workouts_and_muscles", argumentsJSON: #"{"days":7}"#,
            context: AgentExecutionContext(snapshot: context.snapshot, sessions: [linked, manual, future],
                                           storedWorkouts: [imported])
        )
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(envelope["ontologyVersion"] as? String, "bodyseek-evidence-v1")
        XCTAssertNil(envelope["coverage"])
        let data = try XCTUnwrap(envelope["data"] as? [String: Any])
        let workouts = try XCTUnwrap(data["workouts"] as? [[String: Any]])
        XCTAssertEqual(workouts.count, 2)
        let watchRecord = try XCTUnwrap(workouts.first { $0["uuid"] as? String == id })
        XCTAssertEqual(watchRecord["manualSessionID"] as? String, linked.id.uuidString)
        XCTAssertEqual(watchRecord["avgHR"] as? Double, 124)
        XCTAssertEqual(watchRecord["effortUser"] as? Double, 7)
        XCTAssertEqual(workouts.first { $0["source"] as? String == "manual" }?["uuid"] as? String, manual.id.uuidString)
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

    func testChineseFastFoodQueryExtractorMatchesBrandsAndCapsAtTwoQueries() {
        let q1 = ChineseFastFoodQueryExtractor.extractQueries(from: "中午吃了麦当劳的麦辣鸡腿堡，下午喝了瑞幸生椰拿铁和星巴克拿铁")
        XCTAssertEqual(q1.count, 2)
        XCTAssertTrue(q1[0].contains("麦辣鸡腿汉堡"))
        XCTAssertTrue(q1[1].contains("生椰拿铁"))

        let qEmpty = ChineseFastFoodQueryExtractor.extractQueries(from: "早上水煮蛋两个加白米饭一碗")
        XCTAssertTrue(qEmpty.isEmpty)
    }

    func testAnalyzeMealUsesDeepSeekSearchAndFallsBackGracefullyOnSearchError() async throws {
        let searchResp = #"{"results":[{"rerank_score":2.4,"title":"麦当劳麦辣鸡腿汉堡营养表","url":"https://example.com","snippet":"约520kcal 蛋白质24g 脂肪26g 碳水45g"}]}"#
        let chatResp = #"{"choices":[{"message":{"role":"assistant","content":"{\"items\":[{\"name\":\"麦辣鸡腿汉堡\",\"meal\":\"lunch\",\"reportedPortion\":\"1 个\",\"amount\":180,\"unit\":\"g\",\"isEstimatedPortion\":true,\"energyEstimate\":{\"lowerKcal\":495,\"upperKcal\":545,\"assumptions\":\"参考联网营养资料\"}}]}"}}]}"#
        let transport = MockAgentTransport(steps: [
            .data(statusCode: 200, body: searchResp),
            .data(statusCode: 200, body: chatResp),
        ])
        let recorder = AgentPayloadRecorder()
        let client = OpenAICompatibleClient(transport: transport, payloadRecorder: recorder)

        let items = try await client.analyzeMeal(
            endpointURL: "https://api.deepseek.com/v1",
            apiKey: "test-key",
            modelName: "deepseek-chat",
            input: "中午吃了一个麦当劳麦辣鸡腿堡",
            jpeg: nil,
            enableWebSearch: true
        )
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "麦辣鸡腿汉堡")
        let reqs = await transport.allCapturedRequests()
        XCTAssertEqual(reqs.count, 2)
        XCTAssertEqual(reqs[0].url?.absoluteString, "https://api.deepseek.com/v1/tools/search")
        XCTAssertEqual(reqs[1].url?.absoluteString, "https://api.deepseek.com/v1/chat/completions")
        let chatBody = String(data: try XCTUnwrap(reqs[1].httpBody), encoding: .utf8) ?? ""
        XCTAssertTrue(chatBody.contains("【联网营养参考资料"))
        XCTAssertTrue(chatBody.contains("520kcal"))
        let snap = await recorder.latest()
        XCTAssertEqual(snap?.toolNames, ["deepseek_web_search"])

        // Search failure (HTTP 500) must gracefully degrade to chat completion without failing meal analysis
        let fallbackTransport = MockAgentTransport(steps: [
            .data(statusCode: 500, body: "search down"),
            .data(statusCode: 200, body: chatResp),
        ])
        let fallbackClient = OpenAICompatibleClient(transport: fallbackTransport, payloadRecorder: recorder)
        let fallbackItems = try await fallbackClient.analyzeMeal(
            endpointURL: "https://api.deepseek.com/v1",
            apiKey: "test-key",
            modelName: "deepseek-chat",
            input: "中午吃了一个麦当劳麦辣鸡腿堡",
            jpeg: nil,
            enableWebSearch: true
        )
        XCTAssertEqual(fallbackItems.first?.name, "麦辣鸡腿汉堡")
    }

    func testGetEatingContextCompactModeOmitsVerboseDailyAdequacyForOnDeviceBudget() async {
        let day = DayKey(year: 2026, month: 11, day: 21)
        var log = DailyNutritionLog(
            dayKey: day,
            entries: [MealEntry(dayKey: day, mealType: .breakfast, foodName: "水煮蛋", portionAmount: 100, portionUnit: "g", kcal: 150, vitamins: ["C": 95])]
        )
        log.dietDayComplete = true
        let ctx = sampleContext(referenceDate: day.startDate().addingTimeInterval(12 * 3600))
        let plan = NutritionPlanFactory.makeDefaultDRIsPlan(
            for: NutritionProfile(age: 28, referenceSex: "male", heightCm: 175, referenceWeightKg: 70),
            effectiveFrom: day
        )
        let fullCtx = AgentExecutionContext(
            snapshot: ctx.snapshot,
            nutritionTargetPlan: plan,
            nutritionLogs: [log]
        )
        let compactJSON = await CoachToolRegistry.execute(
            name: "get_eating_context",
            argumentsJSON: #"{"days":7,"compact":true}"#,
            context: fullCtx
        )
        XCTAssertTrue(compactJSON.contains(#""state":"available""#))
        XCTAssertTrue(compactJSON.contains(#""adequacy":[]"#), compactJSON)
    }
}
