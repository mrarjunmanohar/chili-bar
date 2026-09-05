import Foundation

/// Reads and writes the zone list.
///
/// Stage 1 keeps this a hand-edited JSON file rather than building a settings UI, so the
/// rolling clock — the part with real product uncertainty — reaches daily use first.
public enum ZoneStore {
    /// Seeded on first run. Deliberately spans three continents so the rotation demonstrates
    /// itself immediately rather than showing one zone the user already knows.
    public static let defaultZones: [Zone] = [
        Zone(label: "SF", timeZoneID: "America/Los_Angeles", opensAtHour: 9, closesAtHour: 17)!,
        Zone(label: "LON", timeZoneID: "Europe/London", opensAtHour: 9, closesAtHour: 17)!,
        Zone(label: "BLR", timeZoneID: "Asia/Kolkata", opensAtHour: 9, closesAtHour: 18)!,
    ]

    /// `~/Library/Application Support/Chili Bar/zones.json`
    public static var defaultURL: URL { JSONFile.applicationSupportURL("zones.json") }

    public static func load(from url: URL) throws -> [Zone] {
        try JSONFile.load([Zone].self, from: url)
    }

    public static func save(_ zones: [Zone], to url: URL) throws {
        try JSONFile.save(zones, to: url)
    }

    public static func loadOrCreateDefaults(at url: URL) throws -> [Zone] {
        try JSONFile.loadOrCreate([Zone].self, defaults: defaultZones, at: url)
    }
}
