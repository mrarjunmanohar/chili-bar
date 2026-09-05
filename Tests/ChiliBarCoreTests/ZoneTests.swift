import Testing
import Foundation
@testable import ChiliBarCore

/// Builds an instant from UTC components, so every test reads as an absolute moment
/// rather than depending on wherever the machine running the tests happens to be.
private func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: components)!
}

private func zone(_ label: String, _ id: String, _ opens: Int = 9, _ closes: Int = 18) -> Zone {
    Zone(label: label, timeZoneID: id, opensAtHour: opens, closesAtHour: closes)!
}

// Thursday 4 September 2025, 16:00 UTC.
// London 17:00 (BST) · Bangalore 21:30 (IST) · San Francisco 09:00 (PDT)
private let thursdayAfternoon = utc(2025, 9, 4, 16)

@Suite("Zone working hours")
struct ZoneWorkingHoursTests {
    @Test("open during working hours on a weekday")
    func openOnWeekday() {
        #expect(zone("LON", "Europe/London").isWorkingHours(at: thursdayAfternoon))
    }

    @Test("closed when the local hour is past closing")
    func closedAfterHours() {
        // 21:30 in Bangalore — well past an 18:00 close.
        #expect(zone("BLR", "Asia/Kolkata").isWorkingHours(at: thursdayAfternoon) == false)
    }

    @Test("open exactly at the opening hour")
    func openAtBoundary() {
        // 09:00 in San Francisco, the first minute of the working day.
        #expect(zone("SF", "America/Los_Angeles").isWorkingHours(at: thursdayAfternoon))
    }

    @Test("closed exactly at the closing hour")
    func closedAtClosingBoundary() {
        // Closing at 09:00 makes the same 09:00 instant the first minute *outside* hours.
        #expect(zone("SF", "America/Los_Angeles", 8, 9).isWorkingHours(at: thursdayAfternoon) == false)
    }

    @Test("closed at the weekend even during working hours")
    func closedAtWeekend() {
        // Saturday 6 September 2025, 12:00 UTC — 13:00 in London, mid-working-day but a Saturday.
        #expect(zone("LON", "Europe/London").isWorkingHours(at: utc(2025, 9, 6, 12)) == false)
    }

    @Test("honours each zone's own hours")
    func respectsPerZoneHours() {
        // 21:30 in Bangalore is outside 9–18 but inside a late 9–22 shift.
        #expect(zone("BLR", "Asia/Kolkata", 9, 22).isWorkingHours(at: thursdayAfternoon))
    }
}

@Suite("Zone daylight saving")
struct ZoneDaylightSavingTests {
    // The same 16:00 UTC instant is 08:00 in California during PST and 09:00 during PDT,
    // which straddles a 9am open. If DST were ignored these two would agree.
    @Test("closed at 16:00 UTC in winter, when California is on PST")
    func closedInWinter() {
        #expect(zone("SF", "America/Los_Angeles").isWorkingHours(at: utc(2025, 1, 15, 16)) == false)
    }

    @Test("open at 16:00 UTC in summer, when California is on PDT")
    func openInSummer() {
        #expect(zone("SF", "America/Los_Angeles").isWorkingHours(at: utc(2025, 7, 15, 16)))
    }
}

@Suite("Zone construction")
struct ZoneConstructionTests {
    @Test("rejects an unknown timezone identifier")
    func rejectsUnknownIdentifier() {
        #expect(Zone(label: "??", timeZoneID: "Mars/Olympus_Mons") == nil)
    }
}
