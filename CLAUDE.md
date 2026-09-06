# Chili Bar

macOS menu bar app: a **Pomodoro timer** + a **rolling world clock** that cycles through
colleagues' timezones. Inspired by TomatoBar, but the world clock is the distinguishing feature.

**Status: Stages 1–3 complete. Settings UI, README and CI are in.**
Remaining: install to /Applications and launch-at-login (deferred), then distribution (Phase 2).

Read `docs/superpowers/specs/2026-09-04-chili-bar-design.md` before doing any work here. It holds
the approved behaviour spec, the decisions already made, and what is still open.

## Toolchain constraints — read before proposing a build approach

- macOS 15.7.9, Swift 6.2.4, x86_64.
- **No Xcode.app is installed** — Command Line Tools only. `xcodebuild` does not work. Do not
  propose an `.xcodeproj` workflow or suggest running Xcode-only tooling.
- Verified working under CLT: `swift build` with AppKit, SwiftUI, `NSHostingController`,
  `UserNotifications`, `NSTrackingArea`. Incremental builds ~4s.
- **Testing works, but only via swift-testing and only with flags** (verified 2026-09-05).
  `XCTest` is absent under CLT — `import XCTest` fails outright. Use `import Testing` / `@Test` /
  `#expect`. Always run tests through `Scripts/test.sh`, never bare `swift test`.
- `notarytool`, `stapler`, `codesign`, `hdiutil` and `iconutil` are all present under CLT, so
  Phase 2 signing/notarization needs an Apple certificate but **not** an Xcode install.
- `xcodegen` is installed; `tuist` and `swiftlint` are not.

## Dependencies

**Zero third-party packages.** `Package.swift` has no `.package(url:)` entries and should stay
that way. Everything comes from the SDK: `AppKit`, `SwiftUI`, `Foundation`, `UserNotifications`
(and `ServiceManagement` if launch-at-login is added).

## Build and test

```sh
swift build                # compile only
./Scripts/test.sh          # tests — wraps the flags below; bare `swift test` WILL fail
./Scripts/make-app.sh      # build dist/Chili Bar.app, then: open "dist/Chili Bar.app"
```

Always run the bundled `.app`, never `.build/debug/ChiliBar` — `UNUserNotificationCenter`
needs a real bundle identifier and `LSUIElement` needs the Info.plist.

Config lives in `~/Library/Application Support/Chili Bar/` as `zones.json` and `settings.json`,
editable either in the settings window or by hand. The settings window writes the same files, so
both routes agree and the watcher reloads either way. Durations are in **minutes** on disk. To test
notifications quickly, set `workMinutes: 1` and `warningMinutes: 0.33`.

Zone hours are `"HH:mm"` strings (plain integer hours still decode, for older configs). A
`closes` earlier than `opens` means an **overnight shift**, which belongs to the day it started
— so Friday 18:30–02:30 counts as work at 01:00 on Saturday, but Saturday night does not.

`"hoursIn"` names the zone the hours are **defined in**, when the person works someone else's
hours. Kanpur working Montreal's 9–5 is written as `"opens": "09:00", "closes": "17:00",
"hoursIn": "America/Montreal"` — the clock still shows IST, the window is evaluated on
Montreal's clock. Prefer this over converting hours by hand: a hand-converted fixed window
drifts by an hour whenever one zone changes DST and the other doesn't, and India never does.

`Scripts/test.sh` exists because swift-testing under CLT needs four things bolted on:

```sh
FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW"
```

Why each is needed: `-F` finds `Testing.framework`; the linker `-F` and `-rpath` let the test
bundle load it at runtime; and `-disable-cross-import-overlays` works around
`_Testing_Foundation.framework` shipping **no `.swiftmodule`** in CLT — without it, any test file
that imports both `Testing` and `Foundation` fails with "no such module '_Testing_Foundation'".

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
  Full-colour chili = work, same chili at ~35% opacity = rest. This is the core visual signal;
  don't dilute it. (Not an outline chili — the logo is solid pixel art.)
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
- **Never assign `contentViewController` on a visible `NSPopover`.** AppKit leaves the old
  window on screen, which shows up as a second, half-hidden panel stacked behind the real one.
  Keep one popover and one `NSHostingController` and assign `rootView` instead. Same reasoning
  applies to allocating a new `NSPopover` per interaction — the previous one is orphaned with
  nothing holding a reference to close it.
- **Config file watching needs mtime polling, not a kqueue watch.** Atomic saves (temp + rename)
  replace the inode so a watch on the file goes deaf; in-place saves don't touch the directory so
  a watch on the directory never fires. Only polling catches both.
- Launching the binary directly (`.app/Contents/MacOS/ChiliBar`) is fine for reading stderr, but
  notifications are refused that way — there's no LaunchServices identity. Use `open` for anything
  involving notifications.
- There is **no chili or pepper SF Symbol** (`carrot` and `flame` exist; chili does not). The
  filled and outline chili are custom template images that have to be authored.

## Running it day to day

The built app lives at `dist/Chili Bar.app` inside the repo. Spotlight indexes it, so ⌘-Space
"Chili Bar" relaunches it. Note `make-app.sh` deletes and recreates that bundle on every build,
and `dist/` is gitignored.

**Deferred until after Stage 3:** installing to `/Applications` (via a `make-app.sh --install`
flag) and launch-at-login via `ServiceManagement`. Both were offered and postponed on 2026-09-06
until the app has been sanity-checked in daily use — no point automating the launch of something
still changing shape.

## Distribution

Deferred to Phase 2 — build the app first. Homebrew's official cask needs 225 stars (or 90
forks/watchers) for a self-submission and a repo 30+ days old, so launch goes through an **own
tap**: `brew install --cask junsterr/tap/chili-bar`. Build the release pipeline so notarization
can be added later via CI secrets without code changes.
