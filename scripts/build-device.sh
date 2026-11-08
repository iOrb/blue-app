#!/bin/bash
source "$(dirname "$0")/env.sh"
xcodebuild -project Blue.xcodeproj -scheme Blue -configuration Debug -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath .build-device CODE_SIGNING_ALLOWED=NO build > artifacts/build-device.log 2>&1 || { tail -n 60 artifacts/build-device.log; exit 1; }
tail -n 3 artifacts/build-device.log
