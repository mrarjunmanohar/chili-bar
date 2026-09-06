import Testing
import Foundation
@testable import ChiliBarCore

@Suite("Countdown formatting")
struct CountdownFormatterTests {
    @Test("formats minutes and seconds")
    func minutesAndSeconds() {
        #expect(CountdownFormatter.string(for: 24 * 60 + 31) == "24:31")
    }

    // Zero-padded so the character count never changes mid-session. "9:59" followed by
    // "10:00" would resize the status item and shift every icon beside it.
    @Test("pads single-digit minutes so the width never changes")
    func padsMinutes() {
        #expect(CountdownFormatter.string(for: 9 * 60 + 5) == "09:05")
    }

    @Test("shows zero as a full clock rather than a bare zero")
    func zero() {
        #expect(CountdownFormatter.string(for: 0) == "00:00")
    }

    @Test("rounds up so a timer never displays 00:00 while still running")
    func roundsUp() {
        // With 0.4s left the session is not over; showing 00:00 would be a lie.
        #expect(CountdownFormatter.string(for: 0.4) == "00:01")
    }

    @Test("clamps negative intervals to zero")
    func negative() {
        #expect(CountdownFormatter.string(for: -5) == "00:00")
    }

    @Test("includes hours only when the interval reaches an hour")
    func hours() {
        #expect(CountdownFormatter.string(for: 60 * 60) == "1:00:00")
    }

    @Test("stays in minutes and seconds just below an hour")
    func justBelowAnHour() {
        #expect(CountdownFormatter.string(for: 59 * 60 + 59) == "59:59")
    }
}
