/// Tracks which zone the menu bar is currently showing.
///
/// Deliberately holds no timer of its own — the shell owns scheduling and calls `advance()`.
/// That keeps the cycling logic testable without waiting on wall-clock time.
public struct RotationState: Equatable, Sendable {
    public private(set) var index: Int = 0
    public private(set) var zoneCount: Int
    /// Paused while a session runs (the countdown takes the status item) and while a panel
    /// is open (so rows don't shift under the cursor).
    public private(set) var isPaused: Bool = false

    public init(zoneCount: Int) {
        self.zoneCount = max(0, zoneCount)
    }

    public mutating func advance() {
        guard !isPaused, zoneCount > 0 else { return }
        index = (index + 1) % zoneCount
    }

    public mutating func pause() {
        isPaused = true
    }

    public mutating func resume() {
        isPaused = false
    }

    /// Applies a new zone list length, keeping the current position where possible.
    ///
    /// The list can shrink under us when the config file is edited, which would otherwise
    /// leave `index` pointing past the end.
    public mutating func updateZoneCount(_ newCount: Int) {
        zoneCount = max(0, newCount)
        if index >= zoneCount {
            index = 0
        }
    }
}
