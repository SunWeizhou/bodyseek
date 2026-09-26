import Foundation

// These values are already immutable projections.  The legacy declarations
// predate Swift concurrency annotations, so the conformance is kept here at
// the feature boundary rather than making the persistence/domain layers know
// about Today.
extension DashboardSummary.DataSource: @unchecked Sendable {}
extension TodayExperienceModel: @unchecked Sendable {}
extension DailyDecisionFeedbackValues: @unchecked Sendable {}


enum TodayMetricID: String, CaseIterable, Codable, Hashable, Sendable {
    case recovery
    case sleep
    case strain
    case stress
    case energy
}

struct TodayScoreProjection: Equatable, Sendable, Identifiable {
    let id: TodayMetricID
    let metric: MetricResult
}

/// The five scores are intentionally separate.  A missing value remains
/// missing all the way to the renderer (`MetricResult.formattedScore == "--"`)
/// and is never converted into an aggregate or a zero.
struct TodayScoreState: Equatable, Sendable {
    var recovery: MetricResult
    var sleep: MetricResult
    var strain: MetricResult
    var stress: MetricResult
    var energy: MetricResult

    var ordered: [TodayScoreProjection] {
        [
            TodayScoreProjection(id: .recovery, metric: recovery),
            TodayScoreProjection(id: .sleep, metric: sleep),
            TodayScoreProjection(id: .strain, metric: strain),
            TodayScoreProjection(id: .stress, metric: stress),
            TodayScoreProjection(id: .energy, metric: energy)
        ]
    }

    func metric(for id: TodayMetricID) -> MetricResult {
        switch id {
        case .recovery: return recovery
        case .sleep: return sleep
        case .strain: return strain
        case .stress: return stress
        case .energy: return energy
        }
    }

    static func empty(for day: Date) -> TodayScoreState {
        func unavailable(_ name: String, _ input: String, _ domain: ScoredHealthDomain) -> MetricResult {
            MetricResult(
                domain: domain,
                name: name,
                value: nil,
                band: .low,
                confidence: .low,
                components: [:],
                componentWeights: [:],
                reasons: ["Health data unavailable."],
                missingInputs: [input],
                dataWindow: DateInterval(start: day, duration: 86_400),
                source: .derived,
                algorithmVersion: "1.0.0",
                lastUpdated: day
            )
        }

        return TodayScoreState(
            recovery: unavailable("Recovery Score", "recoveryMetrics", .recovery),
            sleep: unavailable("Sleep Score", "sleepSummary", .sleep),
            strain: unavailable("Strain Score", "strain", .strain),
            stress: unavailable("Physiological Stress Index", "stress", .physiologicalStress),
            energy: unavailable("Energy Bank", "energy", .energy)
        )
    }

    init(
        recovery: MetricResult,
        sleep: MetricResult,
        strain: MetricResult,
        stress: MetricResult,
        energy: MetricResult
    ) {
        self.recovery = recovery
        self.sleep = sleep
        self.strain = strain
        self.stress = stress
        self.energy = energy
    }

    init(snapshot: DashboardSummary) {
        self.init(
            recovery: snapshot.recovery,
            sleep: snapshot.sleepScore,
            strain: snapshot.strain,
            stress: snapshot.stress,
            energy: snapshot.energy
        )
    }
}

/// Compact, immutable projection for the redesigned Today surface. It keeps
/// page composition independent from the full Store state while preserving
/// the same five-score and evidence semantics.
struct TodayPresentationState: Equatable, Sendable {
    let selectedDay: Date
    let headline: String
    let summary: String
    let primaryActionTitle: String?
    let scores: TodayScoreState
    let phase: TodayViewState.Phase
    let freshness: DataFreshness
    let coverage: DataCoverageSummaryModel
}

enum TodayLoadFailure: Equatable, Sendable, LocalizedError {
    case invalidDay
    case reader(String)

    var errorDescription: String? {
        switch self {
        case .invalidDay: return "Today cannot load a future day."
        case .reader(let message): return message
        }
    }
}

struct TodayLivedStateProjection: Codable, Equatable, Hashable, Sendable {
    var alignment: LivedStateAlignment?
    var checkIn: LivedStateCheckIn?

    static let empty = TodayLivedStateProjection(alignment: nil, checkIn: nil)
}

/// Value-only feedback read model.  The SwiftData record remains behind the
/// compatibility reader; TodayStore/ViewState never carry the record itself.
/// Optional fields preserve an in-progress feedback form without treating it
/// as a completed submission.
struct TodayFeedbackProjection: Codable, Equatable, Hashable, Sendable {
    var isSubmitted: Bool
    var summary: String?
    var adoptionStatus: String?
    var accuracyRating: String?
    var actualAction: String?
    var energyRating: Int?
    var fatigueRating: Int?
    var painRating: Int?
    var satisfactionRating: Int?
    var note: String?

    init(
        isSubmitted: Bool,
        summary: String?,
        adoptionStatus: String? = nil,
        accuracyRating: String? = nil,
        actualAction: String? = nil,
        energyRating: Int? = nil,
        fatigueRating: Int? = nil,
        painRating: Int? = nil,
        satisfactionRating: Int? = nil,
        note: String? = nil
    ) {
        self.isSubmitted = isSubmitted
        self.summary = summary
        self.adoptionStatus = adoptionStatus
        self.accuracyRating = accuracyRating
        self.actualAction = actualAction
        self.energyRating = energyRating
        self.fatigueRating = fatigueRating
        self.painRating = painRating
        self.satisfactionRating = satisfactionRating
        self.note = note
    }

    static let empty = TodayFeedbackProjection(isSubmitted: false, summary: nil)
}

struct TodayPlanProjection: Codable, Equatable, Hashable, Sendable {
    var title: String
    var detail: String?

    init(title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    init(payload: DailyOperatingPlanPayload) {
        self.init(
            title: payload.targetSessionTitle
                ?? payload.primaryAction?.title
                ?? "今日计划",
            detail: payload.summary
        )
    }
}

/// Value-only projection of a proposed plan adaptation. The persisted
/// `TrainingPlanAdaptationRecord` stays behind the compatibility reader; this
/// type deliberately carries only display data needed by Today.
struct TodayPendingPlanProjection: Codable, Equatable, Hashable, Sendable {
    let id: UUID
    let adjustment: String
    let reason: String
    let suggestedAlternative: String?
    let originalDayTitle: String
    let createdAt: Date
    let status: String

    init(
        id: UUID,
        adjustment: String,
        reason: String,
        suggestedAlternative: String? = nil,
        originalDayTitle: String,
        createdAt: Date,
        status: String = "proposed"
    ) {
        self.id = id
        self.adjustment = adjustment
        self.reason = reason
        self.suggestedAlternative = suggestedAlternative
        self.originalDayTitle = originalDayTitle
        self.createdAt = createdAt
        self.status = status
    }
}

/// Weather is intentionally optional and field-wise optional. A location or
/// temperature that has not been fetched is not represented as a fabricated
/// zero; `status == .unavailable` keeps that distinction explicit.
struct TodayWeatherProjection: Codable, Equatable, Hashable, Sendable {
    enum Status: String, Codable, Hashable, Sendable {
        case available
        case unavailable
    }

    let status: Status
    let temperature: Double?
    let apparentTemperature: Double?
    let humidity: Double?
    let windSpeed: Double?
    let conditionCode: Int?
    let isDay: Bool?
    let locationName: String?
    let capturedAt: Date?

    init(
        status: Status,
        temperature: Double? = nil,
        apparentTemperature: Double? = nil,
        humidity: Double? = nil,
        windSpeed: Double? = nil,
        conditionCode: Int? = nil,
        isDay: Bool? = nil,
        locationName: String? = nil,
        capturedAt: Date? = nil
    ) {
        self.status = status
        self.temperature = temperature
        self.apparentTemperature = apparentTemperature
        self.humidity = humidity
        self.windSpeed = windSpeed
        self.conditionCode = conditionCode
        self.isDay = isDay
        self.locationName = locationName
        self.capturedAt = capturedAt
    }

    static let unavailable = TodayWeatherProjection(status: .unavailable)
}

struct TodayNutritionProjection: Codable, Equatable, Hashable, Sendable {
    var calories: Int?
    var calorieTarget: Int?
    var protein: Int?
    var carbs: Int?
    var fat: Int?

    static let empty = TodayNutritionProjection(
        calories: nil,
        calorieTarget: nil,
        protein: nil,
        carbs: nil,
        fat: nil
    )
}

struct TodayNonCriticalState: Equatable, Sendable {
    var weatherMessage: String?
    var nutritionError: String?
    var planError: String?
    var coachError: String?

    static let empty = TodayNonCriticalState(
        weatherMessage: nil,
        nutritionError: nil,
        planError: nil,
        coachError: nil
    )
}

struct TodayViewState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case idle
        case loading(previous: Bool)
        case ready
        case empty
        case failed(TodayLoadFailure)
    }

    let selectedDay: Date
    /// The complete value read-model for the currently selected day.  It is
    /// captured by the reader and is the only dashboard source the Today root
    /// renders; `DashboardViewModel` remains an adapter concern.
    var dashboard: DashboardSummary
    var bodyState: BodyState
    var trainingDecision: DailyTrainingDecision?
    var phase: Phase
    var source: DashboardSummary.DataSource
    var freshness: DataFreshness
    var scores: TodayScoreState
    var command: TodayCommandState?
    var experience: TodayExperienceModel?
    var coverage: DataCoverageSummaryModel
    var livedState: TodayLivedStateProjection
    var feedback: TodayFeedbackProjection
    var plan: TodayPlanProjection?
    /// Active plan and a pending adaptation are separate values so a proposal
    /// cannot be mistaken for the executable plan.
    var activePlan: TodayPlanProjection?
    var pendingPlan: TodayPendingPlanProjection?
    var nutrition: TodayNutritionProjection?
    var weather: TodayWeatherProjection
    var operatingPlanPayload: DailyOperatingPlanPayload?
    var todayAIInsight: DailyAIInsight?
    var lastUpdated: Date?
    var vitalTrendSeries: [String: [Double]]
    var errorMessage: String?
    var secondaryDataErrorMessage: String?
    var nonCritical: TodayNonCriticalState
    var error: TodayLoadFailure?

    var bodySeekPresentation: TodayPresentationState {
        TodayPresentationState(
            selectedDay: selectedDay,
            headline: experience?.hero.decisionTitle ?? "今天的身体状态",
            summary: experience?.hero.summary ?? "正在整理今天的身体信号。",
            primaryActionTitle: experience?.hero.primaryActionTitle,
            scores: scores,
            phase: phase,
            freshness: freshness,
            coverage: coverage
        )
    }

    /// Keep the initial state independent from the app language/preferences
    /// store.  Coverage is an explicit unknown until a reader/coverage adapter
    /// supplies a value; it must not consult a global default while rendering
    /// the first frame.
    private static var unknownCoverage: DataCoverageSummaryModel {
        DataCoverageSummaryModel(
            scorePercent: 0,
            status: .unknown,
            title: "Checking data coverage",
            subtitle: "Key health signals are being checked for freshness and completeness.",
            actionTitle: "View data",
            actionSystemImage: "waveform.path.ecg.rectangle",
            domainSummaries: [],
            topBlockers: [],
            coachContextLine: "Data coverage unknown; avoid high-confidence physiological claims until coverage finishes loading."
        )
    }

    static func initial(day: Date) -> TodayViewState {
        let dashboard = DashboardSummary.empty(date: day)
        return TodayViewState(
            selectedDay: day,
            dashboard: dashboard,
            bodyState: dashboard.bodyState,
            trainingDecision: nil,
            phase: .idle,
            source: .empty,
            freshness: .missing,
            scores: .empty(for: day),
            command: nil,
            experience: nil,
            coverage: Self.unknownCoverage,
            livedState: .empty,
            feedback: .empty,
            plan: nil,
            activePlan: nil,
            pendingPlan: nil,
            nutrition: nil,
            weather: .unavailable,
            operatingPlanPayload: nil,
            todayAIInsight: nil,
            lastUpdated: nil,
            vitalTrendSeries: [:],
            errorMessage: nil,
            secondaryDataErrorMessage: nil,
            nonCritical: .empty,
            error: nil
        )
    }

    static func projection(
        snapshot: TodayDashboardSnapshot,
        selectedDay: Date,
        now: Date,
        calendar: Calendar
    ) -> TodayViewState {
        let dashboard = snapshot.dashboard
        let scores = TodayScoreState(snapshot: dashboard)
        let hasEvidence = scores.ordered.contains { $0.metric.value != nil }
        return TodayViewState(
            selectedDay: selectedDay,
            dashboard: dashboard,
            bodyState: snapshot.bodyState ?? dashboard.bodyState,
            trainingDecision: snapshot.trainingDecision,
            phase: hasEvidence ? .ready : .empty,
            source: dashboard.source,
            freshness: Self.freshness(
                scores: scores,
                selectedDay: selectedDay,
                now: now,
                calendar: calendar
            ),
            scores: scores,
            // These are produced once by the reader's secondary-data
            // assembler.  The Store only carries the value projection; it
            // never invokes either builder while rendering.
            command: snapshot.command,
            experience: snapshot.experience,
            coverage: snapshot.coverage ?? Self.unknownCoverage,
            livedState: snapshot.livedState ?? .empty,
            feedback: snapshot.feedback ?? .empty,
            plan: snapshot.activePlan
                ?? snapshot.operatingPlanPayload.map(TodayPlanProjection.init(payload:)),
            activePlan: snapshot.activePlan
                ?? snapshot.operatingPlanPayload.map(TodayPlanProjection.init(payload:)),
            pendingPlan: snapshot.pendingPlan,
            nutrition: snapshot.nutrition,
            weather: snapshot.weather ?? .unavailable,
            operatingPlanPayload: snapshot.operatingPlanPayload,
            todayAIInsight: snapshot.todayAIInsight,
            lastUpdated: snapshot.lastUpdated,
            vitalTrendSeries: snapshot.vitalTrendSeries,
            errorMessage: snapshot.errorMessage,
            secondaryDataErrorMessage: snapshot.secondaryDataErrorMessage,
            nonCritical: .empty,
            error: nil
        )
    }

    /// Explicit no-data command projection for the first frame.  This is a
    /// value-only placeholder, not a compatibility call into
    /// `TodayCommandBuilder`.
    static func unavailableCommand(for day: Date) -> TodayCommandState {
        TodayCommandState(
            date: day,
            bodyStateTitle: "今日状态待同步",
            summary: "连接 Apple 健康并完成同步后，这里会显示今日建议。",
            readinessDecision: ReadinessDecision(
                decision: .recover,
                confidence: 0,
                reasons: ["今日健康数据尚未同步。"],
                supportingSignals: [],
                userOverrideAvailable: false
            ),
            keySignals: [],
            actions: [],
            coachArtifact: nil,
            dataConfidence: .unavailable
        )
    }

    /// Conservative first-frame experience.  It keeps the five-card grammar
    /// visible with explicit `--` values until the reader provides a complete
    /// projection, without rebuilding the experience model in a View getter.
    static func unavailableExperience(for day: Date) -> TodayExperienceModel {
        let cards: [TodayExperienceSignalCard] = [
            ("recovery", "恢复", .recovery),
            ("sleep", "睡眠", .sleep),
            ("strain", "负荷", .strain),
            ("stress", "压力", .stress),
            ("energy", "能量", .energy)
        ].map { id, title, accent in
            TodayExperienceSignalCard(
                id: id,
                title: title,
                value: "--",
                directionLabel: "待同步",
                confidenceLabel: "数据不足",
                coverageLabel: "未同步",
                subtitle: "等待健康数据",
                trend: [],
                accent: accent,
                state: .moderate
            )
        }
        return TodayExperienceModel(
            generatedAt: day,
            hero: TodayExperienceHero(
                scoreTitle: "今日状态",
                decisionTitle: "今日状态待同步",
                summary: "连接 Apple 健康并完成同步后，这里会显示今日建议。",
                confidenceLabel: "数据不足",
                primaryActionTitle: "查看证据"
            ),
            signalCards: cards,
            baselineFormation: .waiting,
            evidenceChips: [],
            actions: [],
            nutrition: .empty,
            coachPreview: "连接 Apple 健康后开始形成个人基线。"
        )
    }

    private static func freshness(
        scores: TodayScoreState,
        selectedDay: Date,
        now: Date,
        calendar: Calendar
    ) -> DataFreshness {
        let dates = scores.ordered.compactMap { metric in
            metric.metric.value == nil ? nil : metric.metric.lastUpdated
        }
        guard let latest = dates.max() else { return .missing }
        let age = max(0, now.timeIntervalSince(latest))
        if age <= 2 * 3_600 { return .live }
        if calendar.isDate(latest, inSameDayAs: selectedDay) { return .today }
        if age <= 3 * 86_400 { return .recent }
        return .stale
    }
}
