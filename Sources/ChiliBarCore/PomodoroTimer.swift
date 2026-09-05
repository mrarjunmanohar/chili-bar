import Foundation

/// Something worth telling the user about. The shell turns these into notifications.
///
/// Returning events rather than firing notifications directly is what makes the timing
/// testable — otherwise "does the warning fire at exactly two minutes left" could only be
/// checked by sitting and waiting.
public enum TimerEvent: Equatable, Sendable {
    /// Work is nearly over. Fires once per work interval.
    case endingSoon(remaining: TimeInterval)
    case workEnded(restLength: TimeInterval)
    case restEnded
}

/// The Pomodoro cycle: `idle → work → rest → idle`.
///
/// Deliberately has no long-rest-every-Nth-session rule and no persistence. It holds no timer
/// of its own either — the shell calls `tick(at:)`, so every transition is reproducible from
/// an injected `Date` instead of depending on wall-clock time.
///
/// Rest returns to `idle` rather than auto-starting the next work interval, so the app can't
/// quietly cycle all night after you've walked away.
public struct PomodoroTimer: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case work
        case rest
    }

    public private(set) var phase: Phase = .idle
    public private(set) var isPaused = false
    /// Completed since launch. Display only — nothing depends on it, by design.
    public private(set) var completedWorkSessions = 0

    public var settings: TimerSettings

    /// When the current interval ends. Nil while idle.
    private var endsAt: Date?
    /// Time left at the moment of pausing, held until resume.
    private var frozenRemaining: TimeInterval?
    /// Guards the pre-warning so it fires once per work interval, not on every tick after.
    private var hasWarned = false
    /// The rest length announced when the current work interval ends.
    private var pendingRestLength: TimeInterval

    public init(settings: TimerSettings = TimerSettings()) {
        self.settings = settings
        self.pendingRestLength = settings.defaultRestLength
    }

    // MARK: - Queries

    public func remaining(at now: Date) -> TimeInterval {
        if let frozenRemaining { return frozenRemaining }
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    // MARK: - Transitions

    public mutating func startWork(at now: Date) {
        phase = .work
        endsAt = now.addingTimeInterval(settings.workLength)
        frozenRemaining = nil
        isPaused = false
        hasWarned = false
        pendingRestLength = settings.defaultRestLength
    }

    /// Starts (or restarts) a rest of a specific length.
    ///
    /// Restarting mid-rest is how the quick-pick works: choosing 15 while resting replaces
    /// the running 5 rather than queueing behind it.
    public mutating func startRest(length: TimeInterval, at now: Date) {
        phase = .rest
        endsAt = now.addingTimeInterval(length)
        frozenRemaining = nil
        isPaused = false
    }

    public mutating func stop() {
        phase = .idle
        endsAt = nil
        frozenRemaining = nil
        isPaused = false
        hasWarned = false
    }

    public mutating func pause(at now: Date) {
        guard phase != .idle, !isPaused else { return }
        frozenRemaining = remaining(at: now)
        isPaused = true
    }

    public mutating func resume(at now: Date) {
        guard isPaused, let frozenRemaining else { return }
        endsAt = now.addingTimeInterval(frozenRemaining)
        self.frozenRemaining = nil
        isPaused = false
    }

    /// Ends the current interval immediately, emitting the same events it would have on
    /// finishing naturally — except that a skipped work interval isn't counted as completed.
    public mutating func skip(at now: Date) -> [TimerEvent] {
        switch phase {
        case .idle:
            return []
        case .work:
            let restLength = pendingRestLength
            startRest(length: restLength, at: now)
            return [.workEnded(restLength: restLength)]
        case .rest:
            stop()
            return [.restEnded]
        }
    }

    /// Advances the machine to `now`, returning anything that became true along the way.
    public mutating func tick(at now: Date) -> [TimerEvent] {
        guard phase != .idle, !isPaused else { return [] }

        let timeLeft = remaining(at: now)
        var events: [TimerEvent] = []

        // The heads-up applies to work only — a warning that rest is nearly over would just
        // be a second alarm for the same event.
        //
        // `timeLeft > 0` matters after the Mac sleeps: the first tick on wake finds the
        // interval already finished, and without this it would fire "0 seconds left"
        // immediately followed by "break time".
        if phase == .work, !hasWarned, timeLeft > 0, timeLeft <= settings.warningLead {
            hasWarned = true
            events.append(.endingSoon(remaining: timeLeft))
        }

        guard timeLeft <= 0 else { return events }

        switch phase {
        case .work:
            completedWorkSessions += 1
            let restLength = pendingRestLength
            startRest(length: restLength, at: now)
            events.append(.workEnded(restLength: restLength))
        case .rest:
            stop()
            events.append(.restEnded)
        case .idle:
            break
        }

        return events
    }
}
