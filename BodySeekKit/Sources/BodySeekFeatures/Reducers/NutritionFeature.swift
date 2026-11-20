import BodySeekCore
import BodySeekHealth
import ComposableArchitecture
import Foundation

@Reducer
public struct NutritionFeature: Sendable {
    public enum MealLogger: String, Identifiable, Sendable {
        case manual
        case assistant

        public var id: Self { self }
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
        case foodSearchResultsLoaded([FoodLibraryItem])
        case mealLoggerPresented(Bool)
        case mealAssistantTapped
        case libraryPresented(Bool)
        case profileTargetPresented(Bool)
        case mealDraftConfirmed([MealEntry], fromPhoto: Bool)
        case logMealSubmitted(
            mealType: MealType,
            foodName: String,
            foodID: String?,
            portionAmount: Double,
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
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case nutritionDataChanged(
                todayLog: DailyNutritionLog?,
                plan: NutritionTargetPlan?,
                rollingDeficit7d: Double?
            )
        }
    }

    @Dependency(\.bodySeekStoreClient) var storeClient
    @Dependency(\.date.now) var now

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
                if !library.isEmpty {
                    state.foodLibrary = library
                }
                state.recomputeSummary()
                let todayLog = logs.first(where: { $0.dayKey == state.todayKey })
                return .send(.delegate(.nutritionDataChanged(
                    todayLog: todayLog,
                    plan: targetPlan,
                    rollingDeficit7d: state.periodSummary.rollingDeficit7dKcal
                )))

            case let .loadFailed(message):
                state.isLoading = false
                state.isSaving = false
                state.lastError = message
                return .none

            case let .periodModeChanged(mode):
                state.periodMode = mode
                state.recomputeSummary()
                return .none

            case let .stepPeriod(direction):
                let cal = Calendar(identifier: .gregorian)
                let deltaDays = (state.periodMode == .week ? 7 : 30) * direction
                let cur = state.anchorDayKey.calendarDayStart(calendar: cal)
                let nextDate = cal.date(byAdding: .day, value: deltaDays, to: cur) ?? cur
                let candidate = DayKey.fromCalendarDay(nextDate, calendar: cal)
                state.anchorDayKey = min(candidate, state.todayKey)
                state.selectedDayKey = state.anchorDayKey
                state.recomputeSummary()
                return .none

            case let .daySelected(dayKey):
                state.selectedDayKey = dayKey
                return .none

            case let .toggleMicroGroup(group):
                state.expandedMicroGroup = state.expandedMicroGroup == group ? nil : group
                return .none

            case let .foodSearchChanged(query):
                state.foodSearchQuery = query
                return .run { send in
                    do {
                        let results = try await storeClient.searchFoodLibrary(query)
                        await send(.foodSearchResultsLoaded(results))
                    } catch {
                        await send(.mutationFailed("搜索营养库失败：\(error.localizedDescription)"))
                    }
                }

            case let .foodSearchResultsLoaded(items):
                state.foodLibrary = items
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
                state.isSaving = true
                let dayKey = state.selectedDayKey
                let entry = MealEntry(
                    dayKey: dayKey,
                    mealType: mealType,
                    foodID: foodID,
                    foodName: foodName,
                    portionAmount: portionAmount,
                    portionUnit: portionUnit,
                    kcal: kcal,
                    carbsG: carbsG,
                    proteinG: proteinG,
                    fatG: fatG,
                    fiberG: fiberG,
                    waterMl: waterMl,
                    vitamins: vitamins,
                    minerals: minerals,
                    isEstimated: isEstimated,
                    recordedAt: now
                )
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
                            rationale: "用户记录餐次 \(mealType.title)：\(foodName)"
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
                let matchingDay = state.snapshot.historyDays.first(where: { $0.dayKey == dayKey }) ?? state.snapshot.today
                let activeKcal = matchingDay.raw.activeEnergyKcal
                    ?? state.selectedDayLog?.sportKcal
                    ?? 0
                let sportHours: Double? = {
                    let workoutMinutes = matchingDay.raw.workouts.reduce(0) { $0 + $1.durationMinutes }
                    if workoutMinutes > 0 { return (Double(workoutMinutes) / 60.0 * 100).rounded() / 100 }
                    if let ex = matchingDay.raw.exerciseMinutes { return (Double(ex) / 60.0 * 100).rounded() / 100 }
                    return state.selectedDayLog?.sportHours
                }()
                let steps = matchingDay.raw.steps ?? state.selectedDayLog?.steps
                let bmr = state.profile?.bmrKcalReference
                    ?? state.selectedDayLog?.bmrKcalUsed
                    ?? NutritionPlanFactory.estimateBMR(
                        sex: state.profile?.referenceSex,
                        weightKg: matchingDay.raw.bodyMassKg ?? state.profile?.referenceWeightKg,
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
