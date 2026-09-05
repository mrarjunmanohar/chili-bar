import Testing
import Foundation
@testable import ChiliBarCore

/// An instant expressed in Montreal's wall clock, since that's what these hours are defined in.
private func montreal(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Montreal")!
    return calendar.date(from: components)!
}

/// Kanpur, working Montreal's hours. The clock shows IST; the working window is Montreal 9–5.
private let kanpur = Zone(
    label: "KNP",
    timeZoneID: "Asia/Kolkata",
    opensAt: TimeOfDay("09:00")!,
    closesAt: TimeOfDay("17:00")!,
    hoursIn: TimeZone(identifier: "America/Montreal")!
)!

@Suite("Working hours borrowed from another zone")
struct ZoneBorrowedHoursTests {
    @Test("working when the reference zone is mid-morning, whatever the local time is")
    func worksOnReferenceZoneClock() {
        // Tuesday 8 Sep 2026, 10:00 in Montreal — 19:30 in Kanpur.
        #expect(kanpur.isWorkingHours(at: montreal(2026, 9, 8, 10)))
    }

    @Test("not working once the reference zone's day has ended")
    func offAfterReferenceClose() {
        // 18:00 Montreal — 03:30 next morning in Kanpur.
        #expect(kanpur.isWorkingHours(at: montreal(2026, 9, 8, 18)) == false)
    }

    @Test("not working before the reference zone opens")
    func offBeforeReferenceOpen() {
        #expect(kanpur.isWorkingHours(at: montreal(2026, 9, 8, 8)) == false)
    }

    @Test("working at the reference zone's opening minute")
    func openingBoundary() {
        #expect(kanpur.isWorkingHours(at: montreal(2026, 9, 8, 9)))
    }

    @Test("not working at the reference zone's closing minute")
    func closingBoundary() {
        #expect(kanpur.isWorkingHours(at: montreal(2026, 9, 8, 17)) == false)
    }

    // The whole point of the feature. India doesn't observe DST and Montreal does, so a window
    // stored as fixed IST wall-clock drifts by an hour twice a year. Borrowing Montreal's hours
    // means the same reference time is a working hour in both summer and winter.
    @Test("survives daylight saving: 10:00 Montreal is a working hour in summer")
    func correctInSummer() {
        #expect(kanpur.isWorkingHours(at: montreal(2026, 7, 8, 10)))
    }

    @Test("survives daylight saving: 10:00 Montreal is a working hour in winter")
    func correctInWinter() {
        #expect(kanpur.isWorkingHours(at: montreal(2026, 12, 8, 10)))
    }

    @Test("survives daylight saving: 18:00 Montreal is off in both summer and winter")
    func offInBothSeasons() {
        #expect(kanpur.isWorkingHours(at: montreal(2026, 7, 8, 18)) == false)
        #expect(kanpur.isWorkingHours(at: montreal(2026, 12, 8, 18)) == false)
    }

    // Weekends follow the reference zone too — Kanpur's local date can already be tomorrow.
    @Test("off at the weekend in the reference zone")
    func offAtReferenceWeekend() {
        // Saturday 12 Sep 2026, 10:00 Montreal.
        #expect(kanpur.isWorkingHours(at: montreal(2026, 9, 12, 10)) == false)
    }

    @Test("working on a Friday evening in the reference zone even though Kanpur is on Saturday")
    func fridayEveningSpansTheDateLine() {
        // Friday 11 Sep 2026, 16:00 Montreal — 01:30 on Saturday in Kanpur, still a work hour.
        #expect(kanpur.isWorkingHours(at: montreal(2026, 9, 11, 16)))
    }

    @Test("the clock still shows the zone's own local time, not the reference zone's")
    func clockStaysLocal() {
        let formatter = ClockFormatter(locale: Locale(identifier: "en_US_POSIX"))
        // 10:00 Montreal is 19:30 in Kanpur.
        #expect(formatter.time(in: kanpur, at: montreal(2026, 9, 8, 10)) == "19:30")
    }

    @Test("a zone without borrowed hours still uses its own timezone")
    func defaultsToOwnZone() {
        let london = Zone(label: "LON", timeZoneID: "Europe/London", opensAtHour: 9, closesAtHour: 17)!
        // 09:00 Montreal is 14:00 in London — a working hour there.
        #expect(london.isWorkingHours(at: montreal(2026, 9, 8, 9)))
        // 04:00 Montreal is 09:00 in London.
        #expect(london.isWorkingHours(at: montreal(2026, 9, 8, 3)) == false)
    }
}

@Suite("Borrowed hours in config")
struct ZoneBorrowedHoursConfigTests {
    @Test("decodes hoursIn")
    func decodes() throws {
        let json = """
        [{ "label": "KNP", "timezone": "Asia/Kolkata", "opens": "09:00", "closes": "17:00",
           "hoursIn": "America/Montreal" }]
        """
        let zones = try JSONDecoder().decode([Zone].self, from: Data(json.utf8))

        #expect(zones.first?.hoursTimeZone.identifier == "America/Montreal")
        #expect(zones.first?.timeZone.identifier == "Asia/Kolkata")
    }

    @Test("omitting hoursIn falls back to the zone's own timezone")
    func absentMeansOwnZone() throws {
        let json = #"[{ "label": "LON", "timezone": "Europe/London", "opens": 9, "closes": 17 }]"#
        let zones = try JSONDecoder().decode([Zone].self, from: Data(json.utf8))

        #expect(zones.first?.hoursTimeZone.identifier == "Europe/London")
    }

    @Test("rejects an unknown hoursIn identifier")
    func rejectsUnknown() {
        let json = """
        [{ "label": "KNP", "timezone": "Asia/Kolkata", "opens": "09:00", "closes": "17:00",
           "hoursIn": "Mars/Olympus_Mons" }]
        """

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([Zone].self, from: Data(json.utf8))
        }
    }

    @Test("round-trips hoursIn through disk")
    func roundTrips() throws {
        let data = try JSONEncoder().encode([kanpur])
        let decoded = try JSONDecoder().decode([Zone].self, from: data)

        #expect(decoded == [kanpur])
        #expect(decoded.first?.hoursTimeZone.identifier == "America/Montreal")
        #expect(decoded.first?.timeZone.identifier == "Asia/Kolkata")
    }

    // Writing "hoursIn" on every zone would imply the setting is doing something when it isn't.
    @Test("omits hoursIn when a zone uses its own hours")
    func omitsWhenUnused() throws {
        let london = Zone(label: "LON", timeZoneID: "Europe/London", opensAtHour: 9, closesAtHour: 17)!
        let text = String(decoding: try JSONEncoder().encode([london]), as: UTF8.self)

        #expect(text.contains("hoursIn") == false)
    }
}
