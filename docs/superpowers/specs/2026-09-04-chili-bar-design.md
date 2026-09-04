# Chili Bar — Design

**Date:** 2026-09-04
**Status:** Sections 1–5 approved by user. Section 6 (code structure & testing) is DRAFT — not yet presented or approved.

## Overview

Chili Bar is a macOS menu bar app combining two glanceable tools: a **Pomodoro timer** and a
**rolling world clock** that cycles through colleagues' timezones. It is inspired by
[TomatoBar](https://github.com/ivoronin/TomatoBar) but is not a clone — the world clock is the
distinguishing feature, driven by working across three timezones in a remote setting.

Named for the chili icon, which appears in the menu bar only while a session is running.

## 1. The status item

One `NSStatusItem` with three states:

| State | Display | Notes |
|---|---|---|
| Idle | `SF 09:14` → `LON 17:14` → `BLR 22:44 ○` | No icon. Cycles every ~4s. |
| Working | `🌶 24:31` | Filled chili. Rotation paused. |
| Resting | `🌶 08:12` | Outline chili (same glyph, hollow). Rotation paused. |

**Chili visible ⇒ a session is live.** This is the core icon rule. Filled vs. outline separates
work from rest without a second icon or extra text.

Two required polish details:

- **No width jitter.** Labels are padded to the widest and rendered with monospaced digits so the
  status item holds a constant width. Without this, every icon to the left twitches every 4s.
- **Minute-aligned ticks.** Clock updates fire on the real minute boundary, not 60s after launch,
  so a stale minute is never displayed.

## 2. Hover to peek

Hovering the status item — in any state, **including mid-session** — opens a small panel without a
click, so the clocks stay reachable while the rotation is paused:

```
SF    09:14   Thu 4 Sep   ● online
LON   17:14   Thu 4 Sep   ● online
BLR   22:44   Thu 4 Sep   ○ off
```

Day + date appear on every row — essential when a zone has already rolled over to tomorrow.
The `●/○` dot is working-hours status; the same dot appears in the rotation.

Requires AppKit (`NSTrackingArea`); see Constraints.

## 3. The timer

States: `idle → work → rest → work → …`

No long-rest-every-Nth-session rule. The user explicitly wanted the timer stateless, and long rest
is the one feature that would require tracking session history across cycles.

**Rest length is a decision, not just a setting.** Settings hold a default, but when work ends the
panel offers `5 · 10 · 15 · 20 · custom`, so a longer break can be taken in the moment.

Work length is configurable in settings.

### Notifications

| When | Message |
|---|---|
| Lead time before work ends (default 2 min, configurable) | "Wrapping up — break in 2 min" |
| Work ends | "Break time — 10 minutes" |
| Rest ends | "Back to work" |

The pre-warning is a deliberate departure from TomatoBar, which only notifies after the fact.

## 4. The panel (on click)

```
┌─────────────────────────────┐
│        24:31                │
│     ●●●○  session 3         │
│   [ Pause ]   [ Skip ]      │
├─────────────────────────────┤
│ SF   09:14  Thu 4 Sep    ●  │
│ LON  17:14  Thu 4 Sep    ●  │
│ BLR  22:44  Thu 4 Sep    ○  │
├─────────────────────────────┤
│ Settings…            Quit   │
└─────────────────────────────┘
```

Settings is a separate small window:

- Work length
- Default rest length
- Warning lead time
- Rotation speed
- Timezone list: add / remove / reorder, each with label, timezone id, working hours

## 5. Distribution (Phase 2 — deferred)

**Decision deferred by the user: build the app first, decide signing later.**

Homebrew's official cask is not available at launch. Per the
[Package Acceptance Policy](https://docs.brew.sh/Package-Acceptance-Policy) (verified 2026-09-04):

- Self-submission by the repo owner: **90 forks, 90 watchers, or 225 stars**
- Third-party submission: **30 forks, 30 watchers, or 75 stars**
- A repo **less than 30 days old is normally not eligible**

The day-one path is an **own tap** (`homebrew-tap` repo):

```
brew install --cask junsterr/tap/chili-bar
```

Migrating to the official cask later is transparent to existing users. Casks must pass Homebrew's
Gatekeeper checks; unsigned builds require the user to right-click → Open or pass
`--no-quarantine`. Notarization ($99/yr Apple Developer Program) removes that friction and is a
prerequisite for the official cask. The release pipeline should be built so notarization drops in
by adding CI secrets, with no code rework.

## 6. Code structure and testing — DRAFT, NOT YET APPROVED

> This section was being drafted when the session was paused. It has not been presented for
> approval. Resume the brainstorm here.

### App shell — decided

**AppKit `NSStatusItem` shell, SwiftUI content via `NSHostingController`.**

SwiftUI's `MenuBarExtra` was rejected: it exposes no hover hook and gives limited control over the
button label, which rules out both the hover-peek (§2) and the fixed-width rotation (§1).

### Packaging — decided for Phase 1

**SwiftPM + a bundling script.** `Package.swift` builds the binary; a `make app` script assembles
`Chili Bar.app` (Info.plist with `LSUIElement` for no Dock icon, chili icon, ad-hoc codesign).

Rationale: works today with no Xcode install, ~4s incremental builds, and the whole project stays
plain text and diffable rather than a 3,000-line `.pbxproj`. `xcodegen` is installed if a
`project.yml` is wanted later; that is an afternoon's work and does not change the Swift source.

**Zero third-party dependencies.** `TimeZone` for clock math, `UserDefaults` for settings,
`UNUserNotificationCenter` for alerts.

### Proposed target layout

Split so the logic is testable without a running app:

- `Sources/ChiliBarCore/` — pure logic, no AppKit. Zone model and working-hours evaluation, timer
  state machine, rotation scheduling, label formatting/padding. This is what tests target.
- `Sources/ChiliBar/` — AppKit/SwiftUI shell. Status item, tracking area, panels, settings window,
  notification delivery.
- `Tests/ChiliBarCoreTests/` — XCTest against the core.

All time-dependent logic takes an injected `Date` (and `TimeZone`) rather than reading the clock
internally, so behaviour across date boundaries and working-hours edges is testable
deterministically.

### Open question

Whether `swift test` works with Command Line Tools only is **unverified** — the spike was
interrupted before it ran. If XCTest is unavailable without full Xcode, the testing approach needs
revisiting before committing to TDD. Verify first thing on resume.

## Constraints (verified 2026-09-04)

- macOS 15.7.9, Swift 6.2.4, x86_64.
- **No Xcode.app** — Command Line Tools only (`/Library/Developer/CommandLineTools`). `xcodebuild`
  is therefore unavailable, which is why SwiftPM was chosen over an `.xcodeproj`.
- Verified by spike: `swift build` compiles AppKit, SwiftUI, `NSHostingController`,
  `UserNotifications`, and `NSTrackingArea` against CLT alone. Incremental builds ~4s.
- Gotcha found in spike: an `NSTrackingArea` owner must subclass **`NSResponder`**, not `NSObject`,
  or `mouseEntered(with:)` is never called ("method does not override any method from its
  superclass").
- `xcodegen` is installed. `tuist` and `swiftlint` are not.

## Next steps

1. Verify `swift test` works with CLT only.
2. Present §6 for approval.
3. Write the implementation plan (`writing-plans` skill).
