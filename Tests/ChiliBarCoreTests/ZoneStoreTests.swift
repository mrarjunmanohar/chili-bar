import Testing
import Foundation
@testable import ChiliBarCore

/// Each test gets its own directory so they stay independent under parallel execution.
private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("chili-bar-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Zone store")
struct ZoneStoreTests {
    @Test("round-trips zones through disk unchanged")
    func roundTrip() throws {
        let file = try temporaryDirectory().appendingPathComponent("zones.json")
        let zones = [
            Zone(label: "SF", timeZoneID: "America/Los_Angeles")!,
            Zone(label: "BLR", timeZoneID: "Asia/Kolkata", opensAtHour: 9, closesAtHour: 22)!,
        ]

        try ZoneStore.save(zones, to: file)

        #expect(try ZoneStore.load(from: file) == zones)
    }

    // Pins the on-disk format. Stage 1 asks the user to hand-edit this file, so the shape
    // is a user-facing contract, not an implementation detail.
    @Test("reads a hand-written config file")
    func readsHandWrittenFile() throws {
        let file = try temporaryDirectory().appendingPathComponent("zones.json")
        let json = """
        [
          { "label": "LON", "timezone": "Europe/London", "opens": 9, "closes": 17 }
        ]
        """
        try json.write(to: file, atomically: true, encoding: .utf8)

        let zones = try ZoneStore.load(from: file)

        #expect(zones.count == 1)
        #expect(zones.first?.label == "LON")
        #expect(zones.first?.timeZone.identifier == "Europe/London")
        #expect(zones.first?.closesAtHour == 17)
    }

    @Test("rejects a config file naming a timezone that does not exist")
    func rejectsUnknownTimezone() throws {
        let file = try temporaryDirectory().appendingPathComponent("zones.json")
        let json = #"[{ "label": "??", "timezone": "Mars/Olympus_Mons", "opens": 9, "closes": 17 }]"#
        try json.write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: (any Error).self) {
            try ZoneStore.load(from: file)
        }
    }

    @Test("writes a starter config on first run when no file exists")
    func createsDefaultsOnFirstRun() throws {
        let file = try temporaryDirectory().appendingPathComponent("zones.json")

        let zones = try ZoneStore.loadOrCreateDefaults(at: file)

        #expect(zones == ZoneStore.defaultZones)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("keeps an existing config rather than overwriting it")
    func doesNotOverwriteExistingConfig() throws {
        let file = try temporaryDirectory().appendingPathComponent("zones.json")
        let mine = [Zone(label: "TYO", timeZoneID: "Asia/Tokyo")!]
        try ZoneStore.save(mine, to: file)

        #expect(try ZoneStore.loadOrCreateDefaults(at: file) == mine)
    }

    @Test("ships defaults spanning more than one timezone")
    func defaultsAreUseful() {
        #expect(ZoneStore.defaultZones.count >= 2)
    }
}
