import Foundation
import SwiftData

struct AIContextBuilder {
    static let schemaVersion = "v1.0"
    static let canonicalSchemaVersion = "v2.0"

    func build(
        dashboard: DashboardSummary,
        journalEntries: [JournalContextEntry],
        historicalReports: [GeneratedAIReport],
        userWiki: [String: String],
        weeklyTrends: [String: String] = [:],
        foodLogs: [FoodLogRecord] = [],
        workoutEvents: [WorkoutEventRecord] = [],
        strengthWorkouts: [StrengthWorkoutRecord] = [],
        trainingResponses: [TrainingResponseRecord] = [],
        onboardingState: OnboardingState? = nil,
        bodyModelState: BodyModelState? = nil,
        bodyState: BodyState? = nil,
        generatedAt: Date = Date()
    ) -> (envelope: AgentContextEnvelope, metadata: ContextSnapshotMetadata) {
        let mergedUserWiki = Self.mergedUserWiki(userWiki, onboardingState: onboardingState, bodyModelState: bodyModelState)
        let resolvedBodyState = bodyState ?? BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            workoutEvents: workoutEvents.map { $0.dto },
            strengthWorkouts: strengthWorkouts.map { $0.dto },
            trainingResponses: trainingResponses.map { $0.dto },
            foodLogs: foodLogs.map { $0.dto },
            generatedAt: generatedAt
        ))
        let envelope = LegacyReportContextAdapter().render(
            dashboard: dashboard,
            bodyState: resolvedBodyState,
            journalEntries: journalEntries,
            historicalReports: historicalReports,
            mergedUserWiki: mergedUserWiki,
            weeklyTrends: weeklyTrends,
            nutrition: buildNutritionDict(foodLogs),
            unifiedWorkouts: buildUnifiedWorkoutDict(workoutEvents, generatedAt: generatedAt),
            strengthTraining: buildStrengthTrainingDict(
                strengthWorkouts,
                trainingResponses: trainingResponses,
                dashboard: dashboard,
                generatedAt: generatedAt
            ),
            generatedAt: generatedAt
        )

        let hash = legacyContentHash(envelope)
        let metadata = ContextSnapshotMetadata(
            schemaVersion: AIContextBuilder.schemaVersion,
            generatedAt: generatedAt,
            hash: hash,
            includedSections: [
                "today_summary", "body_state", "sleep", "recovery", "strain", "workouts",
                "unified_workouts", "stress", "energy_bank", "health_age_trend", "nutrition",
                "journal", "user_wiki", "extended_metrics", "strength_training"
            ] + (onboardingState == nil ? [] : ["body_model_profile"])
                + (bodyModelState == nil ? [] : ["body_model_state"]),
            redactedFields: []
        )
        return (envelope: envelope, metadata: metadata)
    }

    // MARK: - Canonical Agent Facts (v2)

    func buildFacts(
        dashboard: DashboardSummary,
        journalEntries: [JournalContextEntry],
        historicalReports: [GeneratedAIReport],
        userWiki: [String: String],
        weeklyTrends: [String: String] = [:],
        foodLogs: [FoodLogRecord] = [],
        workoutEvents: [WorkoutEventRecord] = [],
        strengthWorkouts: [StrengthWorkoutRecord] = [],
        trainingResponses: [TrainingResponseRecord] = [],
        onboardingState: OnboardingState? = nil,
        bodyModelState: BodyModelState? = nil,
        bodyState: BodyState? = nil,
        trainingDecision: DailyTrainingDecision? = nil,
        dataCoverage: AgentDataCoverageContext? = nil,
        profileAge: Int? = nil,
        scoringContext: ScoringContext? = nil,
        dailyOperatingPlan: [String: String]? = nil,
        activePlan: TrainingPlanDTO? = nil,
        calendar: Calendar = .current,
        generatedAt: Date = Date()
    ) -> (snapshot: AgentFactSnapshot, metadata: ContextSnapshotMetadata) {
        let mergedUserWiki = Self.mergedUserWiki(userWiki, onboardingState: onboardingState, bodyModelState: bodyModelState)
        let resolvedBodyState = bodyState ?? BodyStateKernel().build(input: BodyStateInput(
            dashboard: dashboard,
            workoutEvents: workoutEvents.map { $0.dto },
            strengthWorkouts: strengthWorkouts.map { $0.dto },
            trainingResponses: trainingResponses.map { $0.dto },
            foodLogs: foodLogs.map { $0.dto },
            generatedAt: generatedAt
        ))
        let hrvMs = dashboard.recoveryMetrics.hrvMilliseconds
        let rhrBpm = dashboard.recoveryMetrics.restingHeartRate

        func dataConfidence(_ confidence: MetricConfidence) -> DataConfidence {
            switch confidence {
            case .high: .high
            case .medium: .medium
            case .low: .low
            }
        }

        func freshness(measuredAt: Date?, hasValue: Bool) -> DataFreshness {
            guard hasValue else { return .missing }
            guard let measuredAt else { return .recent }
            let age = generatedAt.timeIntervalSince(measuredAt)
            if age <= 2 * 3_600 { return .live }
            if calendar.isDate(measuredAt, inSameDayAs: generatedAt) { return .today }
            if age <= 3 * 86_400 { return .recent }
            return .stale
        }

        func healthMetric<T: Codable & Hashable>(
            _ value: T?,
            unit: String,
            note: String,
            measuredAt: Date? = nil,
            source: HealthDataSource = .healthKit,
            confidence: DataConfidence = .high,
            baseline: BaselineComparison? = nil
        ) -> MetricValue<T> {
            guard let value else { return .missing(unit: unit, note: note) }
            return .live(
                value,
                unit: unit,
                source: source,
                measuredAt: measuredAt,
                freshness: freshness(measuredAt: measuredAt, hasValue: true),
                confidence: confidence,
                baseline: baseline
            )
        }

        let recovery = RecoveryContext(
            score: healthMetric(dashboard.recovery.hasData ? dashboard.recovery.value : nil, unit: "pts", note: "Recovery score is not computed yet.", measuredAt: dashboard.recovery.lastUpdated, source: .computed, confidence: dataConfidence(dashboard.recovery.confidence)),
            band: dashboard.recovery.hasData ? dashboard.recovery.band.rawValue : "unavailable",
            hrv: healthMetric(hrvMs, unit: "ms", note: "HRV is unavailable.", measuredAt: dashboard.recovery.lastUpdated),
            hrvRmssd: dashboard.recoveryMetrics.hrvRmssdMilliseconds.map {
                healthMetric($0, unit: "ms", note: "RMSSD is unavailable.", measuredAt: dashboard.recovery.lastUpdated, source: .healthKit)
            },
            restingHeartRate: healthMetric(rhrBpm, unit: "bpm", note: "Resting heart rate is unavailable.", measuredAt: dashboard.recovery.lastUpdated),
            respiratoryRate: healthMetric(dashboard.recoveryMetrics.respiratoryRate, unit: "br/min", note: "Respiratory rate is unavailable.", measuredAt: dashboard.recovery.lastUpdated),
            topReason: dashboard.recovery.reasons.first,
            // 联通专项批次 3：v2 补齐 z-score。
            hrvZScore: healthMetric(dashboard.recovery.metrics["hrv_z_score"], unit: "z", note: "HRV z-score is unavailable.", measuredAt: dashboard.recovery.lastUpdated, source: .computed),
            rhrZScore: healthMetric(dashboard.recovery.metrics["rhr_z_score"], unit: "z", note: "RHR z-score is unavailable.", measuredAt: dashboard.recovery.lastUpdated, source: .computed)
        )

        let sleepMetrics = dashboard.sleepScore.metrics
        let sleep = SleepContext(
            score: healthMetric(dashboard.sleepScore.hasData ? dashboard.sleepScore.value : nil, unit: "pts", note: "Sleep score is not computed yet.", measuredAt: dashboard.sleepScore.lastUpdated, source: .computed, confidence: dataConfidence(dashboard.sleepScore.confidence)),
            band: dashboard.sleepScore.hasData ? dashboard.sleepScore.band.rawValue : "unavailable",
            totalMinutes: healthMetric(dashboard.sleepScore.hasData ? dashboard.sleepSummary.totalSleepMinutes : nil, unit: "min", note: "Sleep duration is unavailable.", measuredAt: dashboard.sleepScore.lastUpdated),
            efficiency: healthMetric(sleepMetrics["sleep_efficiency"], unit: "%", note: "Sleep efficiency is unavailable.", measuredAt: dashboard.sleepScore.lastUpdated, source: .computed),
            remPercent: healthMetric(sleepMetrics["rem_pct"], unit: "%", note: "REM sleep percentage is unavailable.", measuredAt: dashboard.sleepScore.lastUpdated, source: .computed),
            deepPercent: healthMetric(sleepMetrics["deep_pct"], unit: "%", note: "Deep sleep percentage is unavailable.", measuredAt: dashboard.sleepScore.lastUpdated, source: .computed),
            coreMinutes: healthMetric(dashboard.sleepSummary.stageMinutes[.core], unit: "min", note: "Core sleep duration is unavailable.", measuredAt: dashboard.sleepScore.lastUpdated),
            remMinutes: healthMetric(dashboard.sleepSummary.stageMinutes[.rem], unit: "min", note: "REM sleep duration is unavailable.", measuredAt: dashboard.sleepScore.lastUpdated),
            deepMinutes: healthMetric(dashboard.sleepSummary.stageMinutes[.deep], unit: "min", note: "Deep sleep duration is unavailable.", measuredAt: dashboard.sleepScore.lastUpdated),
            awakeMinutes: healthMetric(dashboard.sleepSummary.stageMinutes[.awake], unit: "min", note: "Awake duration is unavailable.", measuredAt: dashboard.sleepScore.lastUpdated),
            bedtime: dashboard.sleepSummary.bedtime,
            wakeTime: dashboard.sleepSummary.wakeTime,
            topReason: dashboard.sleepScore.reasons.first
        )

        let strain = StrainContext(
            score: healthMetric(dashboard.strain.hasData ? dashboard.strain.value : nil, unit: "pts", note: "Strain score is not computed yet.", measuredAt: dashboard.strain.lastUpdated, source: .computed, confidence: dataConfidence(dashboard.strain.confidence)),
            band: dashboard.strain.hasData ? dashboard.strain.band.rawValue : "unavailable",
            targetStatus: dashboard.strain.hasData ? dashboard.strain.targetStatus.rawValue : "unavailable",
            recommendedRangeLower: dashboard.strain.recommendedRange.lowerBound,
            recommendedRangeUpper: dashboard.strain.recommendedRange.upperBound,
            steps: healthMetric(dashboard.strain.metrics["steps_raw"].map(Int.init), unit: "steps", note: "Step count is unavailable.", measuredAt: dashboard.strain.lastUpdated),
            activeEnergyKcal: healthMetric(dashboard.strain.metrics["active_energy_raw"].map(Int.init), unit: "kcal", note: "Active energy is unavailable.", measuredAt: dashboard.strain.lastUpdated),
            exerciseMinutes: healthMetric(dashboard.strain.metrics["exercise_minutes_raw"].map(Int.init), unit: "min", note: "Exercise duration is unavailable.", measuredAt: dashboard.strain.lastUpdated)
        )

        let stress = StressContext(
            stressIndex: healthMetric(dashboard.stress.hasData ? dashboard.stress.value : nil, unit: "index", note: "Stress index is not computed yet.", measuredAt: dashboard.stress.lastUpdated, source: .computed, confidence: dataConfidence(dashboard.stress.confidence)),
            band: dashboard.stress.hasData ? dashboard.stress.band.rawValue : "unavailable",
            confidence: dashboard.stress.hasData ? (dashboard.stress.confidence.rawValue == "high" ? .high : .medium) : .unavailable,
            proxyNote: "Physiological proxy, not a medical or mental health diagnosis.",
            // 联通专项批次 3：压力六因子进 v2。
            rhrStress: healthMetric(dashboard.stress.metrics["rhr_stress"], unit: "pts", note: "RHR stress component is unavailable.", measuredAt: dashboard.stress.lastUpdated, source: .computed),
            hrvStress: healthMetric(dashboard.stress.metrics["hrv_stress"], unit: "pts", note: "HRV stress component is unavailable.", measuredAt: dashboard.stress.lastUpdated, source: .computed),
            respStress: healthMetric(dashboard.stress.metrics["resp_stress"], unit: "pts", note: "Respiratory stress component is unavailable.", measuredAt: dashboard.stress.lastUpdated, source: .computed),
            tempStress: healthMetric(dashboard.stress.metrics["temp_stress"], unit: "pts", note: "Temperature stress component is unavailable.", measuredAt: dashboard.stress.lastUpdated, source: .computed),
            sleepDebtStress: healthMetric(dashboard.stress.metrics["sleep_debt_stress"], unit: "pts", note: "Sleep-debt stress component is unavailable.", measuredAt: dashboard.stress.lastUpdated, source: .computed),
            loadStress: healthMetric(dashboard.stress.metrics["load_stress"], unit: "pts", note: "Load stress component is unavailable.", measuredAt: dashboard.stress.lastUpdated, source: .computed)
        )

        let energyBank = EnergyBankContext(
            morningEnergy: healthMetric(dashboard.energy.hasData ? dashboard.energy.morningEnergy : nil, unit: "pts", note: "Morning energy is unavailable.", measuredAt: dashboard.energy.lastUpdated, source: .computed, confidence: dataConfidence(dashboard.energy.confidence)),
            currentEnergy: healthMetric(dashboard.energy.hasData ? dashboard.energy.value : nil, unit: "pts", note: "Current energy is unavailable.", measuredAt: dashboard.energy.lastUpdated, source: .computed, confidence: dataConfidence(dashboard.energy.confidence)),
            status: dashboard.energy.hasData ? dashboard.energy.status.rawValue : "unavailable",
            chargeEfficiency: healthMetric(dashboard.energy.metrics["charge_efficiency"], unit: "ratio", note: "Charge efficiency is unavailable.", measuredAt: dashboard.energy.lastUpdated, source: .computed),
            atl7Day: healthMetric(dashboard.energy.metrics["atl"], unit: "AU", note: "Acute training load is unavailable.", measuredAt: dashboard.energy.lastUpdated, source: .computed),
            ctl42Day: healthMetric(dashboard.energy.metrics["ctl"], unit: "AU", note: "Chronic training load is unavailable.", measuredAt: dashboard.energy.lastUpdated, source: .computed),
            tsbFreshness: healthMetric(dashboard.energy.metrics["tsb"], unit: "AU", note: "Training stress balance is unavailable.", measuredAt: dashboard.energy.lastUpdated, source: .computed),
            // 联通专项批次 3：v2 补齐 ACWR。
            acwrRatio: healthMetric(dashboard.energy.metrics["acwr"], unit: "ratio", note: "ACWR is unavailable.", measuredAt: dashboard.energy.lastUpdated, source: .computed)
        )

        let workouts = dashboard.workouts
        // A9：v2 TrainingContext 的死字段补齐——激活计划与训练明细此前恒为 nil/"[]"。
        let planSummary: ActivePlanSummary? = activePlan.map { plan in
            ActivePlanSummary(
                title: plan.title,
                goalDescription: plan.goalDescription,
                weeksCount: plan.weeksCount,
                completedDays: plan.days.filter(\.isCompleted).count,
                totalDays: plan.days.count
            )
        }
        let workoutListJSON: String = {
            let recent = workoutEvents
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(12)
                .map { event in
                    [
                        "name": event.title.isEmpty ? event.activityType : event.title,
                        "started_at": ISO8601DateFormatter().string(from: event.startedAt),
                        "duration_min": event.durationMinutes as Any,
                        "energy_kcal": event.energyKilocalories as Any,
                        "source": event.source as Any
                    ] as [String: Any]
                }
            guard JSONSerialization.isValidJSONObject(Array(recent)),
                  let data = try? JSONSerialization.data(withJSONObject: Array(recent)),
                  let text = String(data: data, encoding: .utf8) else { return "[]" }
            return text
        }()
        let training = TrainingContext(
            activePlan: planSummary,
            workoutCount: workouts.count,
            workoutTypes: Array(Set(workouts.map(\.activityName))).sorted(),
            totalEnergyKcal: workouts.compactMap(\.energyKilocalories).reduce(0, +),
            totalDurationMin: workouts.map { Int($0.end.timeIntervalSince($0.start) / 60) }.reduce(0, +),
            workoutListJSON: workoutListJSON
        )

        let nutrition = NutritionContext(
            recentEntries: foodLogs.prefix(8).map { $0.summaryLine },
            recentCount: min(foodLogs.count, 8),
            totalCalories: foodLogs.prefix(8).map(\.totalCalories).reduce(0, +),
            totalProtein: foodLogs.prefix(8).map(\.proteinGrams).reduce(0, +),
            totalCarbs: foodLogs.prefix(8).map(\.carbsGrams).reduce(0, +),
            totalFat: foodLogs.prefix(8).map(\.fatGrams).reduce(0, +),
            totalFiber: foodLogs.prefix(8).map(\.fiberGrams).reduce(0, +)
        )

        let ext = dashboard.extendedMetrics
        let body = dashboard.bodyMetrics
        // A missing field in a resolved context stays missing. In particular,
        // historical/consent-filtered facts must never reopen global settings.
        let resolvedScoringContext = scoringContext ?? dashboard.scoringContext
        let age = resolvedScoringContext.map { $0.profile.age?.value } ?? (profileAge ?? ext.age)
        let sex = resolvedScoringContext.map { $0.profile.biologicalSex?.value } ?? ext.biologicalSex
        let extended = ExtendedMetricsContext(
            age: age,
            biologicalSex: sex,
            heightCm: ext.heightCm.map { MetricValue.live($0, unit: "cm") } ?? MetricValue.missing(),
            weightKg: body.weightKilograms.map { MetricValue.live($0, unit: "kg") } ?? MetricValue.missing(),
            bmi: ext.bmi.map { MetricValue.live($0, unit: "kg/m²") } ?? MetricValue.missing(),
            bodyFatPct: body.bodyFatPercentage.map { MetricValue.live($0, unit: "%") } ?? MetricValue.missing(),
            vo2Max: body.vo2Max.map { MetricValue.live($0, unit: "ml/kg/min") } ?? MetricValue.missing(),
            walkingSpeed: ext.walkingSpeed.map { MetricValue.live($0, unit: "m/s") } ?? MetricValue.missing(),
            walkingAsymmetry: ext.walkingAsymmetry.map { MetricValue.live($0, unit: "%") } ?? MetricValue.missing(),
            doubleSupportPct: ext.walkingDoubleSupport.map { MetricValue.live($0, unit: "%") } ?? MetricValue.missing(),
            spo2: ext.oxygenSaturation.map { MetricValue.live($0, unit: "%") } ?? MetricValue.missing(),
            bloodPressureSystolic: ext.bloodPressureSystolic.map { MetricValue.live(Int($0), unit: "mmHg") },
            bloodPressureDiastolic: ext.bloodPressureDiastolic.map { MetricValue.live(Int($0), unit: "mmHg") },
            bloodGlucose: ext.bloodGlucose.map { MetricValue.live($0, unit: "mg/dL") },
            waterMl: ext.waterMl.map { MetricValue.live(Int($0), unit: "ml") },
            caffeineMg: ext.caffeineMg.map { MetricValue.live(Int($0), unit: "mg") },
            envNoiseDb: ext.environmentalNoisedB.map { MetricValue.live($0, unit: "dB") },
            daylightMinutes: ext.timeInDaylight.map { MetricValue.live(Int($0), unit: "min") },
            wristTempC: ext.bodyTemperature.map { MetricValue.live($0, unit: "°C") }
        )

        let coreAvailability: [(String, Bool)] = [
            ("recovery", dashboard.recovery.hasData),
            ("sleep", dashboard.sleepScore.hasData),
            ("strain", dashboard.strain.hasData),
            ("stress", dashboard.stress.hasData),
            ("energy", dashboard.energy.hasData)
        ]
        let missingSections = coreAvailability.filter { !$0.1 }.map(\.0).sorted()
        let availableSections = coreAvailability.count - missingSections.count
        let coverageConfidence: DataConfidence
        if availableSections == coreAvailability.count {
            coverageConfidence = .high
        } else if availableSections >= 3 {
            coverageConfidence = .medium
        } else if availableSections >= 1 {
            coverageConfidence = .low
        } else {
            coverageConfidence = .unavailable
        }
        let agentTrainingDecision: AgentTrainingDecisionContext
        if let trainingDecision {
            let confidence: DataConfidence
            if trainingDecision.confidence >= 0.8 {
                confidence = .high
            } else if trainingDecision.confidence >= 0.55 {
                confidence = .medium
            } else if trainingDecision.confidence > 0 {
                confidence = .low
            } else {
                confidence = .unavailable
            }
            agentTrainingDecision = AgentTrainingDecisionContext(
                readinessLevel: trainingDecision.decision.rawValue,
                readinessGuidance: trainingDecision.userFacingSummary,
                volumeMultiplier: trainingDecision.volumeMultiplier,
                maxIntensity: "RPE \(trainingDecision.intensityCap)",
                recommendedTrainingType: trainingDecision.targetSessionTitle ?? trainingDecision.decision.rawValue,
                reasons: trainingDecision.reasons.joined(separator: " · "),
                confidence: confidence
            )
        } else {
            let decision = dashboard.trainingDecision
            agentTrainingDecision = AgentTrainingDecisionContext(
                readinessLevel: decision.readinessLevel,
                readinessGuidance: decision.readinessGuidance,
                volumeMultiplier: decision.volumeMultiplier,
                maxIntensity: decision.maxIntensity,
                recommendedTrainingType: decision.recommendedTrainingType,
                reasons: decision.whyThis,
                confidence: decision.trainingLoadConfidence
            )
        }

        let context = AgentFactSnapshot(
            schemaVersion: AIContextBuilder.canonicalSchemaVersion,
            contextHash: "",
            generatedAt: generatedAt,
            contextWindow: "today",
            bodyState: AgentBodyStateContext(
                readiness: resolvedBodyState.readiness,
                confidence: resolvedBodyState.confidence,
                freshness: resolvedBodyState.freshness,
                source: resolvedBodyState.source,
                activeStatus: resolvedBodyState.activeStatus,
                contextHash: resolvedBodyState.hash,
                drivers: resolvedBodyState.drivers.sorted { $0.id < $1.id }
            ),
            trainingDecision: agentTrainingDecision,
            dataCoverage: dataCoverage ?? AgentDataCoverageContext(
                availableSections: availableSections,
                totalSections: coreAvailability.count,
                missingSections: missingSections,
                confidence: coverageConfidence
            ),
            recovery: recovery,
            sleep: sleep,
            strain: strain,
            stress: stress,
            energyBank: energyBank,
            training: training,
            nutrition: nutrition,
            extendedMetrics: extended,
            strengthTraining: buildStrengthTrainingFacts(
                strengthWorkouts,
                trainingResponses: trainingResponses,
                decision: agentTrainingDecision,
                generatedAt: generatedAt
            ),
            // A12：recentTrends 占位符移除——与 weeklyTrends 同源，避免固定死字节。
            recentTrends: weeklyTrends.isEmpty ? ["note": "No weekly trend data available yet."] : weeklyTrends,
            weeklyTrends: weeklyTrends.isEmpty ? ["note": "No weekly trend data available yet."] : weeklyTrends,
            journalEntries: journalEntries.map { "\($0.tags.joined(separator: "|")): \($0.text)" },
            // A4：各上限统一路由到 ContextBudget 字段（此前散落为字面量）。
            historicalReports: historicalReports.prefix(ContextBudget().maxHistoricalReports).map { "\($0.title): \($0.markdownContent.prefix(160))" },
            userWiki: Dictionary(uniqueKeysWithValues: mergedUserWiki.map { key, value in
                (key, ContextBudget.trimWiki(value, maxChars: 3000))
            }),
            dailyOperatingPlan: dailyOperatingPlan,
            personalHealthBrief: dashboard.personalHealthBrief,
            healthTrends: dashboard.healthTrends
        )

        let hash = canonicalContentHash(context)
        var withHash = context
        withHash.contextHash = hash

        let metadata = ContextSnapshotMetadata(
            schemaVersion: AIContextBuilder.canonicalSchemaVersion,
            generatedAt: generatedAt,
            hash: hash,
            includedSections: ["recovery", "sleep", "strain", "stress", "energy_bank", "training", "nutrition", "extended_metrics", "strength_training"]
                + (onboardingState == nil ? [] : ["body_model_profile"])
                + (bodyModelState == nil ? [] : ["body_model_state"]),
            redactedFields: []
        )

        return (snapshot: withHash, metadata: metadata)
    }

    private func canonicalContentHash(_ context: AgentFactSnapshot) -> String {
        var semantic = context
        semantic.contextHash = ""
        semantic.generatedAt = Date(timeIntervalSince1970: 0)
        semantic.bodyState.contextHash = ""
        if var brief = semantic.personalHealthBrief {
            brief.date = Date(timeIntervalSince1970: 0)
            brief.generatedAt = Date(timeIntervalSince1970: 0)
            semantic.personalHealthBrief = brief
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(semantic)) ?? Data("{}".utf8)
        return ContentHash.hash(String(data: data, encoding: .utf8) ?? "{}")
    }

    private func legacyContentHash(_ envelope: AgentContextEnvelope) -> String {
        var semantic = envelope
        semantic.metadata.generatedAt = Date(timeIntervalSince1970: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = (try? encoder.encode(semantic)) ?? Data("{}".utf8)
        return ContentHash.hash(String(data: data, encoding: .utf8) ?? "{}")
    }

    // MARK: - Private Helpers

    private func buildNutritionDict(_ foodLogs: [FoodLogRecord]) -> [String: String] {
        guard !foodLogs.isEmpty else {
            return ["note": "No structured food logs are available yet."]
        }

        let recent = foodLogs.prefix(8)
        let totalCalories = recent.map(\.totalCalories).reduce(0, +)
        let totalProtein = recent.map(\.proteinGrams).reduce(0, +)
        let totalCarbs = recent.map(\.carbsGrams).reduce(0, +)
        let totalFat = recent.map(\.fatGrams).reduce(0, +)
        let totalFiber = recent.map(\.fiberGrams).reduce(0, +)
        let entries = recent.map { log in
            "\(log.mealName): \(log.foods.map(\.name).joined(separator: ", ")) · \(log.totalCalories) kcal · P\(log.proteinGrams) C\(log.carbsGrams) F\(log.fatGrams) Fiber\(log.fiberGrams) · score=\(log.healthScore)"
        }.joined(separator: "\n")

        return [
            "recent_entries": entries,
            "recent_count": "\(recent.count)",
            "recent_total_calories": "\(totalCalories)",
            "recent_total_macros": "P\(totalProtein) C\(totalCarbs) F\(totalFat) Fiber\(totalFiber)",
            "source_note": "Structured food logs may come from Kimi vision analysis, Coach tools, or manual entry."
        ]
    }

    private func buildUnifiedWorkoutDict(
        _ events: [WorkoutEventRecord],
        generatedAt: Date
    ) -> [String: String] {
        let sorted = events.sorted { $0.startedAt > $1.startedAt }
        let sevenDaysAgo = generatedAt.addingTimeInterval(-7 * 24 * 3600)
        let fourteenDaysAgo = generatedAt.addingTimeInterval(-14 * 24 * 3600)
        let twentyEightDaysAgo = generatedAt.addingTimeInterval(-28 * 24 * 3600)
        let recent7d = sorted.filter { $0.startedAt >= sevenDaysAgo && $0.startedAt <= generatedAt }
        let recent14d = sorted.filter { $0.startedAt >= fourteenDaysAgo && $0.startedAt <= generatedAt }
        let recent28d = sorted.filter { $0.startedAt >= twentyEightDaysAgo && $0.startedAt <= generatedAt }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let entries = sorted.prefix(12).map { UnifiedWorkoutContextEntry(event: $0) }
        let encodedEntries = (try? encoder.encode(entries))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return [
            "algorithm_version": "workoutEvents.v1",
            "source": "WorkoutEventRecord unified Apple Watch / HealthKit / Xunji / manual workout timeline",
            "confidence": sorted.isEmpty ? "unavailable" : "medium",
            "note": sorted.isEmpty
                ? "No unified workout history available yet."
                : "Use this as the primary workout timeline. Strength details may be linked through linked_strength_workout_id.",
            "sessions_7d": "\(recent7d.count)",
            "sessions_14d": "\(recent14d.count)",
            "sessions_28d": "\(recent28d.count)",
            "duration_7d_min": String(format: "%.0f", recent7d.reduce(0) { $0 + $1.durationMinutes }),
            "duration_14d_min": String(format: "%.0f", recent14d.reduce(0) { $0 + $1.durationMinutes }),
            "energy_14d_kcal": String(format: "%.0f", recent14d.compactMap(\.energyKilocalories).reduce(0, +)),
            "activity_types_14d": formatWorkoutActivityTypes(recent14d),
            "source_mix_14d": formatWorkoutSourceMix(recent14d),
            "recent_workout_events_json": encodedEntries
        ]
    }

    private func formatWorkoutActivityTypes(_ events: [WorkoutEventRecord]) -> String {
        guard !events.isEmpty else { return "None" }
        let counts = Dictionary(grouping: events, by: { workoutDisplayType($0) })
            .mapValues(\.count)
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }

    private func formatWorkoutSourceMix(_ events: [WorkoutEventRecord]) -> String {
        guard !events.isEmpty else { return "None" }
        let counts = Dictionary(grouping: events, by: \.source)
            .mapValues(\.count)
        return counts
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: ", ")
    }

    private func workoutDisplayType(_ event: WorkoutEventRecord) -> String {
        if !event.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return event.title
        }
        return event.activityType
    }

    private func buildStrengthTrainingDict(
        _ workouts: [StrengthWorkoutRecord],
        trainingResponses: [TrainingResponseRecord],
        dashboard: DashboardSummary,
        generatedAt: Date
    ) -> [String: String] {
        // Algorithm v1/trainingAnalytics: strength context derives from TrainingAnalyticsService so
        // effective-set counting, muscle naming, fatigue and PR detection use one shared source of truth.
        let analytics = TrainingAnalyticsService()
        let dtoWorkouts = workouts.map { $0.dto }
        let recent7d = analytics.buildRecentSummary(workouts: dtoWorkouts, days: 7, endingAt: generatedAt)
        let recent14d = analytics.buildRecentSummary(workouts: dtoWorkouts, days: 14, endingAt: generatedAt)
        let adaptation = trainingAdaptationSummary(dashboard: dashboard)
        let response = trainingResponseSummary(trainingResponses, generatedAt: generatedAt)
        let progressList = exerciseProgressSummaries(workouts: workouts, generatedAt: generatedAt)
            .map {
                "\($0.exerciseName): \($0.setsCount) sets, max \($0.maxWeightKg)kg, peak 1RM \(String(format: "%.1f", $0.estimated1RMPeakKg))kg"
            }
            .sorted()
            .joined(separator: "\n")

        return [
            "algorithm_version": "trainingAnalytics.v1",
            "source": "StrengthWorkoutRecord + TrainingResponseRecord via TrainingAnalyticsService",
            "confidence": workouts.isEmpty ? "unavailable" : "medium",
            "note": workouts.isEmpty ? "No strength training data available yet." : "Strength context uses unified TrainingAnalyticsService muscle groups and effective-set rules.",
            "sessions_7d": "\(recent7d.sessions)",
            "sessions_14d": "\(recent14d.sessions)",
            "hard_sets_7d": "\(recent7d.effectiveSets)",
            "hard_sets_14d": "\(recent14d.effectiveSets)",
            "volume_7d_kg": String(format: "%.1f", recent7d.volumeKg),
            "volume_14d_kg": String(format: "%.1f", recent14d.volumeKg),
            "muscle_groups_7d": formatMuscleGroups(recent7d.muscleGroupSets),
            "muscle_groups_14d": formatMuscleGroups(recent14d.muscleGroupSets),
            "recent_prs": recent14d.recentPRs.map(\.summary).joined(separator: "\n"),
            "local_fatigue": formatFatigue(recent7d.localFatigue),
            "training_adaptation": adaptation,
            "recovery_response_summary": response.summary,
            "average_next_day_recovery_delta": response.averageNextDayRecoveryDelta.map { String(format: "%+.1f", $0) } ?? "N/A",
            "flagged_response_count": "\(response.flaggedCount)",
            "exercise_progress_14d": progressList.isEmpty ? "No exercise data." : progressList,
            "last_session_summary": recent14d.lastWorkoutSummary ?? "No strength training sessions logged in the past 14 days.",
            "recent_workout_details": formatRecentWorkoutDetails(workouts)
        ]
    }

    private func buildStrengthTrainingFacts(
        _ workouts: [StrengthWorkoutRecord],
        trainingResponses: [TrainingResponseRecord],
        decision: AgentTrainingDecisionContext,
        generatedAt: Date
    ) -> StrengthTrainingContext {
        let analytics = TrainingAnalyticsService()
        let dtoWorkouts = workouts.map { $0.dto }
        let recent7d = analytics.buildRecentSummary(workouts: dtoWorkouts, days: 7, endingAt: generatedAt)
        let recent14d = analytics.buildRecentSummary(workouts: dtoWorkouts, days: 14, endingAt: generatedAt)
        let adaptation = trainingAdaptationSummary(decision: decision)
        let response = trainingResponseSummary(trainingResponses, generatedAt: generatedAt)
        return StrengthTrainingContext(
            sessions7d: recent7d.sessions,
            sessions14d: recent14d.sessions,
            hardSets7d: recent7d.effectiveSets,
            hardSets14d: recent14d.effectiveSets,
            volume7dKg: recent7d.volumeKg,
            volume14dKg: recent14d.volumeKg,
            muscleGroupSets7d: recent7d.muscleGroupSets,
            muscleGroupSets14d: recent14d.muscleGroupSets,
            recentPRs: recent14d.recentPRs.map(\.summary),
            localFatigue: recent7d.localFatigue,
            recentExerciseProgress: exerciseProgressSummaries(workouts: workouts, generatedAt: generatedAt),
            lastSessionSummary: recent14d.lastWorkoutSummary ?? "No strength training sessions logged in the past 14 days.",
            trainingAdaptation: adaptation,
            recoveryResponseSummary: response.summary,
            averageNextDayRecoveryDelta: response.averageNextDayRecoveryDelta,
            flaggedResponseCount: response.flaggedCount,
            recentWorkoutDetails: formatRecentWorkoutDetails(workouts)
        )
    }

    private func formatRecentWorkoutDetails(_ workouts: [StrengthWorkoutRecord]) -> String {
        let isZH = AppLanguage.stored.isChinese
        guard !workouts.isEmpty else {
            return isZH ? "近期无力量训练记录。" : "No recent strength workouts logged."
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        
        var result = ""
        for workout in workouts {
            let dateStr = dateFormatter.string(from: workout.startedAt)
            result += "### \(workout.title) (\(dateStr) · \(workout.durationMinutes) \(isZH ? "分钟" : "min"))\n"
            if !workout.notes.isEmpty {
                result += "\(isZH ? "备注" : "Notes"): \(workout.notes)\n"
            }
            if workout.exercises.isEmpty {
                result += isZH ? "本次训练未记录动作。\n" : "No exercises logged in this session.\n"
            } else {
                for exercise in workout.exercises {
                    let completedWorkSets = exercise.sets.filter { !$0.isWarmup && $0.isCompleted != false }
                    let warmupSets = exercise.sets.filter { $0.isWarmup && $0.isCompleted != false }
                    let uncompletedSets = exercise.sets.filter { $0.isCompleted == false }
                    result += "- \(exercise.name) (\(exercise.equipment)): \(completedWorkSets.count) \(isZH ? "完成工作组" : "completed work sets")"
                    if !uncompletedSets.isEmpty {
                        result += ", \(uncompletedSets.count) \(isZH ? "未完成组未计入容量" : "uncompleted sets excluded")"
                    }
                    result += "\n"
                    for (index, set) in completedWorkSets.enumerated() {
                        let rpeStr = set.rpe.map { " RPE \($0)" } ?? ""
                        result += "  * \(isZH ? "完成组" : "Completed set") \(index + 1): \(set.weightKilograms)kg x \(set.repetitions)\(isZH ? "次" : "reps")\(rpeStr)\n"
                    }
                    if !warmupSets.isEmpty {
                        result += "  * \(isZH ? "热身组" : "Warmup sets"): \(warmupSets.count) \(isZH ? "组，未计入工作容量" : "sets, excluded from work volume")\n"
                    }
                }
            }
            result += "\n"
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func exerciseProgressSummaries(
        workouts: [StrengthWorkoutRecord],
        generatedAt: Date
    ) -> [ExerciseProgressSummary] {
        let fourteenDaysAgo = generatedAt.addingTimeInterval(-14 * 24 * 3600)
        let workouts14d = workouts.filter { $0.startedAt >= fourteenDaysAgo && $0.startedAt <= generatedAt }
        var exerciseStats: [String: (sets: Int, maxWeight: Double, max1RM: Double)] = [:]

        for workout in workouts14d {
            for exercise in workout.exercises {
                let name = exercise.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }

                var setsCount = 0
                var localMaxWeight = 0.0
                var localMax1RM = 0.0

                for set in exercise.sets where !set.isWarmup && set.isCompleted == true {
                    setsCount += 1
                    localMaxWeight = max(localMaxWeight, set.weightKilograms)
                    let epley1RM = set.weightKilograms * (1.0 + Double(set.repetitions) / 30.0)
                    localMax1RM = max(localMax1RM, epley1RM)
                }

                if setsCount > 0 {
                    let current = exerciseStats[name] ?? (sets: 0, maxWeight: 0.0, max1RM: 0.0)
                    exerciseStats[name] = (
                        sets: current.sets + setsCount,
                        maxWeight: max(current.maxWeight, localMaxWeight),
                        max1RM: max(current.max1RM, localMax1RM)
                    )
                }
            }
        }

        return exerciseStats.map { name, stats in
            ExerciseProgressSummary(
                exerciseName: name,
                setsCount: stats.sets,
                maxWeightKg: stats.maxWeight,
                estimated1RMPeakKg: stats.max1RM
            )
        }.sorted(by: { $0.exerciseName < $1.exerciseName })
    }

    private func trainingAdaptationSummary(decision: AgentTrainingDecisionContext) -> String {
        return [
            decision.readinessGuidance,
            "\(Int((decision.volumeMultiplier * 100).rounded()))% volume.",
            "\(decision.maxIntensity) cap.",
            decision.reasons
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func trainingAdaptationSummary(dashboard: DashboardSummary) -> String {
        let decision = dashboard.trainingDecision
        return [
            decision.body,
            "\(Int((decision.volumeMultiplier * 100).rounded()))% volume.",
            "\(decision.maxIntensity) cap.",
            decision.whyThis
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private func formatMuscleGroups(_ values: [String: Int]) -> String {
        values.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value) sets" }.joined(separator: ", ")
    }

    private func formatFatigue(_ values: [String: LocalMuscleFatigue]) -> String {
        values.values.sorted { $0.muscleGroup < $1.muscleGroup }.map {
            "\($0.muscleGroup): \($0.fatigueLevel), \($0.setsLast48h) sets/48h, \($0.setsLast7d) sets/7d"
        }.joined(separator: "\n")
    }

    private func trainingResponseSummary(
        _ responses: [TrainingResponseRecord],
        generatedAt: Date
    ) -> (summary: String, averageNextDayRecoveryDelta: Double?, flaggedCount: Int) {
        let start = generatedAt.addingTimeInterval(-28 * 86_400)
        let recent = responses.filter { $0.date >= start && $0.date <= generatedAt }
        guard !recent.isEmpty else {
            return ("No post-training recovery response records in the past 28 days.", nil, 0)
        }

        let recoveryDeltas = recent.compactMap(\.nextDayRecoveryDelta)
        let averageRecoveryDelta = recoveryDeltas.isEmpty ? nil : recoveryDeltas.reduce(0, +) / Double(recoveryDeltas.count)
        let flagged = recent.filter { response in
            (response.nextDayRecoveryDelta ?? 0) <= -8
                || (response.nextDayHRVDelta ?? 0) <= -10
                || (response.nextDayRHRDelta ?? 0) >= 5
        }
        let hardest = recent.max { lhs, rhs in
            let lhsScore = (lhs.sessionRPE ?? 0) * 10 + Double(lhs.totalEffectiveSets)
            let rhsScore = (rhs.sessionRPE ?? 0) * 10 + Double(rhs.totalEffectiveSets)
            return lhsScore < rhsScore
        }

        let summary: String
        if let averageRecoveryDelta {
            summary = "Past 28d post-training response: average next-day recovery \(String(format: "%+.1f", averageRecoveryDelta)) pts across \(recent.count) captured sessions; \(flagged.count) sessions showed a notable recovery cost. Hardest captured session: \(hardest?.primaryMuscleGroups.joined(separator: ", ") ?? "unknown focus"), \(hardest?.totalEffectiveSets ?? 0) effective sets."
        } else {
            summary = "Past 28d post-training response: \(recent.count) sessions captured, but next-day recovery deltas are not available yet."
        }
        return (summary, averageRecoveryDelta, flagged.count)
    }

    private static func mergedUserWiki(
        _ userWiki: [String: String],
        onboardingState: OnboardingState?,
        bodyModelState: BodyModelState? = nil
    ) -> [String: String] {
        // A5：wiki 文件键中未初始化的（空/默认模板）一律剔除，空模板样板不进 AI 上下文。
        var result = userWiki.filter { key, _ in
            guard WikiFileService.allowedFilenames.contains(key) else { return true }
            return !WikiFileService.isUninitialized(key)
        }
        if let onboardingState {
            let goal = onboardingState.goalProfile
            let training = onboardingState.trainingPreference
            let equipment = onboardingState.equipmentProfile
            let coaching = onboardingState.coachingPreference
            let snapshot = onboardingState.initialBodySnapshot

            result["body_model.primary_goal"] = goal.primaryGoal
            result["body_model.secondary_goals"] = goal.secondaryGoals.joined(separator: ", ")
            result["body_model.experience_level"] = goal.experienceLevel
            result["body_model.body_concerns"] = goal.bodyConcerns.joined(separator: ", ")
            result["body_model.training_style"] = training.trainingStyle
            result["body_model.weekly_training_days"] = "\(training.weeklyTrainingDays)"
            result["body_model.session_duration_minutes"] = "\(training.sessionDurationMinutes)"
            result["body_model.preferred_days"] = training.preferredTrainingDays.joined(separator: ", ")
            result["body_model.equipment"] = equipment.equipment.joined(separator: ", ")
            result["body_model.schedule_notes"] = equipment.scheduleNotes
            result["body_model.coach_style"] = coaching.style
            result["body_model.explanation_depth"] = coaching.explanationDepth
            result["body_model.language"] = coaching.language
            result["body_model.initial_confidence"] = snapshot.dataConfidence.rawValue
            result["body_model.missing_data"] = snapshot.missingData.joined(separator: ", ")
            result["body_model.first_brief"] = onboardingState.firstBrief
            result["body_model.first_action_plan"] = onboardingState.firstActionPlan.joined(separator: " | ")
        }
        if let bodyModelState {
            result["body_model.maturity"] = bodyModelState.maturity.overall.rawValue
            result["body_model.baseline_days"] = "\(bodyModelState.maturity.baselineDays)"
            result["body_model.behavior_pairs"] = "\(bodyModelState.maturity.behaviorPairs)"
            result["body_model.training_sessions"] = "\(bodyModelState.maturity.trainingSessions)"
            result["body_model.claims"] = bodyModelState.claims.map {
                "\($0.title): \($0.summary) [\($0.confidence.rawValue), n=\($0.evidenceCount)]"
            }.joined(separator: " | ")
            result["body_model.uncertain_areas"] = bodyModelState.uncertainAreas.map(\.id).joined(separator: ", ")
            result["body_model.training_pattern_summary"] = bodyModelState.trainingPatternSummary
            result["body_model.coach_rules"] = bodyModelState.coachRules.joined(separator: " | ")
        }
        return result
    }

    /// A1：把持久化的 Daily Operating Plan 压缩成结构化事实。
    /// 此前 AI 只拿到 trainingDecision 切片；主行动/支持行动/理由/置信度全部缺席。
    static func compactDailyOperatingPlan(_ plan: DailyOperatingPlanRecord?) -> [String: String]? {
        guard let plan else { return nil }
        var dict: [String: String] = [
            "day_identifier": plan.dayIdentifier,
            "status": plan.status,
            "title": plan.title,
            "primary_action_type": plan.primaryActionType,
            "confidence": String(format: "%.2f", plan.confidence),
            "actions_json": String(plan.payloadJSON.prefix(800)),
            "reasons_json": String(plan.reasonsJSON.prefix(800))
        ]
        if let payload = plan.operatingPlanPayload {
            dict["decision"] = payload.decision.rawValue
            dict["volume_multiplier"] = String(format: "%.2f", payload.volumeMultiplier)
            dict["intensity_cap_rpe"] = "\(payload.intensityCap)"
            dict["summary"] = payload.summary
            if let target = payload.targetSessionTitle {
                dict["target_session_title"] = target
            }
            if let primary = payload.primaryAction {
                dict["primary_action"] = "\(primary.domain.rawValue): \(primary.title) — \(primary.detail)"
            }
            if !payload.supportingActions.isEmpty {
                dict["supporting_actions"] = payload.supportingActions.prefix(2).map {
                    "\($0.domain.rawValue): \($0.title) — \($0.detail)"
                }.joined(separator: " | ")
            }
        }
        if let source = plan.source { dict["source"] = source }
        if let safety = plan.safetyNotice { dict["safety_notice"] = safety }
        return dict
    }

}

/// Compatibility adapter for report prompts and persisted v1 snapshots.
/// New consumers should use AgentFactSnapshot and a purpose-built adapter.
struct LegacyReportContextAdapter {
    func render(
        dashboard: DashboardSummary,
        bodyState: BodyState,
        journalEntries: [JournalContextEntry],
        historicalReports: [GeneratedAIReport],
        mergedUserWiki: [String: String],
        weeklyTrends: [String: String],
        nutrition: [String: String],
        unifiedWorkouts: [String: String],
        strengthTraining: [String: String],
        generatedAt: Date
    ) -> AgentContextEnvelope {
        AgentContextEnvelope(
            metadata: AgentContextMetadata(generatedAt: generatedAt, contextWindow: "today"),
            todaySummary: [
                "date": dashboard.date.formatted(date: .numeric, time: .omitted),
                "overall_state": dashboard.recovery.hasData ? dashboard.recovery.band.rawValue.lowercased() : "unavailable",
                "source": dashboard.source.rawValue,
                "top_reason": dashboard.recovery.reasons.first ?? dashboard.dailyInsight,
                "readiness_level": dashboard.trainingDecision.readinessLevel,
                "readiness_guidance": dashboard.trainingDecision.readinessGuidance
            ],
            bodyState: [
                "readiness": bodyState.readiness.rawValue,
                "confidence": bodyState.confidence.rawValue,
                "freshness": bodyState.freshness.rawValue,
                "source": bodyState.source,
                "context_hash": bodyState.hash,
                "drivers": bodyState.drivers.map { "\($0.title): \($0.detail)" }.joined(separator: " | "),
                "safety": "General wellness guidance only; not a medical diagnosis."
            ],
            sleep: Self.legacySleepContext(dashboard),
            recovery: RecoveryContextBuilder().build(from: dashboard),
            strain: StrainContextBuilder().build(from: dashboard),
            workouts: WorkoutsContextBuilder().build(from: dashboard.workouts),
            unifiedWorkouts: unifiedWorkouts,
            stress: StressContextBuilder().build(from: dashboard),
            energyBank: EnergyBankContextBuilder().build(from: dashboard),
            healthAgeTrend: HealthAgeContextBuilder().build(from: dashboard),
            recentTrends: [
                "note": "Recent trends require enough cached history. No trend is reported until sufficient snapshots exist."
            ],
            weeklyTrends: weeklyTrends.isEmpty
                ? ["note": "No weekly trend data available yet. Historical snapshots require a few days of data."]
                : weeklyTrends,
            nutrition: nutrition,
            journal: [
                "entries": journalEntries.map { "\($0.tags.joined(separator: "|")): \($0.text)" }.joined(separator: "\n")
            ],
            historicalAIReports: [
                "recent": historicalReports.map { "\($0.title): \($0.markdownContent.prefix(160))" }.joined(separator: "\n")
            ],
            userWiki: mergedUserWiki,
            agentInstruction: [
                "role": "Private health data analyst and lifestyle coach",
                "safety": "Do not diagnose. Be cautious with stress and health age trend."
            ],
            extendedMetrics: ExtendedMetricsContextBuilder().build(
                ext: dashboard.extendedMetrics,
                body: dashboard.bodyMetrics
            ),
            strengthTraining: strengthTraining
        )
    }

    /// v1 report snapshots retain their persisted shape even as the domain
    /// context gains richer evidence. New consumers use the typed v2 facts.
    private static func legacySleepContext(_ dashboard: DashboardSummary) -> [String: String] {
        let keys: Set<String> = [
            "sleep_score", "duration_minutes", "band", "reason",
            "rem_minutes", "deep_minutes", "core_minutes", "awake_minutes",
            "sleep_efficiency_pct", "rem_pct", "deep_pct"
        ]
        return SleepContextBuilder().build(from: dashboard).filter { keys.contains($0.key) }
    }
}

/// The single persistence boundary for facts consumed by reports and Coach.
/// Keeping fetch windows and ordering here prevents each agent from seeing a
/// subtly different version of the same day.
@MainActor
struct AgentFactInputLoader {
    struct Input {
        var asOf: Date
        var evaluatedAt: Date
        var calendar: Calendar
        var journalRecords: [JournalEntryRecord]
        var reportRecords: [AIReportRecord]
        var weeklyTrends: [String: String]
        var foodLogs: [FoodLogRecord]
        var workoutEvents: [WorkoutEventRecord]
        var strengthWorkouts: [StrengthWorkoutRecord]
        var trainingResponses: [TrainingResponseRecord]
        var dailySummaries: [DailyHealthSummaryRecord]
        var activePlan: TrainingPlanRecord?
        var dailyOperatingPlan: DailyOperatingPlanRecord?
        var onboardingState: OnboardingState?

        var journalContext: [JournalContextEntry] {
            journalRecords.map { JournalContextEntry(tags: $0.tags, text: $0.note) }
        }

        var reportContext: [GeneratedAIReport] {
            reportRecords.map { record in
                GeneratedAIReport(
                    type: AIReportType(rawValue: record.type) ?? .morningBrief,
                    title: record.title,
                    markdownContent: record.markdownContent,
                    contextSnapshot: record.serializedContextSnapshot,
                    createdAt: record.createdAt
                )
            }
        }

        func bodyState(dashboard: DashboardSummary) -> BodyState {
            BodyStateKernel().build(input: BodyStateInput(
                dashboard: dashboard,
                dailySummary: dailySummaries.first?.dto,
                workoutEvents: workoutEvents.map { $0.dto },
                strengthWorkouts: strengthWorkouts.map { $0.dto },
                trainingResponses: trainingResponses.map { $0.dto },
                foodLogs: foodLogs.map { $0.dto },
                journalEntries: journalRecords.map { $0.dto },
                activePlan: activePlan?.dto,
                activeStatus: ActiveStatusSettings.resolveStatus(at: asOf, now: evaluatedAt, calendar: calendar),
                generatedAt: asOf,
                calendar: calendar
            ))
        }

        func canonicalTrainingDecision(for bodyState: BodyState) -> DailyTrainingDecision? {
            guard let dailyOperatingPlan,
                  dailyOperatingPlan.status == "active",
                  dailyOperatingPlan.bodyStateHash == bodyState.hash else {
                return nil
            }
            return dailyOperatingPlan.trainingDecision
        }
    }

    func load(
        modelContext: ModelContext,
        asOf: Date = Date(),
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Input {
        let historyStart = asOf.addingTimeInterval(-35 * 86_400)
        let dayStart = calendar.startOfDay(for: asOf)
        let usesCurrentProfile = calendar.isDate(asOf, inSameDayAs: now)

        var journalDescriptor = FetchDescriptor<JournalEntryRecord>(
            predicate: #Predicate<JournalEntryRecord> { $0.createdAt <= asOf },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        journalDescriptor.fetchLimit = 12
        let journals = (try? modelContext.fetch(journalDescriptor)) ?? []

        let allReports = (try? modelContext.fetch(FetchDescriptor<AIReportRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))) ?? []
        // A4：历史报告上限路由到 ContextBudget（此前硬编码 6）。
        // 浏览历史日时同样只允许读取 asOf 之前的报告，避免未来信息泄漏进历史快照。
        let reports = Array(allReports.lazy
            .filter { $0.createdAt <= asOf && $0.type != "coach_prompt" && $0.type != "coach_thread" }
            .prefix(ContextBudget().maxHistoricalReports))

        let foods = (try? modelContext.fetch(FetchDescriptor<FoodLogRecord>(
            predicate: #Predicate<FoodLogRecord> { $0.createdAt >= historyStart && $0.createdAt <= asOf },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        ))) ?? []
        let workoutEvents = (try? modelContext.fetch(FetchDescriptor<WorkoutEventRecord>(
            predicate: #Predicate<WorkoutEventRecord> { $0.startedAt >= historyStart && $0.startedAt <= asOf },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))) ?? []
        let strength = (try? modelContext.fetch(FetchDescriptor<StrengthWorkoutRecord>(
            predicate: #Predicate<StrengthWorkoutRecord> { $0.startedAt >= historyStart && $0.startedAt <= asOf },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))) ?? []
        let responses = ((try? modelContext.fetch(FetchDescriptor<TrainingResponseRecord>(
            predicate: #Predicate<TrainingResponseRecord> { $0.date >= historyStart && $0.date <= asOf },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        ))) ?? []).filter { usesCurrentProfile || $0.nextDayDate <= asOf }
        // A8 修复：每日快照只取最新一条（此前抓 35 天只用 .first，白费一次大 fetch）。
        // 这里再加 asOf 上界：浏览历史日时 body state 应使用该日快照，而不是真实今天。
        var summaryDescriptor = FetchDescriptor<DailyHealthSummaryRecord>(
            predicate: #Predicate<DailyHealthSummaryRecord> { $0.date >= dayStart && $0.date <= asOf },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        summaryDescriptor.fetchLimit = 1
        let summaries = (try? modelContext.fetch(summaryDescriptor)) ?? []
        let activePlan = usesCurrentProfile ? (try? modelContext.fetch(FetchDescriptor<TrainingPlanRecord>(
            predicate: #Predicate<TrainingPlanRecord> { $0.isActive }
        )))?.first : nil
        let dayIdentifier = DailyHealthSummaryRecord.dayIdentifier(for: asOf, calendar: calendar)
        let operatingPlans = (try? modelContext.fetch(FetchDescriptor<DailyOperatingPlanRecord>(
            sortBy: [SortDescriptor(\.generatedAt, order: .reverse)]
        ))) ?? []
        var onboardingDescriptor = FetchDescriptor<OnboardingState>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        onboardingDescriptor.fetchLimit = 1

        return Input(
            asOf: asOf,
            evaluatedAt: now,
            calendar: calendar,
            journalRecords: journals,
            reportRecords: reports,
            weeklyTrends: (try? HealthSnapshotRepository(modelContext: modelContext, calendar: calendar).buildWeeklyTrendSummary(referenceDate: asOf)) ?? [:],
            foodLogs: foods,
            workoutEvents: workoutEvents,
            strengthWorkouts: strength,
            trainingResponses: responses,
            dailySummaries: summaries,
            activePlan: activePlan,
            dailyOperatingPlan: operatingPlans.first {
                $0.dayIdentifier == dayIdentifier
                    && (usesCurrentProfile || ($0.generatedAt <= asOf && ($0.operatingPlanPayload?.userEditedAt ?? .distantPast) <= asOf))
            },
            onboardingState: usesCurrentProfile ? (try? modelContext.fetch(onboardingDescriptor))?.first : nil
        )
    }
}

struct CoachCompactContextAdapter {
    func render(
        snapshot: AgentFactSnapshot,
        language: AppLanguage,
        maxCharacters: Int = 800,
        healthReferenceLine: String? = nil
    ) -> String {
        let isChinese = language.isChinese
        let bodyDrivers = snapshot.bodyState.drivers.prefix(3)
            .map(\.title)
            .joined(separator: isChinese ? "、" : ", ")
        let coverage = snapshot.dataCoverage
        let missing = coverage.missingSections.joined(separator: ", ")

        let required: [String] = [
            isChinese ? "## 今日事实快照" : "## Today's Fact Snapshot",
            isChinese
                ? "- Body State：\(snapshot.bodyState.readiness.rawValue) · 置信度 \(localizedDataConfidence(snapshot.bodyState.confidence)) · 新鲜度 \(localizedDataFreshness(snapshot.bodyState.freshness))"
                : "- Body State: \(snapshot.bodyState.readiness.rawValue) · confidence \(snapshot.bodyState.confidence.rawValue) · freshness \(snapshot.bodyState.freshness.rawValue)",
            isChinese
                ? "- 恢复 \(metric(snapshot.recovery.score, language: language)) · 睡眠 \(metric(snapshot.sleep.score, language: language)) · 负荷 \(metric(snapshot.strain.score, language: language))"
                : "- Recovery \(metric(snapshot.recovery.score, language: language)) · Sleep \(metric(snapshot.sleep.score, language: language)) · Strain \(metric(snapshot.strain.score, language: language))",
            isChinese
                ? "- 能量 \(metric(snapshot.energyBank.currentEnergy, language: language)) · 压力代理 \(metric(snapshot.stress.stressIndex, language: language))"
                : "- Energy \(metric(snapshot.energyBank.currentEnergy, language: language)) · Stress proxy \(metric(snapshot.stress.stressIndex, language: language))",
            isChinese
                ? "- Training Decision：\(snapshot.trainingDecision.readinessLevel) · \(snapshot.trainingDecision.readinessGuidance)"
                : "- Training Decision: \(snapshot.trainingDecision.readinessLevel) · \(snapshot.trainingDecision.readinessGuidance)",
            isChinese
                ? "- Data Coverage：\(coverage.availableSections)/\(coverage.totalSections) 可用\(missing.isEmpty ? "" : " · 缺失 \(missing)")"
                : "- Data Coverage: \(coverage.availableSections)/\(coverage.totalSections) available\(missing.isEmpty ? "" : " · missing \(missing)")",
            isChinese ? "- 安全：一般健康建议，不构成医疗诊断。" : "- Safety: General wellness guidance only; not a medical diagnosis.",
            "- content_hash: \(snapshot.contextHash)"
        ]

        var lines = required
        var wasTruncated = false

        func appendIfFits(_ value: String?) {
            guard let value, !value.isEmpty else { return }
            let candidate = (lines + [value]).joined(separator: "\n")
            if candidate.count <= maxCharacters {
                lines.append(value)
            } else {
                wasTruncated = true
            }
        }

        appendIfFits(bodyDrivers.isEmpty ? nil : (isChinese ? "- 主要驱动：\(bodyDrivers)" : "- Main drivers: \(bodyDrivers)"))
        appendIfFits(healthReferenceLine)

        let trendLines = snapshot.weeklyTrends
            .sorted { $0.key < $1.key }
            .map { "- \($0.key): \($0.value.prefix(120))" }
        if !trendLines.isEmpty {
            appendIfFits((isChinese ? "## 周趋势\n" : "## Weekly Trends\n") + trendLines.joined(separator: "\n"))
        }

        if let strength = snapshot.strengthTraining {
            if strength.sessions7d > 0 {
                appendIfFits(isChinese
                    ? "- 近 7 天力量训练：\(strength.sessions7d) 次 · \(strength.hardSets7d) 个有效组 · \(Int(strength.volume7dKg)) kg"
                    : "- Strength 7d: \(strength.sessions7d) sessions · \(strength.hardSets7d) effective sets · \(Int(strength.volume7dKg)) kg")
            }
            // 联通专项批次 1：局部疲劳（48h/7d 逐肌群组数）进紧凑视图——
            // 此前被剥掉，Coach 无法回答「某肌群 48h 练了几组」，只能拿不同口径的
            // 工具原始组次心算。
            let fatigueLines = strength.localFatigue.values
                .filter { $0.setsLast48h > 0 || $0.setsLast7d > 0 }
                .sorted { $0.setsLast48h > $1.setsLast48h }
                .prefix(3)
                .map { fatigue in
                    isChinese
                        ? "\(fatigue.muscleGroup) 48h \(fatigue.setsLast48h) 组 · 7d \(fatigue.setsLast7d) 组（\(fatigue.fatigueLevel)）"
                        : "\(fatigue.muscleGroup): 48h \(fatigue.setsLast48h), 7d \(fatigue.setsLast7d) sets (\(fatigue.fatigueLevel))"
                }
            if !fatigueLines.isEmpty {
                appendIfFits(isChinese
                    ? "- 局部疲劳：\(fatigueLines.joined(separator: "；"))"
                    : "- Local fatigue: \(fatigueLines.joined(separator: "; "))")
            }
            let summary = strength.recoveryResponseSummary
            if !summary.isEmpty && summary != "No post-training response data yet." && summary != "No post-training recovery response records in the past 28 days." {
                appendIfFits(isChinese
                    ? "- 近期恢复反应：\(summary)"
                    : "- Recent recovery response: \(summary)")
            }
        }

        // A1：完整 Daily Operating Plan 进入紧凑快照（此前只有 training decision 切片）。
        if let plan = snapshot.dailyOperatingPlan {
            let planLines: [String] = [
                plan["title"].map { "- 今日计划：\($0)（\(plan["status"] ?? "--")）" },
                plan["primary_action_type"].map { "- 主行动类型：\($0)" },
                plan["summary"].map { "- 计划摘要：\($0)" },
                plan["reasons_json"].map { "- 计划理由：\(String($0.prefix(200)))" }
            ].compactMap { $0 }
            if !planLines.isEmpty {
                appendIfFits(
                    (isChinese ? "## 今日运行计划\n" : "## Daily Operating Plan\n")
                        + planLines.joined(separator: "\n")
                )
            }
        }

        if let goal = snapshot.userWiki["body_model.primary_goal"],
           let style = snapshot.userWiki["body_model.training_style"] {
            let days = snapshot.userWiki["body_model.weekly_training_days"] ?? "--"
            appendIfFits(isChinese
                ? "- 身体模型：目标 \(localizedOnboardingGoal(goal)) · \(localizedOnboardingTrainingStyle(style)) · 每周 \(days) 次"
                : "- Body model: \(localizedOnboardingGoal(goal)) · \(localizedOnboardingTrainingStyle(style)) · \(days)x/week")
        }

        let rendered = lines.joined(separator: "\n")
        guard rendered.count > maxCharacters else {
            if wasTruncated {
                let marker = isChinese ? "\n[其余事实已按预算省略，可通过工具查询。]" : "\n[Additional facts omitted; use tools for details.]"
                if rendered.count + marker.count <= maxCharacters { return rendered + marker }
            }
            return rendered
        }

        // Required safety and hash lines take priority over descriptive detail.
        var compact = required
        while compact.joined(separator: "\n").count > maxCharacters, compact.count > 4 {
            compact.remove(at: compact.count - 3)
        }
        return String(compact.joined(separator: "\n").prefix(maxCharacters))
    }

    private func metric(_ metric: MetricValue<Double>, language: AppLanguage) -> String {
        guard let value = metric.value else {
            return language.isChinese ? "--（缺失）" : "-- (missing)"
        }
        let freshness = language.isChinese
            ? localizedDataFreshness(metric.freshness)
            : metric.freshness.rawValue
        let valueAndUnit = "\(Int(value.rounded())) \(metric.unit ?? "")"
        return language.isChinese ? "\(valueAndUnit)（\(freshness)）" : "\(valueAndUnit) (\(freshness))"
    }
}

// MARK: - Food Vision & Nutrition Intelligence Engine

public struct MacroNutrientAnalysisResult: Sendable, Equatable {
    public var estimatedCalories: Int
    public var proteinGrams: Int
    public var carbsGrams: Int
    public var fatGrams: Int
    public var fiberGrams: Int
    public var glycemicLoadEstimate: String // "low", "medium", "high"
    public var metabolicTag: String          // "protein_rich", "balanced", "high_glycemic_risk"
    public var recommendations: [String]

    public init(
        estimatedCalories: Int,
        proteinGrams: Int,
        carbsGrams: Int,
        fatGrams: Int,
        fiberGrams: Int,
        glycemicLoadEstimate: String,
        metabolicTag: String,
        recommendations: [String]
    ) {
        self.estimatedCalories = estimatedCalories
        self.proteinGrams = proteinGrams
        self.carbsGrams = carbsGrams
        self.fatGrams = fatGrams
        self.fiberGrams = fiberGrams
        self.glycemicLoadEstimate = glycemicLoadEstimate
        self.metabolicTag = metabolicTag
        self.recommendations = recommendations
    }
}

public struct FoodVisionIntelligenceEngine: Sendable {
    public init() {}

    public func analyzeMealText(_ text: String) -> MacroNutrientAnalysisResult {
        let lower = text.lowercased()
        var protein = 25
        var carbs = 45
        let fat = 15
        var fiber = 6
        var gl = "medium"
        var tag = "balanced"
        var recs: [String] = []

        if lower.contains("鸡胸肉") || lower.contains("牛肉") || lower.contains("蛋白") || lower.contains("chicken") || lower.contains("steak") {
            protein += 20
            tag = "protein_rich"
            recs.append("蛋白质比例充沛，非常有利于训练后肌肉修复与合成。")
        }

        if lower.contains("米饭") || lower.contains("面条") || lower.contains("面包") || lower.contains("扎实") || lower.contains("noodle") || lower.contains("rice") {
            carbs += 30
            gl = "high"
            recs.append("高升糖碳水源，建议搭配膳食纤维或饭后散步 10 分钟以平缓血糖波动。")
        }

        if lower.contains("沙拉") || lower.contains("蔬菜") || lower.contains("燕麦") || lower.contains("salad") {
            fiber += 5
            gl = "low"
            recs.append("膳食纤维丰富，有助于维持肠道菌群与平稳能量释放。")
        }

        let calories = protein * 4 + carbs * 4 + fat * 9

        return MacroNutrientAnalysisResult(
            estimatedCalories: calories,
            proteinGrams: protein,
            carbsGrams: carbs,
            fatGrams: fat,
            fiberGrams: fiber,
            glycemicLoadEstimate: gl,
            metabolicTag: tag,
            recommendations: recs
        )
    }
}


// MARK: - 联通专项批次 4：ADR 0002 收敛——共享 adapter
// TrainingPlanAdvisor 与 PostWorkoutAIGenerator 此前自拼 contextText/factsText，
// 绕过 AgentFactSnapshot 共享边界。现统一为「buildFacts → 快照 → adapter 渲染」：
// 健康事实（档案/五维评分/负荷分解/局部疲劳/训练）全部来自规范快照。

enum AgentFactAdapters {
    /// 训练规划上下文（生理档案/五维评分/局部疲劳来自快照；三年基线、近 3 天
    /// 训练与本地轮转建议属视图层实时量，由调用方传入）。
    static func trainingPlanningFacts(
        snapshot: AgentFactSnapshot,
        longTermRHRMedian: Double?,
        longTermHRVMedian: Double?,
        recentTrainedDays: [String],
        localPlanLines: [String],
        isChinese: Bool = AppLanguage.stored.isChinese
    ) -> String {
        var profileParts: [String] = []
        if let age = snapshot.extendedMetrics.age { profileParts.append("年龄 \(age)") }
        if let sex = snapshot.extendedMetrics.biologicalSex {
            profileParts.append(sex == "male" ? "男" : sex == "female" ? "女" : "性别其他")
        }
        if let height = snapshot.extendedMetrics.heightCm.value { profileParts.append("身高 \(Int(height))cm") }
        if let weight = snapshot.extendedMetrics.weightKg.value { profileParts.append("体重 \(String(format: "%.1f", weight))kg") }
        if let goal = snapshot.userWiki["body_model.primary_goal"], !goal.isEmpty { profileParts.append("目标 \(goal)") }
        if let style = snapshot.userWiki["body_model.training_style"], !style.isEmpty { profileParts.append("训练风格 \(style)") }
        if let weekly = snapshot.userWiki["body_model.weekly_training_days"], !weekly.isEmpty { profileParts.append("每周 \(weekly) 次") }
        let profileLine = profileParts.isEmpty ? "暂无" : profileParts.joined(separator: "，")

        var bodyModelParts: [String] = []
        if let maturity = snapshot.userWiki["body_model.maturity"], !maturity.isEmpty {
            let maturityLabel = maturity == "stable" ? "稳定期" : (maturity == "learning" ? "学习期" : "种子期")
            bodyModelParts.append("成熟度 \(maturityLabel)")
        }
        if let claims = snapshot.userWiki["body_model.claims"], !claims.isEmpty {
            bodyModelParts.append("断言 \(claims)")
        }
        if let rules = snapshot.userWiki["body_model.coach_rules"], !rules.isEmpty {
            bodyModelParts.append("教练规则 \(rules)")
        }
        let bodyModelLine = bodyModelParts.isEmpty
            ? "暂无"
            : bodyModelParts.joined(separator: "；")

        func scoreText(_ value: MetricValue<Double>, unavailable: String = "暂无") -> String {
            value.value.map { "\(Int($0.rounded()))" } ?? unavailable
        }

        var fatigueLines: [String] = []
        if let strength = snapshot.strengthTraining {
            fatigueLines = strength.localFatigue
                .map { key, fatigue in
                    "\(key): 48h \(fatigue.setsLast48h) 组, 7天 \(fatigue.setsLast7d) 组, \(fatigue.fatigueLevel)"
                }
                .sorted()
        }
        var longTermParts: [String] = []
        if let rhr = longTermRHRMedian { longTermParts.append("静息心率中位 \(Int(rhr.rounded())) bpm") }
        if let hrv = longTermHRVMedian { longTermParts.append("HRV 中位 \(Int(hrv.rounded())) ms") }
        let longTermLine = longTermParts.isEmpty
            ? ""
            : "三年历史基线(不含近90天):\n\(longTermParts.joined(separator: "，"))\n"
        return """
        生理档案: \(profileLine)
        身体模型: \(bodyModelLine)
        恢复评分: \(scoreText(snapshot.recovery.score))
        睡眠评分: \(scoreText(snapshot.sleep.score))
        压力指数: \(scoreText(snapshot.stress.stressIndex))
        负荷评分: \(scoreText(snapshot.strain.score))
        \(longTermLine)肌群疲劳(48h组数/7天组数/等级):
        \(fatigueLines.isEmpty ? "暂无力量训练数据" : fatigueLines.joined(separator: "\n"))
        最近训练(过去3天):
        \(recentTrainedDays.isEmpty ? "无" : recentTrainedDays.joined(separator: "\n"))
        本地轮转建议:
        \(localPlanLines.isEmpty ? "无" : localPlanLines.joined(separator: "\n"))
        """
    }

    /// 练后复盘上下文（本机训练事实 = 快照里的训练/负荷/评分；训练事实为唯一真值）。
    static func postWorkoutFacts(
        snapshot: AgentFactSnapshot,
        workoutID: UUID?,
        isChinese: Bool = AppLanguage.stored.isChinese,
        policy overridePolicy: AgentOutboundConsentPolicy? = nil
    ) -> String {
        let policy = overridePolicy ?? AgentOutboundConsentPolicy.current
        guard policy.canSendNetworkAI else {
            return isChinese
                ? "练后复盘未发送：尚未授予任何后台联网数据类别授权。"
                : "Post-workout review was not sent: no background outbound data category is authorized."
        }
        // WorkoutAdaptationService is intentionally kept on the local scoring
        // seam.  Redact here, at its final text adapter boundary, so a future
        // caller cannot bypass category consent by passing a complete snapshot.
        let outboundSnapshot = snapshot.redacted(for: policy)
        func scoreText(_ value: MetricValue<Double>) -> String {
            value.value.map { "\(Int($0.rounded()))" } ?? "N/A"
        }
        let decisionLine = outboundSnapshot.dailyOperatingPlan?["summary"]
            ?? outboundSnapshot.trainingDecision.reasons
        let planLine = outboundSnapshot.training.activePlan.map {
            "活跃计划：\($0.title)（\($0.totalDays) 天）"
        } ?? "无活跃计划"
        let safeWorkoutID = policy.training ? (workoutID?.uuidString ?? "-") : "-"
        if isChinese {
            return """
            刚完成的训练：workout_id=\(safeWorkoutID)（训练事实以本机记录为准）。
            当前身体评分：恢复 \(scoreText(outboundSnapshot.recovery.score))、睡眠 \(scoreText(outboundSnapshot.sleep.score))、负荷 \(scoreText(outboundSnapshot.strain.score))、压力 \(scoreText(outboundSnapshot.stress.stressIndex))、能量 \(scoreText(outboundSnapshot.energyBank.currentEnergy))。
            本机今日决定：\(decisionLine)
            \(planLine)
            """
        }
        return """
        Just completed: workout_id=\(safeWorkoutID) (training facts are authoritative locally).
        Current scores: Recovery \(scoreText(outboundSnapshot.recovery.score)), Sleep \(scoreText(outboundSnapshot.sleep.score)), Strain \(scoreText(outboundSnapshot.strain.score)), Stress \(scoreText(outboundSnapshot.stress.stressIndex)), Energy \(scoreText(outboundSnapshot.energyBank.currentEnergy)).
        Local decision: \(decisionLine)
        \(planLine)
        """
    }
}
