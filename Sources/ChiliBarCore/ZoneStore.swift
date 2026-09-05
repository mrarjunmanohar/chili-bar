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
    public static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base
            .appendingPathComponent("Chili Bar", isDirectory: true)
            .appendingPathComponent("zones.json")
    }

    public static func load(from url: URL) throws -> [Zone] {
        try JSONDecoder().decode([Zone].self, from: Data(contentsOf: url))
    }

    public static func save(_ zones: [Zone], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        // Pretty-printed with stable key order because a human edits this file by hand.
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(zones).write(to: url, options: .atomic)
    }

    /// Loads the config, seeding it with defaults the first time the app runs.
    ///
    /// A malformed file is *not* silently replaced — that would throw away hand-written config
    /// on a typo. The error propagates so the app can say what is wrong with which file.
    public static func loadOrCreateDefaults(at url: URL) throws -> [Zone] {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try save(defaultZones, to: url)
            return defaultZones
        }
        return try load(from: url)
    }
}
