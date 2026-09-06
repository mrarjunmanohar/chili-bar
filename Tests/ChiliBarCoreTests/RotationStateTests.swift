import Testing
@testable import ChiliBarCore

@Suite("Rotation")
struct RotationTests {
    @Test("starts at the first zone")
    func startsAtFirst() {
        #expect(RotationState(zoneCount: 3).index == 0)
    }

    @Test("advances to the next zone")
    func advances() {
        var rotation = RotationState(zoneCount: 3)
        rotation.advance()
        #expect(rotation.index == 1)
    }

    @Test("wraps around to the first zone after the last")
    func wrapsAround() {
        var rotation = RotationState(zoneCount: 3)
        rotation.advance()
        rotation.advance()
        rotation.advance()
        #expect(rotation.index == 0)
    }

    @Test("stays put with a single zone")
    func singleZone() {
        var rotation = RotationState(zoneCount: 1)
        rotation.advance()
        #expect(rotation.index == 0)
    }

    // A zero count is reachable in practice: the user can delete every zone from the config.
    // Modulo by zero would trap, so this must be handled rather than assumed away.
    @Test("does not crash or move with no zones")
    func noZones() {
        var rotation = RotationState(zoneCount: 0)
        rotation.advance()
        #expect(rotation.index == 0)
    }
}

@Suite("Rotation pausing")
struct RotationPausingTests {
    // The rotation pauses while a session runs, which is how the countdown keeps the
    // status item to itself, and while a panel is open so the list doesn't shift under the cursor.
    @Test("does not advance while paused")
    func pausedDoesNotAdvance() {
        var rotation = RotationState(zoneCount: 3)
        rotation.pause()
        rotation.advance()
        #expect(rotation.index == 0)
    }

    @Test("advances again once resumed")
    func resumeRestoresAdvancing() {
        var rotation = RotationState(zoneCount: 3)
        rotation.pause()
        rotation.advance()
        rotation.resume()
        rotation.advance()
        #expect(rotation.index == 1)
    }

    @Test("resumes from where it paused rather than restarting")
    func resumesFromSamePosition() {
        var rotation = RotationState(zoneCount: 3)
        rotation.advance()
        rotation.pause()
        rotation.resume()
        #expect(rotation.index == 1)
    }

    @Test("is not paused initially")
    func notPausedInitially() {
        #expect(RotationState(zoneCount: 3).isPaused == false)
    }
}

@Suite("Rotation when zones change")
struct RotationZoneChangeTests {
    // Editing the config file can shrink the list while the rotation sits on a high index.
    @Test("clamps the index when the zone count shrinks")
    func clampsOnShrink() {
        var rotation = RotationState(zoneCount: 5)
        rotation.advance()
        rotation.advance()
        rotation.advance()
        #expect(rotation.index == 3)

        rotation.updateZoneCount(2)
        #expect(rotation.index < 2)
    }

    @Test("keeps the index when the zone count grows")
    func keepsIndexOnGrowth() {
        var rotation = RotationState(zoneCount: 2)
        rotation.advance()
        rotation.updateZoneCount(4)
        #expect(rotation.index == 1)
    }
}
