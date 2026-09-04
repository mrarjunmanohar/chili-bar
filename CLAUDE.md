# Chili Bar

macOS menu bar app: a **Pomodoro timer** + a **rolling world clock** that cycles through
colleagues' timezones. Inspired by TomatoBar, but the world clock is the distinguishing feature.

**Status: design approved, no code written yet.**

Read `docs/superpowers/specs/2026-09-04-chili-bar-design.md` before doing any work here. It holds
the approved behaviour spec, the decisions already made, and what is still open.

## Toolchain constraints — read before proposing a build approach

- macOS 15.7.9, Swift 6.2.4, x86_64.
- **No Xcode.app is installed** — Command Line Tools only. `xcodebuild` does not work. Do not
  propose an `.xcodeproj` workflow or suggest running Xcode-only tooling.
- Verified working under CLT: `swift build` with AppKit, SwiftUI, `NSHostingController`,
  `UserNotifications`, `NSTrackingArea`. Incremental builds ~4s.
- **Unverified:** whether `swift test` / XCTest works without full Xcode. Check this before
  relying on a test-first workflow.
- `xcodegen` is installed; `tuist` and `swiftlint` are not.

## Architecture decisions

- **AppKit `NSStatusItem` shell, SwiftUI content via `NSHostingController`.** SwiftUI's
  `MenuBarExtra` is ruled out — no hover hook, and too little control over the button label. Both
  the hover-peek and the fixed-width clock rotation depend on AppKit.
- **SwiftPM + a bundling script** produces `Chili Bar.app` (`LSUIElement`, so no Dock icon).
- **Zero third-party dependencies.** `TimeZone`, `UserDefaults`, `UNUserNotificationCenter`.
- Planned split: `ChiliBarCore` (pure logic, no AppKit, testable) and `ChiliBar` (the shell).
  Time-dependent logic takes an injected `Date`/`TimeZone` so date-boundary behaviour is testable.

## Product rules that are easy to get wrong

- **The chili icon appears only while a session is running.** Idle shows clock text with no icon.
  Filled chili = work, outline chili = rest. This is the core visual signal; don't dilute it.
- **The status item must not change width** as the clock rotates, or every icon to its left
  twitches every few seconds. Pad labels to the widest, use monospaced digits.
- Clock updates fire on the **real minute boundary**, not on an interval from launch.
- Hover works **during a session too** — that is how the clocks stay reachable while the rotation
  is paused.
- Rest length is chosen **in the moment** (5/10/15/20/custom), not only in settings.
- There is **no long-rest-every-Nth-session** rule. The timer is deliberately stateless.

## Gotchas found the hard way

- An `NSTrackingArea` owner must subclass **`NSResponder`**, not `NSObject`, or `mouseEntered`
  is never called. The error reads "method does not override any method from its superclass".

## Distribution

Deferred to Phase 2 — build the app first. Homebrew's official cask needs 225 stars (or 90
forks/watchers) for a self-submission and a repo 30+ days old, so launch goes through an **own
tap**: `brew install --cask junsterr/tap/chili-bar`. Build the release pipeline so notarization
can be added later via CI secrets without code changes.
