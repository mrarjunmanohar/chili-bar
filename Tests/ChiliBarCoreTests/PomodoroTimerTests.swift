import Testing
import Foundation
@testable import ChiliBarCore

private let t0 = Date(timeIntervalSince1970: 1_757_000_000)
private let minute: TimeInterval = 60

/// 25 minute work, 5 minute default rest, 2 minute warning — the shipped defaults.
private func newTimer(
    work: TimeInterval = 25 * minute,
    rest: TimeInterval = 5 * minute,
    warning: TimeInterval = 2 * minute
) -> PomodoroTimer {
    PomodoroTimer(
        settings: TimerSettings(
            workLength: work,
            defaultRestLength: rest,
            warningLead: warning
        )
    )
}

@Suite("Pomodoro phases")
struct PomodoroPhaseTests {
    @Test("starts idle")
    func startsIdle() {
        #expect(newTimer().phase == .idle)
    }

    @Test("starting work enters the work phase with the full duration remaining")
    func startWork() {
        var timer = newTimer()
        timer.startWork(at: t0)

        #expect(timer.phase == .work)
        #expect(timer.remaining(at: t0) == 25 * minute)
    }

    @Test("remaining time counts down as the clock advances")
    func countsDown() {
        var timer = newTimer()
        timer.startWork(at: t0)

        #expect(timer.remaining(at: t0.addingTimeInterval(10 * minute)) == 15 * minute)
    }

    @Test("remaining never goes negative once the interval is over")
    func remainingFloorsAtZero() {
        var timer = newTimer()
        timer.startWork(at: t0)

        #expect(timer.remaining(at: t0.addingTimeInterval(40 * minute)) == 0)
    }

    @Test("stopping returns to idle")
    func stopReturnsToIdle() {
        var timer = newTimer()
        timer.startWork(at: t0)
        timer.stop()

        #expect(timer.phase == .idle)
    }
}

@Suite("Pomodoro notifications")
struct PomodoroNotificationTests {
    // The pre-warning is the departure from TomatoBar: a heads-up *before* work ends,
    // so a break doesn't arrive mid-thought.
    @Test("warns once the remaining time reaches the warning lead")
    func warnsBeforeWorkEnds() {
        var timer = newTimer()
        timer.startWork(at: t0)

        // 23 minutes in, 2 minutes left — exactly the lead.
        let events = timer.tick(at: t0.addingTimeInterval(23 * minute))

        #expect(events == [.endingSoon(remaining: 2 * minute)])
    }

    @Test("does not warn before the lead is reached")
    func silentBeforeLead() {
        var timer = newTimer()
        timer.startWork(at: t0)

        #expect(timer.tick(at: t0.addingTimeInterval(22 * minute)).isEmpty)
    }

    @Test("warns only once, not on every tick afterwards")
    func warnsOnlyOnce() {
        var timer = newTimer()
        timer.startWork(at: t0)
        _ = timer.tick(at: t0.addingTimeInterval(23 * minute))

        #expect(timer.tick(at: t0.addingTimeInterval(24 * minute)).isEmpty)
    }

    @Test("announces the break and its length when work ends")
    func announcesBreak() {
        var timer = newTimer()
        timer.startWork(at: t0)
        _ = timer.tick(at: t0.addingTimeInterval(23 * minute))
        // Ticking right up to the boundary, as the one-second shell timer does. Leaping
        // straight from 23 to 25 minutes would instead look like a sleeping Mac.
        _ = timer.tick(at: t0.addingTimeInterval(25 * minute - 1))

        let events = timer.tick(at: t0.addingTimeInterval(25 * minute))

        #expect(events == [.workEnded(restLength: 5 * minute)])
        #expect(timer.phase == .rest)
    }

    @Test("announces the return to work when rest ends")
    func announcesReturnToWork() {
        var timer = newTimer()
        timer.startWork(at: t0)
        _ = timer.tick(at: t0.addingTimeInterval(25 * minute - 1))
        _ = timer.tick(at: t0.addingTimeInterval(25 * minute))
        _ = timer.tick(at: t0.addingTimeInterval(30 * minute - 1))

        let events = timer.tick(at: t0.addingTimeInterval(30 * minute))

        #expect(events == [.restEnded])
        #expect(timer.phase == .idle)
    }

    @Test("does not warn during rest, only during work")
    func noWarningDuringRest() {
        var timer = newTimer()
        timer.startWork(at: t0)
        _ = timer.tick(at: t0.addingTimeInterval(25 * minute - 1))
        _ = timer.tick(at: t0.addingTimeInterval(25 * minute))
        #expect(timer.phase == .rest)

        // 3 minutes into a 5 minute rest — 2 minutes left, which would be the work lead.
        _ = timer.tick(at: t0.addingTimeInterval(28 * minute - 1))
        #expect(timer.tick(at: t0.addingTimeInterval(28 * minute)).isEmpty)
    }

    // A sleeping Mac means no ticks fire for a long stretch. The first tick on wake finds
    // the interval already over, and a "2 minutes left" alert at that point would be nonsense.
    //
    // The interval ending unobserved is reported as its own event and does NOT start a
    // break — see PomodoroSleepTests. What matters here is only that no stale warning is
    // bundled alongside it.
    @Test("does not warn when the interval has already ended, as after the Mac slept")
    func noStaleWarningAfterSleep() {
        var timer = newTimer()
        timer.startWork(at: t0)

        let events = timer.tick(at: t0.addingTimeInterval(30 * minute))

        #expect(events == [.workEndedWhileAway(endedAt: t0.addingTimeInterval(25 * minute))])
        #expect(!events.contains { if case .endingSoon = $0 { return true } else { return false } })
    }

    @Test("emits nothing while idle")
    func silentWhileIdle() {
        var timer = newTimer()
        #expect(timer.tick(at: t0.addingTimeInterval(60 * minute)).isEmpty)
    }
}

@Suite("Pomodoro rest length")
struct PomodoroRestLengthTests {
    // Rest length is chosen in the moment, not only in settings — the whole point is being
    // able to take fifteen when fifteen is what you need.
    @Test("a rest can be started with a length other than the default")
    func restWithChosenLength() {
        var timer = newTimer()
        timer.startRest(length: 15 * minute, at: t0)

        #expect(timer.phase == .rest)
        #expect(timer.remaining(at: t0) == 15 * minute)
    }

    @Test("changing rest length mid-rest restarts the rest at the new length")
    func changingRestLength() {
        var timer = newTimer()
        timer.startRest(length: 5 * minute, at: t0)
        timer.startRest(length: 20 * minute, at: t0.addingTimeInterval(minute))

        #expect(timer.remaining(at: t0.addingTimeInterval(minute)) == 20 * minute)
    }

    @Test("offers the rest lengths the design calls for")
    func offersRestOptions() {
        #expect(TimerSettings.restOptions == [5 * minute, 10 * minute, 15 * minute, 20 * minute])
    }
}

@Suite("Pomodoro pausing")
struct PomodoroPausingTests {
    @Test("pausing freezes the remaining time")
    func pauseFreezes() {
        var timer = newTimer()
        timer.startWork(at: t0)
        timer.pause(at: t0.addingTimeInterval(10 * minute))

        #expect(timer.remaining(at: t0.addingTimeInterval(40 * minute)) == 15 * minute)
    }

    @Test("resuming continues from where it paused")
    func resumeContinues() {
        var timer = newTimer()
        timer.startWork(at: t0)
        timer.pause(at: t0.addingTimeInterval(10 * minute))
        timer.resume(at: t0.addingTimeInterval(40 * minute))

        #expect(timer.remaining(at: t0.addingTimeInterval(45 * minute)) == 10 * minute)
    }

    @Test("emits no events while paused")
    func silentWhilePaused() {
        var timer = newTimer()
        timer.startWork(at: t0)
        timer.pause(at: t0.addingTimeInterval(10 * minute))

        #expect(timer.tick(at: t0.addingTimeInterval(60 * minute)).isEmpty)
    }
}

@Suite("Pomodoro skipping")
struct PomodoroSkippingTests {
    @Test("skipping work moves straight to rest")
    func skipWork() {
        var timer = newTimer()
        timer.startWork(at: t0)

        let events = timer.skip(at: t0.addingTimeInterval(3 * minute))

        #expect(events == [.workEnded(restLength: 5 * minute)])
        #expect(timer.phase == .rest)
    }

    @Test("skipping rest returns to idle")
    func skipRest() {
        var timer = newTimer()
        timer.startRest(length: 5 * minute, at: t0)

        let events = timer.skip(at: t0.addingTimeInterval(minute))

        #expect(events == [.restEnded])
        #expect(timer.phase == .idle)
    }

    @Test("skipping while idle does nothing")
    func skipIdle() {
        var timer = newTimer()
        #expect(timer.skip(at: t0).isEmpty)
    }
}

@Suite("Pomodoro session count")
struct PomodoroSessionCountTests {
    @Test("counts a work session once it runs to completion")
    func countsCompletedWork() {
        var timer = newTimer()
        timer.startWork(at: t0)
        // Ticking up to the boundary: a session only counts if the app was there to see it
        // finish. One slept through is counted in PomodoroSleepTests, and it isn't.
        _ = timer.tick(at: t0.addingTimeInterval(25 * minute - 1))
        _ = timer.tick(at: t0.addingTimeInterval(25 * minute))

        #expect(timer.completedWorkSessions == 1)
    }

    // A skipped session wasn't worked, so counting it would flatter the number into meaninglessness.
    @Test("does not count a work session that was skipped")
    func doesNotCountSkipped() {
        var timer = newTimer()
        timer.startWork(at: t0)
        _ = timer.skip(at: t0.addingTimeInterval(3 * minute))

        #expect(timer.completedWorkSessions == 0)
    }
}
