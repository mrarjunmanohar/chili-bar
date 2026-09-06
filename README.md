<p align="center">
  <img src="Resources/chili-source.png" width="96" height="96" alt="Chili Bar">
</p>

<h1 align="center">Chili Bar</h1>

<p align="center">
  A Pomodoro timer and a rolling world clock, sharing one spot in your macOS menu bar.
</p>

---

If you work with people in other timezones, your menu bar probably has a clock that only tells you
your own time. Chili Bar cycles through your colleagues' clocks instead, and tells you at a glance
whether they're actually at their desk — then gets out of the way and runs a focus timer when you
start one.

```
Idle          MTL 14:23  →  LA 11:23  →  KNP 23:53
              cycles every few seconds, no icon

Focusing      🌶 24:31
              chili appears, clocks pause

On a break    🌶 08:12
              same chili, dimmed
```

**The chili only appears while a session is running.** That's the whole signal — if you can see a
chili, you're on the clock.

## What it does

- **Rolling world clock.** Your zones take turns in the menu bar. The item never changes width, so
  nothing beside it twitches.
- **Hover to see them all at once**, with the day and date for each — because "what time is it
  there" isn't much use when they're already on tomorrow.
- **A dot per zone** showing whether they're inside working hours right now.
- **Pomodoro timer** with a heads-up *before* the session ends, so a break never lands mid-thought.
- **Break length chosen in the moment** — 5, 10, 15 or 20 — not buried in settings.
- **Sandboxed with no entitlements.** No network, no access to anything outside its own data.
- No accounts, no telemetry. It reads two JSON files on your Mac and nothing else.

## Install

There's no notarised release yet, so you build it. It takes about a minute and needs no Xcode —
just Apple's Command Line Tools.

**1. Install Command Line Tools** (skip if `swift --version` already works):

```sh
xcode-select --install
```

**2. Clone, build and install:**

```sh
git clone https://github.com/mrarjunmanohar/chili-bar.git
cd chili-bar
./Scripts/make-app.sh --install
```

That builds Chili Bar, copies it to `/Applications`, and opens it. A chili-free clock appears in
your menu bar. There's no Dock icon and no window — that's intended.

Leave off `--install` to build into `dist/` without touching `/Applications`.

> **First launch:** macOS may say the app is from an unidentified developer, because it's signed
> locally rather than with a paid Apple certificate. Right-click the app → **Open** → **Open**.
> You only do this once.

**To quit:** click the menu bar item → **Quit**.
**To relaunch:** ⌘-Space → "Chili Bar".
**To start it automatically:** Settings… → **Start Chili Bar when I log in**.

## Setting up your zones

Click the menu bar item → **Settings…**

For each colleague, set a short label, their timezone, and their working hours. Order in the list
is the order they rotate through.

### If someone works another country's hours

This is the case that's easy to get wrong. Say a colleague in Kanpur works Montreal's 9-to-5. You
*could* convert that by hand to 18:30–02:30 India time — and it would be right for about six
months, until Montreal changes its clocks and India doesn't.

Instead, set their hours to **09:00 to 17:00** and change *on their own clock* to
**America/Montreal's clock**. Their clock still shows India time; the working-hours dot follows
Montreal, daylight saving included, permanently.

## Editing the files directly

Settings live in

```
~/Library/Containers/com.junsterr.ChiliBar/Data/Library/Application Support/Chili Bar/
```

Edit them by hand if you prefer — Chili Bar notices within a couple of seconds and reloads. No
relaunch. (The long path is because Chili Bar runs in Apple's App Sandbox; see
[Security](#security).)

**`zones.json`**

```json
[
  { "label": "MTL", "timezone": "America/Montreal",    "opens": "09:00", "closes": "17:00" },
  { "label": "LA",  "timezone": "America/Los_Angeles", "opens": "09:00", "closes": "17:00" },
  { "label": "KNP", "timezone": "Asia/Kolkata",        "opens": "09:00", "closes": "17:00",
                    "hoursIn": "America/Montreal" }
]
```

| Field | Meaning |
|---|---|
| `label` | What shows in the menu bar. Keep it short. |
| `timezone` | Any [IANA identifier](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones), e.g. `Europe/Berlin`. |
| `opens` / `closes` | `"HH:mm"`. A `closes` earlier than `opens` is an overnight shift. |
| `hoursIn` | *Optional.* Evaluate the hours on another zone's clock. |

**`settings.json`**

```json
{
  "workMinutes": 25,
  "restMinutes": 5,
  "warningMinutes": 2,
  "rotationSeconds": 4
}
```

If a file has a mistake in it, Chili Bar keeps running on defaults and tells you what was wrong in
the panel, rather than overwriting what you wrote.

## Starting it at login

Settings… → **Start Chili Bar when I log in**.

The toggle needs Chili Bar to be in `/Applications` — macOS remembers login items by location, and
a build sitting in `dist/` gets deleted by the next build. If macOS blocks the registration, allow
Chili Bar under System Settings → General → Login Items.

## Building from source

```sh
swift build                       # compile
./Scripts/test.sh                 # run the tests
./Scripts/make-app.sh             # build dist/Chili Bar.app
./Scripts/make-app.sh --install   # ...and install it to /Applications
```

Use `./Scripts/test.sh`, not `swift test`. Command Line Tools ships swift-testing without the
search paths it needs, and without `XCTest` at all; the script supplies the flags. It falls back
to a plain `swift test` if you have full Xcode.

The timezone logic — daylight saving, overnight shifts, borrowed hours — is where this app is
easiest to break without noticing, so please run the tests before opening a pull request.

Two targets: `ChiliBarCore` holds the logic and never imports AppKit, which is what keeps it
testable; `ChiliBar` is the AppKit and SwiftUI shell.

No third-party dependencies, and none wanted.

## Security

Chili Bar runs in Apple's App Sandbox and requests **no entitlements at all** — see
[`Resources/ChiliBar.entitlements`](Resources/ChiliBar.entitlements), which is four lines long.

That means macOS itself prevents it from reaching the network, reading your documents, or touching
anything outside its own container, regardless of what the code does. It needs none of those: the
app is timezone arithmetic on your local clock plus two JSON files it owns.

There is no analytics, no crash reporting, no update check, and no third-party dependency of any
kind. Anything you type into it stays on your Mac.

## Prior art

Inspired by [TomatoBar](https://github.com/ivoronin/TomatoBar), which is an excellent menu bar
Pomodoro timer. Chili Bar is a different app — the world clock is the reason it exists — but
TomatoBar was the starting point.

## Licence

MIT.
