#!/usr/bin/env bash
#
# Assembles "Chili Bar.app" from the SwiftPM build.
#
# There is no .xcodeproj here (this machine has Command Line Tools only, no Xcode), so the
# bundle is put together by hand. Always run the bundled app rather than the bare binary in
# .build/ — LSUIElement and, later, notification registration both need a real Info.plist.
#
# Usage: ./Scripts/make-app.sh [--debug] [--install]
#
#   --install   also copy the result to /Applications and relaunch it from there.
#               Launch-at-login records the app by path, so it needs a permanent location —
#               a build in dist/ is deleted on the next run of this script.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="release"
INSTALL=false
for argument in "$@"; do
    case "${argument}" in
        --debug) CONFIGURATION="debug" ;;
        --install) INSTALL=true ;;
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
# Real Developer ID signing and notarization arrive in Phase 2 and slot in here
# without touching any Swift.
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

    echo
    echo "Installed ${INSTALLED}"
    echo "Opening it now. Enable 'Start Chili Bar when I log in' in Settings if you want it back after a restart."
    open "${INSTALLED}"
else
    echo
    echo "Built ${BUNDLE}"
    echo "Run it with:     open \"${BUNDLE}\""
    echo "Or install it:   ./Scripts/make-app.sh --install"
fi
