#!/bin/bash
source "$(dirname "$0")/env.sh"
xcodebuild -project Blue.xcodeproj -scheme Blue -configuration "${1:-Debug}" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath .build CODE_SIGNING_ALLOWED=NO build > "artifacts/build-${1:-Debug}.log" 2>&1 || { tail -n 80 "artifacts/build-${1:-Debug}.log"; exit 1; }
tail -n 3 "artifacts/build-${1:-Debug}.log"
