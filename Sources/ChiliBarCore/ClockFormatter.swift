import Foundation

/// Turns zones and an instant into the strings the menu bar and hover panel display.
///
/// Times are 24-hour on purpose: an AM/PM suffix varies in width and would fight the
/// constant-width requirement for the status item.
public struct ClockFormatter: Sendable {
    private let locale: Locale

    public init(locale: Locale = .current) {
        self.locale = locale
    }

    /// Builds a formatter per call rather than caching one.
    ///
    /// `DateFormatter` is a reference type, so a stored instance whose `timeZone` is reassigned
    /// on every call is shared mutable state — two zones formatted concurrently can read each
    /// other's timezone. Construction costs microseconds and this runs a few times a minute,
    /// so a fresh formatter is the cheap way to make the type genuinely `Sendable`.
    private func formatter(_ format: String, _ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        return formatter
    }

    /// Local time in the zone, e.g. `09:00`.
    public func time(in zone: Zone, at date: Date) -> String {
        formatter("HH:mm", zone.timeZone).string(from: date)
    }

    /// Local day and date in the zone, e.g. `Thu 4 Sep`.
    ///
    /// This is what makes the hover panel useful rather than merely informative — a zone
    /// can be on a different calendar day, which a bare time hides.
    public func dayAndDate(in zone: Zone, at date: Date) -> String {
        formatter("EEE d MMM", zone.timeZone).string(from: date)
    }

    /// One zone's menu bar text, e.g. `LON 17:00`.
    public func menuBarLabel(for zone: Zone, at date: Date) -> String {
        "\(zone.label) \(time(in: zone, at: date))"
    }

    /// Every zone's menu bar text, each padded to the width of the widest.
    ///
    /// Without this the status item resizes as the rotation advances and every icon to its
    /// left twitches every few seconds. Padding is trailing so the label stays left-aligned
    /// and the eye has a stable anchor.
    public func paddedMenuBarLabels(for zones: [Zone], at date: Date) -> [String] {
        let labels = zones.map { menuBarLabel(for: $0, at: date) }
        guard let widest = labels.map(\.count).max() else { return [] }
        return labels.map { $0.padding(toLength: widest, withPad: " ", startingAt: 0) }
    }
}
