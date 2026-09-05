import Foundation

/// Reads and writes the timer settings.
///
/// Hand-edited JSON until the settings UI arrives in Stage 3, matching how zones work.
public enum SettingsStore {
    /// `~/Library/Application Support/Chili Bar/settings.json`
    public static var defaultURL: URL { JSONFile.applicationSupportURL("settings.json") }

    public static func load(from url: URL) throws -> TimerSettings {
        try JSONFile.load(TimerSettings.self, from: url)
    }

    public static func save(_ settings: TimerSettings, to url: URL) throws {
        try JSONFile.save(settings, to: url)
    }

    public static func loadOrCreateDefaults(at url: URL) throws -> TimerSettings {
        try JSONFile.loadOrCreate(TimerSettings.self, defaults: TimerSettings(), at: url)
    }
}
