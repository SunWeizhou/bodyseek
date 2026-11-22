import Foundation
import os
#if canImport(CoreML)
@preconcurrency import CoreML
#endif

/// Metadata & Split-Conformal calibration parameters for a single forecast target in `personal_forecaster_v1_spec.json`.
public struct PersonalForecasterTargetSpec: Codable, Equatable, Hashable, Sendable {
    public let name: String
    public let title: String
    public let unit: String
    public let weights: [Double]
    public let bias: Double
    public let clipMin: Double
    public let clipMax: Double
    public let q80HalfWidth: Double
    public let q90HalfWidth: Double
    public let walkForwardBestBaseline: String
    public let walkForwardMAE: Double
    public let walkForwardCov80: Double

    private enum CodingKeys: String, CodingKey {
        case name
        case title
        case unit
        case weights
        case bias
        case clipMin = "clip_min"
        case clipMax = "clip_max"
        case q80HalfWidth = "q80_half_width"
        case q90HalfWidth = "q90_half_width"
        case walkForwardBestBaseline = "walk_forward_best_baseline"
        case walkForwardMAE = "walk_forward_mae"
        case walkForwardCov80 = "walk_forward_cov80"
    }
}

/// Shared preprocessing, feature ordering, z-normalization & target specification exported alongside `BodySeekPersonalForecasterV1.mlpackage`.
public struct PersonalForecasterSpec: Codable, Equatable, Sendable {
    public let modelVersion: String
    public let coremlModelName: String
    public let featureColumns: [String]
    public let featureMeans: [Double]
    public let featureStds: [Double]
    public let zClip: Double
    public let eatingContextMaskReservedIndex: Int
    public let targets: [PersonalForecasterTargetSpec]

    private enum CodingKeys: String, CodingKey {
        case modelVersion = "model_version"
        case coremlModelName = "coreml_model_name"
        case featureColumns = "feature_columns"
        case featureMeans = "feature_means"
        case featureStds = "feature_stds"
        case zClip = "z_clip"
        case eatingContextMaskReservedIndex = "eating_context_mask_reserved_index"
        case targets
    }
}

public enum PersonalForecasterError: Error, LocalizedError, Sendable {
    case bundledSpecNotFound
    case invalidFeatureVectorLength(expected: Int, actual: Int)
    case coreMLModelNotFound
    case coreMLPredictionShapeMismatch(actualCount: Int, expectedCount: Int)

    public var errorDescription: String? {
        switch self {
        case .bundledSpecNotFound:
            return "未能在 Bundle.module 中找到 personal_forecaster_v1_spec.json。"
        case let .invalidFeatureVectorLength(expected, actual):
            return "预测特征向量维度不匹配：期望 \(expected)，实际 \(actual)。"
        case .coreMLModelNotFound:
            return "未能在 Bundle.module 中找到 BodySeekPersonalForecasterV1.mlpackage/.mlmodelc。"
        case let .coreMLPredictionShapeMismatch(actualCount, expectedCount):
            return "CoreML 输出维度异常：期望 \(expectedCount)，实际 \(actualCount)。"
        }
    }
}

public struct PersonalForecastDriver: Identifiable, Equatable, Hashable, Codable, Sendable {
    public let id: String
    public let label: String
    public let contribution: Double
    public let unit: String

    public init(id: String, label: String, contribution: Double, unit: String) {
        self.id = id
        self.label = label
        self.contribution = contribution
        self.unit = unit
    }
}

public struct PersonalForecastTargetResult: Identifiable, Equatable, Hashable, Codable, Sendable {
    public var id: String { name }
    public let name: String
    public let title: String
    public let unit: String
    public let point: Double
    public let interval80Low: Double
    public let interval80High: Double
    public let interval90Low: Double
    public let interval90High: Double
    public let walkForwardBestBaseline: String
    public let walkForwardMAE: Double
    public let walkForwardCov80: Double
    public let drivers: [PersonalForecastDriver]
    public let recent14dObservedDays: Int
    public let totalObservedDays: Int

    public var hasDirectTargetEvidence: Bool {
        recent14dObservedDays >= 3
    }

    public init(
        name: String,
        title: String,
        unit: String,
        point: Double,
        interval80Low: Double,
        interval80High: Double,
        interval90Low: Double,
        interval90High: Double,
        walkForwardBestBaseline: String,
        walkForwardMAE: Double,
        walkForwardCov80: Double,
        drivers: [PersonalForecastDriver] = [],
        recent14dObservedDays: Int = 0,
        totalObservedDays: Int = 0
    ) {
        self.name = name
        self.title = title
        self.unit = unit
        self.point = point
        self.interval80Low = interval80Low
        self.interval80High = interval80High
        self.interval90Low = interval90Low
        self.interval90High = interval90High
        self.walkForwardBestBaseline = walkForwardBestBaseline
        self.walkForwardMAE = walkForwardMAE
        self.walkForwardCov80 = walkForwardCov80
        self.drivers = drivers
        self.recent14dObservedDays = recent14dObservedDays
        self.totalObservedDays = totalObservedDays
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case title
        case unit
        case point
        case interval80Low
        case interval80High
        case interval90Low
        case interval90High
        case walkForwardBestBaseline
        case walkForwardMAE
        case walkForwardCov80
        case drivers
        case recent14dObservedDays
        case totalObservedDays
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        title = try container.decode(String.self, forKey: .title)
        unit = try container.decode(String.self, forKey: .unit)
        point = try container.decode(Double.self, forKey: .point)
        interval80Low = try container.decode(Double.self, forKey: .interval80Low)
        interval80High = try container.decode(Double.self, forKey: .interval80High)
        interval90Low = try container.decode(Double.self, forKey: .interval90Low)
        interval90High = try container.decode(Double.self, forKey: .interval90High)
        walkForwardBestBaseline = try container.decode(String.self, forKey: .walkForwardBestBaseline)
        walkForwardMAE = try container.decode(Double.self, forKey: .walkForwardMAE)
        walkForwardCov80 = try container.decode(Double.self, forKey: .walkForwardCov80)
        drivers = try container.decodeIfPresent([PersonalForecastDriver].self, forKey: .drivers) ?? []
        recent14dObservedDays = try container.decodeIfPresent(Int.self, forKey: .recent14dObservedDays) ?? 0
        totalObservedDays = try container.decodeIfPresent(Int.self, forKey: .totalObservedDays) ?? 0
    }
}

public struct PersonalForecastSummary: Equatable, Hashable, Codable, Sendable {
    public let referenceDayKey: DayKey
    public let targetDayKey: DayKey
    public let modelVersion: String
    public let runtimeBackend: String
    public let observedDays: Int
    public let eatingContextObservedToday: Bool
    public let targets: [PersonalForecastTargetResult]
    public let disclaimer: String

    public init(
        referenceDayKey: DayKey,
        targetDayKey: DayKey,
        modelVersion: String,
        runtimeBackend: String,
        observedDays: Int,
        eatingContextObservedToday: Bool,
        targets: [PersonalForecastTargetResult],
        disclaimer: String = "个人统计预测 · 非医学诊断"
    ) {
        self.referenceDayKey = referenceDayKey
        self.targetDayKey = targetDayKey
        self.modelVersion = modelVersion
        self.runtimeBackend = runtimeBackend
        self.observedDays = observedDays
        self.eatingContextObservedToday = eatingContextObservedToday
        self.targets = targets
        self.disclaimer = disclaimer
    }

    public func target(named name: String) -> PersonalForecastTargetResult? {
        targets.first { $0.name == name }
    }
}

public enum PersonalForecastState: Equatable, Hashable, Codable, Sendable {
    case available(PersonalForecastSummary)
    case insufficientData(observedDays: Int, minimumRequired: Int, reason: String)
}

#if canImport(CoreML)
/// Thread-safe singleton wrapper compiling & running `BodySeekPersonalForecasterV1.mlpackage` on Apple CoreML runtime.
public final class CoreMLPersonalForecaster: @unchecked Sendable {
    public static let shared = CoreMLPersonalForecaster()

    private let lock = NSLock()
    private let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "CoreMLPersonalForecaster")
    private var cachedModel: MLModel?
    private var compiledTemporaryURL: URL?

    private init() {}

    public func loadModel() throws -> MLModel {
        lock.lock()
        defer { lock.unlock() }
        if let cachedModel {
            return cachedModel
        }

        let config = MLModelConfiguration()
        config.computeUnits = .cpuOnly

        if let compiledURL = Bundle.module.url(
            forResource: "BodySeekPersonalForecasterV1",
            withExtension: "mlmodelc",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(forResource: "BodySeekPersonalForecasterV1", withExtension: "mlmodelc") {
            let model = try MLModel(contentsOf: compiledURL, configuration: config)
            cachedModel = model
            return model
        }

        guard let packageURL = Bundle.module.url(
            forResource: "BodySeekPersonalForecasterV1",
            withExtension: "mlpackage",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(forResource: "BodySeekPersonalForecasterV1", withExtension: "mlpackage") else {
            throw PersonalForecasterError.coreMLModelNotFound
        }

        let compiledURL = try MLModel.compileModel(at: packageURL)
        compiledTemporaryURL = compiledURL
        let model = try MLModel(contentsOf: compiledURL, configuration: config)
        cachedModel = model
        logger.info("Compiled and loaded BodySeekPersonalForecasterV1 CoreML model from \(packageURL.lastPathComponent, privacy: .public)")
        return model
    }

    public func predictRaw(features: [Double]) throws -> [Double] {
        guard features.count == 31 else {
            throw PersonalForecasterError.invalidFeatureVectorLength(expected: 31, actual: features.count)
        }
        let model = try loadModel()
        let inputArray = try MLMultiArray(shape: [1, 31], dataType: .float32)
        for (idx, val) in features.enumerated() {
            inputArray[[0, NSNumber(value: idx)]] = NSNumber(value: Float(val))
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["features": MLFeatureValue(multiArray: inputArray)])
        let output = try model.prediction(from: provider)
        guard let outputArray = output.featureValue(for: "predictions")?.multiArrayValue,
              outputArray.count >= 3 else {
            let count = output.featureValue(for: "predictions")?.multiArrayValue?.count ?? 0
            throw PersonalForecasterError.coreMLPredictionShapeMismatch(actualCount: count, expectedCount: 3)
        }
        return [
            outputArray[[0, 0]].doubleValue,
            outputArray[[0, 1]].doubleValue,
            outputArray[[0, 2]].doubleValue,
        ]
    }
}
#endif

/// Strictly causal on-device personal multi-target forecaster aligned bit-for-bit with `BodySeekML/src/bodyseek_ml/forecasting.py`.
public enum PersonalForecasterEngine {
    public static let minimumRequiredObservedDays = 7
    private static let logger = Logger(subsystem: "com.sunweizhou.Vela4", category: "PersonalForecasterEngine")

    public static func loadBundledSpec() throws -> PersonalForecasterSpec {
        guard let url = Bundle.module.url(
            forResource: "personal_forecaster_v1_spec",
            withExtension: "json",
            subdirectory: "Resources"
        ) ?? Bundle.module.url(forResource: "personal_forecaster_v1_spec", withExtension: "json") else {
            throw PersonalForecasterError.bundledSpecNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(PersonalForecasterSpec.self, from: data)
    }

    private static let driverGroups: [(id: String, label: String, range: ClosedRange<Int>)] = [
        ("hrv", "HRV 节律", 0...4),
        ("rhr", "静息心率趋势", 5...9),
        ("sleep", "昨夜睡眠与效率", 10...16),
        ("activity", "日活动与训练时长", 17...18),
        ("acwr", "急慢性负荷与 ACWR", 19...21),
        ("banister", "体能与疲劳平衡", 22...23),
        ("effort_cycle", "训练用力与星期节律", 24...30),
    ]

    private static func normalizedFeatures(features: [Double], spec: PersonalForecasterSpec) throws -> [Double] {
        let dim = spec.featureColumns.count
        guard features.count == dim else {
            throw PersonalForecasterError.invalidFeatureVectorLength(expected: dim, actual: features.count)
        }
        var normalized = [Double](repeating: 0.0, count: dim)
        for i in 0..<dim {
            let std = spec.featureStds[i] > 1e-12 ? spec.featureStds[i] : 1.0
            let z = (features[i] - spec.featureMeans[i]) / std
            normalized[i] = min(spec.zClip, max(-spec.zClip, z))
        }
        return normalized
    }

    /// Reference pure-Swift linear/Banister evaluation matching `PersonalForecasterSpec` & `coreml_export.py`.
    public static func predictRawLinear(features: [Double], spec: PersonalForecasterSpec) throws -> [Double] {
        let normalized = try normalizedFeatures(features: features, spec: spec)
        let dim = normalized.count
        return spec.targets.map { target in
            var sum = target.bias
            for i in 0..<min(dim, target.weights.count) {
                sum += normalized[i] * target.weights[i]
            }
            return min(target.clipMax, max(target.clipMin, sum))
        }
    }

    /// Computes exact linear group attributions whose sum equals `(unclippedLinearPoint - target.bias)`.
    public static func computeDrivers(
        features: [Double],
        spec: PersonalForecasterSpec,
        target: PersonalForecasterTargetSpec
    ) throws -> [PersonalForecastDriver] {
        let normalized = try normalizedFeatures(features: features, spec: spec)
        let limit = min(normalized.count, target.weights.count)
        return driverGroups.map { group in
            var contribution = 0.0
            for idx in group.range where idx < limit {
                contribution += normalized[idx] * target.weights[idx]
            }
            return PersonalForecastDriver(
                id: group.id,
                label: group.label,
                contribution: contribution,
                unit: target.unit
            )
        }
        .sorted { abs($0.contribution) > abs($1.contribution) }
    }

    /// Build the 31-dimensional causal feature vector at `referenceDayKey` using only days `<= referenceDayKey`.
    public static func buildFeatureVector(
        from historyDays: [DailyComputedDay],
        referenceDayKey: DayKey,
        eatingAvailableDayKeys: Set<DayKey> = []
    ) -> [Double] {
        // Strictly filter out any future days (> referenceDayKey) so historical evaluation has zero future leakage.
        var byDay: [DayKey: DailyComputedDay] = [:]
        for day in historyDays where day.dayKey <= referenceDayKey {
            byDay[day.dayKey] = day
        }
        var sortedDays = byDay.values.sorted { $0.dayKey < $1.dayKey }
        if sortedDays.isEmpty {
            let emptyRaw = DailyRawMetrics(date: referenceDayKey.calendarDayStart())
            let missingScore: (MetricKind) -> MetricScore = { kind in
                MetricScore(
                    kind: kind,
                    value: nil,
                    availability: .missing(reason: "无观测样本"),
                    badge: "缺失",
                    subtitle: ""
                )
            }
            let emptyComputed = DailyComputedDay(
                date: emptyRaw.date,
                dayKey: referenceDayKey,
                raw: emptyRaw,
                recovery: missingScore(.recovery),
                sleep: missingScore(.sleep),
                strain: missingScore(.strain),
                stress: missingScore(.stress),
                energy: missingScore(.energy),
                energyCurve: [],
                stressTimeline: [],
                factualSummary: "",
                evidenceSummary: ""
            )
            sortedDays = [emptyComputed]
        }

        let n = sortedDays.count
        var hrvRaw = [Double?](repeating: nil, count: n)
        var rhrRaw = [Double?](repeating: nil, count: n)
        var sleepMinRaw = [Double?](repeating: nil, count: n)
        var sleepEffRaw = [Double?](repeating: nil, count: n)
        var sleepDeepRaw = [Double?](repeating: nil, count: n)
        var sleepRemRaw = [Double?](repeating: nil, count: n)
        var activeKcalRaw = [Double?](repeating: nil, count: n)
        var workoutMinRaw = [Double](repeating: 0.0, count: n)
        var effortUserRaw = [Double?](repeating: nil, count: n)
        var effortEstRaw = [Double?](repeating: nil, count: n)

        for (i, day) in sortedDays.enumerated() {
            let raw = day.raw
            hrvRaw[i] = raw.hrvMs
            rhrRaw[i] = raw.restingHeartRateBpm
            if let asleep = raw.sleepAsleepMinutes, asleep > 0 {
                sleepMinRaw[i] = Double(asleep)
                let denom = max(raw.sleepInBedMinutes ?? 0, asleep + (raw.awakeMinutes ?? 0))
                if denom > 0 {
                    sleepEffRaw[i] = min(1.0, max(0.0, Double(asleep) / Double(denom)))
                }
            }
            sleepDeepRaw[i] = raw.deepMinutes.map(Double.init)
            sleepRemRaw[i] = raw.remMinutes.map(Double.init)
            activeKcalRaw[i] = raw.activeEnergyKcal
            workoutMinRaw[i] = Double(raw.workouts.reduce(0) { $0 + max(0, $1.durationMinutes) })

            let userEfforts = raw.workouts.compactMap(\.effortScore)
            if !userEfforts.isEmpty {
                effortUserRaw[i] = userEfforts.reduce(0, +) / Double(userEfforts.count)
            }
            let estEfforts = raw.workouts.compactMap(\.estimatedEffortScore)
            if !estEfforts.isEmpty {
                effortEstRaw[i] = estEfforts.reduce(0, +) / Double(estEfforts.count)
            }
        }

        let hrvRoll7 = causalRollingMean(hrvRaw, window: 7)
        let hrvRoll28 = causalRollingMean(hrvRaw, window: 28)
        let rhrRoll7 = causalRollingMean(rhrRaw, window: 7)
        let rhrRoll28 = causalRollingMean(rhrRaw, window: 28)
        let seffRoll7 = causalRollingMean(sleepEffRaw, window: 7)
        let seffRoll28 = causalRollingMean(sleepEffRaw, window: 28)

        let hrvLag0 = causalExpandingFill(hrvRaw, defaultValue: 43.0)
        let rhrLag0 = causalExpandingFill(rhrRaw, defaultValue: 58.0)
        let sleepMinLag0 = causalExpandingFill(sleepMinRaw, defaultValue: 420.0)
        let sleepEffLag0 = causalExpandingFill(sleepEffRaw, defaultValue: 0.94)
        let sleepEffR7Filled = causalExpandingFill(seffRoll7, defaultValue: 0.94)
        let sleepEffR28Filled = causalExpandingFill(seffRoll28, defaultValue: 0.94)
        let sleepDeepLag0 = causalExpandingFill(sleepDeepRaw, defaultValue: 65.0)
        let sleepRemLag0 = causalExpandingFill(sleepRemRaw, defaultValue: 85.0)
        let activeKcalLag0 = causalExpandingFill(activeKcalRaw, defaultValue: 450.0)
        let effortUserLag0 = causalExpandingFill(effortUserRaw, defaultValue: 7.0)
        let effortEstLag0 = causalExpandingFill(effortEstRaw, defaultValue: 6.5)

        let hrvR7Filled = causalExpandingFill(hrvRoll7, defaultValue: 43.0)
        let hrvR28Filled = causalExpandingFill(hrvRoll28, defaultValue: 43.0)
        let rhrR7Filled = causalExpandingFill(rhrRoll7, defaultValue: 58.0)
        let rhrR28Filled = causalExpandingFill(rhrRoll28, defaultValue: 58.0)

        var dailyLoad = [Double](repeating: 0.0, count: n)
        for i in 0..<n {
            dailyLoad[i] = activeKcalLag0[i] / 100.0 + workoutMinRaw[i] * 0.12
        }

        let decayG = exp(-1.0 / 42.0)
        let decayH = exp(-1.0 / 7.0)
        var gVal = dailyLoad[0]
        var hVal = dailyLoad[0]
        if n > 1 {
            for i in 1..<n {
                gVal = decayG * gVal + (1.0 - decayG) * dailyLoad[i]
                hVal = decayH * hVal + (1.0 - decayH) * dailyLoad[i]
            }
        }

        let last = n - 1
        let strainAcute7 = trailingMean(dailyLoad, endIndex: last, window: 7)
        let strainChronic28 = max(0.5, trailingMean(dailyLoad, endIndex: last, window: 28))
        let acwrRatio = min(2.5, max(0.3, strainAcute7 / strainChronic28))

        let hrvLag1 = last >= 1 ? hrvLag0[last - 1] : hrvLag0[last]
        let rhrLag1 = last >= 1 ? rhrLag0[last - 1] : rhrLag0[last]

        let hrvMask0 = hrvRaw[last] != nil ? 1.0 : 0.0
        let rhrMask0 = rhrRaw[last] != nil ? 1.0 : 0.0
        let sleepMask0 = sleepEffRaw[last] != nil ? 1.0 : 0.0
        let effortUserMask0 = effortUserRaw[last] != nil ? 1.0 : 0.0
        let effortEstMask0 = effortEstRaw[last] != nil ? 1.0 : 0.0
        let eatingMask0 = eatingAvailableDayKeys.contains(sortedDays[last].dayKey) ? 1.0 : 0.0

        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        let weekday = gregorian.component(.weekday, from: sortedDays[last].dayKey.calendarDayStart(calendar: gregorian))
        // Python pandas `day_of_week`: Monday = 0 ... Sunday = 6
        let dow = Double((weekday + 5) % 7)
        let dowSin = sin(2.0 * Double.pi * dow / 7.0)
        let dowCos = cos(2.0 * Double.pi * dow / 7.0)

        return [
            hrvLag0[last],
            hrvLag1,
            hrvR7Filled[last],
            hrvR28Filled[last],
            hrvMask0,
            rhrLag0[last],
            rhrLag1,
            rhrR7Filled[last],
            rhrR28Filled[last],
            rhrMask0,
            sleepMinLag0[last],
            sleepEffLag0[last],
            sleepEffR7Filled[last],
            sleepEffR28Filled[last],
            sleepDeepLag0[last],
            sleepRemLag0[last],
            sleepMask0,
            activeKcalLag0[last],
            workoutMinRaw[last],
            strainAcute7,
            strainChronic28,
            acwrRatio,
            gVal,
            hVal,
            effortUserLag0[last],
            effortUserMask0,
            effortEstLag0[last],
            effortEstMask0,
            eatingMask0,
            dowSin,
            dowCos,
        ]
    }

    public static func forecast(
        historyDays: [DailyComputedDay],
        referenceDate: Date,
        eatingAvailableDayKeys: Set<DayKey> = []
    ) -> PersonalForecastState {
        let referenceDayKey = referenceDate.physiologicalDayKey()
        let pastDays = historyDays.filter { $0.dayKey <= referenceDayKey }
        let observedDays = pastDays.filter {
            $0.raw.hrvMs != nil || $0.raw.restingHeartRateBpm != nil || $0.raw.sleepAsleepMinutes != nil
        }.count

        guard observedDays >= minimumRequiredObservedDays else {
            return .insufficientData(
                observedDays: observedDays,
                minimumRequired: minimumRequiredObservedDays,
                reason: "有效历史观测日需至少 \(minimumRequiredObservedDays) 天（当前 \(observedDays) 天），暂不生成个人统计预测。"
            )
        }

        let spec: PersonalForecasterSpec
        do {
            spec = try loadBundledSpec()
        } catch {
            logger.error("Failed loading bundled PersonalForecasterSpec: \(error.localizedDescription, privacy: .public)")
            return .insufficientData(
                observedDays: observedDays,
                minimumRequired: minimumRequiredObservedDays,
                reason: "预测规格文件加载失败：\(error.localizedDescription)"
            )
        }

        let features = buildFeatureVector(
            from: pastDays,
            referenceDayKey: referenceDayKey,
            eatingAvailableDayKeys: eatingAvailableDayKeys
        )

        var rawPredictions: [Double] = []
        var runtimeBackend = "Swift-LinearSpec-v1"

        #if canImport(CoreML)
        do {
            rawPredictions = try CoreMLPersonalForecaster.shared.predictRaw(features: features)
            runtimeBackend = "CoreML (BodySeekPersonalForecasterV1.mlpackage)"
        } catch {
            logger.warning("CoreML prediction unavailable, falling back to Swift LinearSpec reference: \(error.localizedDescription, privacy: .public)")
        }
        #endif

        if rawPredictions.isEmpty {
            do {
                rawPredictions = try predictRawLinear(features: features, spec: spec)
            } catch {
                logger.error("Swift linear prediction failed: \(error.localizedDescription, privacy: .public)")
                return .insufficientData(
                    observedDays: observedDays,
                    minimumRequired: minimumRequiredObservedDays,
                    reason: "预测执行失败：\(error.localizedDescription)"
                )
            }
        }

        let cutoff14d = referenceDayKey.addingDays(-13)
        let recent14Days = pastDays.filter { $0.dayKey >= cutoff14d }

        func hasTargetObservation(_ day: DailyComputedDay, targetName: String) -> Bool {
            switch targetName {
            case "hrv_sdnn_ms":
                return day.raw.hrvMs != nil
            case "resting_hr_bpm":
                return day.raw.restingHeartRateBpm != nil
            case "sleep_efficiency":
                guard let asleep = day.raw.sleepAsleepMinutes, asleep > 0 else { return false }
                let denom = max(day.raw.sleepInBedMinutes ?? 0, asleep + (day.raw.awakeMinutes ?? 0))
                return denom > 0
            default:
                return false
            }
        }

        let targets: [PersonalForecastTargetResult] = zip(spec.targets, rawPredictions).map { targetSpec, rawPoint in
            let point = min(targetSpec.clipMax, max(targetSpec.clipMin, rawPoint))
            let low80 = min(targetSpec.clipMax, max(targetSpec.clipMin, point - targetSpec.q80HalfWidth))
            let high80 = min(targetSpec.clipMax, max(targetSpec.clipMin, point + targetSpec.q80HalfWidth))
            let low90 = min(targetSpec.clipMax, max(targetSpec.clipMin, point - targetSpec.q90HalfWidth))
            let high90 = min(targetSpec.clipMax, max(targetSpec.clipMin, point + targetSpec.q90HalfWidth))
            let topDrivers: [PersonalForecastDriver]
            do {
                let allDrivers = try computeDrivers(features: features, spec: spec, target: targetSpec)
                let threshold = targetSpec.name == "sleep_efficiency" ? 0.002 : 0.05
                let nonTrivial = allDrivers.filter { abs($0.contribution) >= threshold }
                topDrivers = nonTrivial.isEmpty
                    ? Array(allDrivers.prefix(2))
                    : Array(nonTrivial.prefix(4))
            } catch {
                topDrivers = []
            }
            let recentObs = recent14Days.filter { hasTargetObservation($0, targetName: targetSpec.name) }.count
            let totalObs = pastDays.filter { hasTargetObservation($0, targetName: targetSpec.name) }.count
            return PersonalForecastTargetResult(
                name: targetSpec.name,
                title: targetSpec.title,
                unit: targetSpec.unit,
                point: point,
                interval80Low: low80,
                interval80High: high80,
                interval90Low: low90,
                interval90High: high90,
                walkForwardBestBaseline: targetSpec.walkForwardBestBaseline,
                walkForwardMAE: targetSpec.walkForwardMAE,
                walkForwardCov80: targetSpec.walkForwardCov80,
                drivers: topDrivers,
                recent14dObservedDays: recentObs,
                totalObservedDays: totalObs
            )
        }

        return .available(
            PersonalForecastSummary(
                referenceDayKey: referenceDayKey,
                targetDayKey: referenceDayKey.addingDays(1),
                modelVersion: spec.modelVersion,
                runtimeBackend: runtimeBackend,
                observedDays: observedDays,
                eatingContextObservedToday: eatingAvailableDayKeys.contains(referenceDayKey),
                targets: targets,
                disclaimer: "个人统计预测 · 非医学诊断"
            )
        )
    }

    // MARK: - Causal Numerical Helpers (1:1 with forecasting.py)

    private static func causalRollingMean(_ values: [Double?], window: Int) -> [Double?] {
        var result = [Double?](repeating: nil, count: values.count)
        for i in 0..<values.count {
            let start = max(0, i - window + 1)
            var sum = 0.0
            var count = 0
            for j in start...i {
                if let v = values[j] {
                    sum += v
                    count += 1
                }
            }
            if count > 0 {
                result[i] = sum / Double(count)
            }
        }
        return result
    }

    private static func causalExpandingFill(_ values: [Double?], defaultValue: Double) -> [Double] {
        var out = [Double](repeating: defaultValue, count: values.count)
        var lastFilled: Double?
        var seen: [Double] = []
        var cachedExpandingMedian: Double?
        var seenCountAtMedianCache = -1
        for i in 0..<values.count {
            if let direct = values[i] {
                seen.append(direct)
                out[i] = direct
                lastFilled = direct
                continue
            }
            let start = max(0, i - 27)
            let windowVals = values[start...i].compactMap { $0 }
            if let r28Med = median(of: windowVals) {
                out[i] = r28Med
                lastFilled = r28Med
            } else {
                if seenCountAtMedianCache != seen.count {
                    cachedExpandingMedian = median(of: seen)
                    seenCountAtMedianCache = seen.count
                }
                if let expMed = cachedExpandingMedian {
                    out[i] = expMed
                    lastFilled = expMed
                } else if let prev = lastFilled {
                    out[i] = prev
                } else {
                    out[i] = defaultValue
                }
            }
        }
        return out
    }

    private static func median(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 {
            return sorted[mid]
        }
        return 0.5 * (sorted[mid - 1] + sorted[mid])
    }

    private static func trailingMean(_ values: [Double], endIndex: Int, window: Int) -> Double {
        let start = max(0, endIndex - window + 1)
        let slice = values[start...endIndex]
        return slice.reduce(0, +) / Double(slice.count)
    }
}
