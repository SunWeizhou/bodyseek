import Foundation

/// Each domain provides its own AI context mapping.
/// Add a new builder when adding a new health domain — AIContextBuilder stays unchanged.
protocol DomainContextBuilder {
    /// Returns a [String: String] dict ready for the LLM context envelope.
    func build(from dashboard: DashboardSummary) -> [String: String]
}

// MARK: - Sleep Context

struct SleepContextBuilder: DomainContextBuilder {
    func build(from dashboard: DashboardSummary) -> [String: String] {
        let metrics = dashboard.sleepScore.metrics
        return [
            "sleep_score": (dashboard.sleepScore.hasData ? dashboard.sleepScore.value : nil).map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "N/A",
            "duration_minutes": dashboard.sleepScore.hasData ? "\(dashboard.sleepSummary.totalSleepMinutes)" : "N/A",
            "band": dashboard.sleepScore.hasData ? dashboard.sleepScore.band.rawValue : "unavailable",
            "algorithm_version": dashboard.sleepScore.algorithmVersion,
            "data_coverage": dashboard.sleepScore.dataCoverage.rawValue,
            "confidence": dashboard.sleepScore.confidence.rawValue,
            "missing_inputs": dashboard.sleepScore.missingInputs.joined(separator: ","),
            "reason": dashboard.sleepScore.reasons.first ?? "",
            "rem_minutes": dashboard.sleepSummary.stageMinutes[.rem].map(String.init) ?? "N/A",
            "deep_minutes": dashboard.sleepSummary.stageMinutes[.deep].map(String.init) ?? "N/A",
            "core_minutes": dashboard.sleepSummary.stageMinutes[.core].map(String.init) ?? "N/A",
            "awake_minutes": dashboard.sleepSummary.stageMinutes[.awake].map(String.init) ?? "N/A",
            "sleep_efficiency_pct": metrics["sleep_efficiency"].map { String(format: "%.1f%%", $0) } ?? "N/A",
            "rem_pct": metrics["rem_pct"].map { String(format: "%.1f%%", $0) } ?? "N/A",
            "deep_pct": metrics["deep_pct"].map { String(format: "%.1f%%", $0) } ?? "N/A"
        ]
    }
}

// MARK: - Recovery Context

struct RecoveryContextBuilder: DomainContextBuilder {
    func build(from dashboard: DashboardSummary) -> [String: String] {
        let hrvToday = dashboard.recoveryMetrics.hrvMilliseconds
        let hrvBaseline = dashboard.recoveryBaseline.hrvMilliseconds
        let hrvVsBaselinePct: String = {
            if let t = hrvToday, let b = hrvBaseline, b > 0 {
                return String(format: "%+.1f%%", ((t - b) / b) * 100)
            }
            return "N/A"
        }()
        let hrvZ = dashboard.recovery.metrics["hrv_z_score"].map { String(format: "%.2f", $0) } ?? "N/A"

        return [
            "score": (dashboard.recovery.hasData ? dashboard.recovery.value : nil).map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "N/A",
            "band": dashboard.recovery.hasData ? dashboard.recovery.band.rawValue : "unavailable",
            "confidence": dashboard.recovery.confidence.rawValue,
            "reason": dashboard.recovery.reasons.first ?? "",
            "hrv_ms": hrvToday.map { "\(Int($0))" } ?? "N/A",
            "rhr_bpm": dashboard.recoveryMetrics.restingHeartRate.map { "\(Int($0))" } ?? "N/A",
            "respiratory_rate": dashboard.recoveryMetrics.respiratoryRate.map { String(format: "%.1f", $0) } ?? "N/A",
            "hrv_z_score": hrvZ,
            "hrv_vs_baseline_pct": hrvVsBaselinePct,
            "hrv_baseline_ms": hrvBaseline.map { "\(Int($0))" } ?? "N/A",
            "rhr_baseline_bpm": dashboard.recoveryBaseline.restingHeartRate.map { "\(Int($0))" } ?? "N/A"
        ]
    }
}

// MARK: - Strain Context

struct StrainContextBuilder: DomainContextBuilder {
    func build(from dashboard: DashboardSummary) -> [String: String] {
        var dict: [String: String] = [
            "score": (dashboard.strain.hasData ? dashboard.strain.value : nil).map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "N/A",
            "band": dashboard.strain.hasData ? dashboard.strain.band.rawValue : "unavailable",
            "target_status": dashboard.strain.hasData ? dashboard.strain.targetStatus.rawValue : "unavailable",
            "recommended_range": dashboard.strain.hasData ? "\(dashboard.strain.recommendedRange.lowerBound)-\(dashboard.strain.recommendedRange.upperBound)" : "N/A",
            "steps": dashboard.strain.metrics["steps_raw"].map { "\(Int($0))" } ?? "N/A",
            "active_energy_kcal": dashboard.strain.metrics["active_energy_raw"].map { "\(Int($0))" } ?? "N/A",
            "exercise_minutes": dashboard.strain.metrics["exercise_minutes_raw"].map { "\(Int($0))" } ?? "N/A"
        ]
        // 联通专项批次 1：补齐负荷分解指标（此前 agent 只能看到聚合分数）。
        dict["training_load_ratio"] = dashboard.strain.metrics["training_load_ratio"].map { String(format: "%.2f", $0) } ?? "N/A"
        dict["acute_7d_load"] = dashboard.strain.metrics["acute_7d_load"].map { String(format: "%.0f", $0) } ?? "N/A"
        dict["chronic_28d_equivalent"] = dashboard.strain.metrics["chronic_28d_equivalent"].map { String(format: "%.0f", $0) } ?? "N/A"
        dict["training_load_status"] = dashboard.strain.trainingLoadStatus.rawValue
        return dict
    }
}

// MARK: - Stress Context

struct StressContextBuilder: DomainContextBuilder {
    func build(from dashboard: DashboardSummary) -> [String: String] {
        var dict: [String: String] = [
            "stress_index": (dashboard.stress.hasData ? dashboard.stress.value : nil).map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "N/A",
            "band": dashboard.stress.hasData ? dashboard.stress.band.rawValue : "unavailable",
            "confidence": dashboard.stress.confidence.rawValue,
            "proxy_notice": "Stress is a physiological proxy, not a medical or mental health diagnosis."
        ]
        // 联通专项批次 1：补齐压力六因子分解（此前 agent 只能看到聚合 stress_index）。
        dict["rhr_stress"] = dashboard.stress.metrics["rhr_stress"].map { String(format: "%.0f", $0) } ?? "N/A"
        dict["hrv_stress"] = dashboard.stress.metrics["hrv_stress"].map { String(format: "%.0f", $0) } ?? "N/A"
        dict["resp_stress"] = dashboard.stress.metrics["resp_stress"].map { String(format: "%.0f", $0) } ?? "N/A"
        dict["temp_stress"] = dashboard.stress.metrics["temp_stress"].map { String(format: "%.0f", $0) } ?? "N/A"
        dict["sleep_debt_stress"] = dashboard.stress.metrics["sleep_debt_stress"].map { String(format: "%.0f", $0) } ?? "N/A"
        dict["load_stress"] = dashboard.stress.metrics["load_stress"].map { String(format: "%.0f", $0) } ?? "N/A"
        return dict
    }
}

// MARK: - Energy Bank Context

struct EnergyBankContextBuilder: DomainContextBuilder {
    func build(from dashboard: DashboardSummary) -> [String: String] {
        [
            "morning_energy": dashboard.energy.hasData ? dashboard.energy.morningEnergy.formatted(.number.precision(.fractionLength(0))) : "N/A",
            "current_energy": (dashboard.energy.hasData ? dashboard.energy.value : nil).map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "N/A",
            "status": dashboard.energy.hasData ? dashboard.energy.status.rawValue : "unavailable",
            "charge_efficiency": dashboard.energy.metrics["charge_efficiency"].map { String(format: "%.0f%%", $0 * 100) } ?? "N/A",
            "atl_7day": dashboard.energy.metrics["atl"].map { String(format: "%.0f", $0) } ?? "N/A",
            "ctl_42day": dashboard.energy.metrics["ctl"].map { String(format: "%.0f", $0) } ?? "N/A",
            "tsb_freshness": dashboard.energy.metrics["tsb"].map { String(format: "%+.0f", $0) } ?? "N/A",
            "acwr_ratio": dashboard.energy.metrics["acwr"].map { String(format: "%.2f", $0) } ?? "N/A"
        ]
    }
}

// MARK: - Health Age Context

struct HealthAgeContextBuilder: DomainContextBuilder {
    func build(from dashboard: DashboardSummary) -> [String: String] {
        [
            "trend": dashboard.healthAge.label.rawValue,
            "trend_score": dashboard.healthAge.trendScore.formatted(.number.precision(.fractionLength(2))),
            "beta_notice": "Health Age Trend is beta and does not claim biological age."
        ]
    }
}

// MARK: - Workouts Context Builder

struct WorkoutsContextBuilder {
    func build(from workouts: [WorkoutSummary]) -> [String: String] {
        guard !workouts.isEmpty else {
            return ["note": "No workouts recorded today.", "count": "0"]
        }
        let totalKcal = workouts.compactMap(\.energyKilocalories).reduce(0, +)
        let totalDurationMin = workouts.map { Int($0.end.timeIntervalSince($0.start) / 60) }.reduce(0, +)
        let types = Set(workouts.map(\.activityName)).sorted().joined(separator: ", ")
        let workoutList: [[String: String]] = workouts.map { w in
            var d: [String: String] = [
                "type": w.activityName,
                "duration_min": "\(Int(w.end.timeIntervalSince(w.start) / 60))"
            ]
            if let kcal = w.energyKilocalories { d["calories"] = "\(Int(kcal))" }
            if let hr = w.averageHeartRate { d["avg_hr_bpm"] = "\(Int(hr))" }
            if let dist = w.distanceMeters { d["distance_m"] = String(format: "%.0f", dist) }
            return d
        }
        let listJSON = (try? String(data: JSONEncoder().encode(workoutList), encoding: .utf8)) ?? "[]"
        return [
            "count": "\(workouts.count)",
            "types": types,
            "total_energy_kcal": "\(Int(totalKcal))",
            "total_duration_min": "\(totalDurationMin)",
            "list": listJSON
        ]
    }
}

// MARK: - Extended Metrics Context Builder

struct ExtendedMetricsContextBuilder {
    func build(ext: ExtendedHealthMetrics, body: BodyMetricsSummary) -> [String: String] {
        var d: [String: String] = [:]
        if let age = ext.age ?? WikiFileService.getAgeFromWiki() {
            d["age"] = "\(age)"
        }
        if let sex = ext.biologicalSex { d["biological_sex"] = sex }
        if let h = ext.heightCm { d["height_cm"] = String(format: "%.1f", h) }
        if let bmi = ext.bmi { d["bmi"] = String(format: "%.1f", bmi) }
        if let w = body.weightKilograms { d["weight_kg"] = String(format: "%.1f", w) }
        if let bf = body.bodyFatPercentage { d["body_fat_pct"] = String(format: "%.1f", bf) }
        if let lbm = body.leanBodyMassKilograms { d["lean_body_mass_kg"] = String(format: "%.1f", lbm) }
        if let vo2 = body.vo2Max { d["vo2_max"] = String(format: "%.1f", vo2) }
        if let spo2 = ext.oxygenSaturation { d["spo2_pct"] = String(format: "%.0f", spo2) }
        if let sbp = ext.bloodPressureSystolic { d["blood_pressure_systolic"] = "\(Int(sbp))" }
        if let dbp = ext.bloodPressureDiastolic { d["blood_pressure_diastolic"] = "\(Int(dbp))" }
        if let glucose = ext.bloodGlucose { d["blood_glucose_mgdl"] = String(format: "%.0f", glucose) }
        if let ws = ext.walkingSpeed { d["walking_speed_ms"] = String(format: "%.2f", ws) }
        if let wa = ext.walkingAsymmetry { d["walking_asymmetry_pct"] = String(format: "%.1f", wa) }
        if let temp = ext.bodyTemperature { d["body_temp_c"] = String(format: "%.1f", temp) }
        if let water = ext.waterMl { d["water_ml"] = "\(Int(water))" }
        if let caff = ext.caffeineMg { d["caffeine_mg"] = "\(Int(caff))" }
        if let mindful = ext.mindfulMinutes { d["mindful_minutes"] = "\(Int(mindful))" }
        return d
    }
}
