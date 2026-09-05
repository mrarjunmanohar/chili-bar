import Foundation

/// Renders the remaining time for the menu bar.
public enum CountdownFormatter {
    /// Formats as `MM:SS`, or `H:MM:SS` once the interval reaches an hour.
    ///
    /// Minutes are zero-padded so the character count holds steady for the whole session —
    /// the same constant-width concern that governs the clock rotation.
    public static func string(for interval: TimeInterval) -> String {
        // Rounding up keeps the display honest: with 0.4s left the session is still running,
        // so it should read 00:01, not 00:00.
        let total = Int(max(0, interval).rounded(.up))

        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
