#!/bin/bash
source "$(dirname "$0")/env.sh"
BLUE_ACTUAL_XCODE="$(xcodebuild -version | head -n 1 | cut -d ' ' -f 2)"
if [ -n "${BLUE_EXPECTED_XCODE:-}" ] && [ "$BLUE_ACTUAL_XCODE" != "$BLUE_EXPECTED_XCODE" ]; then
    echo "Expected Xcode $BLUE_EXPECTED_XCODE; found $BLUE_ACTUAL_XCODE." >&2; exit 1
fi
xcodebuild -version
xcrun swift --version
xcrun simctl list runtimes
if [ -n "${BLUE_RUNTIME_IDENTIFIER:-}" ]; then
    xcrun simctl list runtimes -j | python3 -c 'import json,sys; assert any(r["identifier"]==sys.argv[1] and r["isAvailable"] for r in json.load(sys.stdin)["runtimes"]), "Required runtime unavailable"' "$BLUE_RUNTIME_IDENTIFIER"
fi
