import Foundation
import BodySeekDomain

public typealias SleepObservationAvailability = BodySeekDomain.SleepObservationAvailability
public typealias SleepComponentObservation = BodySeekDomain.SleepComponentObservation
public typealias SleepEvidenceContext = BodySeekDomain.SleepEvidenceContext

enum SleepTargetSettings {
    static let hoursKey = "vela_sleep_target_hours"
    static let defaultHours = 7.5
    static let availableHours = stride(from: 5.0, through: 10.0, by: 0.5).map { $0 }

    static func targetMinutes(defaults: UserDefaults = .standard) -> Double {
        let configuredHours = defaults.object(forKey: hoursKey) as? Double ?? defaultHours
        return min(max(configuredHours, 5.0), 10.0) * 60.0
    }

    static func displayHours(_ hours: Double) -> String {
        hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
    }
}
