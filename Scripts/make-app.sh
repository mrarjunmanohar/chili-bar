#!/usr/bin/env bash
#
# Assembles "Chili Bar.app" from the SwiftPM build.
#
# There is no .xcodeproj here (this machine has Command Line Tools only, no Xcode), so the
# bundle is put together by hand. Always run the bundled app rather than the bare binary in
# .build/ — LSUIElement and, later, notification registration both need a real Info.plist.
#
# Usage: ./Scripts/make-app.sh [--debug] [--no-install]
#
#   (default)      build, sign, install to /Applications and launch it from there.
#                  Launch-at-login records the app by path, so it needs a permanent location.
#   --no-install   stage the bundle in dist/ without installing. Use sparingly: a second
#                  copy shares the bundle identifier and competes for the same notification
#                  grant, and only one of them can hold it.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="release"
INSTALL=true
for argument in "$@"; do
    case "${argument}" in
        --debug) CONFIGURATION="debug" ;;
        --no-install) INSTALL=false ;;
        *) echo "error: unknown option ${argument}" >&2; exit 2 ;;
    esac
done

APP_NAME="Chili Bar"
BUNDLE="dist/${APP_NAME}.app"
CONTENTS="${BUNDLE}/Contents"

echo "==> Building (${CONFIGURATION})"
swift build -c "${CONFIGURATION}"
BINARY="$(swift build -c "${CONFIGURATION}" --show-bin-path)/ChiliBar"

if [ ! -x "${BINARY}" ]; then
    echo "error: no binary at ${BINARY}" >&2
    exit 1
fi

echo "==> Generating icons"
swift Scripts/make-icons.swift Resources/chili-source.png Resources/icons

echo "==> Assembling ${BUNDLE}"
rm -rf "${BUNDLE}"
mkdir -p "${CONTENTS}/MacOS" "${CONTENTS}/Resources"

cp "${BINARY}" "${CONTENTS}/MacOS/ChiliBar"
cp Resources/Info.plist "${CONTENTS}/Info.plist"

# The menu bar chili (used from Stage 2 onward).
cp Resources/icons/chili.png Resources/icons/chili@2x.png "${CONTENTS}/Resources/"

iconutil --convert icns Resources/icons/ChiliBar.iconset \
    --output "${CONTENTS}/Resources/ChiliBar.icns"

# Ad-hoc signature carrying the sandbox entitlement. The sandbox is enforced by the
# signature, so it is applied here rather than declared in Info.plist.
#
# Ad-hoc is deliberate, and switching it is not the easy win it looks like. An ad-hoc
# signature has no certificate, so macOS pins the notification grant to a bare cdhash of
# the binary: every rebuild invalidates it, and requestAuthorization then returns denied
# WITHOUT prompting. The obvious fix — sign with a real certificate — does not work while
# the app is sandboxed. A certificate-rooted sandboxed app needs a provisioning profile
# naming the bundle identifier, and without one containermanagerd refuses to build the
# container: the app then hangs in dyld inside _libsecinit_appsandbox, before main(), with
# no window, no status item and no logging. Recovering from that needs a logout, because
# containermanagerd caches the refusal per bundle identifier.
#
# So notifications are treated as a channel that may silently die, and the app carries its
# own in-panel cues instead. Phase 2 revisits this together with Developer ID, notarization
# and a provisioning profile, which is the combination that actually works.
echo "==> Signing (ad-hoc, sandboxed)"
codesign --force --sign - --timestamp=none \
    --entitlements Resources/ChiliBar.entitlements \
    "${BUNDLE}" 2>&1 | sed 's/^/    /'

if [ "${INSTALL}" = true ]; then
    INSTALLED="/Applications/${APP_NAME}.app"

    echo "==> Installing to ${INSTALLED}"
    # A running copy can't be overwritten cleanly, and the old process would keep its own
    # status item alive alongside the new one.
    if pgrep -f "${APP_NAME}.app/Contents/MacOS/ChiliBar" >/dev/null 2>&1; then
        echo "    quitting the running copy"
        pkill -f "${APP_NAME}.app/Contents/MacOS/ChiliBar" || true
        sleep 1
    fi

    rm -rf "${INSTALLED}"
    cp -R "${BUNDLE}" "${INSTALLED}"

    # One local copy only. A leftover dist/ bundle carries the same identifier and a
    # different cdhash, so whichever one you happened to launch would decide whether
    # notifications worked that day.
    rm -rf "${BUNDLE}"

    echo
    echo "Installed ${INSTALLED}"
    echo "Opening it now. Enable 'Start Chili Bar when I log in' in Settings if you want it back after a restart."
    open "${INSTALLED}"
else
    echo
    echo "Staged ${BUNDLE} (not installed)"
    echo "Run it with:     open \"${BUNDLE}\""
    echo "Install it with: ./Scripts/make-app.sh"
    echo
    echo "Note: this copy shares the bundle identifier with /Applications/${APP_NAME}.app."
    echo "Only one of them can hold the notification grant. Delete it when you are done."
fi
