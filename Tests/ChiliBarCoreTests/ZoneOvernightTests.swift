import Testing
import Foundation
@testable import ChiliBarCore

private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, in id: String) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: id)!
    return calendar.date(from: components)!
}

/// Kanpur working Eastern hours: 18:30 to 02:30 the next morning, IST.
private let kanpur = Zone(
    label: "KNP",
    timeZoneID: "Asia/Kolkata",
    opensAt: TimeOfDay("18:30")!,
    closesAt: TimeOfDay("02:30")!
)!

@Suite("Overnight working hours")
struct ZoneOvernightTests {
    // Tuesday 8 September 2026 is a weekday.
    @Test("working during the evening portion of the shift")
    func workingInTheEvening() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 8, 20, 0, in: "Asia/Kolkata")))
    }

    @Test("working in the after-midnight tail of the shift")
    func workingAfterMidnight() {
        // 01:00 Wednesday still belongs to Tuesday's shift.
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 9, 1, 0, in: "Asia/Kolkata")))
    }

    @Test("not working once the shift has ended")
    func notWorkingAfterClose() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 9, 3, 0, in: "Asia/Kolkata")) == false)
    }

    @Test("not working during the middle of the day")
    func notWorkingMidday() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 8, 11, 0, in: "Asia/Kolkata")) == false)
    }

    @Test("working exactly at the opening minute")
    func openingBoundary() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 8, 18, 30, in: "Asia/Kolkata")))
    }

    @Test("not working exactly at the closing minute")
    func closingBoundary() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 9, 2, 30, in: "Asia/Kolkata")) == false)
    }

    @Test("working one minute before close")
    func justBeforeClose() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 9, 2, 29, in: "Asia/Kolkata")))
    }
}

@Suite("Overnight shifts across the weekend")
struct ZoneOvernightWeekendTests {
    // An overnight shift belongs to the day it *started*, which is what decides whether it's
    // a working day at all. Friday's shift spilling into Saturday morning is still work;
    // Saturday night is not.
    @Test("Saturday small hours are still Friday's shift")
    func saturdayMorningIsFridayShift() {
        // Saturday 12 September 2026, 01:00 — Friday's shift, which began 18:30 Friday.
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 12, 1, 0, in: "Asia/Kolkata")))
    }

    @Test("Saturday evening is not a shift")
    func saturdayEveningIsOff() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 12, 20, 0, in: "Asia/Kolkata")) == false)
    }

    @Test("Sunday small hours are not a shift, since Saturday had none")
    func sundayMorningIsOff() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 13, 1, 0, in: "Asia/Kolkata")) == false)
    }

    @Test("Monday evening starts the week's first shift")
    func mondayEveningWorks() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 14, 20, 0, in: "Asia/Kolkata")))
    }

    @Test("Monday small hours are not a shift, since Sunday had none")
    func mondayMorningIsOff() {
        #expect(kanpur.isWorkingHours(at: local(2026, 9, 14, 1, 0, in: "Asia/Kolkata")) == false)
    }
}

@Suite("Zone config accepts both hour formats")
struct ZoneHourFormatTests {
    // Existing hand-written configs use plain integer hours; they must keep working.
    @Test("decodes legacy integer hours")
    func decodesIntegerHours() throws {
        let json = #"[{ "label": "LON", "timezone": "Europe/London", "opens": 9, "closes": 17 }]"#
        let zones = try JSONDecoder().decode([Zone].self, from: Data(json.utf8))

        #expect(zones.first?.opensAt == TimeOfDay("09:00"))
        #expect(zones.first?.closesAt == TimeOfDay("17:00"))
    }

    @Test("decodes HH:mm hours")
    func decodesStringHours() throws {
        let json = #"[{ "label": "KNP", "timezone": "Asia/Kolkata", "opens": "18:30", "closes": "02:30" }]"#
        let zones = try JSONDecoder().decode([Zone].self, from: Data(json.utf8))

        #expect(zones.first?.opensAt == TimeOfDay("18:30"))
        #expect(zones.first?.closesAt == TimeOfDay("02:30"))
    }

    @Test("rejects an unparseable time")
    func rejectsBadTime() {
        let json = #"[{ "label": "??", "timezone": "Asia/Kolkata", "opens": "half nine", "closes": "17:00" }]"#

        #expect(throws: (any Error).self) {
            try JSONDecoder().decode([Zone].self, from: Data(json.utf8))
        }
    }

    @Test("writes hours back as HH:mm so half hours survive a round trip")
    func encodesAsString() throws {
        let data = try JSONEncoder().encode([kanpur])
        let text = String(decoding: data, as: UTF8.self)

        #expect(text.contains("18:30"))
        #expect(text.contains("02:30"))
    }
}
