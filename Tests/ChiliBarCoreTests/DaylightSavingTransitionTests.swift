import Testing
import Foundation
@testable import ChiliBarCore

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

private let formatter = ClockFormatter(locale: Locale(identifier: "en_US_POSIX"))

private let kanpur = Zone(
    label: "KNP",
    timeZoneID: "Asia/Kolkata",
    opensAt: TimeOfDay("09:00")!,
    closesAt: TimeOfDay("17:00")!,
    hoursIn: TimeZone(identifier: "America/Montreal")!
)!

private let montrealZone = Zone(
    label: "MTL", timeZoneID: "America/Montreal", opensAtHour: 9, closesAtHour: 17
)!

private let losAngeles = Zone(
    label: "LA", timeZoneID: "America/Los_Angeles", opensAtHour: 9, closesAtHour: 17
)!

/// North American daylight saving ends on Sunday 1 November 2026 and begins on Sunday 8 March 2026.
/// These tests straddle both, because that is precisely when a hand-converted window breaks.
@Suite("Daylight saving transitions")
struct DaylightSavingTransitionTests {
    // Friday 30 October 2026 — still EDT. Monday 2 November 2026 — now EST.
    private let beforeFallBack = montreal(2026, 10, 30, 9)
    private let afterFallBack = montreal(2026, 11, 2, 9)

    @Test("Kanpur is working at Montreal 09:00 the Friday before the clocks change")
    func workingBeforeTransition() {
        #expect(kanpur.isWorkingHours(at: beforeFallBack))
    }

    @Test("Kanpur is still working at Montreal 09:00 the Monday after the clocks change")
    func workingAfterTransition() {
        #expect(kanpur.isWorkingHours(at: afterFallBack))
    }

    /// The invariant that matters: Kanpur's *local time* shifts by an hour across the
    /// transition, while whether they are working does not. A hand-converted fixed IST window
    /// gets this exactly backwards — it holds the local time steady and moves the working day.
    @Test("Kanpur's local clock moves an hour but its working state does not")
    func localTimeMovesWorkingStateDoesNot() {
        #expect(formatter.time(in: kanpur, at: beforeFallBack) == "18:30")
        #expect(formatter.time(in: kanpur, at: afterFallBack) == "19:30")

        #expect(kanpur.isWorkingHours(at: beforeFallBack))
        #expect(kanpur.isWorkingHours(at: afterFallBack))
    }

    @Test("Kanpur is off at Montreal 08:00 in both seasons")
    func offBeforeOpeningInBothSeasons() {
        #expect(kanpur.isWorkingHours(at: montreal(2026, 10, 30, 8)) == false)
        #expect(kanpur.isWorkingHours(at: montreal(2026, 11, 2, 8)) == false)
    }

    @Test("Kanpur is working at Montreal 16:00 in both seasons")
    func workingBeforeCloseInBothSeasons() {
        #expect(kanpur.isWorkingHours(at: montreal(2026, 10, 30, 16)))
        #expect(kanpur.isWorkingHours(at: montreal(2026, 11, 2, 16)))
    }

    // Zones keeping their own local hours were always DST-correct, since 09:00 local stays
    // 09:00 local. Pinned so a future change to the hours logic can't quietly break it.
    @Test("a zone on its own hours is unaffected by its own transition")
    func ownHoursSurviveTransition() {
        #expect(montrealZone.isWorkingHours(at: beforeFallBack))
        #expect(montrealZone.isWorkingHours(at: afterFallBack))
    }

    // Los Angeles and Montreal change on the same date, but a zone pair that changes on
    // different dates is the harder case — Europe shifts a week earlier than North America.
    @Test("Los Angeles keeps its own 09:00 across the spring transition")
    func losAngelesAcrossSpringForward() {
        // Friday 6 March 2026 is PST; Monday 9 March 2026 is PDT.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let before = calendar.date(from: DateComponents(year: 2026, month: 3, day: 6, hour: 9))!
        let after = calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 9))!

        #expect(losAngeles.isWorkingHours(at: before))
        #expect(losAngeles.isWorkingHours(at: after))
    }

    /// Documents *why* `hoursIn` exists, by pinning the failure of the obvious alternative.
    ///
    /// If someone later "simplifies" a borrowed-hours zone back to a hand-converted fixed
    /// window, this is the behaviour they would be reintroducing: correct in one season,
    /// wrong by an hour in the other.
    @Test("a hand-converted fixed window is wrong after the clocks change")
    func handConvertedWindowBreaks() {
        // 18:30–02:30 IST, which matched Montreal 09:00–17:00 while Eastern was on EDT.
        let handConverted = Zone(
            label: "KNP",
            timeZoneID: "Asia/Kolkata",
            opensAt: TimeOfDay("18:30")!,
            closesAt: TimeOfDay("02:30")!
        )!

        // Before the change the two agree.
        #expect(handConverted.isWorkingHours(at: beforeFallBack) == kanpur.isWorkingHours(at: beforeFallBack))

        // After it, the fixed window reports Kanpur online at 08:00 Montreal — an hour before
        // their day starts — while the borrowed-hours zone correctly reports them off.
        let eightAmAfter = montreal(2026, 11, 2, 8)
        #expect(handConverted.isWorkingHours(at: eightAmAfter))
        #expect(kanpur.isWorkingHours(at: eightAmAfter) == false)

        // And offline at 16:00 Montreal, an hour before their day ends.
        let fourPmAfter = montreal(2026, 11, 2, 16)
        #expect(handConverted.isWorkingHours(at: fourPmAfter) == false)
        #expect(kanpur.isWorkingHours(at: fourPmAfter))
    }

    // The UK moves to summer time a week after North America, so for that week the offset
    // between them is an hour off its usual value. A zone borrowing London's hours must track
    // London through that week, not through its own zone's transition.
    @Test("borrowed hours track the reference zone through a mismatched transition week")
    func mismatchedTransitionWeek() {
        let onLondonHours = Zone(
            label: "KNP",
            timeZoneID: "Asia/Kolkata",
            opensAt: TimeOfDay("09:00")!,
            closesAt: TimeOfDay("17:00")!,
            hoursIn: TimeZone(identifier: "Europe/London")!
        )!

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        // Wednesday 25 March 2026: North America is on DST, the UK is not yet.
        let midWeek = calendar.date(from: DateComponents(year: 2026, month: 3, day: 25, hour: 10))!

        #expect(onLondonHours.isWorkingHours(at: midWeek))
        #expect(onLondonHours.isWorkingHours(
            at: calendar.date(from: DateComponents(year: 2026, month: 3, day: 25, hour: 18))!
        ) == false)
    }
}
