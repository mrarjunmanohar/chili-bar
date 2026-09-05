#!/usr/bin/env bash
# Runs the test suite.
#
# Under Command Line Tools (no Xcode), swift-testing needs four flags bolted on:
#   -F / -Xlinker -F / -rpath   Testing.framework lives outside the default search paths
#   -disable-cross-import-overlays
#       _Testing_Foundation.framework ships in CLT with NO .swiftmodule, so any test file
#       importing both Testing and Foundation fails without this.
#
# With full Xcode installed none of that is needed, so we fall back to a plain `swift test`.
set -euo pipefail
cd "$(dirname "$0")/.."

FW=/Library/Developer/CommandLineTools/Library/Developer/Frameworks

if [ -d "$FW/Testing.framework" ]; then
    exec swift test \
        -Xswiftc -F -Xswiftc "$FW" \
        -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
        -Xlinker -F -Xlinker "$FW" \
        -Xlinker -rpath -Xlinker "$FW" \
        "$@"
else
    exec swift test "$@"
fi
