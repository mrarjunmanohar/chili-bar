import Testing
@testable import ChiliBarCore

@Suite("Time of day")
struct TimeOfDayTests {
    @Test("parses a whole hour")
    func wholeHour() {
        #expect(TimeOfDay("09:00")?.minutesSinceMidnight == 9 * 60)
    }

    // Half-hour offsets are the reason this type exists: India sits at UTC+5:30, so any
    // working window converted from another zone lands on :30.
    @Test("parses a half hour")
    func halfHour() {
        #expect(TimeOfDay("18:30")?.minutesSinceMidnight == 18 * 60 + 30)
    }

    @Test("parses midnight")
    func midnight() {
        #expect(TimeOfDay("00:00")?.minutesSinceMidnight == 0)
    }

    @Test("parses the last minute of the day")
    func endOfDay() {
        #expect(TimeOfDay("23:59")?.minutesSinceMidnight == 23 * 60 + 59)
    }

    @Test("rejects an hour beyond the clock")
    func rejectsBadHour() {
        #expect(TimeOfDay("25:00") == nil)
    }

    @Test("rejects minutes beyond the hour")
    func rejectsBadMinute() {
        #expect(TimeOfDay("09:75") == nil)
    }

    @Test("rejects text that isn't a time")
    func rejectsNonsense() {
        #expect(TimeOfDay("lunchtime") == nil)
    }

    @Test("rejects a missing minute component")
    func rejectsPartial() {
        #expect(TimeOfDay("9") == nil)
    }

    @Test("renders back to the same text")
    func rendersBack() {
        #expect(TimeOfDay("18:30")?.description == "18:30")
    }

    @Test("pads a single-digit hour when rendering")
    func padsWhenRendering() {
        #expect(TimeOfDay(hour: 9, minute: 5)?.description == "09:05")
    }
}
