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
    /// Seconds each zone holds the menu bar before the rotation advances.
    ///
    /// Lives here because settings.json is the app's one settings file; `PomodoroTimer`
    /// ignores it.
    public var rotationSeconds: TimeInterval

    public init(
        workLength: TimeInterval = 25 * 60,
        defaultRestLength: TimeInterval = 5 * 60,
        warningLead: TimeInterval = 2 * 60,
        rotationSeconds: TimeInterval = 4
    ) {
        self.workLength = workLength
        self.defaultRestLength = defaultRestLength
        // A warning at or beyond the work length would fire the instant work began.
        self.warningLead = min(warningLead, workLength / 2)
        // Below a second the rotation spins as fast as the run loop allows.
        self.rotationSeconds = max(1, rotationSeconds)
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
        case rotationSeconds
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
        // Absent in files written before the setting existed.
        let rotation = try container.decodeIfPresent(Double.self, forKey: .rotationSeconds) ?? 4

        self.init(
            workLength: work * 60,
            defaultRestLength: rest * 60,
            warningLead: max(0, warning) * 60,
            rotationSeconds: rotation
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(workLength / 60, forKey: .workMinutes)
        try container.encode(defaultRestLength / 60, forKey: .restMinutes)
        try container.encode(warningLead / 60, forKey: .warningMinutes)
        try container.encode(rotationSeconds, forKey: .rotationSeconds)
    }
}
