import Foundation

/// A place whose local time appears in the rotation.
///
/// Working hours are what turn a plain clock into something that answers "can I ping them
/// right now" — the question that actually matters when colleagues are spread across timezones.
public struct Zone: Equatable, Sendable {
    /// Short label shown in the menu bar, e.g. "SF". Kept short because menu bar space is scarce.
    public let label: String
    public let timeZone: TimeZone
    /// Local hour the working day starts, inclusive.
    public let opensAtHour: Int
    /// Local hour the working day ends, exclusive — so 18 means 17:59 is the last working minute.
    public let closesAtHour: Int

    public init(label: String, timeZone: TimeZone, opensAtHour: Int = 9, closesAtHour: Int = 18) {
        self.label = label
        self.timeZone = timeZone
        self.opensAtHour = opensAtHour
        self.closesAtHour = closesAtHour
    }

    /// Fails rather than silently falling back to UTC, so a typo in a timezone identifier
    /// surfaces as a bad config file instead of a clock that is quietly wrong.
    public init?(label: String, timeZoneID: String, opensAtHour: Int = 9, closesAtHour: Int = 18) {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return nil }
        self.init(
            label: label,
            timeZone: timeZone,
            opensAtHour: opensAtHour,
            closesAtHour: closesAtHour
        )
    }

    /// Whether it is a working weekday hour in this zone at the given instant.
    ///
    /// `Calendar` resolves the UTC offset for that specific date, so daylight saving is
    /// handled without any offset arithmetic here.
    public func isWorkingHours(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let components = calendar.dateComponents([.hour, .weekday], from: date)
        guard let hour = components.hour, let weekday = components.weekday else { return false }

        // Calendar weekdays are 1 = Sunday ... 7 = Saturday, so Monday–Friday is 2...6.
        guard (2...6).contains(weekday) else { return false }

        return hour >= opensAtHour && hour < closesAtHour
    }
}

// MARK: - Persistence

/// Encoded with the timezone as its identifier string, so the config file stays hand-editable.
extension Zone: Codable {
    private enum CodingKeys: String, CodingKey {
        case label
        case timeZoneID = "timezone"
        case opensAtHour = "opens"
        case closesAtHour = "closes"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let identifier = try container.decode(String.self, forKey: .timeZoneID)

        guard let timeZone = TimeZone(identifier: identifier) else {
            throw DecodingError.dataCorruptedError(
                forKey: .timeZoneID,
                in: container,
                debugDescription: "'\(identifier)' is not a known timezone identifier"
            )
        }

        self.init(
            label: try container.decode(String.self, forKey: .label),
            timeZone: timeZone,
            opensAtHour: try container.decode(Int.self, forKey: .opensAtHour),
            closesAtHour: try container.decode(Int.self, forKey: .closesAtHour)
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(timeZone.identifier, forKey: .timeZoneID)
        try container.encode(opensAtHour, forKey: .opensAtHour)
        try container.encode(closesAtHour, forKey: .closesAtHour)
    }
}
