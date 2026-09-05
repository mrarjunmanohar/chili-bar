#!/usr/bin/env bash
#
# Assembles "Chili Bar.app" from the SwiftPM build.
#
# There is no .xcodeproj here (this machine has Command Line Tools only, no Xcode), so the
# bundle is put together by hand. Always run the bundled app rather than the bare binary in
# .build/ — LSUIElement and, later, notification registration both need a real Info.plist.
#
# Usage: ./Scripts/make-app.sh [--debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIGURATION="release"
if [ "${1:-}" = "--debug" ]; then
    CONFIGURATION="debug"
fi

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

# Ad-hoc signature. Enough for the app to run locally; real Developer ID signing and
# notarization arrive in Phase 2 and slot in here without touching any Swift.
echo "==> Signing (ad-hoc)"
codesign --force --sign - --timestamp=none "${BUNDLE}" 2>&1 | sed 's/^/    /'

echo
echo "Built ${BUNDLE}"
echo "Run it with:  open \"${BUNDLE}\""
