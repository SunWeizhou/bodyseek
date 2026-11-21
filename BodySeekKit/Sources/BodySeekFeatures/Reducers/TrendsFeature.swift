import BodySeekCore
import BodySeekHealth
import ComposableArchitecture
import Foundation
import os

@Reducer
public struct TrendsFeature: Sendable {
    public struct EvaluatedExperimentRow: Identifiable, Equatable, Sendable {
        public let planItem: PlanItemRecord
        public let record: NOfOneExperimentRecord
        public let evaluation: NOfOneExperimentEvaluation
        public var id: UUID { planItem.id }
    }

    @ObservableState
    public struct State: Equatable, Sendable {
        public var horizon: TrendHorizon = .month {
            didSet {
                if oldValue != horizon {
                    refreshActiveSlices()
                }
            }
        }

        public var selectedKind: MetricKind = .recovery {
            didSet {
                if oldValue != selectedKind {
                    refreshActiveSlices()
                }
            }
        }

        public var selectedDate: Date?
        public var showCoverageSheet: Bool = false
        public var snapshot: BodySeekDashboardSnapshot {
            didSet {
                if oldValue != snapshot {
                    refreshExperimentEvaluations()
                }
            }
        }
        public var patternFindings: [PatternFindingRecord] = []
        public var experimentPlanItems: [PlanItemRecord] = [] {
            didSet {
                if oldValue != experimentPlanItems {
                    refreshExperimentEvaluations()
                }
            }
        }
        public var eatingAvailableDayKeys: Set<DayKey> = []
        public var personalForecast: PersonalForecastState
        public var lastError: String?
        public var chartCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]
        public var activeChartSnapshot: ChartSeriesSnapshot
        public var allMetricSnapshots: [ChartSeriesSnapshot]
        public var activeSeries: TrendSeries
        public var allMetricSeries: [TrendSeries]

        /// N-of-1 实验的解码与评估结果。原先每次 body 渲染都重新解码 JSON 并重跑评估，
        /// 现在只在快照或实验条目变化时计算一次。
        private var experimentEvaluations: [EvaluatedExperimentRow] = []

        public var evaluatedExperiments: [EvaluatedExperimentRow] {
            experimentEvaluations
        }

        private mutating func refreshExperimentEvaluations() {
            experimentEvaluations = Self.evaluateExperiments(
                planItems: experimentPlanItems,
                snapshot: snapshot
            )
        }

        private static let experimentLogger = Logger(
            subsystem: "com.sunweizhou.Vela4",
            category: "TrendsFeature"
        )

        private static func evaluateExperiments(
            planItems: [PlanItemRecord],
            snapshot: BodySeekDashboardSnapshot
        ) -> [EvaluatedExperimentRow] {
            let decoder = JSONDecoder()
            let referenceKey = snapshot.referenceDate.physiologicalDayKey()
            return planItems.compactMap { item in
                guard item.kind == .experiment,
                      let data = item.payloadJSON.data(using: .utf8) else {
                    return nil
                }
                do {
                    let rec = try decoder.decode(NOfOneExperimentRecord.self, from: data)
                    let eval = NOfOneExperimentEvaluator.evaluate(
                        record: rec,
                        historyDays: snapshot.historyDays,
                        referenceDayKey: referenceKey
                    )
                    return EvaluatedExperimentRow(planItem: item, record: rec, evaluation: eval)
                } catch {
                    experimentLogger.error("Failed decoding NOfOneExperimentRecord: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
        }

        public func cache(for kind: MetricKind) -> [TrendHorizon: ChartSeriesSnapshot] {
            var map: [TrendHorizon: ChartSeriesSnapshot] = [:]
            for h in TrendHorizon.allCases {
                if let snap = chartCache[h]?[kind] {
                    map[h] = snap
                }
            }
            return map
        }

        public init(
            snapshot: BodySeekDashboardSnapshot,
            precomputedCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]? = nil
        ) {
            let initialHorizon: TrendHorizon = .month
            let initialKind: MetricKind = .recovery
            let resolvedCache = precomputedCache ?? BevelScoringEngine.buildAllChartSnapshots(
                days: snapshot.historyDays,
                referenceDate: snapshot.referenceDate
            )
            let slices = Self.deriveSlices(
                cache: resolvedCache,
                horizon: initialHorizon,
                selectedKind: initialKind,
                snapshot: snapshot
            )
            self.snapshot = snapshot
            self.personalForecast = PersonalForecasterEngine.forecast(
                historyDays: snapshot.historyDays,
                referenceDate: snapshot.referenceDate
            )
            self.chartCache = resolvedCache
            self.activeChartSnapshot = slices.activeSnapshot
            self.allMetricSnapshots = slices.allSnapshots
            self.activeSeries = slices.activeSeries
            self.allMetricSeries = slices.allSeries
            self.experimentEvaluations = Self.evaluateExperiments(
                planItems: self.experimentPlanItems,
                snapshot: snapshot
            )
        }

        public mutating func updateSnapshot(
            _ newSnapshot: BodySeekDashboardSnapshot,
            precomputedCache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]]? = nil,
            eatingAvailableDayKeys: Set<DayKey>? = nil
        ) {
            if let eatingAvailableDayKeys {
                self.eatingAvailableDayKeys = eatingAvailableDayKeys
            }
            self.snapshot = newSnapshot
            self.personalForecast = PersonalForecasterEngine.forecast(
                historyDays: newSnapshot.historyDays,
                referenceDate: newSnapshot.referenceDate,
                eatingAvailableDayKeys: self.eatingAvailableDayKeys
            )
            self.chartCache = precomputedCache ?? BevelScoringEngine.buildAllChartSnapshots(
                days: newSnapshot.historyDays,
                referenceDate: newSnapshot.referenceDate
            )
            refreshActiveSlices()
        }

        public mutating func refreshPersonalForecast() {
            self.personalForecast = PersonalForecasterEngine.forecast(
                historyDays: snapshot.historyDays,
                referenceDate: snapshot.referenceDate,
                eatingAvailableDayKeys: eatingAvailableDayKeys
            )
        }

        private mutating func refreshActiveSlices() {
            let slices = Self.deriveSlices(
                cache: chartCache,
                horizon: horizon,
                selectedKind: selectedKind,
                snapshot: snapshot
            )
            self.activeChartSnapshot = slices.activeSnapshot
            self.allMetricSnapshots = slices.allSnapshots
            self.activeSeries = slices.activeSeries
            self.allMetricSeries = slices.allSeries
        }

        private struct DerivedSlices {
            let activeSnapshot: ChartSeriesSnapshot
            let allSnapshots: [ChartSeriesSnapshot]
            let activeSeries: TrendSeries
            let allSeries: [TrendSeries]
        }

        private static func deriveSlices(
            cache: [TrendHorizon: [MetricKind: ChartSeriesSnapshot]],
            horizon: TrendHorizon,
            selectedKind: MetricKind,
            snapshot: BodySeekDashboardSnapshot
        ) -> DerivedSlices {
            let horizonMap = cache[horizon] ?? [:]
            let allSnapshots: [ChartSeriesSnapshot] = MetricKind.allCases.map { kind in
                horizonMap[kind] ?? BevelScoringEngine.buildChartSeriesSnapshot(
                    for: kind,
                    horizon: horizon,
                    days: snapshot.historyDays,
                    referenceDate: snapshot.referenceDate
                )
            }
            let activeSnapshot = horizonMap[selectedKind]
                ?? allSnapshots.first(where: { $0.kind == selectedKind })
                ?? allSnapshots[0]
            let allSeries = allSnapshots.map { $0.toLegacyTrendSeries() }
            let activeSeries = activeSnapshot.toLegacyTrendSeries()
            return DerivedSlices(
                activeSnapshot: activeSnapshot,
                allSnapshots: allSnapshots,
                activeSeries: activeSeries,
                allSeries: allSeries
            )
        }
    }

    public enum Action: Equatable, Sendable {
        case horizonChanged(TrendHorizon)
        case kindSelected(MetricKind)
        case selectedDateChanged(Date?)
        case coverageSheetPresented(Bool)
        case openMetricDetail(MetricKind)
        case startExperimentTapped(NOfOneExperimentTemplate)
        case completeExperimentTapped(PlanItemRecord)
        case experimentPersisted(PlanItemRecord)
        case confirmPatternTapped(PatternFindingRecord)
        case dismissPatternTapped(PatternFindingRecord)
        case patternUpdated(PatternFindingRecord, TieredMemoryRecord?)
        case storeOperationFailed(String)
        case delegate(Delegate)

        @CasePathable
        public enum Delegate: Equatable, Sendable {
            case openMetric(MetricKind, TrendHorizon)
            case patternFindingsUpdated([PatternFindingRecord])
            case tieredMemoryAdded(TieredMemoryRecord)
        }
    }

    @Dependency(\.bodySeekStoreClient) var bodySeekStoreClient
    @Dependency(\.date.now) var now

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .horizonChanged(horizon):
                state.horizon = horizon
                state.selectedDate = nil
                return .none

            case let .kindSelected(kind):
                state.selectedKind = kind
                state.selectedDate = nil
                return .none

            case let .selectedDateChanged(date):
                state.selectedDate = date
                return .none

            case let .coverageSheetPresented(presented):
                state.showCoverageSheet = presented
                return .none

            case let .openMetricDetail(kind):
                return .send(.delegate(.openMetric(kind, state.horizon)))

            case let .startExperimentTapped(template):
                if state.evaluatedExperiments.contains(where: { $0.record.templateID == template.id && $0.planItem.state == .adopted }) {
                    return .none
                }
                let refDayKey = state.snapshot.referenceDate.physiologicalDayKey()
                let experiment = NOfOneExperimentRecord(template: template, startDayKey: refDayKey)
                do {
                    let payloadData = try JSONEncoder().encode(experiment)
                    let payloadJSON = String(data: payloadData, encoding: .utf8) ?? "{}"
                    let item = PlanItemRecord(
                        id: experiment.id,
                        dayKey: refDayKey,
                        kind: .experiment,
                        payloadJSON: payloadJSON,
                        state: .adopted,
                        origin: .user
                    )
                    let itemToSave = item
                    return .run { send in
                        do {
                            let proposal = try ActionProposal(
                                kind: .adjustPlan,
                                origin: .user,
                                encodablePayload: AdjustPlanPayload(item: itemToSave),
                                rationale: "发起 14 天 N-of-1 自实验：\(template.title)"
                            )
                            _ = try await bodySeekStoreClient.executeProposal(proposal)
                            await send(.experimentPersisted(itemToSave))
                        } catch {
                            await send(.storeOperationFailed("保存 N-of-1 实验失败：\(error.localizedDescription)"))
                        }
                    }
                } catch {
                    state.lastError = "编码实验方案失败：\(error.localizedDescription)"
                    return .none
                }

            case let .completeExperimentTapped(planItem):
                var updated = planItem
                updated.state = .completed
                let itemToSave = updated
                return .run { send in
                    do {
                        let proposal = try ActionProposal(
                            kind: .adjustPlan,
                            origin: .user,
                            encodablePayload: AdjustPlanPayload(item: itemToSave),
                            rationale: "完成并归档 N-of-1 自实验"
                        )
                        _ = try await bodySeekStoreClient.executeProposal(proposal)
                        await send(.experimentPersisted(itemToSave))
                    } catch {
                        await send(.storeOperationFailed("结束 N-of-1 实验失败：\(error.localizedDescription)"))
                    }
                }

            case let .experimentPersisted(item):
                if let idx = state.experimentPlanItems.firstIndex(where: { $0.id == item.id }) {
                    state.experimentPlanItems[idx] = item
                } else {
                    state.experimentPlanItems.insert(item, at: 0)
                }
                state.lastError = nil
                return .none

            case let .confirmPatternTapped(finding):
                var updatedFinding = finding
                updatedFinding.status = .confirmed
                let findingToSave = updatedFinding
                let mem = TieredMemoryRecord(
                    tier: .verifiedPattern,
                    content: finding.statement,
                    scopeJSON: "{\"pattern_id\":\"\(finding.id.uuidString)\"}",
                    confidence: 1.0,
                    expiresAt: nil,
                    confirmedAt: now,
                    retiredAt: nil
                )
                return .run { send in
                    do {
                        try await bodySeekStoreClient.savePatternFinding(findingToSave)
                        let proposal = try ActionProposal(
                            kind: .commitMemory,
                            origin: .user,
                            encodablePayload: CommitMemoryPayload(memory: mem),
                            rationale: "用户于趋势页确认个人统计规律并晋升为 Verified Pattern"
                        )
                        _ = try await bodySeekStoreClient.executeProposal(proposal)
                        await send(.patternUpdated(findingToSave, mem))
                    } catch {
                        await send(.storeOperationFailed("确认个人规律失败：\(error.localizedDescription)"))
                    }
                }

            case let .dismissPatternTapped(finding):
                var updatedFinding = finding
                updatedFinding.status = .dismissed
                let findingToSave = updatedFinding
                return .run { send in
                    do {
                        try await bodySeekStoreClient.savePatternFinding(findingToSave)
                        await send(.patternUpdated(findingToSave, nil))
                    } catch {
                        await send(.storeOperationFailed("忽略规律条目失败：\(error.localizedDescription)"))
                    }
                }

            case let .patternUpdated(finding, newMemory):
                if let idx = state.patternFindings.firstIndex(where: { $0.id == finding.id }) {
                    state.patternFindings[idx] = finding
                } else {
                    state.patternFindings.insert(finding, at: 0)
                }
                let updatedFindings = state.patternFindings
                state.lastError = nil
                if let newMemory {
                    return .merge(
                        .send(.delegate(.patternFindingsUpdated(updatedFindings))),
                        .send(.delegate(.tieredMemoryAdded(newMemory)))
                    )
                }
                return .send(.delegate(.patternFindingsUpdated(updatedFindings)))

            case let .storeOperationFailed(message):
                state.lastError = message
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
