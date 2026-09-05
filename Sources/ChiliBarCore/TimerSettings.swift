import Foundation

/// Durations for the Pomodoro cycle.
///
/// Stored internally in seconds but written to disk in minutes — nobody hand-editing a config
/// file wants to work out that 1500 means 25 minutes.
public struct TimerSettings: Equatable, Sendable {
    public var workLength: TimeInterval
    /// Used when a rest starts without an explicit choice. The rest length is still
    /// pickable in the moment — this is only the starting point.
    public var defaultRestLength: TimeInterval
    /// How long before work ends the heads-up fires.
    public var warningLead: TimeInterval

    public init(
        workLength: TimeInterval = 25 * 60,
        defaultRestLength: TimeInterval = 5 * 60,
        warningLead: TimeInterval = 2 * 60
    ) {
        self.workLength = workLength
        self.defaultRestLength = defaultRestLength
        // A warning at or beyond the work length would fire the instant work began.
        self.warningLead = min(warningLead, workLength / 2)
    }

    /// The quick-pick rest lengths offered when a break starts.
    public static let restOptions: [TimeInterval] = [5 * 60, 10 * 60, 15 * 60, 20 * 60]
}

// MARK: - Persistence

extension TimerSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case workMinutes
        case restMinutes
        case warningMinutes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        let work = try container.decode(Double.self, forKey: .workMinutes)
        let rest = try container.decode(Double.self, forKey: .restMinutes)
        let warning = try container.decode(Double.self, forKey: .warningMinutes)

        // A zero or negative interval would end the moment it started, looping the app
        // through phases as fast as the timer fires.
        guard work > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .workMinutes,
                in: container,
                debugDescription: "workMinutes must be greater than zero"
            )
        }
        guard rest > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .restMinutes,
                in: container,
                debugDescription: "restMinutes must be greater than zero"
            )
        }

        // The initialiser clamps an oversized warning rather than rejecting it — it's a
        // harmless mistake with an obvious sensible reading.
        self.init(
            workLength: work * 60,
            defaultRestLength: rest * 60,
            warningLead: max(0, warning) * 60
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workLength / 60, forKey: .workMinutes)
        try container.encode(defaultRestLength / 60, forKey: .restMinutes)
        try container.encode(warningLead / 60, forKey: .warningMinutes)
    }
}
