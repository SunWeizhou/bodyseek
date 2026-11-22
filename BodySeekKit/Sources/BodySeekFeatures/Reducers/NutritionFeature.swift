import BodySeekAgent
import BodySeekCore
import BodySeekHealth
import ComposableArchitecture
import Foundation

@Reducer
public struct NutritionFeature: Sendable {
    public enum MealLogger: Identifiable, Equatable, Sendable {
        case manual
        case assistant
        case edit(MealEntry)

        public var id: String {
            switch self {
            case .manual: "manual"
            case .assistant: "assistant"
            case let .edit(entry): entry.id.uuidString
            }
        }
    }

    public enum PeriodMode: String, CaseIterable, Identifiable, Hashable, Sendable {
        case week
        case month

        public var id: String { rawValue }
        public var title: String {
            switch self {
            case .week: "周看板"
            case .month: "月看板"
            }
        }
    }

    public struct AdviceScopeKey: Equatable, Hashable, Sendable {
        public let periodMode: PeriodMode
        public let anchorDayKey: DayKey
        public let selectedDayKey: DayKey
        public let logCount: Int
        public let entryCount: Int
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var periodMode: PeriodMode = .week
        public var todayKey: DayKey
        public var anchorDayKey: DayKey
        public var selectedDayKey: DayKey
        public var snapshot: BodySeekDashboardSnapshot
        public var profile: NutritionProfile?
        public var targetPlan: NutritionTargetPlan?
        public var logs: [DailyNutritionLog] = []
        public var periodSummary: NutritionPeriodSummary
        public var foodSearchQuery: String = ""
        public var foodSearchRequestID: UUID?
        public var foodSearchError: String?
        public var foodLibrary: [FoodLibraryItem] = NutritionCatalog.starterFoodItems
        public var expandedMicroGroup: String?
        public var mealLogger: MealLogger?
        public var showLibrarySheet: Bool = false
        public var showProfileTargetSheet: Bool = false
        public var exportedMarkdown: String?
        public var statusMessage: String?
        public var lastError: String?
        public var isLoading: Bool = false
        public var isSaving: Bool = false
        public var isPreviewMode: Bool
        public var coachAdviceByScope: [AdviceScopeKey: AIBriefingStatus] = [:]
        public var coachAdviceStatus: AIBriefingStatus {
            coachAdviceByScope[currentAdviceScopeKey] ?? .idle
        }
        public var currentAdviceScopeKey: AdviceScopeKey {
            AdviceScopeKey(
                periodMode: periodMode,
                anchorDayKey: anchorDayKey,
                selectedDayKey: selectedDayKey,
                logCount: logs.count,
                entryCount: logs.reduce(0) { $0 + $1.entries.count }
            )
        }
        public var deterministicAdviceSummary: String = "近 7 天暂无足够完整或估算记录，先用「AI 记饮食」拍图或写一句话记一餐，即可实时计算宏量、维生素与矿物质进展。"

        public init(
            snapshot: BodySeekDashboardSnapshot,
            todayKey: DayKey? = nil,
            isPreviewMode: Bool = ProcessInfo.processInfo.arguments.contains("-velaPreviewDashboard")
        ) {
            let resolvedToday = todayKey ?? snapshot.referenceDate.physiologicalDayKey()
            self.snapshot = snapshot
            self.todayKey = resolvedToday
            self.anchorDayKey = resolvedToday
            self.selectedDayKey = resolvedToday
            self.isPreviewMode = isPreviewMode
            let window = Self.dateBounds(mode: .week, anchor: resolvedToday)
            self.periodSummary = NutritionBoardAggregator.summarizePeriod(
                logs: [],
                targetPlan: nil,
                startDayKey: window.start,
                endDayKey: window.end,
                todayKey: resolvedToday
            )
        }

        mutating func showToday() {
            anchorDayKey = todayKey
            selectedDayKey = todayKey
            recomputeSummary()
        }

        public var periodDayKeys: [DayKey] {
            let cal = Calendar(identifier: .gregorian)
            let start = periodSummary.startDayKey.calendarDayStart(calendar: cal)
            let end = periodSummary.endDayKey.calendarDayStart(calendar: cal)
            var result: [DayKey] = []
            var cur = start
            while cur <= end && result.count < 35 {
                result.append(DayKey.fromCalendarDay(cur, calendar: cal))
                cur = cal.date(byAdding: .day, value: 1, to: cur) ?? end.addingTimeInterval(86_400)
            }
            return result
        }

        public var selectedHealthDay: DailyComputedDay? {
            snapshot.historyDays.first { $0.dayKey == selectedDayKey }
                ?? (snapshot.today.dayKey == selectedDayKey ? snapshot.today : nil)
        }

        public var selectedDayLog: DailyNutritionLog? {
            periodSummary.dayLogsByKey[selectedDayKey]
                ?? logs.first(where: { $0.dayKey == selectedDayKey })
        }

        public mutating func recomputeSummary() {
            let window = Self.dateBounds(mode: periodMode, anchor: anchorDayKey)
            self.periodSummary = NutritionBoardAggregator.summarizePeriod(
                logs: logs,
                targetPlan: targetPlan,
                startDayKey: window.start,
                endDayKey: window.end,
                todayKey: todayKey
            )
            self.deterministicAdviceSummary = buildDeterministicAdviceSummary()
        }

        private func buildDeterministicAdviceSummary() -> String {
            let avgs = periodSummary.metricAverages
            let loggedDays = periodSummary.dayLogsByKey.values.filter {
                !$0.entries.isEmpty || $0.dietKcal != nil || $0.dietWaterMl != nil
            }.count
            guard loggedDays > 0 else {
                return "当前周期还没有饮食记录，点击上方「AI 记饮食」拍餐食照片或写一句话，就能自动拆出热量、宏量与 29 项微营养素。"
            }
            let lows = avgs.filter { $0.displayStatus == .low }.prefix(3).map { avg in
                avg.isEstimateOnly ? "\(avg.metricName)(估算偏低)" : avg.metricName
            }
            let overs = avgs.filter { $0.displayStatus == .over }.prefix(2).map { avg in
                avg.isEstimateOnly ? "\(avg.metricName)(估算偏高)" : avg.metricName
            }
            let mets = avgs.filter { $0.displayStatus == .met }.prefix(2).map(\.metricName)
            var segments: [String] = []
            segments.append("近\(periodMode == .week ? " 7 天" : " 30 天")已记录 \(loggedDays) 天")
            if let deficit = periodSummary.rollingDeficit7dKcal {
                let d = Int(deficit.rounded())
                if abs(d) < 30 {
                    segments.append("近 7 天日均能量基本持平（约 \(abs(d)) kcal）")
                } else if d > 0 {
                    segments.append("近 7 天日均缺口 \(d) kcal")
                } else {
                    segments.append("近 7 天日均盈余 \(abs(d)) kcal")
                }
            } else {
                segments.append("近 7 天有效结账日 \(periodSummary.validSurplusDays) 天（需满 3 天才算日均缺口）")
            }
            if !lows.isEmpty {
                segments.append("建议优先补充 \(lows.joined(separator: "、"))")
            }
            if !overs.isEmpty {
                segments.append("注意节制 \(overs.joined(separator: "、"))")
            }
            if lows.isEmpty && overs.isEmpty && !mets.isEmpty {
                segments.append("\(mets.joined(separator: "、")) 目前处于理想区间")
            }
            return segments.joined(separator: "；") + "。"
        }

        public static func dateBounds(mode: PeriodMode, anchor: DayKey) -> (start: DayKey, end: DayKey) {
            let cal = Calendar(identifier: .gregorian)
            let anchorDate = anchor.calendarDayStart(calendar: cal)
            switch mode {
            case .week:
                let start = cal.date(byAdding: .day, value: -6, to: anchorDate) ?? anchorDate
                return (
                    DayKey.fromCalendarDay(start, calendar: cal),
                    DayKey.fromCalendarDay(anchorDate, calendar: cal)
                )
            case .month:
                let start = cal.date(byAdding: .day, value: -29, to: anchorDate) ?? anchorDate
                return (
                    DayKey.fromCalendarDay(start, calendar: cal),
                    DayKey.fromCalendarDay(anchorDate, calendar: cal)
                )
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case loaded(
            profile: NutritionProfile?,
            targetPlan: NutritionTargetPlan?,
            logs: [DailyNutritionLog],
            foodLibrary: [FoodLibraryItem]
        )
        case loadFailed(String)
        case periodModeChanged(PeriodMode)
        case stepPeriod(Int)
        case daySelected(DayKey)
        case toggleMicroGroup(String)
        case foodSearchChanged(String)
        case foodSearchResultsLoaded([FoodLibraryItem], query: String, requestID: UUID)
        case foodSearchFailed(query: String, requestID: UUID, message: String)
        case mealLoggerPresented(Bool)
        case mealAssistantTapped
        case mealEditTapped(MealEntry)
        case mealDeleteConfirmed(MealEntry)
        case libraryPresented(Bool)
        case profileTargetPresented(Bool)
        case mealDraftConfirmed([MealEntry], fromPhoto: Bool)
        case logMealSubmitted(
            mealType: MealType,
            foodName: String,
            foodID: String?,
            portionAmount: Double?,
            portionUnit: String,
            kcal: Double?,
            carbsG: Double?,
            proteinG: Double?,
            fatG: Double?,
            fiberG: Double?,
            waterMl: Double?,
            vitamins: [String: Double],
            minerals: [String: Double],
            isEstimated: Bool,
            isPartial: Bool,
            note: String?
        )
        case closeSelectedDayTapped(reviewSummary: String?)
        case saveProfileTapped(NutritionProfile, generateAndActivateDRIs: Bool)
        case addFoodItemTapped(FoodLibraryItem)
        case exportDailyMarkdownTapped
        case exportTargetsMarkdownTapped
        case markdownSheetDismissed
        case mutationSucceeded(message: String)
        case mutationFailed(String)
        case generateNutritionAdviceTapped
        case nutritionAdviceLoaded(AdviceScopeKey, AIBriefingStatus)
        case askCoachTapped(String)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case nutritionDataChanged(
                todayLog: DailyNutritionLog?,
                plan: NutritionTargetPlan?,
                rollingDeficit7d: Double?
            )
            case askCoach(String)
        }
    }

    private enum CancelID {
        case nutritionAdvice
    }

    @Dependency(\.bodySeekStoreClient) var storeClient
    @Dependency(\.coachAIClient) var coachAIClient
    @Dependency(\.date.now) var now
    @Dependency(\.uuid) var uuid

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.isLoading = true
                return loadAllEffect(state: state)

            case let .loaded(profile, targetPlan, logs, library):
                state.isLoading = false
                state.profile = profile
                state.targetPlan = targetPlan
                state.logs = logs
                if !library.isEmpty,
                   state.foodSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    state.foodLibrary = library
                }
                state.recomputeSummary()
                let todayLog = logs.first(where: { $0.dayKey == state.todayKey })
                return .merge(
                    .cancel(id: CancelID.nutritionAdvice),
                    .send(.delegate(.nutritionDataChanged(
                        todayLog: todayLog,
                        plan: targetPlan,
                        rollingDeficit7d: NutritionBoardAggregator.rollingDeficit(logs: logs, endingAt: state.todayKey)
                    )))
                )

            case let .loadFailed(message):
                state.isLoading = false
                state.isSaving = false
                state.lastError = message
                return .none

            case let .periodModeChanged(mode):
                state.periodMode = mode
                state.recomputeSummary()
                return .cancel(id: CancelID.nutritionAdvice)

            case let .stepPeriod(direction):
                let cal = Calendar(identifier: .gregorian)
                let deltaDays = (state.periodMode == .week ? 7 : 30) * direction
                let cur = state.anchorDayKey.calendarDayStart(calendar: cal)
                let nextDate = cal.date(byAdding: .day, value: deltaDays, to: cur) ?? cur
                let candidate = DayKey.fromCalendarDay(nextDate, calendar: cal)
                state.anchorDayKey = min(candidate, state.todayKey)
                state.selectedDayKey = state.anchorDayKey
                state.recomputeSummary()
                return .cancel(id: CancelID.nutritionAdvice)

            case let .daySelected(dayKey):
                state.selectedDayKey = dayKey
                return .cancel(id: CancelID.nutritionAdvice)

            case let .toggleMicroGroup(group):
                state.expandedMicroGroup = state.expandedMicroGroup == group ? nil : group
                return .none

            case let .foodSearchChanged(query):
                state.foodSearchQuery = query
                state.foodSearchError = nil
                let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                let requestID = uuid()
                state.foodSearchRequestID = requestID
                guard !trimmed.isEmpty else { return .none }
                return .run { send in
                    do {
                        let results = try await storeClient.searchFoodLibrary(trimmed)
                        await send(.foodSearchResultsLoaded(results, query: trimmed, requestID: requestID))
                    } catch {
                        await send(.foodSearchFailed(
                            query: trimmed,
                            requestID: requestID,
                            message: "搜索营养库失败：\(error.localizedDescription)"
                        ))
                    }
                }

            case let .foodSearchResultsLoaded(items, query, requestID):
                guard state.foodSearchRequestID == requestID,
                      state.foodSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query
                else { return .none }
                state.foodLibrary = items
                state.foodSearchError = nil
                return .none

            case let .foodSearchFailed(query, requestID, message):
                guard state.foodSearchRequestID == requestID,
                      state.foodSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines) == query
                else { return .none }
                state.foodSearchError = message
                return .none

            case let .mealLoggerPresented(presented):
                state.mealLogger = presented ? .manual : nil
                return .none

            case .mealAssistantTapped:
                state.mealLogger = .assistant
                return .none

            case let .libraryPresented(presented):
                state.showLibrarySheet = presented
                return .none

            case let .profileTargetPresented(presented):
                state.showProfileTargetSheet = presented
                return .none

            case let .mealEditTapped(entry):
                state.mealLogger = .edit(entry)
                state.foodSearchQuery = ""
                state.lastError = nil
                return .none

            case let .mealDeleteConfirmed(entry):
                guard !state.isSaving else { return .none }
                state.isSaving = true
                state.lastError = nil
                return .run { send in
                    do {
                        let proposal = try ActionProposal(
                            kind: .deleteNutritionMeal, origin: .user,
                            encodablePayload: DeleteNutritionMealPayload(dayKey: entry.dayKey, entryID: entry.id)
                        )
                        _ = try await storeClient.executeProposal(proposal)
                        await send(.mutationSucceeded(message: "已删除饮食条目"))
                    } catch {
                        await send(.mutationFailed("删除餐食失败：\(error.localizedDescription)"))
                    }
                }

            case let .mealDraftConfirmed(entries, fromPhoto):
                guard !state.isSaving, let day = entries.first?.dayKey,
                      entries.allSatisfy({ $0.dayKey == day })
                else { return .none }
                state.isSaving = true
                state.lastError = nil
                let evidence = entries.compactMap { entry in
                    entry.foodID.map { EvidenceRef(kind: "food_catalog", identifier: $0, summary: entry.foodName) }
                }
                return .run { send in
                    do {
                        let proposal = try ActionProposal(
                            kind: .logNutritionMeals, origin: .user,
                            encodablePayload: LogNutritionMealsPayload(dayKey: day, entries: entries),
                            rationale: fromPhoto ? "用户确认照片餐食草稿" : "用户确认文字餐食草稿",
                            evidenceRefs: evidence
                        )
                        _ = try await storeClient.executeProposal(proposal)
                        await send(.mutationSucceeded(message: "已保存饮食记录"))
                    } catch {
                        await send(.mutationFailed("保存餐食失败：\(error.localizedDescription)"))
                    }
                }

            case let .logMealSubmitted(
                mealType, foodName, foodID, portionAmount, portionUnit,
                kcal, carbsG, proteinG, fatG, fiberG, waterMl,
                vitamins, minerals, isEstimated, isPartial, note
            ):
                guard !state.isSaving else { return .none }
                state.isSaving = true
                let original: MealEntry? = if case let .edit(entry) = state.mealLogger { entry } else { nil }
                let dayKey = original?.dayKey ?? state.selectedDayKey
                let samePortion = original?.portionAmount == portionAmount && original?.portionUnit == portionUnit
                let sameFood = original?.foodName == foodName && original?.foodID == foodID
                var entry = MealEntry(
                    id: original?.id ?? UUID(),
                    dayKey: dayKey,
                    mealType: mealType,
                    foodID: foodID,
                    foodName: foodName,
                    portionAmount: portionAmount,
                    portionUnit: portionUnit,
                    portionDescription: samePortion ? original?.portionDescription : nil,
                    kcal: kcal,
                    carbsG: carbsG,
                    proteinG: proteinG,
                    fatG: fatG,
                    fiberG: fiberG ?? (sameFood && samePortion ? original?.fiberG : nil),
                    waterMl: waterMl,
                    alaMg: sameFood && samePortion ? original?.alaMg : nil,
                    epaDhaMg: sameFood && samePortion ? original?.epaDhaMg : nil,
                    vitamins: vitamins.isEmpty && sameFood && samePortion ? original?.vitamins ?? [:] : vitamins,
                    minerals: minerals.isEmpty && sameFood && samePortion ? original?.minerals ?? [:] : minerals,
                    isEstimated: isEstimated,
                    estimationNote: sameFood && samePortion && original?.kcal == kcal ? original?.estimationNote : nil,
                    recordedAt: original?.recordedAt ?? now
                )
                if sameFood && samePortion {
                    entry.aiEstimatedNutrientIDs = original?.aiEstimatedNutrientIDs?.filter { id in
                        guard let field = MealEntry.additionalNutrientKeyPath(id) else { return false }
                        return entry[keyPath: field] != nil && entry[keyPath: field] == original?[keyPath: field]
                    }
                }
                if sameFood && samePortion && original?.kcal == kcal {
                    entry.energyEstimate = original?.energyEstimate
                }
                let partialFields = isPartial ? [mealType.rawValue] : []
                let payload = LogNutritionMealPayload(
                    dayKey: dayKey,
                    entry: entry,
                    partialFields: partialFields,
                    note: note
                )
                return .run { send in
                    do {
                        let proposal = try ActionProposal(
                            kind: .logNutritionMeal,
                            origin: .user,
                            encodablePayload: payload,
                            rationale: original == nil ? "用户记录餐次" : "用户修正已保存餐次"
                        )
                        _ = try await storeClient.executeProposal(proposal)
                        await send(.mutationSucceeded(message: "已记录 \(foodName)"))
                    } catch {
                        await send(.mutationFailed("保存餐次记录失败：\(error.localizedDescription)"))
                    }
                }

            case let .closeSelectedDayTapped(reviewSummary):
                state.isSaving = true
                let dayKey = state.selectedDayKey
                let matchingDay = state.selectedHealthDay
                let activeKcal = matchingDay?.raw.activeEnergyKcal ?? state.selectedDayLog?.sportKcal
                let sportHours: Double? = {
                    let workoutMinutes = matchingDay?.raw.workouts.reduce(0) { $0 + $1.durationMinutes } ?? 0
                    if workoutMinutes > 0 { return (Double(workoutMinutes) / 60.0 * 100).rounded() / 100 }
                    if let ex = matchingDay?.raw.exerciseMinutes { return (Double(ex) / 60.0 * 100).rounded() / 100 }
                    return state.selectedDayLog?.sportHours
                }()
                let steps = matchingDay?.raw.steps ?? state.selectedDayLog?.steps
                let bmr = state.profile?.bmrKcalReference
                    ?? state.selectedDayLog?.bmrKcalUsed
                    ?? NutritionPlanFactory.estimateBMR(
                        sex: state.profile?.referenceSex,
                        weightKg: matchingDay?.raw.bodyMassKg ?? state.profile?.referenceWeightKg,
                        heightCm: state.profile?.heightCm,
                        age: state.profile?.age
                    )

                let payload = CloseNutritionDayPayload(
                    dayKey: dayKey,
                    markComplete: true,
                    sportHours: sportHours,
                    sportKcal: activeKcal,
                    steps: steps,
                    bmrKcalUsed: bmr,
                    reviewSummary: reviewSummary
                )
                return .run { send in
                    do {
                        let proposal = try ActionProposal(
                            kind: .closeNutritionDay,
                            origin: .user,
                            encodablePayload: payload,
                            rationale: "收尾 \(dayKey.isoString) 并核对热量平衡"
                        )
                        _ = try await storeClient.executeProposal(proposal)
                        await send(.mutationSucceeded(message: "已完成 \(dayKey.isoString) 饮食结账"))
                    } catch {
                        await send(.mutationFailed("饮食结账失败：\(error.localizedDescription)"))
                    }
                }

            case let .saveProfileTapped(profile, generateAndActivateDRIs):
                state.isSaving = true
                let todayKey = state.todayKey
                return .run { send in
                    do {
                        let profileProposal = try ActionProposal(
                            kind: .upsertNutritionProfile,
                            origin: .user,
                            encodablePayload: UpsertNutritionProfilePayload(profile: profile),
                            rationale: "更新营养个人档案"
                        )
                        _ = try await storeClient.executeProposal(profileProposal)

                        if generateAndActivateDRIs {
                            let versionTag = "v1.\(Int(Date().timeIntervalSince1970) % 10_000)"
                            let plan = NutritionPlanFactory.makeDefaultDRIsPlan(
                                for: profile,
                                effectiveFrom: todayKey,
                                version: versionTag
                            )
                            let targetProposal = try ActionProposal(
                                kind: .commitNutritionTargets,
                                origin: .agent,
                                encodablePayload: CommitNutritionTargetsPayload(plan: plan),
                                rationale: "根据更新后的个人档案生成 DRIs 2023 目标方案"
                            )
                            _ = try await storeClient.executeProposal(targetProposal)
                        }
                        await send(.mutationSucceeded(message: generateAndActivateDRIs ? "个人档案与 DRIs 目标已生效" : "个人档案已更新"))
                    } catch {
                        await send(.mutationFailed("保存档案或生成目标失败：\(error.localizedDescription)"))
                    }
                }

            case let .addFoodItemTapped(item):
                state.isSaving = true
                return .run { send in
                    do {
                        try await storeClient.saveFoodLibraryItem(item)
                        await send(.mutationSucceeded(message: "已将 \(item.name) 加入营养库"))
                    } catch {
                        await send(.mutationFailed("保存营养库条目失败：\(error.localizedDescription)"))
                    }
                }

            case .exportDailyMarkdownTapped:
                let log = state.selectedDayLog ?? DailyNutritionLog(dayKey: state.selectedDayKey)
                state.exportedMarkdown = NutritionMarkdownExporter.exportDailyMarkdown(log: log)
                return .none

            case .exportTargetsMarkdownTapped:
                if let plan = state.targetPlan {
                    state.exportedMarkdown = NutritionMarkdownExporter.exportTargetsMarkdown(plan: plan)
                } else {
                    state.lastError = "暂无已保存的目标方案可导出"
                }
                return .none

            case .markdownSheetDismissed:
                state.exportedMarkdown = nil
                return .none

            case let .mutationSucceeded(message):
                state.isSaving = false
                state.lastError = nil
                state.statusMessage = message
                state.mealLogger = nil
                state.showProfileTargetSheet = false
                return loadAllEffect(state: state)

            case let .mutationFailed(message):
                state.isSaving = false
                state.lastError = message
                return .none

            case .generateNutritionAdviceTapped:
                let scope = state.currentAdviceScopeKey
                guard !state.isPreviewMode else {
                    state.coachAdviceByScope[scope] = .generated(text: state.deterministicAdviceSummary, engineName: "预览模式")
                    return .none
                }
                state.coachAdviceByScope[scope] = .loading
                let topic = "营养摄入与下顿配餐建议"
                let summary = state.deterministicAdviceSummary
                let todayStrain = state.snapshot.today.strain.value.map { "今日负荷 \($0) 分" } ?? "今日负荷待同步"
                let lows = state.periodSummary.metricAverages.filter { $0.displayStatus == .low }.prefix(5)
                    .map { "\($0.metricName)(\($0.isEstimateOnly ? "估算均值" : "均值") \($0.averageValue.map { String(format: "%.1f", $0) } ?? "--")\($0.unit))" }
                    .joined(separator: "、")
                let promptContext = "\(summary) \(todayStrain)。偏低项：\(lows.isEmpty ? "无明显偏低项" : lows)。"
                let execContext = AgentExecutionContext(
                    snapshot: state.snapshot,
                    todayNutritionLog: state.selectedDayLog,
                    nutritionTargetPlan: state.targetPlan,
                    nutritionLogs: state.logs
                )
                return .run { send in
                    let status = await coachAIClient.generatePageInsight(topic, promptContext, execContext)
                    await send(.nutritionAdviceLoaded(scope, status))
                }
                .cancellable(id: CancelID.nutritionAdvice, cancelInFlight: true)

            case let .nutritionAdviceLoaded(scope, status):
                guard scope == state.currentAdviceScopeKey else { return .none }
                state.coachAdviceByScope[scope] = status
                return .none

            case let .askCoachTapped(question):
                return .send(.delegate(.askCoach(question)))

            case .delegate:
                return .none
            }
        }
    }

    private func loadAllEffect(state: State) -> Effect<Action> {
        let isPreview = state.isPreviewMode
        let todayKey = state.todayKey
        let searchQuery = state.foodSearchQuery
        return .run { send in
            do {
                try await storeClient.seedStarterFoodLibraryIfNeeded()
                var profile = try await storeClient.loadNutritionProfile()
                var plan = try await storeClient.loadNutritionTargetPlan()
                var logs = try await storeClient.loadNutritionLogs(nil, nil)

                if isPreview && profile == nil && logs.isEmpty {
                    let seedProfile = NutritionPlanFactory.makePreviewProfile()
                    let seedPlan = NutritionPlanFactory.makeDefaultDRIsPlan(for: seedProfile, effectiveFrom: todayKey)
                    let seedLogs = NutritionPlanFactory.makePreviewLogs(endingAt: todayKey, bmrKcal: seedProfile.bmrKcalReference ?? 1640)

                    let profProp = try ActionProposal(kind: .upsertNutritionProfile, origin: .system, encodablePayload: UpsertNutritionProfilePayload(profile: seedProfile))
                    _ = try await storeClient.executeProposal(profProp)
                    let planProp = try ActionProposal(kind: .commitNutritionTargets, origin: .system, encodablePayload: CommitNutritionTargetsPayload(plan: seedPlan))
                    _ = try await storeClient.executeProposal(planProp)
                    for log in seedLogs {
                        for entry in log.entries {
                            let mealProp = try ActionProposal(
                                kind: .logNutritionMeal,
                                origin: .system,
                                encodablePayload: LogNutritionMealPayload(dayKey: log.dayKey, entry: entry, partialFields: log.dietPartialFields)
                            )
                            _ = try await storeClient.executeProposal(mealProp)
                        }
                        if log.dietDayComplete == true {
                            let closeProp = try ActionProposal(
                                kind: .closeNutritionDay,
                                origin: .system,
                                encodablePayload: CloseNutritionDayPayload(
                                    dayKey: log.dayKey,
                                    markComplete: true,
                                    sportHours: log.sportHours,
                                    sportKcal: log.sportKcal,
                                    steps: log.steps,
                                    bmrKcalUsed: log.bmrKcalUsed,
                                    reviewSummary: log.reviewSummary
                                )
                            )
                            _ = try await storeClient.executeProposal(closeProp)
                        }
                    }

                    profile = try await storeClient.loadNutritionProfile()
                    plan = try await storeClient.loadNutritionTargetPlan()
                    logs = try await storeClient.loadNutritionLogs(nil, nil)
                }

                let library = try await storeClient.searchFoodLibrary(searchQuery)
                await send(.loaded(profile: profile, targetPlan: plan, logs: logs, foodLibrary: library))
            } catch {
                await send(.loadFailed("读取营养看板数据失败：\(error.localizedDescription)"))
            }
        }
    }
}
