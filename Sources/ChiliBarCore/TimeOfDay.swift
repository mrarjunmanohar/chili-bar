import Foundation

/// A wall-clock time within a day, to the minute.
///
/// Working hours can't be whole hours only: a window converted from another timezone lands on
/// :30 whenever India (UTC+5:30) is involved, which is exactly the case Chili Bar exists for.
public struct TimeOfDay: Equatable, Comparable, Hashable, Sendable, CustomStringConvertible {
    public let minutesSinceMidnight: Int

    public init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        minutesSinceMidnight = hour * 60 + minute
    }

    /// Parses `"HH:mm"`.
    public init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              // Int() accepts "+9" and " 9"; require plain digits so config typos are caught.
              parts[0].allSatisfy(\.isNumber),
              parts[1].allSatisfy(\.isNumber)
        else { return nil }

        self.init(hour: hour, minute: minute)
    }

    public var hour: Int { minutesSinceMidnight / 60 }
    public var minute: Int { minutesSinceMidnight % 60 }

    public var description: String {
        String(format: "%02d:%02d", hour, minute)
    }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }
}
