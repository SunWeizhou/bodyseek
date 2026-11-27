import Foundation

/// 体能-疲劳模型里的一天。
public struct FitnessFatiguePoint: Identifiable, Hashable, Sendable, Codable {
    /// 日期。
    public let date: Date
    /// 当天的训练负荷；当天没有负荷数据时为 `nil`（缺失，不是零）。
    public let load: Double?
    /// 体能（CTL）：42 天指数加权负荷均值；还没有任何负荷数据时为 `nil`。
    public let fitness: Double?
    /// 疲劳（ATL）：7 天指数加权负荷均值；还没有任何负荷数据时为 `nil`。
    public let fatigue: Double?

    public var id: Date { date }

    /// 状态差（TSB）：体能减疲劳。正值表示恢复得比累积得快。
    public var form: Double? {
        guard let fitness, let fatigue else { return nil }
        return fitness - fatigue
    }

    /// 创建一天的数据点。
    public init(date: Date, load: Double?, fitness: Double?, fatigue: Double?) {
        self.date = date
        self.load = load
        self.fitness = fitness
        self.fatigue = fatigue
    }
}

/// 某一天的训练负荷；没有数据时 `load` 为 `nil`。
public struct DatedLoad: Hashable, Sendable {
    /// 日期。
    public let date: Date
    /// 当天的训练负荷。
    public let load: Double?

    /// 创建一天的负荷。
    public init(date: Date, load: Double?) {
        self.date = date
        self.load = load
    }
}

/// 体能-疲劳模型（Banister 形式）：体能 = 42 天指数加权负荷均值（CTL），疲劳 = 7 天（ATL）。
///
/// 每个数据点按 `值 += (当天负荷 - 值) / 窗口天数` 更新；第一个有负荷的日子用当天负荷作为起点。
/// 没有负荷数据的日子不当作零：体能和疲劳保持前一天的值，不衰减。
public enum FitnessFatigueModel {
    /// 体能窗口（天）。
    public static let fitnessDays = 42
    /// 疲劳窗口（天）。
    public static let fatigueDays = 7

    /// 某天的训练负荷：有手表心率分区时取 TRIMP，否则取负荷分；都没有时为 `nil`。
    public static func dailyLoad(_ day: DailyComputedDay) -> Double? {
        let trimp = day.raw.workouts.compactMap { $0.heartRateZones?.trimpScore }.reduce(0, +)
        if trimp > 0 { return trimp }
        return day.strain.value.map(Double.init)
    }

    /// 从每日计算结果得到体能-疲劳序列，按日期升序。
    public static func series(from days: [DailyComputedDay]) -> [FitnessFatiguePoint] {
        series(from: days.map { DatedLoad(date: $0.date, load: dailyLoad($0)) })
    }

    /// 从每日负荷得到体能-疲劳序列，按日期升序。输入每天最多一条。
    public static func series(
        from loads: [DatedLoad],
        fitnessDays: Int = FitnessFatigueModel.fitnessDays,
        fatigueDays: Int = FitnessFatigueModel.fatigueDays
    ) -> [FitnessFatiguePoint] {
        let fitnessWindow = Double(max(1, fitnessDays))
        let fatigueWindow = Double(max(1, fatigueDays))
        var fitness: Double?
        var fatigue: Double?
        var points: [FitnessFatiguePoint] = []
        for item in loads.sorted(by: { $0.date < $1.date }) {
            if let load = item.load {
                if let currentFitness = fitness, let currentFatigue = fatigue {
                    fitness = currentFitness + (load - currentFitness) / fitnessWindow
                    fatigue = currentFatigue + (load - currentFatigue) / fatigueWindow
                } else {
                    fitness = load
                    fatigue = load
                }
            }
            points.append(FitnessFatiguePoint(date: item.date, load: item.load, fitness: fitness, fatigue: fatigue))
        }
        return points
    }
}
