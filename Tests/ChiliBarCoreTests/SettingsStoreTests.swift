import Testing
import Foundation
@testable import ChiliBarCore

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("chili-bar-settings-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Settings store")
struct SettingsStoreTests {
    @Test("round-trips settings through disk unchanged")
    func roundTrip() throws {
        let file = try temporaryDirectory().appendingPathComponent("settings.json")
        let settings = TimerSettings(workLength: 50 * 60, defaultRestLength: 10 * 60, warningLead: 5 * 60)

        try SettingsStore.save(settings, to: file)

        #expect(try SettingsStore.load(from: file) == settings)
    }

    // The file is hand-edited until the settings UI lands, so its shape is a user-facing
    // contract. Durations are in minutes because nobody wants to write 1500 for 25 minutes.
    @Test("reads a hand-written settings file with durations in minutes")
    func readsHandWrittenFile() throws {
        let file = try temporaryDirectory().appendingPathComponent("settings.json")
        let json = #"{ "workMinutes": 50, "restMinutes": 10, "warningMinutes": 5 }"#
        try json.write(to: file, atomically: true, encoding: .utf8)

        let settings = try SettingsStore.load(from: file)

        #expect(settings.workLength == 50 * 60)
        #expect(settings.defaultRestLength == 10 * 60)
        #expect(settings.warningLead == 5 * 60)
    }

    @Test("writes starter settings on first run")
    func createsDefaultsOnFirstRun() throws {
        let file = try temporaryDirectory().appendingPathComponent("settings.json")

        let settings = try SettingsStore.loadOrCreateDefaults(at: file)

        #expect(settings == TimerSettings())
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("keeps existing settings rather than overwriting them")
    func doesNotOverwrite() throws {
        let file = try temporaryDirectory().appendingPathComponent("settings.json")
        let mine = TimerSettings(workLength: 45 * 60, defaultRestLength: 15 * 60, warningLead: 60)
        try SettingsStore.save(mine, to: file)

        #expect(try SettingsStore.loadOrCreateDefaults(at: file) == mine)
    }

    // A warning longer than the work interval would fire the instant work started,
    // which is worse than useless.
    @Test("clamps a warning lead that exceeds the work length")
    func clampsOversizedWarning() throws {
        let file = try temporaryDirectory().appendingPathComponent("settings.json")
        let json = #"{ "workMinutes": 5, "restMinutes": 5, "warningMinutes": 30 }"#
        try json.write(to: file, atomically: true, encoding: .utf8)

        let settings = try SettingsStore.load(from: file)

        #expect(settings.warningLead < settings.workLength)
    }

    @Test("rejects a non-positive work length")
    func rejectsZeroWork() throws {
        let file = try temporaryDirectory().appendingPathComponent("settings.json")
        try #"{ "workMinutes": 0, "restMinutes": 5, "warningMinutes": 2 }"#
            .write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try SettingsStore.load(from: file)
        }
    }
}

@Suite("Rotation speed setting")
struct RotationSpeedTests {
    @Test("defaults to four seconds")
    func defaultValue() {
        #expect(TimerSettings().rotationSeconds == 4)
    }

    @Test("reads a custom rotation speed")
    func readsCustom() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("rot-\(UUID().uuidString).json")
        try #"{ "workMinutes": 25, "restMinutes": 5, "warningMinutes": 2, "rotationSeconds": 8 }"#
            .write(to: file, atomically: true, encoding: .utf8)

        #expect(try SettingsStore.load(from: file).rotationSeconds == 8)
    }

    // Older settings files predate this key and must keep working.
    @Test("falls back to the default when the key is absent")
    func absentKeyUsesDefault() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("rot-\(UUID().uuidString).json")
        try #"{ "workMinutes": 25, "restMinutes": 5, "warningMinutes": 2 }"#
            .write(to: file, atomically: true, encoding: .utf8)

        #expect(try SettingsStore.load(from: file).rotationSeconds == 4)
    }

    // A zero or negative interval would spin the rotation as fast as the run loop allows.
    @Test("clamps a rotation speed below one second")
    func clampsTooFast() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("rot-\(UUID().uuidString).json")
        try #"{ "workMinutes": 25, "restMinutes": 5, "warningMinutes": 2, "rotationSeconds": 0 }"#
            .write(to: file, atomically: true, encoding: .utf8)

        #expect(try SettingsStore.load(from: file).rotationSeconds >= 1)
    }
}
