import BodySeekAgent
import BodySeekCore
import BodySeekStore
import Foundation
import XCTest

private actor RunCounter {
    private(set) var runs: [BriefEngine] = []

    func record(_ engine: BriefEngine) {
        runs.append(engine)
    }
}

/// 第五轮：每日简报的引擎选择、回落、缓存、过期与反馈。
final class DailyBriefTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_760_500_000)

    private func makeContext(
        authorized: Bool = true,
        memories: [TieredMemoryRecord] = []
    ) -> AgentExecutionContext {
        let rawDays = PreviewSeedFactory.makeRawWindow(endingAt: now, days: 35)
        let snapshot = BevelScoringEngine.computeWindow(
            rawDays: rawDays,
            sleepGoalMinutes: 450,
            referenceDate: now,
            sourceLabel: "测试数据源",
            isAuthorized: authorized
        )
        return AgentExecutionContext(snapshot: snapshot, tieredMemories: memories, asOf: now)
    }

    private func makeGenerator(
        counter: RunCounter,
        cloudBehavior: @escaping @Sendable (BriefInputs, Date) async throws -> DailyBrief
    ) throws -> (DailyBriefGenerator, BodySeekRepository) {
        let db = try BodySeekDatabase.inMemory()
        let repo = BodySeekRepository(database: db)
        let generator = DailyBriefGenerator(store: RepositoryBriefStore(repository: repo)) { choice, inputs, date in
            await counter.record(choice.engine)
            switch choice {
            case .cloud:
                return try await cloudBehavior(inputs, date)
            case .onDevice:
                throw BriefEngineError.unavailable("测试里没有端侧模型")
            case .localTemplate:
                return LocalTemplateBriefEngine.generate(inputs: inputs, now: date)
            }
        }
        return (generator, repo)
    }

    private static func cloudBrief(headline: String, inputs: BriefInputs, date: Date) -> DailyBrief {
        DailyBrief(
            dayKey: inputs.dayKey,
            generatedAt: date,
            modelInputsDigest: inputs.digest,
            engine: .cloud,
            headline: headline,
            pageNotes: [BriefPage.today.rawValue: headline]
        )
    }

    // MARK: - 引擎选择

    func testSelectorPrefersCloudThenOnDeviceThenLocalTemplate() {
        let choices = BriefEngineSelector.candidates(
            isPreview: false, apiKey: "sk-test", endpoint: "", modelName: "",
            foundationModelsAvailable: true, isOnline: true
        )
        XCTAssertEqual(choices, [
            .cloud(endpoint: "https://api.deepseek.com/v1", model: "deepseek-chat"),
            .onDevice,
            .localTemplate,
        ])
    }

    func testSelectorSkipsCloudWhenOfflineOrKeyMissing() {
        let offline = BriefEngineSelector.candidates(
            isPreview: false, apiKey: "sk-test", endpoint: "https://api.example.com/v1", modelName: "m",
            foundationModelsAvailable: false, isOnline: false
        )
        XCTAssertEqual(offline, [.localTemplate])

        let noKey = BriefEngineSelector.candidates(
            isPreview: false, apiKey: "  ", endpoint: "", modelName: "",
            foundationModelsAvailable: true, isOnline: true
        )
        XCTAssertEqual(noKey, [.onDevice, .localTemplate])

        let nothing = BriefEngineSelector.candidates(
            isPreview: false, apiKey: "", endpoint: "", modelName: "",
            foundationModelsAvailable: false, isOnline: true
        )
        XCTAssertEqual(nothing, [.localTemplate])
    }

    func testSelectorUsesOnlyLocalTemplateInPreview() {
        let choices = BriefEngineSelector.candidates(
            isPreview: true, apiKey: "sk-test", endpoint: "", modelName: "",
            foundationModelsAvailable: true, isOnline: true
        )
        XCTAssertEqual(choices, [.localTemplate])
    }

    // MARK: - 回落

    func testCloudFailureFallsBackToLocalTemplate() async throws {
        let counter = RunCounter()
        let (generator, _) = try makeGenerator(counter: counter) { _, _ in
            throw BriefEngineError.unavailable("断网")
        }
        let inputs = BriefInputs.make(from: makeContext())
        let result = await generator.resolve(
            inputs: inputs,
            choices: [.cloud(endpoint: "https://api.example.com/v1", model: "m"), .onDevice, .localTemplate],
            now: now
        )
        XCTAssertEqual(result.brief.engine, .localTemplate)
        XCTAssertEqual(result.source, .generated)
        XCTAssertEqual(result.fallbacks.count, 2, "云端和端侧各记一条失败原因")
        let runs = await counter.runs
        XCTAssertEqual(runs, [.cloud, .onDevice, .localTemplate])
    }

    func testOfflineSelectionProducesLocalTemplateBrief() async throws {
        let counter = RunCounter()
        let (generator, _) = try makeGenerator(counter: counter) { _, _ in
            XCTFail("离线时不应该调用云端")
            throw BriefEngineError.unavailable("不会走到")
        }
        let choices = BriefEngineSelector.candidates(
            isPreview: false, apiKey: "sk-test", endpoint: "", modelName: "",
            foundationModelsAvailable: false, isOnline: false
        )
        let result = await generator.resolve(inputs: BriefInputs.make(from: makeContext()), choices: choices, now: now)
        XCTAssertEqual(result.brief.engine, .localTemplate)
        XCTAssertTrue(result.fallbacks.isEmpty)
        XCTAssertFalse(result.brief.headline.isEmpty)
    }

    func testCloudBriefWithUnverifiedNumberFallsBack() async throws {
        let counter = RunCounter()
        let (generator, _) = try makeGenerator(counter: counter) { inputs, date in
            DailyBriefTests.cloudBrief(headline: "今天恢复 987 分，放心加量。", inputs: inputs, date: date)
        }
        let inputs = BriefInputs.make(from: makeContext())
        let result = await generator.resolve(
            inputs: inputs,
            choices: [.cloud(endpoint: "https://api.example.com/v1", model: "m"), .localTemplate],
            now: now
        )
        XCTAssertEqual(result.brief.engine, .localTemplate)
        XCTAssertEqual(result.fallbacks.count, 1)
        XCTAssertTrue(result.fallbacks[0].contains("未核实"))
    }

    // MARK: - 缓存与过期

    func testCacheHitThenInputChangeMarksStaleAndRegenerates() async throws {
        let counter = RunCounter()
        let (generator, repo) = try makeGenerator(counter: counter) { _, _ in
            throw BriefEngineError.unavailable("本测试只用本地模板")
        }
        let choices: [BriefEngineChoice] = [.localTemplate]
        let inputs = BriefInputs.make(from: makeContext())

        let first = await generator.resolve(inputs: inputs, choices: choices, now: now)
        XCTAssertEqual(first.source, .generated)

        let second = await generator.resolve(inputs: inputs, choices: choices, now: now.addingTimeInterval(60))
        XCTAssertEqual(second.source, .cacheHit)
        XCTAssertEqual(second.brief, first.brief)
        let runsAfterHit = await counter.runs
        XCTAssertEqual(runsAfterHit.count, 1, "命中缓存不应该再次运行引擎")

        // 输入变化：多了一条生效中的记忆。
        let memory = TieredMemoryRecord(tier: .profile, content: "素食", confirmedAt: now)
        let changed = BriefInputs.make(from: makeContext(memories: [memory]))
        XCTAssertNotEqual(changed.digest, inputs.digest)
        let third = await generator.resolve(inputs: changed, choices: choices, now: now.addingTimeInterval(120))
        XCTAssertEqual(third.source, .generated)

        let old = try await repo.loadDailyBrief(dayKey: inputs.dayKey, inputsDigest: inputs.digest)
        XCTAssertEqual(old?.isStale, true, "输入变化后，旧简报被标记为过期")
        let fresh = try await repo.loadDailyBrief(dayKey: changed.dayKey, inputsDigest: changed.digest)
        XCTAssertEqual(fresh?.isStale, false)

        // 再回到旧输入：旧记录已过期，必须重新生成。
        let fourth = await generator.resolve(inputs: inputs, choices: choices, now: now.addingTimeInterval(180))
        XCTAssertEqual(fourth.source, .generated)
    }

    func testForceRefreshIgnoresCache() async throws {
        let counter = RunCounter()
        let (generator, _) = try makeGenerator(counter: counter) { _, _ in
            throw BriefEngineError.unavailable("本测试只用本地模板")
        }
        let inputs = BriefInputs.make(from: makeContext())
        _ = await generator.resolve(inputs: inputs, choices: [.localTemplate], now: now)
        let forced = await generator.resolve(inputs: inputs, choices: [.localTemplate], forceRefresh: true, now: now)
        XCTAssertEqual(forced.source, .generated)
        let runs = await counter.runs
        XCTAssertEqual(runs.count, 2)
    }

    func testLatestReturnsStaleBriefForImmediateDisplay() async throws {
        let counter = RunCounter()
        let (generator, _) = try makeGenerator(counter: counter) { _, _ in
            throw BriefEngineError.unavailable("本测试只用本地模板")
        }
        let inputs = BriefInputs.make(from: makeContext())
        _ = await generator.resolve(inputs: inputs, choices: [.localTemplate], now: now)
        let memory = TieredMemoryRecord(tier: .profile, content: "素食", confirmedAt: now)
        let changed = BriefInputs.make(from: makeContext(memories: [memory]))
        _ = await generator.resolve(inputs: changed, choices: [.localTemplate], now: now.addingTimeInterval(60))

        let latest = await generator.latest(dayKey: inputs.dayKey)
        XCTAssertEqual(latest?.brief.modelInputsDigest, changed.digest)
        XCTAssertEqual(latest?.isStale, false)
    }

    // MARK: - 反馈

    func testFeedbackIsWrittenToBriefFeedbackTable() async throws {
        let counter = RunCounter()
        let (generator, repo) = try makeGenerator(counter: counter) { _, _ in
            throw BriefEngineError.unavailable("本测试只用本地模板")
        }
        let day = BriefInputs.make(from: makeContext()).dayKey
        try await generator.submitFeedback(.inaccurate, dayKey: day, note: "恢复分偏高", now: now)
        try await generator.submitFeedback(.accurate, dayKey: day, now: now.addingTimeInterval(1))

        let stored = try await repo.loadBriefFeedback()
        XCTAssertEqual(stored.map(\.rating), [.accurate, .inaccurate])
        XCTAssertEqual(stored.last?.note, "恢复分偏高")
        XCTAssertEqual(Set(BriefFeedbackRating.allCases.map(\.rawValue)), ["accurate", "inaccurate", "useless"])
    }

    // MARK: - 本地模板与解析

    func testLocalTemplateNumbersAreAllVerified() {
        let inputs = BriefInputs.make(from: makeContext())
        let brief = LocalTemplateBriefEngine.generate(inputs: inputs, now: now)
        XCTAssertEqual(brief.engine, .localTemplate)
        XCTAssertFalse(brief.headline.isEmpty)
        XCTAssertEqual(DailyBriefVerifier.unverifiedNumbers(in: brief, inputs: inputs), [])
        for page in BriefPage.allCases {
            XCTAssertFalse(brief.note(for: page).isEmpty, "每一页都应该有解读文案：\(page.rawValue)")
        }
    }

    func testLocalTemplateWithoutAuthorizationAsksToConnectHealth() {
        let inputs = BriefInputs.make(from: makeContext(authorized: false))
        let brief = LocalTemplateBriefEngine.generate(inputs: inputs, now: now)
        XCTAssertTrue(brief.headline.contains("连接 Apple 健康"))
        XCTAssertTrue(brief.actions.isEmpty)
    }

    func testBriefRoundTripsThroughJSONAndNoteFallsBackToHeadline() throws {
        let brief = DailyBrief(
            dayKey: DayKey(year: 2026, month: 11, day: 22),
            generatedAt: now,
            modelInputsDigest: "abc",
            engine: .onDevice,
            headline: "一句话",
            changes: [BriefChange(id: "c", title: "变化", detail: "说明")],
            actions: [BriefAction(id: "a", title: "动作", detail: "详情", basis: "依据", coachPrompt: "问")],
            pageNotes: [BriefPage.trends.rawValue: "趋势解读"],
            evidence: [EvidenceRef(kind: "metric", identifier: "k", summary: "s")]
        )
        let data = try JSONEncoder().encode(brief)
        XCTAssertEqual(try JSONDecoder().decode(DailyBrief.self, from: data), brief)
        XCTAssertEqual(brief.note(for: .trends), "趋势解读")
        XCTAssertEqual(brief.note(for: .nutrition), "一句话")
    }

    func testPromptParserAcceptsFencedJSONAndRejectsGarbage() throws {
        let inputs = BriefInputs.make(from: makeContext())
        let raw = """
        ```json
        {"headline":"今天按计划训练","changes":[{"title":"睡眠","detail":"比平时短"}],
         "actions":[{"title":"早点睡","detail":"提前半小时","basis":"睡眠偏短","coachPrompt":"怎么早睡"}],
         "pageNotes":{"today":"按计划","trends":"稳定"}}
        ```
        """
        let brief = try BriefPrompt.parse(raw, inputs: inputs, engine: .cloud, generatedAt: now)
        XCTAssertEqual(brief.headline, "今天按计划训练")
        XCTAssertEqual(brief.actions.first?.coachPrompt, "怎么早睡")
        XCTAssertEqual(brief.pageNotes[BriefPage.trends.rawValue], "稳定")
        XCTAssertEqual(brief.modelInputsDigest, inputs.digest)

        XCTAssertThrowsError(try BriefPrompt.parse("我无法回答", inputs: inputs, engine: .cloud, generatedAt: now))
        XCTAssertThrowsError(try BriefPrompt.parse(#"{"headline":"  "}"#, inputs: inputs, engine: .cloud, generatedAt: now))
    }
}
