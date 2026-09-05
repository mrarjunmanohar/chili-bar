import Testing
import Foundation
@testable import ChiliBarCore

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

private let sf = Zone(label: "SF", timeZoneID: "America/Los_Angeles")!
private let london = Zone(label: "LON", timeZoneID: "Europe/London")!
private let bangalore = Zone(label: "BLR", timeZoneID: "Asia/Kolkata")!

/// Pinned locale so these assertions don't depend on the machine's regional settings.
private let formatter = ClockFormatter(locale: Locale(identifier: "en_US_POSIX"))

// Thursday 4 September 2025, 16:00 UTC.
private let thursdayAfternoon = utc(2025, 9, 4, 16)

@Suite("Clock formatting")
struct ClockFormattingTests {
    @Test("formats local time as 24-hour with a leading zero")
    func formatsTime() {
        #expect(formatter.time(in: sf, at: thursdayAfternoon) == "09:00")
    }

    @Test("renders the menu bar label as label plus time")
    func menuBarLabel() {
        #expect(formatter.menuBarLabel(for: london, at: thursdayAfternoon) == "LON 17:00")
    }

    @Test("formats day and date for the hover panel")
    func dayAndDate() {
        #expect(formatter.dayAndDate(in: london, at: thursdayAfternoon) == "Thu 4 Sep")
    }
}

@Suite("Date boundaries")
struct DateBoundaryTests {
    // 20:00 UTC on Thursday is already 01:30 on Friday in Bangalore. This is the case the
    // hover panel's day+date exists for — the reason "what time is it there" isn't enough.
    private let thursdayEvening = utc(2025, 9, 4, 20)

    @Test("shows the next calendar day for a zone that has rolled over")
    func nextDayForBangalore() {
        #expect(formatter.dayAndDate(in: bangalore, at: thursdayEvening) == "Fri 5 Sep")
    }

    @Test("shows the current day for a zone that has not rolled over")
    func sameDayForLondon() {
        #expect(formatter.dayAndDate(in: london, at: thursdayEvening) == "Thu 4 Sep")
    }

    @Test("crosses a month boundary correctly")
    func monthBoundary() {
        // 23:30 UTC on 30 September is 05:00 on 1 October in Bangalore.
        #expect(formatter.dayAndDate(in: bangalore, at: utc(2025, 9, 30, 23, 30)) == "Wed 1 Oct")
    }
}

@Suite("Equal-width padding")
struct PaddingTests {
    // The status item must not change width as the rotation advances, or every icon to its
    // left shifts every few seconds. Equal character count plus a monospaced-digit font
    // is what delivers that.
    @Test("pads every label to the same character count")
    func labelsShareOneWidth() {
        let labels = formatter.paddedMenuBarLabels(for: [sf, london, bangalore], at: thursdayAfternoon)
        let widths = Set(labels.map(\.count))
        #expect(widths.count == 1)
    }

    @Test("pads to the widest label rather than truncating it")
    func padsToWidest() {
        let labels = formatter.paddedMenuBarLabels(for: [sf, london, bangalore], at: thursdayAfternoon)
        // "LON 17:00" and "BLR 21:30" are 9 characters; "SF 09:00" is 8 and must grow to match.
        #expect(labels.allSatisfy { $0.count == 9 })
    }

    @Test("preserves the underlying text so nothing is lost to padding")
    func preservesContent() {
        let labels = formatter.paddedMenuBarLabels(for: [sf, london], at: thursdayAfternoon)
        #expect(labels.map { $0.trimmingCharacters(in: .whitespaces) } == ["SF 09:00", "LON 17:00"])
    }

    @Test("returns an empty array for no zones")
    func handlesNoZones() {
        #expect(formatter.paddedMenuBarLabels(for: [], at: thursdayAfternoon).isEmpty)
    }
}
