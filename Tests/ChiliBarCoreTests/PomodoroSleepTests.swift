import Testing
import Foundation
@testable import ChiliBarCore

private let t0 = Date(timeIntervalSince1970: 1_757_000_000)
private let minute: TimeInterval = 60

private func newTimer(
    work: TimeInterval = 25 * minute,
    rest: TimeInterval = 5 * minute,
    warning: TimeInterval = 2 * minute
) -> PomodoroTimer {
    PomodoroTimer(
        settings: TimerSettings(workLength: work, defaultRestLength: rest, warningLead: warning)
    )
}

/// What happens when the Mac sleeps mid-session.
///
/// Timers don't fire while the machine is asleep, so the first tick on wake can find the
/// work interval long finished. Rolling straight into a fresh break at that point hands the
/// user a break they never saw start — reported as "a break timer started automatically,
/// unprompted" (#2). The gap between ticks is what tells the two cases apart: the shell
/// ticks every second, so anything past `awayThreshold` means the process wasn't running.
@Suite("Sleeping through an interval")
struct PomodoroSleepTests {
    @Test("work ending during a long gap returns to idle instead of starting a break")
    func longGapDoesNotStartRest() {
        var timer = newTimer(work: 25 * minute)
        timer.startWork(at: t0)

        // Last tick a second in, then the lid closes for an hour.
        _ = timer.tick(at: t0.addingTimeInterval(1))
        let events = timer.tick(at: t0.addingTimeInterval(60 * minute))

        #expect(timer.phase == .idle)
        #expect(events == [.workEndedWhileAway(endedAt: t0.addingTimeInterval(25 * minute))])
    }

    @Test("a short gap still rolls into the break as normal")
    func shortGapStartsRestNormally() {
        var timer = newTimer(work: 1 * minute, rest: 5 * minute)
        timer.startWork(at: t0)

        _ = timer.tick(at: t0.addingTimeInterval(1))
        // 70s is longer than a tick but well under the away threshold — a busy run loop,
        // not a sleeping machine.
        let events = timer.tick(at: t0.addingTimeInterval(71))

        #expect(timer.phase == .rest)
        #expect(events == [.workEnded(restLength: 5 * minute)])
    }

    @Test("a session slept through is not counted as completed")
    func sleptSessionIsNotCounted() {
        var timer = newTimer(work: 25 * minute)
        timer.startWork(at: t0)

        _ = timer.tick(at: t0.addingTimeInterval(1))
        _ = timer.tick(at: t0.addingTimeInterval(60 * minute))

        #expect(timer.completedWorkSessions == 0)
    }

    @Test("rest ending during a long gap is unremarkable — you were resting")
    func longGapDuringRestJustEnds() {
        var timer = newTimer(rest: 5 * minute)
        timer.startRest(length: 5 * minute, at: t0)

        _ = timer.tick(at: t0.addingTimeInterval(1))
        let events = timer.tick(at: t0.addingTimeInterval(60 * minute))

        #expect(timer.phase == .idle)
        #expect(events == [.restEnded])
    }

    @Test("the first tick after starting work is never treated as a gap")
    func firstTickIsNotAGap() {
        var timer = newTimer(work: 25 * minute)
        timer.startWork(at: t0)

        // No prior tick at all, and the interval is still running.
        let events = timer.tick(at: t0.addingTimeInterval(1))

        #expect(timer.phase == .work)
        #expect(events.isEmpty)
    }

    @Test("resuming from pause is not mistaken for waking from sleep")
    func resumeIsNotAGap() {
        var timer = newTimer(work: 25 * minute)
        timer.startWork(at: t0)
        _ = timer.tick(at: t0.addingTimeInterval(1))

        timer.pause(at: t0.addingTimeInterval(2))
        // Paused for an hour — ticks keep arriving and keep being ignored.
        _ = timer.tick(at: t0.addingTimeInterval(60 * minute))
        timer.resume(at: t0.addingTimeInterval(60 * minute))

        let events = timer.tick(at: t0.addingTimeInterval(60 * minute + 1))

        #expect(timer.phase == .work)
        #expect(events.isEmpty)
    }

    @Test("work slept through still stops the session cleanly")
    func sleptSessionClearsRemaining() {
        var timer = newTimer(work: 25 * minute)
        timer.startWork(at: t0)
        _ = timer.tick(at: t0.addingTimeInterval(1))
        _ = timer.tick(at: t0.addingTimeInterval(60 * minute))

        #expect(timer.remaining(at: t0.addingTimeInterval(60 * minute)) == 0)
        #expect(timer.isPaused == false)
    }

    @Test("a gap that ends before the interval does leaves work running")
    func longGapMidIntervalKeepsWorking() {
        var timer = newTimer(work: 25 * minute, warning: 2 * minute)
        timer.startWork(at: t0)
        _ = timer.tick(at: t0.addingTimeInterval(1))

        // Slept ten minutes into a twenty-five minute session: still fifteen to go.
        let events = timer.tick(at: t0.addingTimeInterval(10 * minute))

        #expect(timer.phase == .work)
        #expect(events.isEmpty)
        #expect(timer.remaining(at: t0.addingTimeInterval(10 * minute)) == 15 * minute)
    }
}
