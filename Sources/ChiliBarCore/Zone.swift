import Foundation

/// A place whose local time appears in the rotation.
///
/// Working hours are what turn a plain clock into something that answers "can I ping them
/// right now" — the question that actually matters when colleagues are spread across timezones.
public struct Zone: Equatable, Sendable {
    /// Short label shown in the menu bar, e.g. "SF". Kept short because menu bar space is scarce.
    public let label: String
    public let timeZone: TimeZone
    /// Start of the working day, inclusive.
    public let opensAt: TimeOfDay
    /// End of the working day, exclusive.
    ///
    /// May be *earlier* than `opensAt`, meaning the shift runs past midnight — which is what
    /// happens to anyone working another continent's hours.
    public let closesAt: TimeOfDay

    /// The zone the working hours are *defined in*, when that differs from where the person is.
    ///
    /// A colleague in Kanpur working Montreal's 9–5 is the case this exists for. Storing that
    /// as a fixed IST window silently drifts by an hour twice a year, because Montreal observes
    /// daylight saving and India does not. Naming the reference zone instead keeps it correct
    /// permanently, and says what is actually true: they work Montreal's hours.
    public let hoursTimeZoneOverride: TimeZone?

    /// The zone the working window is evaluated in — the reference zone if one is set,
    /// otherwise the zone's own.
    public var hoursTimeZone: TimeZone { hoursTimeZoneOverride ?? timeZone }

    public init(
        label: String,
        timeZone: TimeZone,
        opensAt: TimeOfDay,
        closesAt: TimeOfDay,
        hoursIn: TimeZone? = nil
    ) {
        self.label = label
        self.timeZone = timeZone
        self.opensAt = opensAt
        self.closesAt = closesAt
        self.hoursTimeZoneOverride = hoursIn
    }

    /// Fails rather than silently falling back to UTC, so a typo in a timezone identifier
    /// surfaces as a bad config file instead of a clock that is quietly wrong.
    public init?(
        label: String,
        timeZoneID: String,
        opensAt: TimeOfDay,
        closesAt: TimeOfDay,
        hoursIn: TimeZone? = nil
    ) {
        guard let timeZone = TimeZone(identifier: timeZoneID) else { return nil }
        self.init(
            label: label,
            timeZone: timeZone,
            opensAt: opensAt,
            closesAt: closesAt,
            hoursIn: hoursIn
        )
    }

    /// Convenience for whole-hour windows.
    public init?(label: String, timeZoneID: String, opensAtHour: Int = 9, closesAtHour: Int = 18) {
        guard let opensAt = TimeOfDay(hour: opensAtHour, minute: 0),
              let closesAt = TimeOfDay(hour: closesAtHour, minute: 0)
        else { return nil }
        self.init(label: label, timeZoneID: timeZoneID, opensAt: opensAt, closesAt: closesAt)
    }

    /// Whether the shift runs past midnight into the following day.
    public var isOvernight: Bool { closesAt <= opensAt }

    /// Whether it is a working weekday hour in this zone at the given instant.
    ///
    /// `Calendar` resolves the UTC offset for that specific date, so daylight saving is
    /// handled without any offset arithmetic here.
    public func isWorkingHours(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        // Borrowed hours are evaluated on the reference zone's clock. That also removes the
        // overnight wrap for the common case: Montreal 9–5 is a plain daytime window there,
        // even though it lands after midnight in Kanpur.
        calendar.timeZone = hoursTimeZone

        let components = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard let hour = components.hour,
              let minute = components.minute,
              let weekday = components.weekday
        else { return false }

        let nowInMinutes = hour * 60 + minute

        guard isOvernight else {
            return isWeekday(weekday)
                && nowInMinutes >= opensAt.minutesSinceMidnight
                && nowInMinutes < closesAt.minutesSinceMidnight
        }

        // An overnight shift belongs to the day it *started*, which is what decides whether
        // it counts as a working day. Friday's shift spilling into Saturday morning is still
        // work; Saturday night is not.
        if nowInMinutes >= opensAt.minutesSinceMidnight {
            return isWeekday(weekday)
        }
        if nowInMinutes < closesAt.minutesSinceMidnight {
            return isWeekday(previousDay(of: weekday))
        }
        return false
    }

    /// Calendar weekdays are 1 = Sunday ... 7 = Saturday, so Monday–Friday is 2...6.
    private func isWeekday(_ weekday: Int) -> Bool { (2...6).contains(weekday) }

    private func previousDay(of weekday: Int) -> Int {
        weekday == 1 ? 7 : weekday - 1
    }
}

// MARK: - Persistence

/// Encoded with the timezone as its identifier string, so the config file stays hand-editable.
extension Zone: Codable {
    private enum CodingKeys: String, CodingKey {
        case label
        case timeZoneID = "timezone"
        case opensAt = "opens"
        case closesAt = "closes"
        case hoursIn
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

        var hoursIn: TimeZone?
        if let reference = try container.decodeIfPresent(String.self, forKey: .hoursIn) {
            guard let referenceZone = TimeZone(identifier: reference) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .hoursIn,
                    in: container,
                    debugDescription: "'\(reference)' is not a known timezone identifier"
                )
            }
            hoursIn = referenceZone
        }

        self.init(
            label: try container.decode(String.self, forKey: .label),
            timeZone: timeZone,
            opensAt: try Self.decodeTime(from: container, forKey: .opensAt),
            closesAt: try Self.decodeTime(from: container, forKey: .closesAt),
            hoursIn: hoursIn
        )
    }

    /// Accepts `"18:30"` or a plain hour number.
    ///
    /// The integer form predates half-hour support; configs written against it must keep
    /// working rather than breaking on upgrade.
    private static func decodeTime(
        from container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> TimeOfDay {
        if let hour = try? container.decode(Int.self, forKey: key) {
            guard let time = TimeOfDay(hour: hour, minute: 0) else {
                throw DecodingError.dataCorruptedError(
                    forKey: key, in: container,
                    debugDescription: "\(hour) is not an hour between 0 and 23"
                )
            }
            return time
        }

        let text = try container.decode(String.self, forKey: key)
        guard let time = TimeOfDay(text) else {
            throw DecodingError.dataCorruptedError(
                forKey: key, in: container,
                debugDescription: "'\(text)' is not a time in HH:mm form"
            )
        }
        return time
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(label, forKey: .label)
        try container.encode(timeZone.identifier, forKey: .timeZoneID)
        // Always written as HH:mm so half-hour windows survive a round trip.
        try container.encode(opensAt.description, forKey: .opensAt)
        try container.encode(closesAt.description, forKey: .closesAt)
        // Omitted when unused, so the file doesn't imply a setting is doing something it isn't.
        try container.encodeIfPresent(hoursTimeZoneOverride?.identifier, forKey: .hoursIn)
    }
}
