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
    /// Work finished while the machine was asleep, so nobody saw it happen.
    ///
    /// Kept distinct from `workEnded` because the response differs: this one does *not*
    /// start a break. `endedAt` is when the interval actually ran out, which can be hours
    /// before the tick that noticed.
    case workEndedWhileAway(endedAt: Date)
}

/// The Pomodoro cycle: `idle → work → rest → idle`.
///
/// Deliberately has no long-rest-every-Nth-session rule and no persistence. It holds no timer
/// of its own either — the shell calls `tick(at:)`, so every transition is reproducible from
/// an injected `Date` instead of depending on wall-clock time.
///
/// Rest returns to `idle` rather than auto-starting the next work interval, so the app can't
/// quietly cycle all night after you've walked away. For the same reason a break never starts
/// across a sleep — see `tick(at:)`.
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
    /// When `tick` was last called. Nil before the first tick of an interval.
    private var lastTickAt: Date?
    /// The rest length announced when the current work interval ends.
    private var pendingRestLength: TimeInterval

    /// A gap between ticks longer than this means the process wasn't running.
    ///
    /// The shell ticks once a second, so ninety seconds is far outside anything a merely
    /// busy run loop produces, while still being short enough to catch a quick lid close.
    ///
    /// Sleep is the case this was written for, but it deliberately doesn't try to identify
    /// the cause — App Nap throttling a background menu bar app would trip it too, and that
    /// is fine. The question being asked is not "did the Mac sleep" but "was anyone told the
    /// interval ended", and a throttled process told them just as little as a sleeping one
    /// did. Either way the safe answer is to stop rather than to start a break unannounced.
    public static let awayThreshold: TimeInterval = 90

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
        lastTickAt = now
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
        lastTickAt = now
    }

    public mutating func stop() {
        phase = .idle
        endsAt = nil
        frozenRemaining = nil
        isPaused = false
        hasWarned = false
        lastTickAt = nil
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
        // A pause can last as long as a sleep. Resuming is not waking up.
        lastTickAt = now
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
        let previousTick = lastTickAt
        lastTickAt = now

        guard phase != .idle, !isPaused else { return [] }

        // No previous tick means this is the first one of the interval, not a gap.
        let gap = previousTick.map { now.timeIntervalSince($0) } ?? 0
        let wasAway = gap > Self.awayThreshold

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
            if wasAway {
                // Don't hand back a break that started itself while the lid was shut. The
                // user never saw the work interval end, so a running countdown on wake reads
                // as the app doing something unprompted — which is exactly how it was
                // reported. Not counted as completed either: it wasn't seen through.
                let endedAt = endsAt ?? now
                stop()
                events.append(.workEndedWhileAway(endedAt: endedAt))
            } else {
                completedWorkSessions += 1
                let restLength = pendingRestLength
                startRest(length: restLength, at: now)
                events.append(.workEnded(restLength: restLength))
            }
        case .rest:
            // A rest slept through needs no special handling: you were away, which is what
            // a break is for, and idle is where rest ends anyway.
            stop()
            events.append(.restEnded)
        case .idle:
            break
        }

        return events
    }
}
